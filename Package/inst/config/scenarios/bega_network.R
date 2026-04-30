BegaNetwork <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    is_dry_season = FALSE,
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    lake_snap_tolerance_m = bc$lake_snap_tolerance_m,
    lake_snap_enabled = bc$lake_snap_enabled,
    lake_use_pour_point = bc$lake_use_pour_point,
    lake_require_inlet_and_outlet = bc$lake_require_inlet_and_outlet,
    lake_transport_mode = bc$lake_transport_mode_default,
    enable_canals = FALSE,
    canal_shp_path = NULL,
    pop_raster_path = bc$pop_raster_path,
    wwtp_csv_path = bc$wwtp_csv_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    run_output_dir = file.path(output_root, "bega"),
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction
  )
}
