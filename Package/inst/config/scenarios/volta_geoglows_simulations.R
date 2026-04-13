VoltaGeoGLOWSWetChemicalIbuprofen <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 9:10,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_wet_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_wet", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSDryChemicalIbuprofen <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 3:4,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_dry_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_dry", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSWetPathogenCrypto <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "cryptosporidium",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 9:10,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_crypto_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_wet", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSDryPathogenCrypto <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "cryptosporidium",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 3:4,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_crypto_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_dry", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSWetPathogenCampylobacter <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "campylobacter",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 9:10,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_campy_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_wet", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSDryPathogenCampylobacter <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "campylobacter",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 3:4,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_campy_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_dry", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSWetPathogenRotavirus <- function(data_root, output_root) {
VoltaGeoGLOWSWetPathogenGiardia <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "rotavirus",
    pathogen_name = "giardia",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 9:10,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_rota_wet"),
    run_output_dir = file.path(output_root, "volta_geoglows_giardia_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_wet", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaGeoGLOWSDryPathogenRotavirus <- function(data_root, output_root) {
VoltaGeoGLOWSDryPathogenGiardia <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    network_source = "geoglows",
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "rotavirus",
    pathogen_name = "giardia",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    simulation_year = 2020,
    simulation_months = 3:4,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    run_output_dir = file.path(output_root, "volta_geoglows_rota_dry"),
    run_output_dir = file.path(output_root, "volta_geoglows_giardia_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_dry", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}
