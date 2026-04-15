#' Refactor RunSimulationPipeline
#'
#' Orchestrates the full simulation process, using an accumulating state list
#' to ensure consistency and enable checkpointing.
#'
#' @param state Pipeline state list from BuildNetworkPipeline.
#' @param substance Character. Substance to simulate.
#' @param checkpoint_dir Character. Optional directory to save simulation states.
#' @export
RunSimulationPipeline <- function(state, substance, checkpoint_dir = NULL) {
  message("--- Running Simulation Pipeline for: ", substance, " ---")
  
  sim_state <- state
  
  # Ensure output dir exists
  if (!is.null(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  # Step 1: Initialize pathogen/chemical parameters
  sim_state <- InitializeSubstance(sim_state, substance)
  if (!is.null(checkpoint_dir)) saveRDS(sim_state, file.path(checkpoint_dir, "sim_init.rds"))
  
  # Step 2: Compute concentrations
  sim_state$results <- ComputeEnvConcentrations(
    basin_data = sim_state,
    chem = sim_state$chem,
    cons = sim_state$cons,
    verbose = TRUE,
    cpp = TRUE
  )
  if (!is.null(checkpoint_dir)) saveRDS(sim_state, file.path(checkpoint_dir, "sim_results.rds"))
  
  message(">>> Simulation complete.")
  return(sim_state)
}
