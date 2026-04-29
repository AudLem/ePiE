VisualizeConcentrations <- function(simulation_results,
                                    run_output_dir,
                                    input_paths = list(),
                                    target_substance = NULL,
                                    basin_id = NULL,
                                    substance_type = "chemical",
                                    pathogen_name = NULL,
                                    pathogen_units = NULL,
                                    open_map_output_in_browser = TRUE,
                                    show_interactive_map_preview = FALSE) {
  message("--- Step 6: Generating Simulation Visualizations ---")

  plots_dir <- file.path(run_output_dir, "plots")
  if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

  spec <- BuildConcentrationMapSpec(
    simulation_results = simulation_results,
    run_output_dir = run_output_dir,
    input_paths = input_paths,
    target_substance = target_substance,
    basin_id = basin_id,
    substance_type = substance_type,
    pathogen_name = pathogen_name,
    pathogen_units = pathogen_units
  )

  leaflet_path <- RenderLeafletConcentrationMap(
    spec = spec,
    plots_dir = plots_dir
  )

  RenderTmapConcentrationMap(
    spec = spec,
    plots_dir = plots_dir
  )

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive concentration map saved to:\n")
  cat(">>> ", normalizePath(leaflet_path), "\n")

  invisible(spec)
}
