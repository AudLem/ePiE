# ==============================================================================
# Pathogen Emission and Decay Parameter Assignment
# ==============================================================================
# This file contains two functions that prepare a network for pathogen
# concentration modelling:
#   1. AssignPathogenEmissions  — computes E_in (load entering each node)
#   2. AssignPathogenDecayParameters — computes decay rates (k) per node
#
# Both functions are called from the concentration engine orchestrator
# (02_ComputeEnvConcentrations.R) when substance_type = "pathogen".
# ==============================================================================

# ------------------------------------------------------------------------------
# AssignPathogenEmissions
# ------------------------------------------------------------------------------
# Computes the pathogen load (oocysts/year) entering each network node.
#
# Two source types are handled:
#   A) WWTP nodes: treated discharge from connected population
#   B) Agglomeration nodes: direct (untreated) discharge from local population
#
# Formula P6 (WWTP emission):
#   E_in_WWTP = total_pop * prevalence * excretion * f_connection
#   where f_connection = f_STP (fraction of population connected to sewer)
#
# Formula P7 (WWTP removal):
#   f_remain = (1 - f_prim) * (1 - f_sec)
#   E_w = E_in * f_remain
#   Default values: f_prim = 0.23 (primary), f_sec = 0.96 (secondary)
#   Source: Vermeulen et al. (2019), WHO guidelines
#
# Formula P8 (Agglomeration emission — PARTIAL implementation):
#   E_in_agglomeration = local_pop * prevalence * excretion
#   NOTE: The proposal includes f_diff (sanitation access fraction) and
#   f_runoff (overland transport fraction) but these are NOT yet applied.
#
# Parameters come from inst/pathogen_input/<pathogen_name>.R, which defines
# a simulation_parameters list with pathogen-specific values.
#
# TODO(MULTI-PATHOGEN): prevalence and excretion rates are pathogen-specific.
#   Currently read from pathogen_params (which comes from the parameter file).
#   To support multiple pathogens simultaneously:
#     1. Loop over pathogen parameter sets in 02_ComputeEnvConcentrations.R
#     2. Create separate E_in_<pathogen> columns or run the engine per pathogen
#     3. Add parameter files for Rotavirus, Campylobacter, Giardia following
#        the same structure as inst/pathogen_input/cryptosporidium.R
#
# TODO(DIFFUSE-EMISSION): Add f_diff and f_runoff factors to agglomeration nodes:
#     E_in_aggl = local_pop * prevalence * excretion * f_diff * f_runoff
#   - f_diff: fraction of population WITHOUT sanitation access (from JMP dataset)
#   - f_runoff: fraction reaching surface water (land-cover-dependent)
#   This requires new data layers (sanitation access, land cover rasters).
#
# TODO(SEASONAL): Prevalence rate is currently a static scalar (0.05).
#   To add seasonal variation:
#     1. Add monthly/seasonal prevalence multipliers to parameter file
#     2. Accept a "season" or "month" argument in this function
#     3. Look up the seasonal multiplier: prevalence = base * seasonal_factor
# ------------------------------------------------------------------------------
AssignPathogenEmissions <- function(network_nodes, pathogen_params) {
  total_pop <- pathogen_params$total_population
  prev_rate <- pathogen_params$prevalence_rate
  exc_rate  <- pathogen_params$excretion_rate

  resolve_source_population <- function(nodes, idx, fallback_total) {
    n <- length(idx)
    if (n == 0) return(numeric(0))

    resolved <- rep(NA_real_, n)

    assign_if_positive <- function(col_name) {
      if (!(col_name %in% names(nodes))) return(invisible(NULL))
      vals <- suppressWarnings(as.numeric(nodes[[col_name]][idx]))
      use_idx <- is.na(resolved) & !is.na(vals) & vals > 0
      resolved[use_idx] <<- vals[use_idx]
    }

    assign_if_positive("total_population")
    assign_if_positive("Inh")
    assign_if_positive("uwwLoadEnt")
    assign_if_positive("uwwCapacit")

    resolved[is.na(resolved)] <- fallback_total
    resolved
  }

  # Initialise emission columns
  network_nodes$E_in <- rep(0, nrow(network_nodes))
  network_nodes$f_rem_WWTP <- NA_real_

  # --- A) WWTP nodes: treated discharge ---
  # Each WWTP emits based on its local connected population (per-node basis),
  # not the basin total. This avoids overcounting when multiple WWTPs exist.
  # f_STP represents the sewer connection rate for this WWTP's catchment.
  wwtp_idx <- which(network_nodes$Pt_type == "WWTP")
  if (length(wwtp_idx) > 0) {
    wwtp_pop <- resolve_source_population(network_nodes, wwtp_idx, total_pop)
    network_nodes$E_in[wwtp_idx] <- wwtp_pop * prev_rate * exc_rate
  }

  # WWTP removal: each plant removes a fraction depending on treatment type.
  # uwwPrimary == -1 means primary treatment is present → apply f_prim removal.
  # uwwSeconda == -1 means secondary treatment is present → apply f_sec removal.
  # The combined remaining fraction is: (1 - f_prim) * (1 - f_sec)
  # and the removal fraction stored is: 1 - (1 - f_prim) * (1 - f_sec)
  for (idx in wwtp_idx) {
    f_prim <- if (!is.null(pathogen_params$wwtp_primary_removal) &&
                   !is.na(pathogen_params$wwtp_primary_removal) &&
                   network_nodes$uwwPrimary[idx] == -1) {
      pathogen_params$wwtp_primary_removal
    } else 0
    f_sec <- if (!is.null(pathogen_params$wwtp_secondary_removal) &&
                  !is.na(pathogen_params$wwtp_secondary_removal) &&
                  network_nodes$uwwSeconda[idx] == -1) {
      pathogen_params$wwtp_secondary_removal
    } else 0
    network_nodes$f_rem_WWTP[idx] <- 1 - (1 - f_prim) * (1 - f_sec)
  }

  # --- B) Agglomeration nodes: untreated direct discharge ---
  # Each agglomeration emits based on its local population.
  # TODO(DIFFUSE-EMISSION): multiply by f_diff * f_runoff here
  aggl_idx <- which(tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations"))
  if (length(aggl_idx) > 0) {
    aggl_pop <- resolve_source_population(network_nodes, aggl_idx, total_pop)
    network_nodes$E_in[aggl_idx] <- aggl_pop * prev_rate * exc_rate
    network_nodes$f_STP[aggl_idx] <- 0
  }

  # Compute final emission after treatment:
  #   WWTP nodes: E_w = E_in * (1 - f_rem_WWTP)   [treated discharge]
  #   Agglomeration: E_w = E_in                    [untreated, direct]
  #   All other nodes: E_w = 0                     [no source]
  network_nodes$E_w <- ifelse(
    network_nodes$Pt_type == "WWTP",
    network_nodes$E_in * (1 - ifelse(is.na(network_nodes$f_rem_WWTP), 0, network_nodes$f_rem_WWTP)),
    ifelse(tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations"),
           network_nodes$E_in, 0)
  )

  network_nodes
}

# ------------------------------------------------------------------------------
# AssignPathogenDecayParameters
# ------------------------------------------------------------------------------
# Computes the three decay pathways (K_T, K_R, K_S) and total rate k for each
# network node and each lake node, using the formulas in Process_formulas.R.
#
# The helper get_val() provides backward-compatible column name lookup:
#   e.g. "T_sw" (old name) is accepted as fallback for "water_temperature" (new).
#
# Key unit conversions:
#   - Temperature: T_AIR is in K, but the decay formulas expect Celsius,
#     so we subtract 273.15 at the call site.
#   - Solar radiation: AR (kJ m^-2 day^-1) is used directly.
#   - Depth: H (m) is used directly.
#   - DOC: C_DOC (kg/L) is used directly; kd converts to ke (m^-1).
#
# The resulting k (s^-1) is stored per node and used by the transport engine
# for first-order exponential decay during downstream routing.
# ------------------------------------------------------------------------------
AssignPathogenDecayParameters <- function(network_nodes, lake_nodes, pathogen_params) {
  get_val <- function(df, new_name, old_name, default) {
    if (new_name %in% names(df)) return(df[[new_name]])
    if (old_name %in% names(df)) return(df[[old_name]])
    rep(default, nrow(df))
  }

  # Extract environmental fields from network nodes (with fallbacks)
  temp_w <- get_val(network_nodes, "water_temperature", "T_sw", 285)
  solar_r <- get_val(network_nodes, "solar_radiation", "AR", 0)
  depth <- get_val(network_nodes, "river_depth", "H", 0.001)
  doc <- get_val(network_nodes, "doc_concentration", "C_DOC", 0.005e-3)

  # Compute three decay pathways for river nodes
  # K_T: temperature-dependent inactivation (Celsius conversion: T_K - 273.15)
  network_nodes$K_T <- calc_temp_decay(pathogen_params$decay_rate_base, temp_w - 273.15, pathogen_params$temp_corr_factor)
  # ke: light attenuation from dissolved organic carbon
  network_nodes$ke  <- calc_light_attenuation(doc, pathogen_params$doc_attenuation)
  # K_R: solar radiation inactivation (depth-averaged Beer-Lambert)
  network_nodes$K_R <- calc_solar_decay(solar_r, pathogen_params$solar_rad_factor, network_nodes$ke, depth)
  # K_S: sedimentation (settling velocity / depth)
  network_nodes$K_S <- calc_sedimentation_decay(pathogen_params$settling_velocity, depth)
  # k: total dissipation rate (sum, converted from day^-1 to s^-1)
  network_nodes$k   <- calc_total_dissipation_rate(network_nodes$K_T, network_nodes$K_R, network_nodes$K_S)

  # Same computation for lake nodes (deeper, different default depth)
  if (!is.null(lake_nodes) && nrow(lake_nodes) != 0) {
    temp_l <- get_val(lake_nodes, "water_temperature", "T_sw", 285)
    solar_l <- get_val(lake_nodes, "solar_radiation", "AR", 0)
    depth_l <- get_val(lake_nodes, "river_depth", "H_av", 3.0)
    doc_l <- get_val(lake_nodes, "doc_concentration", "C_DOC", 0.005e-3)

    lake_nodes$K_T <- calc_temp_decay(pathogen_params$decay_rate_base, temp_l - 273.15, pathogen_params$temp_corr_factor)
    lake_nodes$ke  <- calc_light_attenuation(doc_l, pathogen_params$doc_attenuation)
    lake_nodes$K_R <- calc_solar_decay(solar_l, pathogen_params$solar_rad_factor, lake_nodes$ke, depth_l)
    lake_nodes$K_S <- calc_sedimentation_decay(pathogen_params$settling_velocity, depth_l)
    lake_nodes$k   <- calc_total_dissipation_rate(lake_nodes$K_T, lake_nodes$K_R, lake_nodes$K_S)
  }

  list(network_nodes = network_nodes, lake_nodes = lake_nodes)
}
