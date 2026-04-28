VoltaWetNetwork <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    is_dry_season = FALSE,
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = TRUE,
    canal_shp_path = bc$canal_shp_path,
    canal_discharge_table = bc$canal_discharge_table,
    canal_q_anchor_table = bc$canal_q_anchor_table,
    connect_canals_to_rivers = bc$connect_canals_to_rivers,
    canal_junction_snap_tolerance_m = bc$canal_junction_snap_tolerance_m,
    pop_raster_path = bc$pop_raster_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    run_output_dir = file.path(output_root, "volta_wet"),
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction
  )
}
