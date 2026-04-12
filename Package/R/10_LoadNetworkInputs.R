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
  dir <- raster::raster(flow_dir_path)

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
