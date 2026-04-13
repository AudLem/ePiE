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
    target_substance = "Ibuprofen",
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
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
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
    target_substance = "Ibuprofen",
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
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}

BegaPathogenRotavirus <- function(data_root, output_root) {
BegaPathogenGiardia <- function(data_root, output_root) {
  bc <- BegaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "Ibuprofen",
    pathogen_name = "rotavirus",
    pathogen_name = "giardia",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "bega_rota"),
    run_output_dir = file.path(output_root, "bega_giardia"),
    input_paths = list(
      pts = file.path(output_root, "bega", "pts.csv"),
      hl = file.path(output_root, "bega", "HL.csv"),
      rivers = file.path(output_root, "bega", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}
