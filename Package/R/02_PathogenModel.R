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
# Computes the pathogen load (pathogen-specific units/year) entering each
# network node. Units are defined by the selected pathogen parameter file.
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
#   E_in_agglomeration = local_pop * prevalence * excretion * f_pathogen_direct
#   f_pathogen_direct is a pathogen-only direct-to-water fraction.
#   It is not the same variable as f_direct.
#   NOTE: The proposal includes f_diff (sanitation access fraction) and
#   f_runoff (overland transport fraction) but these are NOT yet applied.
#
# Decay/base parameters come from inst/pathogen_input/<pathogen_name>.R.
# Place-dependent emission assumptions (prevalence, excretion, WWTP removal)
# are overlaid by the selected pathogen profile before this function is called.
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
ApplyPathogenDirectFractionOverrides <- function(network_nodes, overrides = NULL) {
  if (is.null(network_nodes) || nrow(network_nodes) == 0) {
    return(network_nodes)
  }

  node_type <- if ("Pt_type" %in% names(network_nodes)) {
    network_nodes$Pt_type
  } else if ("pt_type" %in% names(network_nodes)) {
    network_nodes$pt_type
  } else {
    rep("", nrow(network_nodes))
  }
  is_agglomeration <- tolower(as.character(node_type)) %in% c("agglomeration", "agglomerations")

  if (!("f_pathogen_direct" %in% names(network_nodes))) {
    network_nodes$f_pathogen_direct <- NA_real_
  }
  if (!("f_pathogen_direct_place" %in% names(network_nodes))) {
    network_nodes$f_pathogen_direct_place <- NA_character_
  }
  if (!("f_pathogen_direct_basis" %in% names(network_nodes))) {
    network_nodes$f_pathogen_direct_basis <- NA_character_
  }

  network_nodes$f_pathogen_direct <- suppressWarnings(as.numeric(network_nodes$f_pathogen_direct))
  network_nodes$f_pathogen_direct_place <- as.character(network_nodes$f_pathogen_direct_place)
  network_nodes$f_pathogen_direct_basis <- as.character(network_nodes$f_pathogen_direct_basis)
  missing_direct <- is.na(network_nodes$f_pathogen_direct) | !is.finite(network_nodes$f_pathogen_direct)

  # Default assumption:
  #   - agglomeration sources send all local pathogen load directly to water (1)
  #   - non-agglomeration nodes do not use this factor (0)
  # Scenario configs can override selected agglomeration source IDs or stable
  # reference coordinates when source IDs change between wet and dry networks.
  network_nodes$f_pathogen_direct[is_agglomeration & missing_direct] <- 1
  network_nodes$f_pathogen_direct[!is_agglomeration] <- 0
  missing_basis <- is.na(network_nodes$f_pathogen_direct_basis) |
    !nzchar(network_nodes$f_pathogen_direct_basis)
  network_nodes$f_pathogen_direct_basis[is_agglomeration & missing_basis] <- "default"
  network_nodes$f_pathogen_direct_basis[!is_agglomeration] <- "not_applicable"
  network_nodes$f_pathogen_direct_place[!is_agglomeration] <- NA_character_

  validate_direct_fraction <- function() {
    bad <- is_agglomeration &
      (is.na(network_nodes$f_pathogen_direct) |
         !is.finite(network_nodes$f_pathogen_direct) |
         network_nodes$f_pathogen_direct < 0 |
         network_nodes$f_pathogen_direct > 1)
    if (any(bad)) {
      stop("f_pathogen_direct values must be finite fractions from 0 to 1.")
    }
  }

  override_distance_m <- function(node_x, node_y, ref_x, ref_y) {
    node_x <- suppressWarnings(as.numeric(node_x))
    node_y <- suppressWarnings(as.numeric(node_y))
    ref_x <- suppressWarnings(as.numeric(ref_x))
    ref_y <- suppressWarnings(as.numeric(ref_y))

    valid <- is.finite(node_x) & is.finite(node_y) & is.finite(ref_x) & is.finite(ref_y)
    out <- rep(Inf, length(node_x))
    if (!any(valid)) return(out)

    lonlat <- all(abs(c(node_x[valid], ref_x[valid])) <= 180) &&
      all(abs(c(node_y[valid], ref_y[valid])) <= 90)
    if (lonlat) {
      rad <- pi / 180
      dlon <- (node_x[valid] - ref_x[valid]) * rad
      dlat <- (node_y[valid] - ref_y[valid]) * rad
      lat1 <- ref_y[valid] * rad
      lat2 <- node_y[valid] * rad
      a <- sin(dlat / 2)^2 + cos(lat1) * cos(lat2) * sin(dlon / 2)^2
      out[valid] <- 2 * 6371000 * atan2(sqrt(a), sqrt(1 - a))
    } else {
      out[valid] <- sqrt((node_x[valid] - ref_x[valid])^2 + (node_y[valid] - ref_y[valid])^2)
    }
    out
  }

  coordinate_column <- function(df, primary, fallback) {
    if (primary %in% names(df)) return(df[[primary]])
    if (fallback %in% names(df)) return(df[[fallback]])
    rep(NA_real_, nrow(df))
  }

  apply_override <- function(node_idx, override_idx, basis) {
    network_nodes$f_pathogen_direct[node_idx] <<- override_values[override_idx]
    network_nodes$f_pathogen_direct_basis[node_idx] <<- basis
    if ("place" %in% names(overrides)) {
      network_nodes$f_pathogen_direct_place[node_idx] <<- as.character(overrides$place[override_idx])
    }
  }

  if (is.null(overrides) || nrow(overrides) == 0) {
    validate_direct_fraction()
    return(network_nodes)
  }
  if (!all(c("source_id", "f_pathogen_direct") %in% names(overrides))) {
    stop("pathogen_direct_fraction_overrides must contain `source_id` and `f_pathogen_direct`.")
  }
  if (!("ID" %in% names(network_nodes))) {
    stop("Network nodes must contain `ID` to apply pathogen direct fraction overrides.")
  }

  override_values <- suppressWarnings(as.numeric(overrides$f_pathogen_direct))
  bad_values <- is.na(override_values) | !is.finite(override_values) |
    override_values < 0 | override_values > 1
  if (any(bad_values)) {
    stop("f_pathogen_direct override values must be finite fractions from 0 to 1.")
  }

  match_idx <- match(as.character(overrides$source_id), as.character(network_nodes$ID))
  found <- !is.na(match_idx) & is_agglomeration[match_idx]
  if (any(found)) {
    found_rows <- which(found)
    for (row_idx in found_rows) {
      apply_override(match_idx[row_idx], row_idx, "source_id")
    }
  }

  found_by_coordinate <- rep(FALSE, nrow(overrides))
  can_match_by_coordinate <- all(c("x", "y", "match_radius_m") %in% names(overrides)) &&
    any(!found)
  if (can_match_by_coordinate) {
    node_x <- coordinate_column(network_nodes, "x", "X")
    node_y <- coordinate_column(network_nodes, "y", "Y")
    ref_x <- suppressWarnings(as.numeric(overrides$x))
    ref_y <- suppressWarnings(as.numeric(overrides$y))
    match_radius <- suppressWarnings(as.numeric(overrides$match_radius_m))

    candidate_nodes <- which(is_agglomeration & is.finite(as.numeric(node_x)) & is.finite(as.numeric(node_y)))
    for (row_idx in which(!found)) {
      if (!is.finite(ref_x[row_idx]) || !is.finite(ref_y[row_idx]) ||
          !is.finite(match_radius[row_idx]) || match_radius[row_idx] < 0) {
        next
      }
      distances <- override_distance_m(
        node_x[candidate_nodes],
        node_y[candidate_nodes],
        rep(ref_x[row_idx], length(candidate_nodes)),
        rep(ref_y[row_idx], length(candidate_nodes))
      )
      matched_nodes <- candidate_nodes[is.finite(distances) & distances <= match_radius[row_idx]]
      if (length(matched_nodes) > 0) {
        for (node_idx in matched_nodes) {
          apply_override(node_idx, row_idx, "coordinate_radius")
        }
        found_by_coordinate[row_idx] <- TRUE
      }
    }
  }

  missing_ids <- as.character(overrides$source_id[!found & !found_by_coordinate])
  if (length(missing_ids) > 0) {
    message("Pathogen direct fraction overrides not matched to network IDs or coordinates: ",
            paste(missing_ids, collapse = ", "))
  }

  validate_direct_fraction()
  network_nodes
}

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

  network_nodes <- ApplyPathogenDirectFractionOverrides(network_nodes)

  # Initialise emission columns
  network_nodes$E_in <- rep(0, nrow(network_nodes))
  network_nodes$f_rem_WWTP <- NA_real_
  network_nodes$pathogen_profile_id <- pathogen_params$pathogen_profile_id %||% NA_character_
  network_nodes$pathogen_profile_set <- pathogen_params$pathogen_profile_set %||% NA_character_
  network_nodes$pathogen_profile_label <- pathogen_params$pathogen_profile_label %||% NA_character_
  network_nodes$pathogen_profile_region <- pathogen_params$pathogen_profile_region %||% NA_character_
  network_nodes$pathogen_profile_country <- pathogen_params$pathogen_profile_country %||% NA_character_
  network_nodes$pathogen_profile_confidence <- pathogen_params$pathogen_profile_confidence %||% NA_character_
  network_nodes$pathogen_prevalence_rate <- prev_rate
  network_nodes$pathogen_excretion_rate <- exc_rate
  network_nodes$pathogen_prevalence_source <- pathogen_params$pathogen_profile_prevalence_source_short %||% NA_character_
  network_nodes$pathogen_excretion_source <- pathogen_params$pathogen_profile_excretion_source_short %||% NA_character_
  network_nodes$pathogen_wwtp_source <- pathogen_params$pathogen_profile_wwtp_source_short %||% NA_character_
  network_nodes$pathogen_reference_url <- pathogen_params$pathogen_profile_prevalence_source_url %||% NA_character_

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
  # local_pop: local population assigned to this agglomeration source.
  # prevalence_rate: fraction of people assumed infected/shedding.
  # excretion_rate: pathogen units shed per infected person per year.
  # f_pathogen_direct: fraction of the local pathogen load assumed to reach
  #   the canal/river directly. This is pathogen-only. It is not the same
  #   variable as f_direct, which is used by the chemical/sanitation model.
  # E_in: pathogen load entering the source node before downstream transport.
  #
  # Akuse and Asutsuare use lower f_pathogen_direct values in the Volta
  # pathogen scenario config because these towns have more infrastructure
  # than smaller settlements. Some households, schools, clinics, health
  # centres, and public facilities may use septic tanks or pit latrines.
  # The value 0.5 is a simple scenario assumption. It is not a measured
  # sanitation fraction.
  # TODO(DIFFUSE-EMISSION): multiply by f_diff * f_runoff here
  aggl_idx <- which(tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations"))
  if (length(aggl_idx) > 0) {
    aggl_pop <- resolve_source_population(network_nodes, aggl_idx, total_pop)
    direct_fraction <- network_nodes$f_pathogen_direct[aggl_idx]
    network_nodes$E_in[aggl_idx] <- aggl_pop * prev_rate * exc_rate * direct_fraction
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
