BegaChemicalIbuprofen <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "bega_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "bega", "pts.csv"),
      hl = file.path(output_root, "bega", "HL.csv"),
      rivers = file.path(output_root, "bega", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    canal_shp_path = NULL,
    pop_raster_path = bc$pop_raster_path,
    wwtp_csv_path = bc$wwtp_csv_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}

BegaPathogenCrypto <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "cryptosporidium",
    pathogen_name = "cryptosporidium",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "bega_crypto"),
    input_paths = list(
      pts = file.path(output_root, "bega", "pts.csv"),
      hl = file.path(output_root, "bega", "HL.csv"),
      rivers = file.path(output_root, "bega", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    canal_shp_path = NULL,
    pop_raster_path = bc$pop_raster_path,
    wwtp_csv_path = bc$wwtp_csv_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}

BegaPathogenCampylobacter <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "campylobacter",
    pathogen_name = "campylobacter",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "bega_campy"),
    input_paths = list(
      pts = file.path(output_root, "bega", "pts.csv"),
      hl = file.path(output_root, "bega", "HL.csv"),
      rivers = file.path(output_root, "bega", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    canal_shp_path = NULL,
    pop_raster_path = bc$pop_raster_path,
    wwtp_csv_path = bc$wwtp_csv_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}

BegaPathogenRotavirus <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "rotavirus",
    pathogen_name = "rotavirus",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "bega_rota"),
    input_paths = list(
      pts = file.path(output_root, "bega", "pts.csv"),
      hl = file.path(output_root, "bega", "HL.csv"),
      rivers = file.path(output_root, "bega", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    canal_shp_path = NULL,
    pop_raster_path = bc$pop_raster_path,
    wwtp_csv_path = bc$wwtp_csv_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}

BegaPathogenGiardia <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "giardia",
    pathogen_name = "giardia",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "bega_giardia"),
    input_paths = list(
      pts = file.path(output_root, "bega", "pts.csv"),
      hl = file.path(output_root, "bega", "HL.csv"),
      rivers = file.path(output_root, "bega", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    canal_shp_path = NULL,
    pop_raster_path = bc$pop_raster_path,
    wwtp_csv_path = bc$wwtp_csv_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    utm_crs_string = bc$utm_crs_string,
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}
