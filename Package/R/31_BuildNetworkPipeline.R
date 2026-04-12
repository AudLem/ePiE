#' Build Network Pipeline
#'
#' Orchestrates the full 10-step network generation process: loads spatial inputs,
#' processes rivers, lakes, population, and WWTPs, builds topology, integrates
#' sources, and saves artifacts to disk.
#'
#' @param cfg Named list. Configuration produced by \code{LoadScenarioConfig}.
#' @return A named list with \code{points} (sf nodes) and \code{HL_basin} (sf lakes).
#' @export
BuildNetworkPipeline <- function(cfg) {
  message("====================================================")
  message("STARTING NETWORK GENERATION FOR: ", cfg$basin_id)
  message("Output Directory: ", cfg$run_output_dir)
  message("====================================================")

  step_01 <- LoadNetworkInputs(
    run_output_dir = cfg$run_output_dir,
    flow_dir_path = cfg$flow_dir_path,
    river_shp_path = cfg$river_shp_path,
    reference_river_shp_path = cfg$reference_river_shp_path,
    basin_shp_path = cfg$basin_shp_path,
    lakes_shp_path = cfg$lakes_shp_path,
    is_dry_season = isTRUE(cfg$is_dry_season),
    canal_shp_path = cfg$canal_shp_path,
    enable_canals = isTRUE(cfg$enable_canals)
  )
  state <- step_01

  step_02b <- PrepareCanalLayers(state, cfg)
  state[names(step_02b)] <- step_02b

  step_03 <- ProcessRiverGeometry(
    hydro_sheds_rivers = state$hydro_sheds_rivers,
    reference_hydro_sheds_rivers = state$reference_hydro_sheds_rivers,
    Basin = state$Basin,
    Basin_buff = state$Basin_buff
  )
  state[names(step_03)] <- step_03

  step_04 <- ProcessLakeGeometries(
    dir = state$dir,
    HL = state$HL,
    Basin = state$Basin,
    Basin_buff_r = state$Basin_buff_r,
    enable_lakes = if (!is.null(cfg$enable_lakes)) cfg$enable_lakes else TRUE
  )
  state[names(step_04)] <- step_04

  step_05 <- ExtractPopulationSources(
    Basin = state$Basin,
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    HL_basin = state$HL_basin,
    pop_raster_path = cfg$pop_raster_path
  )
  state[names(step_05)] <- step_05

  step_06 <- MapWWTPLocations(
    Basin = state$Basin,
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    agglomeration_points = state$agglomeration_points,
    river_segments_sf = state$river_segments_sf,
    wwtp_csv_path = cfg$wwtp_csv_path
  )
  state[names(step_06)] <- step_06

  step_07 <- BuildNetworkTopology(
    hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
    dir = state$dir,
    Basin = state$Basin
  )
  state[names(step_07)] <- step_07

  withCallingHandlers(
    {
      step_08 <- IntegratePointsAndLines(
        agglomeration_points = state$agglomeration_points,
        lines = state$lines,
        points = state$points
      )
      state[names(step_08)] <- step_08
    },
    warning = function(w) {
      if (grepl("NAs introduced by coercion", w$message)) invokeRestart("muffleWarning")
    }
  )

  step_08b <- ConnectLakesToNetwork(
    points = state$points,
    HL_basin = state$HL_basin
  )
  state[names(step_08b)] <- step_08b

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

  message("====================================================")
  message("NETWORK GENERATION COMPLETED SUCCESSFULLY")
  message("====================================================")

  invisible(state)
}
