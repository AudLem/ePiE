#' Edge-Aware Concentration Engine
#'
#' Routes transported load over an explicit edge table so canal splits and
#' confluences conserve mass without relying on the legacy scalar ID_nxt field.
Compute_env_concentrations_edges <- function(pts,
                                             HL,
                                             transport_edges,
                                             print = TRUE,
                                             substance_type = "chemical") {
  is_pathogen <- identical(substance_type, "pathogen")

  if (inherits(pts, "sf")) pts <- sf::st_drop_geometry(pts)
  if (inherits(HL, "sf")) HL <- sf::st_drop_geometry(HL)

  if (is.null(transport_edges) || nrow(transport_edges) == 0) {
    return(Compute_env_concentrations_v4(pts, HL, print = print, substance_type = substance_type))
  }

  if (!("Hylak_id" %in% names(pts))) pts$Hylak_id <- rep(1, nrow(pts))
  if (!("lake_out" %in% names(pts))) pts$lake_out <- rep(0, nrow(pts))
  if (!("is_canal" %in% names(pts))) pts$is_canal <- rep(FALSE, nrow(pts))
  if (!("Q_model_m3s" %in% names(pts))) pts$Q_model_m3s <- rep(NA_real_, nrow(pts))
  if (!("dist_nxt" %in% names(pts))) pts$dist_nxt <- rep(0, nrow(pts))
  if (!("E_up" %in% names(pts))) pts$E_up <- rep(0, nrow(pts))
  if (!("E_w_NXT" %in% names(pts))) pts$E_w_NXT <- rep(0, nrow(pts))
  if (!("C_w" %in% names(pts))) pts$C_w <- rep(NA_real_, nrow(pts))
  if (!("C_sd" %in% names(pts))) pts$C_sd <- rep(NA_real_, nrow(pts))
  if (!("fin" %in% names(pts))) pts$fin <- rep(0, nrow(pts))

  if (is.null(HL) || nrow(HL) == 0) {
    HL <- data.frame(
      Hylak_id = numeric(0),
      basin_id = numeric(0),
      fin = logical(0),
      E_in = numeric(0),
      C_w = numeric(0),
      C_sd = numeric(0),
      k = numeric(0),
      Vol_total = numeric(0),
      k_ws = numeric(0),
      k_sw = numeric(0),
      Depth_avg = numeric(0),
      H_sed = numeric(0),
      poros = numeric(0),
      rho_sd = numeric(0)
    )
  } else {
    if (!("fin" %in% names(HL))) HL$fin <- rep(0, nrow(HL))
    if (!("E_in" %in% names(HL))) HL$E_in <- rep(0, nrow(HL))
    if (!("C_w" %in% names(HL))) HL$C_w <- rep(NA_real_, nrow(HL))
    if (!("C_sd" %in% names(HL))) HL$C_sd <- rep(NA_real_, nrow(HL))
  }

  pts$E_up[] <- 0
  pts$E_w_NXT[] <- 0
  pts$fin[] <- 0

  edge_df <- transport_edges
  edge_df <- edge_df[!is.na(edge_df$from_id) & !is.na(edge_df$to_id), , drop = FALSE]
  edge_df$from_idx <- match(edge_df$from_id, pts$ID)
  edge_df$to_idx <- match(edge_df$to_id, pts$ID)
  edge_df <- edge_df[!is.na(edge_df$from_idx) & !is.na(edge_df$to_idx), , drop = FALSE]
  if (nrow(edge_df) == 0) {
    return(Compute_env_concentrations_v4(pts, HL, print = print, substance_type = substance_type))
  }

  edge_df$flow_fraction[is.na(edge_df$flow_fraction)] <- 1
  edge_df$dist_m[is.na(edge_df$dist_m)] <- 0
  edge_df$V_edge_mps[is.na(edge_df$V_edge_mps) | edge_df$V_edge_mps <= 0] <- NA_real_

  incoming_count <- integer(nrow(pts))
  incoming_tab <- table(edge_df$to_idx)
  incoming_count[as.integer(names(incoming_tab))] <- as.integer(incoming_tab)

  outgoing_map <- split(seq_len(nrow(edge_df)), edge_df$from_idx)
  pending <- incoming_count
  incoming_load <- rep(0, nrow(pts))
  break_vec <- integer(0)
  seconds_per_year <- 365 * 24 * 3600
  hl_match <- match(pts$Hylak_id, HL$Hylak_id)

  edge_velocity <- function(edge_row) {
    v <- edge_df$V_edge_mps[edge_row]
    if (is.finite(v) && v > 0) return(v)
    from_idx <- edge_df$from_idx[edge_row]
    to_idx <- edge_df$to_idx[edge_row]
    if ("V" %in% names(pts) && is.finite(pts$V[to_idx]) && pts$V[to_idx] > 0) return(pts$V[to_idx])
    if ("V_NXT" %in% names(pts) && is.finite(pts$V_NXT[from_idx]) && pts$V_NXT[from_idx] > 0) return(pts$V_NXT[from_idx])
    if ("V" %in% names(pts) && is.finite(pts$V[from_idx]) && pts$V[from_idx] > 0) return(pts$V[from_idx])
    1
  }

  while (any(pts$fin == 0)) {
    break_vec <- c(break_vec, sum(pts$fin == 0))
    if (length(break_vec) - length(unique(break_vec)) > 10) {
      stop("Edge-aware transport stalled before all nodes were processed.")
    }

    pts_to_process <- which(pts$fin == 0 & pending == 0)
    if (length(pts_to_process) == 0) {
      stop("Edge-aware transport found unresolved dependencies with no processable nodes.")
    }

    for (j in pts_to_process) {
      hl_idx <- hl_match[j]
      E_total <- incoming_load[j] + pts$E_w[j]
      outgoing_load_base <- E_total

      if (!is.na(match(pts$basin_id[j], HL$basin_id)) && pts$lake_out[j] == 1) {
        E_total <- HL$E_in[hl_idx] + pts$E_w[j] + incoming_load[j]
        V_lake <- HL$Vol_total[hl_idx] * 1e9
        k_lake <- HL$k[hl_idx]
        if (is_pathogen) {
          pts$C_w[j] <- (E_total / (pts$Q[j] + k_lake * V_lake)) / seconds_per_year / 1000
          outgoing_load_base <- pts$C_w[j] * pts$Q[j] * 1000 * seconds_per_year
        } else {
          pts$C_w[j] <- E_total / (pts$Q[j] + k_lake * V_lake) * 1e6 / seconds_per_year
          chem_exchange <- HL$k_ws[hl_idx] / HL$k_sw[hl_idx]
          H_ratio <- HL$Depth_avg[hl_idx] / HL$H_sed[hl_idx]
          dens_transform <- HL$poros[hl_idx] + (1 - HL$poros[hl_idx]) * HL$rho_sd[hl_idx]
          pts$C_sd[j] <- pts$C_w[j] * chem_exchange * H_ratio * dens_transform
          outgoing_load_base <- pts$C_w[j] * pts$Q[j] * seconds_per_year / 1e6
        }
        HL$C_w[hl_idx] <- pts$C_w[j]
        HL$C_sd[hl_idx] <- pts$C_sd[j]
        HL$fin[hl_idx] <- 1
      } else if ((pts$Hylak_id[j] == 0) | (pts$lake_out[j] == 1)) {
        if (is_pathogen) {
          pts$C_w[j] <- as.numeric((E_total / seconds_per_year) / (pts$Q[j] * 1000))
        } else {
          pts$C_w[j] <- as.numeric(E_total / pts$Q[j] * 1e6 / seconds_per_year)
          chem_exchange <- pts$k_ws[j] / pts$k_sw[j]
          H_ratio <- pts$H[j] / pts$H_sed[j]
          dens_transform <- pts$poros[j] + (1 - pts$poros[j]) * pts$rho_sd[j]
          pts$C_sd[j] <- as.numeric(pts$C_w[j] * chem_exchange * H_ratio * dens_transform)
        }
      } else {
        pts$C_w[j] <- NA_real_
        pts$C_sd[j] <- NA_real_
      }

      outgoing_edges <- outgoing_map[[as.character(j)]]
      routed_total <- 0
      if (length(outgoing_edges) > 0) {
        for (edge_row in outgoing_edges) {
          flow_fraction <- edge_df$flow_fraction[edge_row]
          if (!is.finite(flow_fraction) || flow_fraction < 0) {
            flow_fraction <- 0
          }
          dist_m <- edge_df$dist_m[edge_row]
          if (!is.finite(dist_m) || dist_m < 0) dist_m <- 0
          velocity <- edge_velocity(edge_row)
          decay_factor <- if ((pts$Hylak_id[j] == 0) | (pts$lake_out[j] == 1)) {
            exp(-pts$k_NXT[j] * dist_m / velocity)
          } else if (!is.na(match(pts$basin_id[j], HL$basin_id)) && pts$lake_out[j] == 1) {
            exp(-pts$k_NXT[j] * dist_m / velocity)
          } else {
            1
          }
          edge_load <- outgoing_load_base * flow_fraction * decay_factor
          to_idx <- edge_df$to_idx[edge_row]
          incoming_load[to_idx] <- incoming_load[to_idx] + edge_load
          pending[to_idx] <- pending[to_idx] - 1L
          routed_total <- routed_total + edge_load
        }
      }

      pts$E_up[j] <- incoming_load[j]
      pts$E_w_NXT[j] <- routed_total
      pts$upcount[j] <- pending[j]
      pts$fin[j] <- 1
    }
  }

  if (!is.null(HL) && nrow(HL) != 0) {
    return(list(
      pts = data.frame(
        ID = pts$ID,
        Pt_type = pts$Pt_type,
        ID_nxt = pts$ID_nxt,
        basin_ID = pts$basin_id,
        Hylak_id = pts$Hylak_id,
        x = pts$x,
        y = pts$y,
        Q = pts$Q,
        C_w = pts$C_w,
        C_sd = pts$C_sd,
        WWTPremoval = pts$f_rem_WWTP,
        is_canal = pts$is_canal,
        Q_model_m3s = pts$Q_model_m3s,
        dist_nxt = pts$dist_nxt
      ),
      HL = data.frame(
        Hylak_id = HL$Hylak_id,
        C_w = HL$C_w,
        C_sd = HL$C_sd
      )
    ))
  }

  list(
    pts = data.frame(
      ID = pts$ID,
      Pt_type = pts$Pt_type,
      ID_nxt = pts$ID_nxt,
      basin_ID = pts$basin_id,
      x = pts$x,
      y = pts$y,
      Q = pts$Q,
      C_w = pts$C_w,
      C_sd = pts$C_sd,
      WWTPremoval = pts$f_rem_WWTP,
      is_canal = pts$is_canal,
      Q_model_m3s = pts$Q_model_m3s,
      dist_nxt = pts$dist_nxt
    )
  )
}
