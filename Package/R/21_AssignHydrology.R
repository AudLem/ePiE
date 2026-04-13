#' Assign Hydrology to Network
#'
#' Extracts river discharge values from flow rasters onto each network node,
#' applies manual overrides, and falls back to alternative rasters when needed.
#' Optionally scales discharge for dry-season simulations.
#'
#' @param network_nodes data.frame. Normalised network nodes (from \code{NormalizeScenarioState}).
#' @param input_paths Named list. Must contain \code{flow_raster} path.
#' @param dataDir Character. Root data directory for fallback rasters.
#' @param basin_id Character. Basin identifier.
#' @param prefer_highres_flow Logical. Prefer 1km FLO1K rasters over 30min NetCDF.
#' @param is_dry_season Logical. Scale discharge by 0.1 for dry-season runs.
#' @return A named list with \code{network_nodes} (enriched with \code{river_discharge} and \code{Q}).
#' @export
AssignHydrology <- function(network_nodes,
                               input_paths,
                               dataDir,
                               basin_id,
                               prefer_highres_flow = FALSE,
                               is_dry_season = FALSE,
                               network_source = "hydrosheds",
                               discharge_gpkg_path = NULL,
                               simulation_year = NULL,
                               simulation_months = NULL,
                               discharge_aggregation = "mean") {
  message("--- Step 3: Hydrology Assignment ---")

  network_nodes$basin_id <- basin_id

  network_nodes$river_discharge <- NULL
  basin_list <- list(pts = network_nodes)

  if (network_source == "geoglows" && !is.null(discharge_gpkg_path)) {
    message("  Using GeoGLOWS v2 per-segment discharge (", discharge_aggregation, ")")
    basin_list <- AddFlowToBasinData(
      basin_data = basin_list,
      flow_rast = NULL,
      discharge_gpkg_path = discharge_gpkg_path,
      simulation_year = simulation_year,
      simulation_months = simulation_months,
      discharge_aggregation = discharge_aggregation,
      network_source = "geoglows"
    )
  } else {
    selected_flow_data <- LoadPreferredFlowRaster(
      input_paths = input_paths,
      dataDir = dataDir,
      prefer_highres_flow = prefer_highres_flow,
      is_dry_season = is_dry_season
    )
    basin_list <- AddFlowToBasinData(basin_data = basin_list, flow_rast = selected_flow_data$flow)
  }

  network_nodes <- basin_list$pts

  network_nodes$river_discharge <- network_nodes$Q
  network_nodes <- ApplyManualDischargeOverrides(network_nodes)

  non_manual_idx <- if ("manual_Q" %in% names(network_nodes)) {
    which(is.na(network_nodes$manual_Q))
  } else {
    seq_along(network_nodes$river_discharge)
  }
  needs_flow_fallback <- length(non_manual_idx) > 0 &&
    all(is.na(network_nodes$river_discharge[non_manual_idx]) |
          network_nodes$river_discharge[non_manual_idx] == 0)

  if (needs_flow_fallback) {
    message("Warning: Primary flow extraction failed. Attempting fallback to NetCDF...")
    fallback_nc <- file.path(dataDir, "baselines", "environmental", "FLO1K.30min.ts.1960.2015.qav.nc")
    if (file.exists(fallback_nc)) {
      network_nodes$river_discharge <- NULL
      basin_list <- list(pts = network_nodes)
      basin_list <- AddFlowToBasinData(basin_data = basin_list, flow_rast = terra::rast(fallback_nc)[[1]])
      network_nodes <- basin_list$pts
      network_nodes$river_discharge <- network_nodes$Q
      network_nodes <- ApplyManualDischargeOverrides(network_nodes)
    }
  }

  network_nodes$river_discharge[is.na(network_nodes$river_discharge) | network_nodes$river_discharge == 0] <- 0.001

  flow_source <- if (network_source == "geoglows") "geoglows" else selected_flow_data$flow_source
  if (prefer_highres_flow && is_dry_season && flow_source != "qmi") {
    message("  Scaling extracted flow by 0.1 for dry season simulation...")
    scale_idx <- if ("manual_Q" %in% names(network_nodes)) which(is.na(network_nodes$manual_Q)) else seq_along(network_nodes$river_discharge)
    network_nodes$river_discharge[scale_idx] <- network_nodes$river_discharge[scale_idx] * 0.1
  }

  network_nodes$Q <- network_nodes$river_discharge

  list(network_nodes = network_nodes)
}

LoadPreferredFlowRaster <- function(input_paths, dataDir, prefer_highres_flow, is_dry_season) {
  base_env_dir <- file.path(dataDir, "baselines", "environmental")
  qmi_tif <- file.path(base_env_dir, "FLO1k.lt.2000.2015.qmi.tif")
  qav_tif <- file.path(base_env_dir, "FLO1k.lt.2000.2015.qav.tif")

  if (prefer_highres_flow && is_dry_season && file.exists(qmi_tif)) {
    message("Dry season: Using high-resolution (1km) minimum flow raster (qmi.tif)")
    return(list(flow = terra::rast(qmi_tif), flow_source = "qmi"))
  }

  if (prefer_highres_flow && file.exists(qav_tif)) {
    message("Using high-resolution (1km) average flow raster (qav.tif)")
    return(list(flow = terra::rast(qav_tif), flow_source = "qav"))
  }

  message("Using configured flow raster: ", input_paths$flow_raster)
  list(flow = terra::rast(input_paths$flow_raster)[[1]], flow_source = "configured")
}

ApplyManualDischargeOverrides <- function(network_nodes) {
  if (!("manual_Q" %in% names(network_nodes))) return(network_nodes)
  manual_idx <- which(!is.na(network_nodes$manual_Q))
  if (length(manual_idx) > 0) {
    message(">>> Applying manual Q override to ", length(manual_idx), " nodes.")
    network_nodes$river_discharge[manual_idx] <- network_nodes$manual_Q[manual_idx]
  }
  network_nodes
}
