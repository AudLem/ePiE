#' Build Network Pipeline
#'
#' Orchestrates the full 10-step network generation process: loads spatial inputs,
#' processes rivers, lakes, population, and WWTPs, builds topology, integrates
#' sources, and saves artifacts to disk.
#'
#' @param cfg Named list. Configuration produced by \code{LoadScenarioConfig}.
#' @param checkpoint_dir Character. Optional directory to save intermediate states.
#' @param stop_after_step Character. Optional name of step to stop after.
#' @param diagnostics Character. Optional diagnostic level: "none", "light", "maps", or "full".
#' @param interactive_diagnostics Logical. If \code{TRUE}, prints and displays step-01 diagnostics, then pauses in interactive sessions.
#' @return A named list with \code{points} (sf nodes) and \code{HL_basin} (sf lakes).
#' @export
BuildNetworkPipeline <- function(cfg,
                                 checkpoint_dir = NULL,
                                 stop_after_step = NULL,
                                 diagnostics = NULL,
                                 interactive_diagnostics = FALSE) {
  message("====================================================")
  message("STARTING NETWORK GENERATION FOR: ", cfg$basin_id)
  message("Output Directory: ", cfg$run_output_dir)
  message("Diagnostics: ", if (is.null(diagnostics)) "off" else diagnostics)
  message("====================================================")
  
  diag_level <- DiagLevel(diagnostics, default = "none")

  if (!is.null(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  diag_dir <- if (!is.null(diagnostics) && diag_level != "none") {
    file.path(cfg$run_output_dir, "plots", "diagnostics")
  } else {
    NULL
  }
  
  save_checkpoint <- function(step_name, state) {
    if (!is.null(checkpoint_dir)) {
      checkpoint_file <- file.path(checkpoint_dir, paste0(step_name, ".rds"))
      saveRDS(state, checkpoint_file)
      message(">>> Checkpoint saved: ", checkpoint_file)
      PrintCheckpointSummary(state)
    }
    if (!is.null(stop_after_step) && step_name == stop_after_step) {
      message(">>> Stopping after step: ", step_name)
      return(TRUE)
    }
    FALSE
  }

  step_01 <- LoadNetworkInputs(
    run_output_dir = cfg$run_output_dir,
    flow_dir_path = cfg$flow_dir_path,
    river_shp_path = cfg$river_shp_path,
    reference_river_shp_path = cfg$reference_river_shp_path,
    basin_shp_path = cfg$basin_shp_path,
    lakes_shp_path = cfg$lakes_shp_path,
    is_dry_season = isTRUE(cfg$is_dry_season),
    canal_shp_path = cfg$canal_shp_path,
    enable_canals = isTRUE(cfg$enable_canals),
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
  state <- step_01
  state$basin_id <- cfg$basin_id
  state$study_country <- cfg$study_country
  state$country_population <- cfg$country_population
  state$run_output_dir <- cfg$run_output_dir
  state$data_root <- cfg$dataDir
  state$is_dry_season <- isTRUE(cfg$is_dry_season)
  state$network_source <- if (!is.null(cfg$network_source)) cfg$network_source else "hydrosheds"
  state$discharge_gpkg_path <- cfg$discharge_gpkg_path
  state$simulation_year <- cfg$simulation_year
  state$simulation_months <- cfg$simulation_months
  state$discharge_aggregation <- cfg$discharge_aggregation
  state$prefer_highres_flow <- isTRUE(cfg$prefer_highres_flow)
  state$flow_source <- if (!is.null(cfg$flow_source)) cfg$flow_source else NULL
  state$diagnostics_level <- diag_level
  state$diagnostics_dir <- diag_dir
  if (!is.null(diag_dir) && diag_level %in% c("maps", "full")) {
    SaveStep01InputDiagnostics(state, diag_dir)
  }
  if (isTRUE(interactive_diagnostics)) {
    ShowInteractiveStep01Diagnostics(state)
  }
  if (save_checkpoint("01_load_inputs", state)) return(invisible(state))

  step_02b <- PrepareCanalLayers(state, cfg, diagnostics_level = diag_level, diagnostics_dir = diag_dir)
  state[names(step_02b)] <- step_02b
  if (save_checkpoint("02b_prepare_canals", state)) return(invisible(state))

  step_03 <- ProcessRiverGeometry(
    hydro_sheds_rivers = state$hydro_sheds_rivers,
    reference_hydro_sheds_rivers = state$reference_hydro_sheds_rivers,
    Basin = state$Basin,
    Basin_buff = state$Basin_buff,
    cfg = cfg,
    river_simplification_tolerance = if (!is.null(cfg$simplification$river_tolerance)) cfg$simplification$river_tolerance else 100,
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
  state[names(step_03)] <- step_03
  if (save_checkpoint("03_process_river_geometry", state)) return(invisible(state))

  step_04 <- ProcessLakeGeometries(
    dir = state$dir,
    HL = state$HL,
    Basin = state$Basin,
    Basin_buff_r = state$Basin_buff_r,
    enable_lakes = if (!is.null(cfg$enable_lakes)) cfg$enable_lakes else TRUE,
    lake_simplification_tolerance = if (!is.null(cfg$simplification$lake_tolerance)) cfg$simplification$lake_tolerance else 0,
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
  state[names(step_04)] <- step_04
  if (save_checkpoint("04_process_lake_geometries", state)) return(invisible(state))

  step_05 <- ExtractPopulationSources(
    Basin = state$Basin,
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    HL_basin = state$HL_basin,
    pop_raster_path = cfg$pop_raster_path,
    study_country = cfg$study_country,
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
  state[names(step_05)] <- step_05
  if (save_checkpoint("05_extract_population", state)) return(invisible(state))

  step_06 <- MapWWTPLocations(
    Basin = state$Basin,
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    agglomeration_points = state$agglomeration_points,
    # Let Step 6 build a validated segment snap network from basin rivers.
    river_segments_sf = NULL,
    wwtp_csv_path = cfg$wwtp_csv_path,
    hydrowaste_raw = if (!is.null(cfg$hydrowaste_csv_path) && file.exists(cfg$hydrowaste_csv_path)) {
      message("Loading HydroWASTE points from: ", cfg$hydrowaste_csv_path)
      read.csv(cfg$hydrowaste_csv_path, stringsAsFactors = FALSE)
    } else NULL,
    study_country = cfg$study_country,
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
  state[names(step_06)] <- step_06
  if (save_checkpoint("06_map_wwtp", state)) return(invisible(state))

  step_07 <- BuildNetworkTopology(
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    dir = state$dir,
    Basin = state$Basin,
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
  state[names(step_07)] <- step_07
  if (save_checkpoint("07_build_topology", state)) return(invisible(state))

  withCallingHandlers(
    {
  step_08 <- IntegratePointsAndLines(
    agglomeration_points = state$agglomeration_points,
    lines = state$lines,
    points = state$points,
    diagnostics_level = diag_level,
    diagnostics_dir = diag_dir
  )
      state[names(step_08)] <- step_08
    },
    warning = function(w) {
      if (grepl("NAs introduced by coercion", w$message)) invokeRestart("muffleWarning")
    }
  )
  state$points <- AnnotateCanalTopology(state$points, state$lines, state$Basin)
  if (save_checkpoint("08_integrate_points", state)) return(invisible(state))

  step_08b <- ConnectLakesToNetwork(
    points = state$points,
    HL_basin = state$HL_basin
  )
  state[names(step_08b)] <- step_08b
  state$points <- AnnotateDisplayJunctions(state$points)
  if (save_checkpoint("08b_connect_lakes", state)) return(invisible(state))

  step_09 <- SaveNetworkArtifacts(
    points = state$points,
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    HL_basin = state$HL_basin,
    shp_dir = state$shp_dir,
    run_output_dir = cfg$run_output_dir,
    slope_raster_path = cfg$slope_raster_path,
    temp_raster_path = cfg$temp_raster_path,
    wind_raster_path = cfg$wind_raster_path
  )
  state[names(step_09)] <- step_09
  if (save_checkpoint("09_save_artifacts", state)) return(invisible(state))

  tryCatch(
    {
      step_10 <- VisualizeNetwork(
        Basin = state$Basin,
        hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
        points = state$points,
        HL_basin = state$HL_basin,
        run_output_dir = cfg$run_output_dir,
        basin_id = cfg$basin_id,
        agglomeration_points = state$agglomeration_points,
        natural_rivers = state$natural_rivers_processed,
        artificial_canals = state$artificial_canals,
        open_map_output_in_browser = FALSE
      )
    },
    error = function(e) {
      message("Note: network visualization skipped: ", e$message)
      tryCatch(
        {
          GenerateNetworkMapFallback(
            Basin = state$Basin,
            hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
            points = state$points,
            HL_basin = state$HL_basin,
            run_output_dir = cfg$run_output_dir,
            basin_id = cfg$basin_id
          )
        },
        error = function(e2) {
          message("Note: fallback network visualization also failed: ", e2$message)
        }
      )
    }
  )
  if (save_checkpoint("10_visualize_network", state)) return(invisible(state))

  message("====================================================")
  message("NETWORK GENERATION COMPLETED SUCCESSFULLY")
  message("====================================================")

  invisible(state)
}
