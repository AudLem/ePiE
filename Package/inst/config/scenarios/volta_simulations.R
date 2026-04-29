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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
      # The packaged "dry" raster is Europe-only and leaves the Volta basin
      # with all-NA discharge. Fall back to the global FLO1K baseline until a
      # Volta-specific dry-season discharge layer is available.
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$dry_river_shp_path,
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
    target_substance = "cryptosporidium",
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
      flow_raster = bc$flow_raster_path
    ),
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
    target_substance = "cryptosporidium",
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
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$dry_river_shp_path,
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
    target_substance = "campylobacter",
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
      flow_raster = bc$flow_raster_path
    ),
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
    target_substance = "campylobacter",
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
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$dry_river_shp_path,
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
    target_substance = "rotavirus",
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
      flow_raster = bc$flow_raster_path
    ),
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
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
    target_substance = "rotavirus",
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
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$dry_river_shp_path,
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaWetPathogenGiardia <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
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
    run_output_dir = file.path(output_root, "volta_giardia_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_wet", "pts.csv"),
      hl = file.path(output_root, "volta_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}

VoltaDryPathogenGiardia <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "giardia",
    pathogen_name = "giardia",
    is_dry_season = TRUE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_giardia_dry"),
    input_paths = list(
      pts = file.path(output_root, "volta_dry", "pts.csv"),
      hl = file.path(output_root, "volta_dry", "HL.csv"),
      rivers = file.path(output_root, "volta_dry", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
    river_shp_path = bc$dry_river_shp_path,
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
    simplification = bc$simplification,
    canal_tail_flow_fraction = bc$canal_tail_flow_fraction,
    dataDir = data_root,
    country_population = bc$country_population
  )
}
