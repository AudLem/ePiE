#' Assign Hydrology to Network
#'
#' Extracts river discharge values from flow rasters onto each network node,
#' applies canal discharge overrides, and falls back to alternative rasters when needed.
#' Optionally scales discharge for dry-season simulations.
#'
#' @param network_nodes data.frame. Normalised network nodes (from \code{NormalizeScenarioState}).
#' @param input_paths Named list. Must contain \code{flow_raster} path.
#' @param dataDir Character. Root data directory for fallback rasters.
#' @param basin_id Character. Basin identifier.
#' @param prefer_highres_flow Logical. Prefer 1km FLO1K rasters over 30min NetCDF.
#' @param is_dry_season Logical. Scale discharge by 0.1 for dry-season runs.
#' @param flow_source Character or \code{NULL}. Explicit flow source selector.
#'   Supported values: \code{"configured"} and \code{"highres_qav"}.
#'   When \code{NULL}, the function falls back to legacy behavior driven by
#'   \code{prefer_highres_flow}.
#' @return A named list with \code{network_nodes} (enriched with \code{river_discharge} and \code{Q}).
#' @export
AssignHydrology <- function(network_nodes,
                               input_paths,
                               dataDir,
                               basin_id,
                               prefer_highres_flow = FALSE,
                               is_dry_season = FALSE,
                               flow_source = NULL,
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
      is_dry_season = is_dry_season,
      flow_source = flow_source
    )
    basin_list <- AddFlowToBasinData(basin_data = basin_list, flow_rast = selected_flow_data$flow)
  }

  network_nodes <- basin_list$pts

  network_nodes$river_discharge <- network_nodes$Q
  network_nodes <- ApplyCanalDischargeOverrides(network_nodes)

  non_override_idx <- if ("Q_model_m3s" %in% names(network_nodes)) {
    which(is.na(network_nodes$Q_model_m3s))
  } else {
    seq_along(network_nodes$river_discharge)
  }
  needs_flow_fallback <- length(non_override_idx) > 0 &&
    all(is.na(network_nodes$river_discharge[non_override_idx]) |
          network_nodes$river_discharge[non_override_idx] == 0)

  if (needs_flow_fallback) {
    message("Warning: Primary flow extraction failed. Attempting fallback to NetCDF...")
    fallback_nc <- file.path(dataDir, "baselines", "environmental", "FLO1K.30min.ts.1960.2015.qav.nc")
    if (file.exists(fallback_nc)) {
      network_nodes$river_discharge <- NULL
      basin_list <- list(pts = network_nodes)
      basin_list <- AddFlowToBasinData(basin_data = basin_list, flow_rast = terra::rast(fallback_nc)[[1]])
      network_nodes <- basin_list$pts
      network_nodes$river_discharge <- network_nodes$Q
      network_nodes <- ApplyCanalDischargeOverrides(network_nodes)
    }
  }

  network_nodes$river_discharge[is.na(network_nodes$river_discharge) | network_nodes$river_discharge == 0] <- 0.001

  flow_source <- if (network_source == "geoglows") "geoglows" else selected_flow_data$flow_source
  if (prefer_highres_flow && is_dry_season && flow_source != "qmi") {
    message("  Scaling extracted flow by 0.1 for dry season simulation...")
    scale_idx <- if ("Q_model_m3s" %in% names(network_nodes)) which(is.na(network_nodes$Q_model_m3s)) else seq_along(network_nodes$river_discharge)
    network_nodes$river_discharge[scale_idx] <- network_nodes$river_discharge[scale_idx] * 0.1
  }

  network_nodes$Q <- network_nodes$river_discharge

  list(network_nodes = network_nodes)
}

LoadPreferredFlowRaster <- function(input_paths, dataDir, prefer_highres_flow, is_dry_season, flow_source = NULL) {
  base_env_dir <- file.path(dataDir, "baselines", "environmental")
  qmi_tif_default <- file.path(base_env_dir, "FLO1k.lt.2000.2015.qmi.tif")
  qav_tif_default <- file.path(base_env_dir, "FLO1k.lt.2000.2015.qav.tif")

  # ---------------------------------------------------------------------------
  # EXPLICIT FLOW SOURCE SELECTION (NEW, USER-FACING)
  #
  # Priority order:
  #   1) `flow_source` function argument (when provided)
  #   2) `input_paths$flow_source` from scenario config
  #   3) legacy fallback behavior based on `prefer_highres_flow`
  #
  # Supported values:
  #   - "configured"  : use input_paths$flow_raster exactly as configured
  #   - "highres_qav" : force use of high-resolution FLO1K qav TIFF
  #
  # We keep legacy behavior to avoid breaking existing callers that set only
  # `prefer_highres_flow`.
  # ---------------------------------------------------------------------------
  flow_source_selected <- flow_source
  if (is.null(flow_source_selected) && !is.null(input_paths$flow_source)) {
    flow_source_selected <- input_paths$flow_source
  }
  if (is.character(flow_source_selected) && length(flow_source_selected) > 1) {
    flow_source_selected <- flow_source_selected[[1]]
  }
  if (is.character(flow_source_selected)) {
    flow_source_selected <- trimws(flow_source_selected)
    if (!nzchar(flow_source_selected)) flow_source_selected <- NULL
  }

  qav_tif <- if (!is.null(input_paths$flow_raster_highres)) input_paths$flow_raster_highres else qav_tif_default
  qmi_tif <- if (!is.null(input_paths$flow_raster_dry)) input_paths$flow_raster_dry else qmi_tif_default

  if (!is.null(flow_source_selected)) {
    if (identical(flow_source_selected, "highres_qav")) {
      if (!file.exists(qav_tif)) {
        stop(
          "Requested flow_source='highres_qav' but high-resolution raster is missing: ",
          qav_tif,
          ". Provide input_paths$flow_raster_highres or install FLO1K high-res inputs."
        )
      }
      message("Using explicitly selected high-resolution (1km) average flow raster (qav.tif)")
      return(list(flow = terra::rast(qav_tif), flow_source = "highres_qav"))
    }
    if (identical(flow_source_selected, "configured")) {
      if (is.null(input_paths$flow_raster) || !file.exists(input_paths$flow_raster)) {
        stop(
          "Requested flow_source='configured' but configured flow raster is missing: ",
          input_paths$flow_raster
        )
      }
      message("Using explicitly selected configured flow raster: ", input_paths$flow_raster)
      return(list(flow = terra::rast(input_paths$flow_raster)[[1]], flow_source = "configured"))
    }
    stop(
      "Unsupported flow_source '", flow_source_selected, "'. ",
      "Supported values: 'configured', 'highres_qav'."
    )
  }

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

ApplyCanalDischargeOverrides <- function(network_nodes) {
  if (!("Q_model_m3s" %in% names(network_nodes))) return(network_nodes)
  override_idx <- which(!is.na(network_nodes$Q_model_m3s))
  if (length(override_idx) > 0) {
    message(">>> Applying canal Q_model_m3s override to ", length(override_idx), " nodes.")
    network_nodes$river_discharge[override_idx] <- network_nodes$Q_model_m3s[override_idx]
  }
  network_nodes
}
