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
  
  filename <- file.path(output_dir, paste0("diagnostic_", sprintf("%02d_", step_number(step_name), title, ".png"))
  
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
