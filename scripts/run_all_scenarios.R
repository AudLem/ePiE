#!/usr/bin/env Rscript
script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else "scripts/run_all_scenarios.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
pkg_dir <- file.path(repo_root, "Package")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(pkg_dir)) {
  pkgload::load_all(pkg_dir, quiet = TRUE)
} else {
  library(ePiE)
}

data_root <- "Inputs"
output_root <- "Outputs"

# Run a single scenario
run_single_scenario <- function(s) {
  tryCatch({
    message("Running scenario: ", s$name)

    # Load scenario configuration
    cfg <- LoadScenarioConfig(s$config_name, data_root, output_root)

    if (s$type == "network") {
      # Build network
      state <- BuildNetworkPipeline(cfg, diagnostics = "full")
      return(paste("Success:", s$name, "- network built"))
    } else if (s$type == "simulation" || s$type == "pathogen") {
      # For simulations, we need a pre-built network
      if (is.null(s$network_dir) || !dir.exists(file.path("Outputs", s$network_dir))) {
        return(paste("Error in", s$name, ": Network directory not found:", s$network_dir))
      }

      # Load network state
      state <- list()
      state$input_paths <- cfg$input_paths
      state$study_country <- cfg$study_country
      state$country_population <- cfg$country_population
      state$discharge_gpkg_path <- cfg$discharge_gpkg_path
      state$simulation_year <- cfg$simulation_year
      state$simulation_months <- cfg$simulation_months
      state$discharge_aggregation <- cfg$discharge_aggregation
      state$network_source <- cfg$network_source
      state$basin_id <- cfg$basin_id
      state$run_output_dir <- cfg$run_output_dir
      state$is_dry_season <- isTRUE(cfg$is_dry_season)
      state$data_root <- cfg$dataDir
      state$data_root <- cfg$dataDir

      pts_path <- if (!is.null(cfg$input_paths$pts)) cfg$input_paths$pts else file.path("Outputs", s$network_dir, "pts.csv")
      hl_path <- if (!is.null(cfg$input_paths$hl)) cfg$input_paths$hl else file.path("Outputs", s$network_dir, "HL.csv")

      state$points <- read.csv(pts_path, stringsAsFactors = FALSE)
      state$hl <- read.csv(hl_path, stringsAsFactors = FALSE)
      source_points <- state$points

      # Ensure basin_id is present (needed for Set_upstream_points_v2)
      if (!"basin_id" %in% names(state$points)) {
        state$points$basin_id <- s$network_dir
      }

      # HL_basin is needed by the pipeline (not just hl)
      state$HL_basin <- state$hl

      # Add required columns for pathogens
      if (!"Hylak_id" %in% names(state$points) && "HL_ID_new" %in% names(state$points)) {
        state$points$Hylak_id <- state$points$HL_ID_new
      }
      if (!"Pt_type" %in% names(state$points) && "pt_type" %in% names(state$points)) {
        state$points$Pt_type <- state$points$pt_type
      }

      # Rename columns to match expected format
      if ("pt_type" %in% names(state$points) && !"Pt_type" %in% names(state$points)) {
        names(state$points)[names(state$points) == "pt_type"] <- "Pt_type"
      }
      if ("HL_ID_new" %in% names(state$points) && !"Hylak_id" %in% names(state$points)) {
        names(state$points)[names(state$points) == "HL_ID_new"] <- "Hylak_id"
      }

      # Initialize HL environment parameters
      if (nrow(state$hl) > 0) {
        if (!"T_AIR" %in% names(state$hl)) state$hl$T_AIR <- NA_real_
        if (!"Wind" %in% names(state$hl)) state$hl$Wind <- NA_real_

        for (col in c("T_AIR", "Wind", "slope")) {
          if (col %in% names(state$points) && col %in% names(state$hl)) {
            for (i in 1:nrow(state$hl)) {
              if ("Hylak_id" %in% names(state$hl) && "Hylak_id" %in% names(state$points)) {
                idx <- which(state$points$Hylak_id == state$hl$Hylak_id[i])
                if (length(idx) > 0) {
                  state$hl[[col]][i] <- mean(state$points[[col]][idx], na.rm = TRUE)
                }
              }
            }
          }
        }
      }

      # Fill missing environmental parameters
      state$points$T_AIR[is.na(state$points$T_AIR)] <- 15
      state$points$Wind[is.na(state$points$Wind)] <- 4
      state$hl$T_AIR[is.na(state$hl$T_AIR)] <- 15
      if (!"Wind" %in% names(state$hl)) state$hl$Wind <- 4
      state$hl$Wind[is.na(state$hl$Wind)] <- 4

      # Add Inh column
      state$points$Inh <- ifelse(is.na(state$points$uwwLoadEnt), NA,
                                  ifelse(state$points$uwwLoadEnt != 0, state$points$uwwLoadEnt,
                                         ifelse(state$points$uwwCapacit != 0, state$points$uwwCapacit, 10000)))
      state$points$Inh <- as.numeric(state$points$Inh)

      # Determine substance
      if (s$type == "pathogen") {
        substance <- cfg$target_substance
      } else {
        substance <- cfg$target_substance
      }

      # Run simulation
      results <- RunSimulationPipeline(state, substance, cpp = isTRUE(cfg$use_cpp))

      # Save results
      if (!is.null(results$results)) {
        sim_results <- if (!is.null(results$results$pts)) results$results$pts else results$results
        ordered_results <- sim_results[match(source_points$ID, sim_results$ID), , drop = FALSE]
        simulation_output <- source_points
        metric_cols <- setdiff(names(ordered_results), c("ID", "ID_nxt"))
        for (col in metric_cols) {
          simulation_output[[col]] <- ordered_results[[col]]
        }
        write.csv(simulation_output, file.path(cfg$run_output_dir, "simulation_results.csv"), row.names = FALSE)

        # Generate visualizations
        if (s$type == "pathogen") {
          VisualizeConcentrations(
            simulation_results = simulation_output,
            run_output_dir = cfg$run_output_dir,
            input_paths = cfg$input_paths,
            target_substance = cfg$target_substance,
            basin_id = cfg$basin_id,
            substance_type = "pathogen",
            pathogen_name = cfg$pathogen_name,
            pathogen_units = if (!is.null(cfg$pathogen_units)) cfg$pathogen_units else "CFU/100mL",
            open_map_output_in_browser = FALSE,
            show_interactive_map_preview = FALSE
          )
        }
      }

      return(paste("Success:", s$name))
    }
  }, error = function(e) {
    message(paste("Error in", s$name, ":", e$message))
    return(NULL)
  })
}

# Scenario list with proper configuration
scenarios <- list(
  # Bega scenarios
  list(name="bega_network", type="network", config_name="BegaNetwork"),
  list(name="bega_ibuprofen", type="simulation", config_name="BegaChemicalIbuprofen", network_dir="bega"),
  list(name="bega_campylobacter", type="pathogen", config_name="BegaPathogenCampylobacter", network_dir="bega"),
  list(name="bega_crypto", type="pathogen", config_name="BegaPathogenCrypto", network_dir="bega"),
  list(name="bega_rotavirus", type="pathogen", config_name="BegaPathogenRotavirus", network_dir="bega"),
  list(name="bega_giardia", type="pathogen", config_name="BegaPathogenGiardia", network_dir="bega"),

  # Volta Wet scenarios
  list(name="volta_wet_network", type="network", config_name="VoltaWetNetwork"),
  list(name="volta_wet_ibuprofen", type="simulation", config_name="VoltaWetChemicalIbuprofen", network_dir="volta_wet"),
  list(name="volta_wet_campylobacter", type="pathogen", config_name="VoltaWetPathogenCampylobacter", network_dir="volta_wet"),
  list(name="volta_wet_crypto", type="pathogen", config_name="VoltaWetPathogenCrypto", network_dir="volta_wet"),
  list(name="volta_wet_rotavirus", type="pathogen", config_name="VoltaWetPathogenRotavirus", network_dir="volta_wet"),
  list(name="volta_wet_giardia", type="pathogen", config_name="VoltaWetPathogenGiardia", network_dir="volta_wet"),

  # Volta Dry scenarios
  list(name="volta_dry_network", type="network", config_name="VoltaDryNetwork"),
  list(name="volta_dry_ibuprofen", type="simulation", config_name="VoltaDryChemicalIbuprofen", network_dir="volta_dry"),
  list(name="volta_dry_campylobacter", type="pathogen", config_name="VoltaDryPathogenCampylobacter", network_dir="volta_dry"),
  list(name="volta_dry_crypto", type="pathogen", config_name="VoltaDryPathogenCrypto", network_dir="volta_dry"),
  list(name="volta_dry_rotavirus", type="pathogen", config_name="VoltaDryPathogenRotavirus", network_dir="volta_dry"),
  list(name="volta_dry_giardia", type="pathogen", config_name="VoltaDryPathogenGiardia", network_dir="volta_dry"),

  # Volta GeoGLOWS Wet scenarios
  list(name="volta_geoglows_wet_network", type="network", config_name="VoltaGeoGLOWSNetwork"),
  list(name="volta_geoglows_wet_ibuprofen", type="simulation", config_name="VoltaGeoGLOWSWetChemicalIbuprofen", network_dir="volta_geoglows_wet"),
  list(name="volta_geoglows_wet_campylobacter", type="pathogen", config_name="VoltaGeoGLOWSWetPathogenCampylobacter", network_dir="volta_geoglows_wet"),
  list(name="volta_geoglows_wet_crypto", type="pathogen", config_name="VoltaGeoGLOWSWetPathogenCrypto", network_dir="volta_geoglows_wet"),
  list(name="volta_geoglows_wet_rotavirus", type="pathogen", config_name="VoltaGeoGLOWSWetPathogenRotavirus", network_dir="volta_geoglows_wet"),
  list(name="volta_geoglows_wet_giardia", type="pathogen", config_name="VoltaGeoGLOWSWetPathogenGiardia", network_dir="volta_geoglows_wet"),

  # Volta GeoGLOWS Dry scenarios
  list(name="volta_geoglows_dry_network", type="network", config_name="VoltaGeoGLOWSDryNetwork"),
  list(name="volta_geoglows_dry_ibuprofen", type="simulation", config_name="VoltaGeoGLOWSDryChemicalIbuprofen", network_dir="volta_geoglows_dry"),
  list(name="volta_geoglows_dry_campylobacter", type="pathogen", config_name="VoltaGeoGLOWSDryPathogenCampylobacter", network_dir="volta_geoglows_dry"),
  list(name="volta_geoglows_dry_crypto", type="pathogen", config_name="VoltaGeoGLOWSDryPathogenCrypto", network_dir="volta_geoglows_dry"),
  list(name="volta_geoglows_dry_rotavirus", type="pathogen", config_name="VoltaGeoGLOWSDryPathogenRotavirus", network_dir="volta_geoglows_dry"),
  list(name="volta_geoglows_dry_giardia", type="pathogen", config_name="VoltaGeoGLOWSDryPathogenGiardia", network_dir="volta_geoglows_dry")
)

# Run scenarios sequentially for better error tracking
message("Running all scenarios sequentially...")
for (s in scenarios) {
  result <- run_single_scenario(s)
  message(result)
}

print("\nAll scenarios completed.")
