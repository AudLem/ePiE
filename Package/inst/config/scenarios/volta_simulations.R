VoltaWetChemicalIbuprofen <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_wet_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "volta_wet", "pts.csv"),
      hl = file.path(output_root, "volta_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaDryChemicalIbuprofen <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_dry_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "volta_dry", "pts.csv"),
      hl = file.path(output_root, "volta_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaWetPathogenCrypto <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "cryptosporidium",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_crypto_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_wet", "pts.csv"),
      hl = file.path(output_root, "volta_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaDryPathogenCrypto <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "cryptosporidium",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_crypto_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_dry", "pts.csv"),
      hl = file.path(output_root, "volta_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaWetPathogenCampylobacter <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "campylobacter",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_campy_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_wet", "pts.csv"),
      hl = file.path(output_root, "volta_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaDryPathogenCampylobacter <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "campylobacter",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_campy_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_dry", "pts.csv"),
      hl = file.path(output_root, "volta_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaWetPathogenRotavirus <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "rotavirus",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_rota_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_wet", "pts.csv"),
      hl = file.path(output_root, "volta_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaDryPathogenRotavirus <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "rotavirus",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_rota_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_dry", "pts.csv"),
      hl = file.path(output_root, "volta_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_dry_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}
