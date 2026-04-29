#' Save Network Artifacts
#'
#' Writes the final network points, lake nodes, and river geometries to disk as
#' CSV and Shapefile, extracting slope, temperature, and wind rasters onto points.
#'
#' @param points sf object. Final network point nodes.
#' @param hydro_sheds_rivers_basin sf object. Clipped river network.
#' @param HL_basin sf object or \code{NULL}. In-basin lake polygons.
#' @param shp_dir Character. Directory containing source shapefiles.
#' @param run_output_dir Character. Directory where outputs will be written.
#' @param slope_raster_path Character or \code{NULL}. Path to slope raster.
#' @param temp_raster_path Character or \code{NULL}. Path to temperature raster.
#' @param wind_raster_path Character or \code{NULL}. Path to wind speed raster.
#' @return A named list with \code{points} (enriched) and \code{HL_basin}.
#' @export
SaveNetworkArtifacts <- function(points,
                                   hydro_sheds_rivers_basin,
                                   HL_basin,
                                   shp_dir,
                                   run_output_dir,
                                   slope_raster_path = NULL,
                                   temp_raster_path = NULL,
                                   wind_raster_path = NULL) {
  message("--- Step 9: Harmonizing and Saving Network ---")

  if (!dir.exists(run_output_dir)) {
    message("Creating output directory: ", run_output_dir)
    dir.create(run_output_dir, recursive = TRUE)
  }
  if (!dir.exists(shp_dir)) {
    message("Creating shapefile directory: ", shp_dir)
    dir.create(shp_dir, recursive = TRUE)
  }

  pts_wgs84 <- sf::st_transform(points, crs = 4326)
  coords <- sf::st_coordinates(pts_wgs84)
  points$x <- coords[, 1]
  points$y <- coords[, 2]

  if (!("is_canal" %in% names(points))) points$is_canal <- FALSE
  if (!("total_population" %in% names(points))) points$total_population <- 0
  points <- AnnotateDisplayJunctions(points)

  extract_val <- function(pts, rast_path, col_name) {
    if (!is.null(rast_path) && file.exists(rast_path)) {
      message("Extracting: ", col_name)
      r <- raster::raster(rast_path)
      vals <- raster::extract(r, methods::as(pts, "Spatial"))
      pts[[col_name]] <- as.numeric(vals)
    } else {
      warning(
        "Raster not found for '", col_name, "'. Column will be NA.\n",
        "  Path checked: ", if (!is.null(rast_path)) rast_path else "<not configured>"
      )
      pts[[col_name]] <- NA
    }
    pts
  }

  points <- extract_val(points, slope_raster_path, "slope")
  points <- extract_val(points, temp_raster_path, "T_AIR")
  points <- extract_val(points, wind_raster_path, "Wind")

  points$basin_id <- basename(run_output_dir)

  pts_df <- as.data.frame(points)
  pts_df$geometry <- NULL
  pts_df <- pts_df[, !duplicated(colnames(pts_df))]

  pts_path <- file.path(run_output_dir, "pts.csv")
  hl_path <- file.path(run_output_dir, "hl.csv")
  hl_legacy_path <- file.path(run_output_dir, "HL.csv")

  write.csv(pts_df, pts_path, row.names = FALSE)

  # NOTE: hydrology_nodes.csv (Q, V, H) is NOT written here.
  # This function runs during the network-build stage, before simulation
  # hydrology is computed. The hydrology-enriched CSV is written by
  # ExportHydrologyNodes() in RunSimulationPipeline.R, after the simulation
  # engine has computed Q, V, and H via Manning-Strickler.
  # Writing it here would produce a file with NA/missing Q, V, H values.

  if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
    hl_df <- as.data.frame(HL_basin)
    hl_df$geometry <- NULL
    write.csv(hl_df, hl_path, row.names = FALSE)
    write.csv(hl_df, hl_legacy_path, row.names = FALSE)
  }

  core_cols <- c(
    "ID", "ID_nxt", "x", "y", "is_canal",
    "canal_id", "canal_name", "canal_pt_type", "chainage_m",
    "canal_d_nxt_m", "Q_design_m3s", "Q_model_m3s",
    "display_pt_type", "junction_role",
    "slope", "T_AIR", "Wind", "total_population",
    "HL_ID_new", "lake_in", "lake_out", "node_type"
  )
  available_cols <- intersect(core_cols, names(points))

  sf::st_write(points[, available_cols], file.path(shp_dir, "network_points.shp"),
               delete_layer = TRUE, quiet = TRUE)
  sf::st_write(hydro_sheds_rivers_basin, file.path(shp_dir, "network_rivers.shp"),
               delete_layer = TRUE, quiet = TRUE)

  if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
    sf::st_write(HL_basin, file.path(shp_dir, "network_lakes.shp"),
                 delete_layer = TRUE, quiet = TRUE)
  }

  save(points, hydro_sheds_rivers_basin, HL_basin, file = file.path(run_output_dir, "FinalEnv.RData"))

  message("Network data saved to: ", run_output_dir)
  message("Is_canal attribute preserved: ", "is_canal" %in% names(pts_df))

  list(
    pts = pts_df,
    HL = if (exists("hl_df", envir = environment())) hl_df else NULL
  )
}
