#' Refactor RunSimulationPipeline
#'
#' Orchestrates the full simulation process, using an accumulating state list
#' to ensure consistency and enable checkpointing.
#'
#' @param state Pipeline state list from BuildNetworkPipeline.
#' @param substance Character. Substance to simulate.
#' @param checkpoint_dir Character. Optional directory to save simulation states.
#' @export
RunSimulationPipeline <- function(state, substance, checkpoint_dir = NULL, verbose = FALSE, cpp = FALSE) {
  message("--- Running Simulation Pipeline for: ", substance, " ---")
  
  sim_state <- state
  
  if (!is.null(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  # Accept lake data under any of these field names
  if (is.null(sim_state$HL_basin)) {
    hl_fallback <- if (!is.null(sim_state$HLL_basin)) sim_state$HLL_basin else sim_state$hl
    sim_state$HL_basin <- hl_fallback
  }

  # Accept points from state, or try fallback names
  if (is.null(sim_state$points)) {
    pts_fallback <- if (!is.null(sim_state$normalized_network_nodes)) sim_state$normalized_network_nodes else sim_state$pts
    sim_state$points <- pts_fallback
  }

  # Accept basin_id from state, or try to read it from points
  if (is.null(sim_state$basin_id) && !is.null(sim_state$points) && ("basin_id" %in% names(sim_state$points))) {
    sim_state$basin_id <- sim_state$points$basin_id[1]
  }
  
  norm <- NormalizeScenarioState(
    raw_network_nodes = sim_state$points,
    lake_nodes = sim_state$HL_basin,
    study_country = sim_state$study_country,
    basin_id = sim_state$basin_id
  )
  sim_state$points <- norm$normalized_network_nodes
  sim_state$HL_basin <- norm$lake_nodes
  sim_state$hl <- norm$lake_nodes
  
  flow_result <- AddFlowToBasinData(
    basin_data = list(pts = sim_state$points),
    flow_rast = if (!is.null(sim_state$input_paths$flow_raster) && file.exists(sim_state$input_paths$flow_raster)) {
      terra::rast(sim_state$input_paths$flow_raster)
    } else {
      NULL
    },
    discharge_gpkg_path = sim_state$discharge_gpkg_path,
    simulation_year = sim_state$simulation_year,
    simulation_months = sim_state$simulation_months,
    discharge_aggregation = if (!is.null(sim_state$discharge_aggregation)) sim_state$discharge_aggregation else "mean",
    network_source = if (!is.null(sim_state$network_source)) sim_state$network_source else "hydrosheds"
  )
  sim_state$points <- flow_result$pts
  
  freq_pts <- Set_upstream_points_v2(sim_state$points)
  sim_state$points <- freq_pts
  
  sim_state <- InitializeSubstance(sim_state, substance)
  if (!is.null(checkpoint_dir)) saveRDS(sim_state, file.path(checkpoint_dir, "sim_init.rds"))
  
  is_pathogen <- !is.null(sim_state$pathogen_params)
  if (is_pathogen) {
    sim_state$results <- ComputeEnvConcentrations(
      basin_data = sim_state,
      chem = NULL,
      cons = NULL,
      verbose = verbose,
      cpp = cpp,
      substance_type = "pathogen",
      pathogen_params = sim_state$pathogen_params
    )
    } else {
    sim_state$results <- ComputeEnvConcentrations(
      basin_data = sim_state,
      chem = sim_state$chem,
      cons = sim_state$cons,
      verbose = verbose,
      cpp = cpp,
      substance_type = "chemical"
    )
  }

  if (!is.null(checkpoint_dir)) saveRDS(sim_state, file.path(checkpoint_dir, "sim_results.rds"))
  
  # Visualization
  if (!is.null(sim_state$run_output_dir)) {
    tryCatch(
      {
        is_pathogen <- !is.null(sim_state$pathogen_params)
        VisualizeConcentrations(
          simulation_results = sim_state$results$pts,
          run_output_dir = sim_state$run_output_dir,
          input_paths = sim_state$input_paths,
          target_substance = substance,
          basin_id = sim_state$basin_id,
          substance_type = if (is_pathogen) "pathogen" else "chemical",
          pathogen_name = if (is_pathogen) substance else NULL,
          open_map_output_in_browser = FALSE
        )
      },
      error = function(e) {
        message("Note: visualization skipped: ", e$message)
      }
    )
  }
  
  message(">>> Simulation complete.")
  return(sim_state)
}
