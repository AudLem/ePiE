#' Validate and normalize diagnostic level
#'
#' @param level Character string: "none", "light", "maps", or "full"
#' @param default Default level if level is NULL
#' @return Normalized diagnostic level string
DiagLevel <- function(level, default = "none") {
  if (is.null(level)) return("none")
  valid_levels <- c("none", "light", "maps", "full")
  if (!(level %in% valid_levels)) {
    warning(paste0("Invalid diagnostics level '", level, "'. Using 'none'. Valid levels: ", paste(valid_levels, collapse = ", ")))
    return("none")
  }
  level
}

#' Save diagnostic map as PNG
#'
#' @param sf_data Spatial data to plot
#' @param title Map title
#' @param output_dir Directory to save output
#' @param step_name Pipeline step name for file naming
SaveDiagnosticMap <- function(sf_data, title, output_dir, step_name) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  
  filename <- file.path(output_dir, paste0("diagnostic_", sprintf("%02d_", step_number(step_name)), title, ".png"))
  
  m <- tmap::tm_layout(bg.color = "white", frame = FALSE,
                           legend.position = c("right", "bottom"),
                           legend.bg.color = "white", legend.bg.alpha = 0.9)
  
  m <- m + tmap::tm_shape(sf_data) + tmap::tm_polygons(fill = "lightgrey", col = "darkgrey", lwd = 1)
  m <- m + tmap::tm_scalebar() + tmap::tm_compass() + tmap::tm_title(title)
  
  tmap::tmap_mode("plot")
  tryCatch({
    tmap::tmap_save(m, filename, width = 1200, height = 1000, dpi = 150)
    message("    Diagnostic map saved: ", filename)
  }, error = function(e) {
    warning(paste0("Failed to save diagnostic map: ", e$message))
  })
}

is_spatial_diagnostic_object <- function(x) {
  inherits(x, "sf") || inherits(x, c("RasterLayer", "RasterStack", "RasterBrick"))
}

get_spatial_crs <- function(x) {
  tryCatch(sf::st_crs(x), error = function(e) NA)
}

format_crs_input <- function(crs) {
  if (is.na(crs)) return(NA_character_)
  if (!is.null(crs$input) && !is.na(crs$input) && nzchar(crs$input)) return(crs$input)
  if (!is.null(crs$wkt) && !is.na(crs$wkt)) return(crs$wkt)
  NA_character_
}

spatial_bbox_record <- function(x) {
  if (inherits(x, "sf")) {
    bb <- sf::st_bbox(x)
    return(list(
      xmin = unname(bb["xmin"]),
      ymin = unname(bb["ymin"]),
      xmax = unname(bb["xmax"]),
      ymax = unname(bb["ymax"])
    ))
  }
  if (inherits(x, c("RasterLayer", "RasterStack", "RasterBrick"))) {
    ext <- raster::extent(x)
    return(list(
      xmin = ext@xmin,
      ymin = ext@ymin,
      xmax = ext@xmax,
      ymax = ext@ymax
    ))
  }
  list(xmin = NA_real_, ymin = NA_real_, xmax = NA_real_, ymax = NA_real_)
}

#' Collect CRS metadata for spatial objects in a pipeline state
#'
#' @param state Named list returned by a pipeline step.
#' @return data.frame with CRS, extent, and feature/cell metadata.
CollectStateCrsReport <- function(state) {
  spatial_names <- names(state)[vapply(state, is_spatial_diagnostic_object, logical(1))]
  records <- lapply(spatial_names, function(object_name) {
    obj <- state[[object_name]]
    crs <- get_spatial_crs(obj)
    bb <- spatial_bbox_record(obj)
    is_longlat <- tryCatch(
      {
        if (inherits(obj, "sf")) {
          sf::st_is_longlat(obj)
        } else {
          raster::isLonLat(obj)
        }
      },
      error = function(e) NA
    )
    geometry_type <- if (inherits(obj, "sf")) {
      paste(unique(as.character(sf::st_geometry_type(obj))), collapse = "|")
    } else {
      NA_character_
    }
    feature_count <- if (inherits(obj, "sf")) {
      nrow(obj)
    } else if (inherits(obj, c("RasterLayer", "RasterStack", "RasterBrick"))) {
      raster::ncell(obj)
    } else {
      NA_integer_
    }

    data.frame(
      object = object_name,
      class = paste(class(obj), collapse = "|"),
      geometry_type = geometry_type,
      feature_count = feature_count,
      crs_input = format_crs_input(crs),
      epsg = if (!is.na(crs) && !is.null(crs$epsg)) crs$epsg else NA_integer_,
      is_longlat = is_longlat,
      xmin = bb$xmin,
      ymin = bb$ymin,
      xmax = bb$xmax,
      ymax = bb$ymax,
      crs_wkt = if (!is.na(crs) && !is.null(crs$wkt)) crs$wkt else NA_character_,
      stringsAsFactors = FALSE
    )
  })

  if (length(records) == 0) {
    return(data.frame(
      object = character(),
      class = character(),
      geometry_type = character(),
      feature_count = integer(),
      crs_input = character(),
      epsg = integer(),
      is_longlat = logical(),
      xmin = numeric(),
      ymin = numeric(),
      xmax = numeric(),
      ymax = numeric(),
      crs_wkt = character(),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, records)
}

RasterExtentToSf <- function(raster_obj) {
  ext <- raster::extent(raster_obj)
  coords <- matrix(
    c(
      ext@xmin, ext@ymin,
      ext@xmax, ext@ymin,
      ext@xmax, ext@ymax,
      ext@xmin, ext@ymax,
      ext@xmin, ext@ymin
    ),
    ncol = 2,
    byrow = TRUE
  )
  sf::st_sf(
    layer = "flow_dir_extent",
    geometry = sf::st_sfc(sf::st_polygon(list(coords)), crs = sf::st_crs(raster_obj))
  )
}

has_sf_rows <- function(x) {
  inherits(x, "sf") && nrow(x) > 0
}

crop_sf_for_diagnostic_map <- function(x, extent_sf) {
  if (!has_sf_rows(x) || is.null(extent_sf)) return(x)
  tryCatch(
    suppressWarnings(sf::st_crop(x, sf::st_bbox(extent_sf))),
    error = function(e) x
  )
}

prepare_dir_raster_for_diagnostic_map <- function(raster_obj, max_cells = 50000) {
  if (!inherits(raster_obj, c("RasterLayer", "RasterStack", "RasterBrick"))) return(NULL)
  r <- raster_obj
  if (raster::nlayers(r) > 1) r <- r[[1]]
  if (raster::ncell(r) > max_cells) {
    factor <- ceiling(sqrt(raster::ncell(r) / max_cells))
    r <- raster::aggregate(r, fact = factor, fun = raster::modal, na.rm = TRUE)
  }
  r
}

#' Build a tmap overlay of the raw step-01 spatial inputs
#'
#' @param state Step-01 pipeline state.
#' @return tmap object.
BuildStep01InputOverlayMap <- function(state) {
  dir_extent <- NULL
  dir_raster <- NULL
  if (inherits(state$dir, c("RasterLayer", "RasterStack", "RasterBrick"))) {
    dir_extent <- RasterExtentToSf(state$dir)
    dir_raster <- prepare_dir_raster_for_diagnostic_map(state$dir)
  }
  
  reference_rivers <- crop_sf_for_diagnostic_map(state$reference_hydro_sheds_rivers, dir_extent)
  rivers <- crop_sf_for_diagnostic_map(state$hydro_sheds_rivers, dir_extent)
  canals <- crop_sf_for_diagnostic_map(state$canals_raw, dir_extent)
  lakes <- crop_sf_for_diagnostic_map(state$HL, dir_extent)

  map <- tmap::tm_layout(
    bg.color = "white",
    frame = FALSE,
    legend.outside = TRUE,
    legend.outside.position = "right",
    legend.bg.color = "white",
    legend.bg.alpha = 0.85
  ) +
    tmap::tm_title("Step 01 loaded network inputs")

  if (has_sf_rows(state$Basin)) {
    map <- map +
      tmap::tm_shape(state$Basin) +
      tmap::tm_polygons(fill = NA, col = "#252525", lwd = 2)
  }
  
  if (!is.null(dir_raster)) {
    map <- map +
      tmap::tm_shape(dir_raster) +
      tmap::tm_raster(col_alpha = 0.45, col.scale = tmap::tm_scale_continuous(values = "Greys"), col.legend = tmap::tm_legend(title = "Flow dir", show = FALSE))
  }

  if (has_sf_rows(reference_rivers)) {
    reference_rivers$type <- "Reference Rivers"
    map <- map +
      tmap::tm_shape(reference_rivers) +
      tmap::tm_lines(col = "#969696", lwd = 0.8)
  }
  
  if (has_sf_rows(rivers)) {
    rivers$type <- "HydroSHEDS Rivers"
    map <- map +
      tmap::tm_shape(rivers) +
      tmap::tm_lines(col = "#2171b5", lwd = 1.2)
  }
  
  if (has_sf_rows(canals)) {
    canals$type <- "Input Canals"
    map <- map +
      tmap::tm_shape(canals) +
      tmap::tm_lines(col = "#f28e2b", lwd = 2.0)
  }
  
  if (has_sf_rows(lakes)) {
    map <- map +
      tmap::tm_shape(lakes) +
      tmap::tm_polygons(fill = "#9ecae1", col = "#3182bd", lwd = 0.8, fill_alpha = 0.65)
  }
  
  # Manual legend for clarification of line colors
  map <- map + tmap::tm_legend(
    type = "line",
    labels = c("HydroSHEDS Rivers", "Input Canals", "Reference Rivers"),
    col = c("#2171b5", "#f28e2b", "#969696"),
    lwd = c(1.2, 2.0, 0.8),
    title = "Waterways"
  )
  
  map
}

#' Save step-01 CRS report and loaded-inputs overlay map
#'
#' @param state Step-01 pipeline state.
#' @param diagnostics_dir Directory for diagnostic outputs.
#' @return Invisibly returns the CRS report.
SaveStep01InputDiagnostics <- function(state, diagnostics_dir) {
  if (is.null(diagnostics_dir)) return(invisible(NULL))
  dir.create(diagnostics_dir, recursive = TRUE, showWarnings = FALSE)

  report <- CollectStateCrsReport(state)
  report_path <- file.path(diagnostics_dir, "step_01_crs_report.csv")
  utils::write.csv(report, report_path, row.names = FALSE)
  message("    Step 01 CRS report saved: ", report_path)

  map_path <- file.path(diagnostics_dir, "step_01_loaded_inputs_map.png")
  map <- BuildStep01InputOverlayMap(state)
  tmap::tmap_mode("plot")
  tryCatch({
    tmap::tmap_save(map, map_path, width = 1600, height = 1200, dpi = 150)
    message("    Step 01 input overlay map saved: ", map_path)
  }, error = function(e) {
    warning(paste0("Failed to save Step 01 input overlay map: ", e$message))
  })

  invisible(report)
}

#' Print and pause on step-01 diagnostics for interactive debugging
#'
#' @param state Step-01 pipeline state.
#' @return Invisibly returns the CRS report.
ShowInteractiveStep01Diagnostics <- function(state) {
  report <- CollectStateCrsReport(state)
  console_report <- report[, setdiff(names(report), "crs_wkt"), drop = FALSE]

  message("--- Step 01 CRS report ---")
  print(console_report, row.names = FALSE)

  map <- BuildStep01InputOverlayMap(state)
  tmap::tmap_mode("plot")
  print(map)

  if (interactive()) {
    readline("Inspect Step 01 CRS/map, then press Enter to continue...")
  } else {
    message("Skipping interactive Step 01 pause: non-interactive session")
  }

  invisible(report)
}

#' Log diagnostic message if diagnostic level permits
#'
#' @param level Minimum diagnostic level required: "light", "maps", or "full"
#' @param step_name Pipeline step name for context
#' @param message Message to log
#' @param diag_level Current diagnostic level setting
LogDiagnostic <- function(level, step_name, message, diag_level = NULL) {
  if (is.null(diag_level)) return()
  
  level_order <- c("light" = 1, "maps" = 1, "full" = 3)
  required_level <- if (is.character(level)) level_order[[level]] else 0
  
  if (level_order[[diag_level]] >= required_level) {
    message(paste0("--- Diagnostic [", diag_level, "/", step_name, "] ---"))
    message(message)
  }
}

#' Display diagnostic progress bar
#'
#' @param current Current progress count
#' @param total Total count
#' @param diag_level Current diagnostic level setting
#' @param label Progress bar label
DiagnosticProgressBar <- function(current, total, diag_level = NULL, label = "Progress") {
  if (is.null(diag_level)) return()
  if (diag_level == "none") return()
  if (total <= 0) return()
  
  percent <- round(100 * current / total)
  bar_width <- 40
  filled <- round(bar_width * percent / 100)
  empty <- bar_width - filled
  bar <- paste0("[", paste(rep("=", filled), collapse = ""), paste(rep(" ", empty), collapse = ""), "]")
  
  message(paste0(bar, " ", percent, "% ", label, " (", current, "/", total, ")"))
}

#' Convert step name to numeric ID for diagnostic file naming
#'
#' @param step_name Pipeline step name
#' @return Numeric step ID or 99 if unknown
step_number <- function(step_name) {
  step_num <- switch(step_name,
    "LoadNetworkInputs" = 1,
    "PrepareCanalLayers" = 2,
    "ProcessRiverGeometry" = 3,
    "ProcessLakeGeometries" = 4,
    "ExtractPopulationSources" = 5,
    "MapWWTPLocations" = 6,
    "BuildNetworkTopology" = 7,
    "IntegratePointsAndLines" = 8,
    "ConnectLakesToNetwork" = "8b",
    "DetectLakeSegmentCrossings" = "8c",
    "SaveNetworkArtifacts" = 9,
    "VisualizeNetwork" = 10,
    99
  )
  if (step_num == 99) warning(paste0("Unknown step name: ", step_name))
  step_num
}
