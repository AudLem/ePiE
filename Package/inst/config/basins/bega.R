BegaBasinConfig <- function(data_root) {
  b <- file.path(data_root, "basins", "bega")
  h <- file.path(data_root, "baselines", "hydrosheds")
  e <- file.path(data_root, "baselines", "environmental")

  list(
    basin_id = "bega",
    study_country = "RO",
    default_wind = 4.5,
    default_temp = 11.0,
    utm_crs_string = "+proj=utm +zone=34 +datum=WGS84 +units=m +no_defs",

    basin_shp_path = file.path(b, "bega_basin.shp"),
    lakes_shp_path = file.path(b, "HL_crop2.shp"),
    flow_dir_path = file.path(h, "eu_dir_30s_grid", "eu_dir_30s", "eu_dir_30s", "w001001.adf"),
    wet_river_shp_path = file.path(h, "eu_riv_30s", "eu_riv_30s.shp"),
    dry_river_shp_path = NULL,
    canal_shp_path = NULL,
    canal_discharge_table = NULL,
    slope_raster_path = file.path(b, "PAGER_mean_slope_Danube.tif"),
    wind_raster_path = file.path(e, "wind_LTM_yearly_averaged_raster_1981_2010.tif"),
    temp_raster_path = file.path(e, "temp.tif"),
    pop_raster_path = NULL,
    wwtp_csv_path = file.path(data_root, "user", "EEF_points_updated.csv"),
    chem_data_path = file.path(data_root, "user", "chem_Oldenkamp2018_SI.xlsx"),
    flow_raster_path = file.path(e, "FLO1K.30min.ts.1960.2015.qav.nc"),
    flow_raster_dry_path = NULL,
    country_population = 19000000,
    simplification = list(
      lake_tolerance = NULL,
      river_tolerance = 100,
      canal_simplify = FALSE
    )
  )
}
