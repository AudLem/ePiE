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
    canal_tail_flow_fraction = 0.5,
    canal_discharge_table = NULL,
    lake_snap_tolerance_m = 250,
    lake_snap_enabled = FALSE,
    lake_use_pour_point = TRUE,
    lake_require_inlet_and_outlet = TRUE,
    slope_raster_path = file.path(b, "PAGER_mean_slope_Danube.tif"),
    wind_raster_path = file.path(e, "wind_LTM_yearly_averaged_raster_1981_2010.tif"),
    temp_raster_path = file.path(e, "temp.tif"),
    pop_raster_path = NULL,
    wwtp_csv_path = file.path(data_root, "user", "EEF_points_updated.csv"),
    hydrowaste_csv_path = file.path(b, "HydroWASTE_v10", "HydroWASTE_v10.csv"),
    chem_data_path = file.path(data_root, "user", "chem_Oldenkamp2018_SI.xlsx"),
    # -------------------------------------------------------------------------
    # FLOW INPUTS (USER-SELECTABLE)
    #
    # `flow_raster_path` is the currently configured default source used by
    # scenario configs (coarse global FLO1K NetCDF, 30-minute grid).
    #
    # `flow_raster_highres_path` points to the legacy high-resolution FLO1K
    # TIFF (~1 km) used in historical Bega runs.
    #
    # `flow_source_default` controls which source is chosen by default:
    #   - "configured"  : use `flow_raster_path`
    #   - "highres_qav" : use `flow_raster_highres_path`
    #
    # Users can change this default in one place (this basin config), and
    # scenario configs/pipeline code will propagate it automatically.
    # -------------------------------------------------------------------------
    flow_raster_path = file.path(e, "FLO1K.30min.ts.1960.2015.qav.nc"),
    flow_raster_highres_path = file.path(e, "FLO1k.lt.2000.2015.qav.tif"),
    flow_source_default = "highres_qav",
    flow_raster_dry_path = NULL,
    country_population = 19000000,
    simplification = list(
      lake_tolerance = NULL,
      river_tolerance = 100,
      canal_simplify = FALSE
    )
  )
}
