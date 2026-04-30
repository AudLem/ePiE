# ==============================================================================
# R Concentration Engine (v4) — Chemical & Pathogen Transport
# ==============================================================================
# Computes steady-state concentrations at each network node using a
# topologically-ordered upstream-to-downstream sweep.
#
# The engine processes nodes whose upstream dependencies are all resolved
# (upcount == 0), working from headwaters to outlet.
#
# Three node types are handled differently:
#   1. Lake outlet nodes  — either CSTR or legacy pass-through, by config
#   2. Regular river nodes — simple steady-state mass balance
#   3. Lake inlet nodes    — pass-through (load forwarded unchanged)
#
# Unit conventions:
#   - Pathogen: C_w in pathogen-specific units/L, E in pathogen units/year,
#               Q in m^3/s
#   - Chemical: C_w in ug/L, E in kg/year, Q in m^3/s
#   The factor 1000 vs 1e6 in the concentration formulas reflects this.
# ==============================================================================

Compute_env_concentrations_v4 = function(pts, HL, print = TRUE, substance_type = "chemical",
                                         lake_transport_mode = "cstr"){

  is_pathogen <- identical(substance_type, "pathogen")
  lake_transport_mode <- match.arg(as.character(lake_transport_mode[[1]]),
                                   c("cstr", "legacy_pass_through"))

  # --- Geometry Guard ---------------------------------------------------------
  # The transport loops below use column vectorisation via assign().
  # This logic is incompatible with sf list-columns.
  # ----------------------------------------------------------------------------
  if (inherits(pts, "sf")) pts <- sf::st_drop_geometry(pts)
  if (inherits(HL, "sf")) HL <- sf::st_drop_geometry(HL)

  # Store all columns as vectors for performance (direct indexing is faster
  # than repeated data.frame column access in tight loops)
  for(i in 1:ncol(pts)) assign(paste('pts.',colnames(pts)[i],sep=''),pts[,i])
  if (!is.null(HL) && ncol(HL) > 0) {
    for(i in 1:ncol(HL)) assign(paste('HL.',colnames(HL)[i],sep=''),HL[,i])
  } else {
    # If HL is NULL or empty, initialize HL.fin to something that exists
    # to avoid errors in Case 1 / Case 3 checks.
    HL.fin <- logical(0)
    HL.Hylak_id <- numeric(0)
    HL.basin_id <- numeric(0)
  }
  if(!exists("pts.Hylak_id")) pts.Hylak_id = rep(1,length(pts.ID))
  if(!exists("pts.lake_in")) pts.lake_in = rep(0,length(pts.ID))
  if(!exists("pts.lake_out")) pts.lake_out = rep(0,length(pts.ID))
  if(!exists("pts.is_canal")) pts.is_canal = rep(FALSE,length(pts.ID))
  if(!exists("pts.Q_model_m3s")) pts.Q_model_m3s = rep(NA_real_,length(pts.ID))
  if(!exists("pts.dist_nxt")) pts.dist_nxt = rep(0,length(pts.ID))
  if(!exists("pts.lake_residence_time_days")) pts.lake_residence_time_days = rep(NA_real_,length(pts.ID))
  if(!exists("pts.Q_lake_m3s")) pts.Q_lake_m3s = rep(NA_real_,length(pts.ID))
  if(!exists("pts.lake_throughflow_m3s")) pts.lake_throughflow_m3s = rep(NA_real_,length(pts.ID))
  if(!exists("pts.lake_transport_mode")) pts.lake_transport_mode = rep(NA_character_,length(pts.ID))
  if(!exists("HL.lake_residence_time_days")) HL.lake_residence_time_days = rep(NA_real_,length(HL.Hylak_id))
  lake_node_idx <- which((!is.na(pts.lake_in) & pts.lake_in == 1) |
                           (!is.na(pts.lake_out) & pts.lake_out == 1))
  pts.lake_transport_mode[lake_node_idx] <- lake_transport_mode
  if (lake_transport_mode == "legacy_pass_through") {
    lake_out_idx <- which(!is.na(pts.lake_out) & pts.lake_out == 1)
    pts.lake_residence_time_days[lake_out_idx] <- NA_real_
    HL.lake_residence_time_days[] <- NA_real_
  }

  break.vec1 = c();

  # Pre-compute matching indices for lake nodes and downstream nodes.
  # These are used in every iteration of the while loop.
  HL_indices_match = match(pts.Hylak_id,HL.Hylak_id)
  pts_indices_down = match(paste0(pts.basin_id,'_',pts.ID_nxt),paste0(pts.basin_id,'_',pts.ID))

  # Main loop: process nodes from upstream to downstream.
  # The loop continues until all nodes are marked finished (fin == 1)
  # or convergence stalls (same count repeated >10 times — safety break).
  while (any(pts.fin==0)){

    break.vec1 = c(break.vec1,sum(pts.fin == 0));
    if(length(break.vec1)-length(unique(break.vec1))>10) break

    # Select nodes that are not yet finished AND have no unresolved upstream nodes
    pts_to_process = which(pts.fin==0 & pts.upcount==0)

    for (j in pts_to_process) {

      if(pts.fin[j]==0){
        HL_index_match = HL_indices_match[j]
        pts_index_down = pts_indices_down[j]
      }

      # ======================================================================
      # Case 1: Lake outlet node in CSTR mode
      # ======================================================================
      # This node sits at the outlet of a lake. In CSTR mode, the lake is
      # modelled as a Completely Stirred Tank Reactor.
      #
      # Formula P11 (Lake CSTR):
      #   C_lake = E_total / (Q + k * V)
      #   where:
      #     E_total = sum of all upstream loads + local emission + lake inflow
      #     Q       = outflow discharge (m^3/s)
      #     k       = total decay rate (s^-1)
      #     V       = lake volume (m^3, converted from km^3 via * 1e9)
      #
      # The CSTR assumes instantaneous and complete mixing within the lake.
      # Reference: Vermeulen et al. (2019); standard surface water quality modelling.
      # ======================================================================
        is_lake_outlet <- isTRUE(!is.na(match(pts.basin_id[j], HL.basin_id)) &&
                                   !is.na(pts.lake_out[j]) &&
                                   pts.lake_out[j] == 1)
        if (is_lake_outlet && lake_transport_mode == "cstr") {

          E_total = HL.E_in[HL_index_match] + pts.E_w[j] + pts.E_up[j]

          # 1 km^3 = 10^9 m^3 (was 1e6 — this is the correct conversion)
          V = HL.Vol_total[HL_index_match] * 1e9
          k = HL.k[HL_index_match]
          if (is.finite(pts.Q[j]) && pts.Q[j] > 0) {
            pts.lake_residence_time_days[j] = V / (pts.Q[j] * 86400)
            HL.lake_residence_time_days[HL_index_match] = pts.lake_residence_time_days[j]
          }

          if (is_pathogen) {
            # Pathogen: E_total in pathogen units/year, Q in m^3/s,
            # C_w in pathogen-specific units/L
            # C_w = (E_total / seconds_per_year) / (Q * 1000 L/m^3)
            # The (Q + k*V) denominator combines advective outflow and decay.
            # Convert m^3 to L by dividing by 1000 (1 m^3 = 1000 L).
            pts.C_w[j] = (E_total / (pts.Q[j] + k * V)) / (365 * 24 * 3600) / 1000
          } else {
            # Chemical: E_total in kg/year, Q in m^3/s, C_w in ug/L
            # C_w = (E_total * 1e9 ug/kg) / (seconds_per_year * Q * 1000 L/m^3)
            pts.C_w[j] = E_total / (pts.Q[j] + k * V) * 1e6 / (365*24*3600)
            # Sediment concentration via equilibrium partitioning:
            # C_sd = C_w * (k_ws/k_sw) * (H/H_sed) * (poros + (1-poros)*rho_sd)
            chem_exchange = HL.k_ws[HL_index_match] / HL.k_sw[HL_index_match]
            H_ratio = HL.Depth_avg[HL_index_match] / HL.H_sed[HL_index_match]
            dens_transform = HL.poros[HL_index_match] + (1 - HL.poros[HL_index_match]) * HL.rho_sd[HL_index_match]
            pts.C_sd[j] = pts.C_w[j] * chem_exchange * H_ratio * dens_transform
          }

          HL.C_w[HL_index_match] = pts.C_w[j]
          HL.C_sd[HL_index_match] = pts.C_sd[j]
          HL.fin[HL_index_match] = 1

          # Downstream transport from lake outlet with first-order decay
          # Formula P10: E_downstream = E_total * exp(-k * travel_time)
          # where travel_time = distance / velocity = dist_nxt / V_NXT
          if (is_pathogen) {
            # Convert C_w back to pathogen units/year via Q (m^3/s)
            # and 1000 L/m^3.
            pts.E_w_NXT[j] = pts.C_w[j] * pts.Q[j] * 1000 * 365 * 24 * 3600 * exp(-pts.k_NXT[j] * pts.dist_nxt[j] / pts.V_NXT[j])
          } else {
            pts.E_w_NXT[j] = pts.C_w[j] * pts.Q[j] * 365 * 24 * 3600 / 1e6 * exp(-pts.k_NXT[j] * pts.dist_nxt[j] / pts.V_NXT[j])
          }
          if (!is.na(pts_index_down)) {
            pts.E_up[pts_index_down] = pts.E_up[pts_index_down] + pts.E_w_NXT[j]
            pts.upcount[pts_index_down] = pts.upcount[pts_index_down] - 1
          }


        # ======================================================================
        # Case 2: Regular river node, or legacy pass-through lake outlet
        # ======================================================================
        # Formula P9 (River node concentration):
        #   C_w = (E_total / seconds_per_year) / (Q * 1000)   [pathogen units/L]
        #   C_w = (E_total * 1e6 / seconds_per_year) / Q       [chemical: ug/L]
        #
        # This is the steady-state mass balance: concentration = load / flow.
        # E_total = local emission (E_w) + cumulative upstream load (E_up).
        # ======================================================================
        } else if ((pts.Hylak_id[j] == 0) | (pts.lake_out[j] == 1)) {

          E_total = pts.E_w[j] + pts.E_up[j]

          if (is_pathogen) {
            # Pathogen concentration in pathogen-specific units/L.
            pts.C_w[j] = as.numeric((E_total / (365 * 24 * 3600)) / (pts.Q[j] * 1000))
          } else {
            # Chemical concentration: ug/L
            pts.C_w[j] = as.numeric(E_total / pts.Q[j] * 1e6 / (365*24*3600))
            chem_exchange = pts.k_ws[j] / pts.k_sw[j]
            H_ratio = pts.H[j] / pts.H_sed[j]
            dens_transform = pts.poros[j] + (1 - pts.poros[j]) * pts.rho_sd[j]
            pts.C_sd[j] = as.numeric(pts.C_w[j] * chem_exchange * H_ratio * dens_transform)
          }

          # Formula P10: Downstream transport with exponential decay
          # E_downstream = E_total * exp(-k * dist / velocity)
          pts.E_w_NXT[j] = E_total * exp(-pts.k_NXT[j] * pts.dist_nxt[j] / pts.V_NXT[j])
          if (!is.na(pts_index_down)) {
            pts.E_up[pts_index_down] = pts.E_up[pts_index_down] + pts.E_w_NXT[j]
            pts.upcount[pts_index_down] = pts.upcount[pts_index_down] - 1
          }
          if (is_lake_outlet && lake_transport_mode == "legacy_pass_through") {
            HL.C_w[HL_index_match] = pts.C_w[j]
            HL.C_sd[HL_index_match] = pts.C_sd[j]
            HL.fin[HL_index_match] = 1
          }

        # ======================================================================
        # Case 3: Lake inlet node (load passes through to outlet unmodified)
        # ======================================================================
        # The concentration is not computed here. The total load is forwarded
        # unchanged to the outlet, where the configured lake mode decides
        # whether to apply CSTR removal or legacy pass-through routing.
        # ======================================================================
        } else {

          E_total = pts.E_w[j] + pts.E_up[j]
          pts.C_w[j] = NA
          pts.C_sd[j] = NA

          # Pass load through without decay. Any configured lake fate happens at
          # the outlet node, not at the inlet boundary.
          pts.E_w_NXT[j] = E_total
          if (!is.na(pts_index_down)) {
            pts.E_up[pts_index_down] = pts.E_up[pts_index_down] + pts.E_w_NXT[j]
            pts.upcount[pts_index_down] = pts.upcount[pts_index_down] - 1
          }
        }

        pts.fin[j] = 1

    }

  }

  # Assemble output data frames
  if (!is.null(HL) && nrow(HL) != 0) {
    return(list(
      pts = data.frame(
        ID = pts.ID,
        Pt_type = pts.Pt_type,
        ID_nxt = pts.ID_nxt,
        basin_ID = pts.basin_id,
        Hylak_id = pts.Hylak_id,
        x = pts.x,
        y = pts.y,
        Q = pts.Q,
        C_w = pts.C_w,
        C_sd = pts.C_sd,
        WWTPremoval = pts.f_rem_WWTP,
        is_canal = pts.is_canal,
        Q_model_m3s = pts.Q_model_m3s,
        dist_nxt = pts.dist_nxt,
        Q_lake_m3s = pts.Q_lake_m3s,
        lake_throughflow_m3s = pts.lake_throughflow_m3s,
        lake_transport_mode = pts.lake_transport_mode,
        lake_residence_time_days = pts.lake_residence_time_days
      ),
      HL = data.frame(
        Hylak_id = HL.Hylak_id,
        C_w = HL.C_w,
        C_sd = HL.C_sd,
        lake_residence_time_days = HL.lake_residence_time_days
      )
    ))
  } else {
    return(list(
      pts = data.frame(
        ID = pts.ID,
        Pt_type = pts.Pt_type,
        ID_nxt = pts.ID_nxt,
        basin_ID = pts.basin_id,
        x = pts.x,
        y = pts.y,
        Q = pts.Q,
        C_w = pts.C_w,
        C_sd = pts.C_sd,
        WWTPremoval = pts.f_rem_WWTP,
        is_canal = pts.is_canal,
        Q_model_m3s = pts.Q_model_m3s,
        dist_nxt = pts.dist_nxt,
        Q_lake_m3s = pts.Q_lake_m3s,
        lake_throughflow_m3s = pts.lake_throughflow_m3s,
        lake_transport_mode = pts.lake_transport_mode,
        lake_residence_time_days = pts.lake_residence_time_days
      )
    ))
  }
}
