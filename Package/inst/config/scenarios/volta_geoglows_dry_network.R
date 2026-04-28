VoltaGeoGLOWSDryNetwork <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    # GeoGLOWS provides a complete river network model including main channels.
    # Manual canals are disabled here to avoid:
    # 1. Duplicate ARCIDs causing overlapping river segments in visualizations
    # 2. Orphaned agglomeration points when duplicate segments are filtered out
    # HydroSHEDS-based networks (volta_wet, volta_dry) still use canals to supplement incomplete data.
    #
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = bc$network_source,
    discharge_gpkg_path = bc$discharge_gpkg_path,
    river_id_field = bc$river_id_field,
    river_downstream_id_field = bc$river_downstream_id_field,
    river_upstream_area_field = bc$river_upstream_area_field,
    is_dry_season = TRUE,
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
  flow_dir_path = NULL,
  enable_lakes = TRUE,
  enable_canals = FALSE,
  canal_shp_path = bc$canal_shp_path,
    canal_discharge_table = bc$canal_discharge_table,
    pop_raster_path = bc$pop_raster_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    run_output_dir = file.path(output_root, "volta_geoglows_dry"),
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction
  )
}
