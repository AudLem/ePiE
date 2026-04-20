#!/usr/bin/env Rscript
library(ePiE)

# Run a single scenario
run_single_scenario <- function(s) {
  tryCatch({
    message(paste("Running scenario:", s$name))

    # Load scenario configuration
    cfg <- LoadScenarioConfig(s$config_name, "Inputs", "Outputs")

    if (s$type == "network") {
      # Build network
      state <- BuildNetworkPipeline(cfg, diagnostics = "full")
      return(paste("Success:", s$name, "- network built"))
    } else if (s$type == "simulation") {
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

      state$points <- read.csv(file.path("Outputs", s$network_dir, "pts.csv"))
      state$hl <- read.csv(file.path("Outputs", s$network_dir, "HL.csv"))

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
      results <- RunSimulationPipeline(state, substance)

      # Save results
      if (!is.null(results$results)) {
        sim_results <- if (!is.null(results$results$pts)) results$results$pts else results$results
        write.csv(sim_results, file.path(cfg$run_output_dir, "simulation_results.csv"), row.names = FALSE)

        # Generate visualizations
        if (s$type == "pathogen") {
          VisualizeConcentrations(
            simulation_results = sim_results,
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
    return(paste("Error in", s$name, ":", e$message))
  })
}

# Scenario list with proper configuration
scenarios <- list(
  # Bega scenarios
  list(name="bega_network", type="network", config_name="BegaNetwork"),
  list(name="bega_ibuprofen", type="simulation", config_name="BegaChemicalIbuprofen", network_dir="bega"),
  list(name="bega_campylobacter", type="pathogen", config_name="BegaPathogenCampylobacter", network_dir="bega"),

  # Volta Wet scenarios
  list(name="volta_wet_network", type="network", config_name="VoltaWetNetwork"),
  list(name="volta_wet_ibuprofen", type="simulation", config_name="VoltaWetChemicalIbuprofen", network_dir="volta_wet"),
  list(name="volta_wet_campylobacter", type="pathogen", config_name="VoltaWetPathogenCampylobacter", network_dir="volta_wet"),
  list(name="volta_wet_crypto", type="pathogen", config_name="VoltaWetPathogenCrypto", network_dir="volta_wet"),

  # Volta Dry scenarios
  list(name="volta_dry_network", type="network", config_name="VoltaDryNetwork"),
  list(name="volta_dry_ibuprofen", type="simulation", config_name="VoltaDryChemicalIbuprofen", network_dir="volta_dry"),
  list(name="volta_dry_campylobacter", type="pathogen", config_name="VoltaDryPathogenCampylobacter", network_dir="volta_dry"),
  list(name="volta_dry_crypto", type="pathogen", config_name="VoltaDryPathogenCrypto", network_dir="volta_dry")
)

# Run scenarios sequentially for better error tracking
print("Running all scenarios sequentially...")
for (s in scenarios) {
  result <- run_single_scenario(s)
  print(result)
}

print("\nAll scenarios completed.")
