VoltaGeoGLOWSConfig <- function(data_root) {
  b <- file.path(data_root, "basins", "volta")
  e <- file.path(data_root, "baselines", "environmental")

  list(
    basin_id = "volta",
    study_country = "GH",
    default_wind = 4.5,
    default_temp = 27.5,
    utm_crs_string = "+proj=utm +zone=31 +datum=WGS84 +units=m +no_defs",

    network_source = "geoglows",
    river_id_field = "LINKNO",
    river_downstream_id_field = "DSLINKNO",
    river_upstream_area_field = "USContArea",

    basin_shp_path = file.path(b, "small_sub_basin_volta_dissolved.shp"),
    river_shp_path = file.path(b, "geoglows", "streams_in_volta_basin.gpkg"),
    discharge_gpkg_path = file.path(b, "geoglows", "discharge_in_volta_basin.gpkg"),
    flow_dir_path = NULL,
    lakes_shp_path = file.path(b, "cropped_lakes_Akuse_no_kpong.shp"),
    wet_river_shp_path = file.path(b, "geoglows", "streams_in_volta_basin.gpkg"),
    dry_river_shp_path = file.path(b, "af_riv_dry_season.shp"),
    canal_shp_path = file.path(b, "KIS_canals.shp"),
    canal_discharge_table = file.path(b, "KIS_canal_discharge.csv"),
    slope_raster_path = file.path(b, "slope_Volta_sub_basin.tif"),
    wind_raster_path = file.path(e, "wind_LTM_yearly_averaged_raster_1981_2010.tif"),
    temp_raster_path = file.path(e, "temp.tif"),
    pop_raster_path = file.path(e, "GHS_POP_E2025_GLOBE_R2023A_54009_100_V1_0_R9_C19.tif"),
    wwtp_csv_path = NULL,
    hydrowaste_csv_path = file.path(b, "HydroWASTE_v10", "HydroWASTE_v10.csv"),
    chem_data_path = file.path(data_root, "user", "chem_Oldenkamp2018_SI.xlsx"),
    flow_raster_path = file.path(e, "FLO1K.30min.ts.1960.2015.qav.nc"),
    # The 1km minimum flow raster (qmi.tif) is Europe-only. Use the global
    # average annual flow NetCDF as a safer fallback for Volta.
    flow_raster_dry_path = file.path(e, "FLO1K.30min.ts.1960.2015.qav.nc"),
    country_population = 35100000,
    simplification = list(
      lake_tolerance = NULL,
      river_tolerance = 100,
      canal_simplify = FALSE
    )
  )
}
