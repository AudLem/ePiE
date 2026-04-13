#' Load Spatial Network Inputs
#'
#' Reads river, basin, lake, canal, and flow-direction rasters and shapefiles,
#' harmonises their CRS, and rasterises the basin polygons for later masking.
#'
#' @param run_output_dir Character. Directory where outputs will be written.
#' @param flow_dir_path Character. Path to the flow-direction raster (e.g. HydroSHEDS).
#' @param river_shp_path Character. Path to the river network shapefile.
#' @param reference_river_shp_path Character or \code{NULL}. Optional reference river shapefile for mouth validation.
#' @param basin_shp_path Character. Path to the basin boundary polygon shapefile.
#' @param lakes_shp_path Character. Path to the lake polygons shapefile (HydroLAKES).
#' @param is_dry_season Logical. If \code{TRUE}, selects dry-season flow data where applicable.
#' @param canal_shp_path Character or \code{NULL}. Path to an artificial canal shapefile.
#' @param enable_canals Logical. Whether to load and include canal geometries.
#' @param river_layer_name Character or \code{NULL}. Specific layer name when reading multi-layer files.
#' @return A named list containing rasterised basin layers, raw spatial objects, and working state.
#' @export
LoadNetworkInputs <- function(run_output_dir,
                                flow_dir_path,
                                river_shp_path,
                                reference_river_shp_path = NULL,
                                basin_shp_path,
                                lakes_shp_path,
                                is_dry_season = FALSE,
                                canal_shp_path = NULL,
                                enable_canals = FALSE,
                                river_layer_name = NULL) {
  message("--- Step 1: Loading Spatial Data ---")

  Basin <- sf::st_read(basin_shp_path, quiet = TRUE)
  hydro_sheds_rivers <- sf::st_read(river_shp_path, quiet = TRUE)

  # --- GeoGLOWS v2 detection ---
  # GeoGLOWS data ships as a .gpkg with LINKNO identifiers and has no
  # flow-direction raster.  Detect by: river file is .gpkg AND
  # flow_dir_path is NULL.  Deduplicate LINKNOs so each reach appears
  # exactly once (93 raw rows -> 64 unique LINKNOs).
  geoglows_mode <- !is.null(river_shp_path) &&
                   grepl("\\.gpkg$", river_shp_path, ignore.case = TRUE) &&
                   is.null(flow_dir_path)

  if (geoglows_mode && "LINKNO" %in% names(hydro_sheds_rivers)) {
    meta_cols <- c("DSLINKNO", "strmOrder", "USContArea", "DSContArea",
                    "TopologicalOrder", "LengthGeodesicMeters", "TerminalLink", "musk_k", "musk_x")
    for (mc in meta_cols) {
      if (mc %in% names(hydro_sheds_rivers) && !("UPLAND_SKM" %in% names(hydro_sheds_rivers))) {
        attr(hydro_sheds_rivers[[mc]], "class") <- NULL
      }
    }
    hydro_sheds_rivers <- dplyr::summarise(
      dplyr::group_by(hydro_sheds_rivers, LINKNO),
      DSLINKNO = DSLINKNO[1],
      strmOrder = strmOrder[1],
      USContArea = USContArea[1],
      DSContArea = DSContArea[1],
      TopologicalOrder = TopologicalOrder[1],
      LengthGeodesicMeters = sum(LengthGeodesicMeters, na.rm = TRUE),
      TerminalLink = TerminalLink[1],
      musk_k = musk_k[1],
      musk_x = musk_x[1]
    )
    if ("USContArea" %in% names(hydro_sheds_rivers) && !("UPLAND_SKM" %in% names(hydro_sheds_rivers))) {
      hydro_sheds_rivers$UPLAND_SKM <- hydro_sheds_rivers$USContArea / 1e6
    }
    hydro_sheds_rivers$ARCID <- hydro_sheds_rivers$LINKNO

    # GeoGLOWS gpkg files use 'geom' as the geometry column, but the
    # pipeline (and canal shapefiles) expect 'geometry'.  Rename now so
    # downstream rbind / column look-ups stay consistent.
    geom_col <- attr(hydro_sheds_rivers, "sf_column")
    if (geom_col != "geometry") {
      names(hydro_sheds_rivers)[names(hydro_sheds_rivers) == geom_col] <- "geometry"
      sf::st_geometry(hydro_sheds_rivers) <- "geometry"
    }

    message("GeoGLOWS mode: deduplicated river network to ",
            nrow(hydro_sheds_rivers), " unique LINKNOs")
  }

  reference_hydro_sheds_rivers <- NULL
  if (!is.null(reference_river_shp_path) && file.exists(reference_river_shp_path)) {
    reference_hydro_sheds_rivers <- sf::st_read(reference_river_shp_path, quiet = TRUE)
  }

  canals_raw <- NULL
  if (enable_canals && !is.null(canal_shp_path) && file.exists(canal_shp_path)) {
    message("Loading canal shapefile: ", canal_shp_path)
    canals_raw <- sf::st_read(canal_shp_path, quiet = TRUE)
    canals_raw <- sf::st_transform(canals_raw, sf::st_crs(hydro_sheds_rivers))
  }

  HL <- sf::st_read(lakes_shp_path, quiet = TRUE)

  # --- Flow-direction raster / GeoGLOWS dummy ---
  if (geoglows_mode) {
    # No real flow-direction raster exists for GeoGLOWS.  Build a dummy
    # RasterLayer (all NA) from the Basin extent so that downstream code
    # relying on `dir` for CRS look-ups, cropping, and fasterize
    # templating continues to work unchanged.
    basin_bbox <- sf::st_bbox(Basin)
    dummy_ext <- raster::extent(
      as.numeric(basin_bbox["xmin"]),
      as.numeric(basin_bbox["xmax"]),
      as.numeric(basin_bbox["ymin"]),
      as.numeric(basin_bbox["ymax"])
    )
    dir <- raster::raster(dummy_ext)
    raster::res(dir) <- 0.008333333
    raster::crs(dir)  <- sf::st_crs(Basin)$wkt
    raster::values(dir) <- NA
    message("GeoGLOWS mode: created dummy flow-direction raster (",
            nrow(dir), "x", ncol(dir), " cells)")
  } else {
    dir <- raster::raster(flow_dir_path)
  }

  Basin_buff <- sf::st_buffer(Basin, dist = 0.1)

  Basin <- EnsureSameCrs(dir, Basin, "flow_dir", "Basin")
  hydro_sheds_rivers <- EnsureSameCrs(dir, hydro_sheds_rivers, "flow_dir", "Rivers")
  if (!is.null(reference_hydro_sheds_rivers)) {
    reference_hydro_sheds_rivers <- EnsureSameCrs(dir, reference_hydro_sheds_rivers, "flow_dir", "Reference rivers")
  }
  if (!is.null(canals_raw)) {
    canals_raw <- EnsureSameCrs(dir, canals_raw, "flow_dir", "Canals")
  }

  dir <- raster::crop(dir, raster::extent(Basin) + c(-1, 1, -1, 1))
  Basin_r <- fasterize::fasterize(Basin, dir)
  Basin_buff_r <- fasterize::fasterize(Basin_buff, dir)

  list(
    shp_dir = run_output_dir,
    dir = dir,
    natural_rivers = hydro_sheds_rivers,
    reference_hydro_sheds_rivers = reference_hydro_sheds_rivers,
    artificial_canals = canals_raw,
    Basin = Basin,
    lake_polygons = HL,
    HL = HL,
    Basin_r = Basin_r,
    Basin_buff = Basin_buff,
    Basin_buff_r = Basin_buff_r,
    hydro_sheds_rivers = hydro_sheds_rivers,
    canals_raw = canals_raw
  )
}
