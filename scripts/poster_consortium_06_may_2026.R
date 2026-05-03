#' Poster Consortium (06 May 2026) Maps Preparation
#'
#' This script runs all pathogen scenarios for Bega and Volta Wet basins
#' to generate interactive HTML maps for use in the consortium poster.
#'
#' Maps will be located in: Outputs/[scenario_dir]/plots/concentration_map.html

if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all("Package", quiet = TRUE)
} else {
  library(ePiE)
}

data_root <- "Inputs"
output_root <- "Outputs"

# Define the presentation scenarios
target_scenarios <- list(
  # Bega Pathogens
  "BegaPathogenCrypto",
  "BegaPathogenCampylobacter",
  "BegaPathogenRotavirus",
  "BegaPathogenGiardia",
  
  # Volta Wet Pathogens (Standard)
  "VoltaWetPathogenCrypto",
  "VoltaWetPathogenCampylobacter",
  "VoltaWetPathogenRotavirus",
  "VoltaWetPathogenGiardia"
)

# Function to run and report
run_poster_scenario <- function(config_name) {
  message("\n====================================================")
  message("PROCESSING FOR POSTER: ", config_name)
  message("====================================================")
  
  tryCatch({
    cfg <- LoadScenarioConfig(config_name, data_root, output_root)
    
    # 1. Build or Load Network
    # Presentation maps require a valid network state. 
    # BuildNetworkPipeline handles the dependency check automatically.
    state <- BuildNetworkPipeline(cfg)
    
    # 2. Run Simulation
    # This generates the concentration_map.html in the plots/ subdirectory
    results <- RunSimulationPipeline(state, cfg$target_substance, cpp = FALSE)
    
    map_path <- file.path(cfg$run_output_dir, "plots", "concentration_map.html")
    if (file.exists(map_path)) {
      message("SUCCESS: Map generated at ", map_path)
    } else {
      message("WARNING: Simulation finished but map not found at ", map_path)
    }
  }, error = function(e) {
    message("ERROR in ", config_name, ": ", e$message)
  })
}

# Execute
for (s in target_scenarios) {
  run_poster_scenario(s)
}

message("\n====================================================")
message("All poster maps processed.")
message("====================================================")
message("To host these for QR codes, copy the contents of the ")
message("'plots/' folders to your web host or GitHub Pages.")
