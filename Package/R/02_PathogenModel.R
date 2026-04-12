AssignPathogenEmissions <- function(network_nodes, pathogen_params) {
  total_pop <- pathogen_params$total_population
  prev_rate <- pathogen_params$prevalence_rate
  exc_rate  <- pathogen_params$excretion_rate

  n_infected <- total_pop * prev_rate
  total_oocysts <- n_infected * exc_rate

  network_nodes$E_in <- rep(0, nrow(network_nodes))
  network_nodes$f_rem_WWTP <- NA_real_

  wwtp_idx <- which(network_nodes$Pt_type == "WWTP")
  network_nodes$E_in[wwtp_idx] <- total_oocysts * network_nodes$f_STP[wwtp_idx]

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

  aggl_idx <- which(tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations"))
  if (length(aggl_idx) > 0) {
    if ("total_population" %in% names(network_nodes)) {
      network_nodes$E_in[aggl_idx] <- network_nodes$total_population[aggl_idx] * prev_rate * exc_rate
    }
    network_nodes$f_STP[aggl_idx] <- 0
  }

  network_nodes$E_w <- ifelse(
    network_nodes$Pt_type == "WWTP",
    network_nodes$E_in * (1 - ifelse(is.na(network_nodes$f_rem_WWTP), 0, network_nodes$f_rem_WWTP)),
    ifelse(tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations"),
           network_nodes$E_in, 0)
  )

  network_nodes
}

AssignPathogenDecayParameters <- function(network_nodes, lake_nodes, pathogen_params) {
  get_val <- function(df, new_name, old_name, default) {
    if (new_name %in% names(df)) return(df[[new_name]])
    if (old_name %in% names(df)) return(df[[old_name]])
    rep(default, nrow(df))
  }

  temp_w <- get_val(network_nodes, "water_temperature", "T_sw", 285)
  solar_r <- get_val(network_nodes, "solar_radiation", "AR", 0)
  depth <- get_val(network_nodes, "river_depth", "H", 0.001)
  doc <- get_val(network_nodes, "doc_concentration", "C_DOC", 0.005e-3)

  network_nodes$K_T <- calc_temp_decay(pathogen_params$decay_rate_base, temp_w - 273.15, pathogen_params$temp_corr_factor)
  network_nodes$ke  <- calc_light_attenuation(doc, pathogen_params$doc_attenuation)
  network_nodes$K_R <- calc_solar_decay(solar_r, pathogen_params$solar_rad_factor, network_nodes$ke, depth)
  network_nodes$K_S <- calc_sedimentation_decay(pathogen_params$settling_velocity, depth)
  network_nodes$k   <- calc_total_dissipation_rate(network_nodes$K_T, network_nodes$K_R, network_nodes$K_S)

  if (!is.null(lake_nodes) && nrow(lake_nodes) != 0) {
    temp_l <- get_val(lake_nodes, "water_temperature", "T_sw", 285)
    solar_l <- get_val(lake_nodes, "solar_radiation", "AR", 0)
    depth_l <- get_val(lake_nodes, "river_depth", "H_av", 0.001)
    doc_l <- get_val(lake_nodes, "doc_concentration", "C_DOC", 0.005e-3)

    lake_nodes$K_T <- calc_temp_decay(pathogen_params$decay_rate_base, temp_l - 273.15, pathogen_params$temp_corr_factor)
    lake_nodes$ke  <- calc_light_attenuation(doc_l, pathogen_params$doc_attenuation)
    lake_nodes$K_R <- calc_solar_decay(solar_l, pathogen_params$solar_rad_factor, lake_nodes$ke, depth_l)
    lake_nodes$K_S <- calc_sedimentation_decay(pathogen_params$settling_velocity, depth_l)
    lake_nodes$k   <- calc_total_dissipation_rate(lake_nodes$K_T, lake_nodes$K_R, lake_nodes$K_S)
  }

  list(network_nodes = network_nodes, lake_nodes = lake_nodes)
}
