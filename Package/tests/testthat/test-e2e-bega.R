library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

skip_if_not(dir.exists(data_root), "Bega data root not found")

has_bega_prebuilt <- all(file.exists(
  file.path(output_root, "bega", "pts.csv"),
  file.path(output_root, "bega", "HL.csv"),
  file.path(output_root, "bega", "network_rivers.shp")
))

has_bega_build_data <- all(file.exists(
  file.path(data_root, "basins", "bega", "bega_basin.shp"),
  file.path(data_root, "basins", "bega", "HL_crop2.shp"),
  file.path(data_root, "baselines", "hydrosheds", "eu_riv_30s", "eu_riv_30s.shp"),
  file.path(data_root, "baselines", "hydrosheds", "eu_dir_30s_grid", "eu_dir_30s", "eu_dir_30s", "w001001.adf"),
  file.path(data_root, "basins", "bega", "PAGER_mean_slope_Danube.tif"),
  file.path(data_root, "user", "EEF_points_updated.csv"),
  file.path(data_root, "user", "chem_Oldenkamp2018_SI.xlsx")
))

test_that("RunSimulationPipeline produces chemical results on pre-built Bega network", {
  skip_if_not(has_bega_prebuilt, "Pre-built Bega network files not found")

  prebuilt_dir <- file.path(output_root, "bega")
  pts_raw <- read.csv(file.path(prebuilt_dir, "pts.csv"), stringsAsFactors = FALSE)
  HL <- read.csv(file.path(prebuilt_dir, "HL.csv"), stringsAsFactors = FALSE)
  state <- NormalizeScenarioState(pts_raw, HL, "HU", "bega", 10.0, 3.0)

  sim_dir <- tempfile(pattern = "bega_chem_")
  on.exit(unlink(sim_dir, recursive = TRUE), add = TRUE)

  sim_cfg <- LoadScenarioConfig("BegaChemicalIbuprofen", data_root, output_root)
  sim_cfg$run_output_dir <- sim_dir
  sim_cfg$input_paths$pts <- file.path(prebuilt_dir, "pts.csv")
  sim_cfg$input_paths$hl <- file.path(prebuilt_dir, "HL.csv")
  sim_cfg$input_paths$rivers <- file.path(prebuilt_dir, "network_rivers.shp")

  # Add missing configuration fields to the state for the simulation pipeline
  state$input_paths <- sim_cfg$input_paths
  state$study_country <- sim_cfg$study_country
  state$country_population <- sim_cfg$country_population
  state$run_output_dir <- sim_cfg$run_output_dir
  state$basin_id <- sim_cfg$basin_id

  results <- RunSimulationPipeline(state, substance = "Ibuprofen")

  expect_type(results, "list")
  expect_true("results" %in% names(results))
  expect_true("pts" %in% names(results$results))
  expect_true("C_w" %in% names(results$results$pts))
  expect_gt(nrow(results$results$pts), 0)

  positive <- sum(results$results$pts$C_w > 0, na.rm = TRUE)
  expect(positive > 0, "Expected at least some positive concentrations in Bega")
})

test_that("BuildNetworkPipeline completes for Bega", {
  skip_if_not(has_bega_build_data, "Not all Bega build data files present")

  test_output_dir <- tempfile(pattern = "bega_build_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)

  cfg <- LoadScenarioConfig("BegaNetwork", data_root, output_root)
  cfg$run_output_dir <- test_output_dir

  state <- BuildNetworkPipeline(cfg)

  expect_type(state, "list")
  expect_true("points" %in% names(state))
  expect_true("HL_basin" %in% names(state))

  pts_file <- file.path(test_output_dir, "pts.csv")
  hl_file <- file.path(test_output_dir, "HL.csv")
  expect_true(file.exists(pts_file))
  expect_true(file.exists(hl_file))

  pts <- read.csv(pts_file, stringsAsFactors = FALSE)
  expect_gt(nrow(pts), 50)
  expect_true("ID" %in% names(pts))
  expect_true("ID_nxt" %in% names(pts))
  expect_true("x" %in% names(pts))
  expect_true("y" %in% names(pts))
  expect_true("d_nxt" %in% names(pts))
  expect_true("pt_type" %in% names(pts))
})

test_that("RunSimulationPipeline produces pathogen results on pre-built Bega network", {
  skip_if_not(has_bega_prebuilt, "Pre-built Bega network files not found")

  prebuilt_dir <- file.path(output_root, "bega")
  pts_raw <- read.csv(file.path(prebuilt_dir, "pts.csv"), stringsAsFactors = FALSE)
  HL <- read.csv(file.path(prebuilt_dir, "HL.csv"), stringsAsFactors = FALSE)
  state <- NormalizeScenarioState(pts_raw, HL, "HU", "bega", 10.0, 3.0)

  sim_dir <- tempfile(pattern = "bega_crypto_")
  on.exit(unlink(sim_dir, recursive = TRUE), add = TRUE)

  sim_cfg <- LoadScenarioConfig("BegaPathogenCrypto", data_root, output_root)
  sim_cfg$run_output_dir <- sim_dir
  sim_cfg$input_paths$pts <- file.path(prebuilt_dir, "pts.csv")
  sim_cfg$input_paths$hl <- file.path(prebuilt_dir, "HL.csv")
  sim_cfg$input_paths$rivers <- file.path(prebuilt_dir, "network_rivers.shp")

  # Add missing configuration fields to the state for the simulation pipeline
  state$input_paths <- sim_cfg$input_paths
  state$study_country <- sim_cfg$study_country
  state$country_population <- sim_cfg$country_population
  state$run_output_dir <- sim_cfg$run_output_dir
  state$basin_id <- sim_cfg$basin_id

  results <- RunSimulationPipeline(state, substance = "cryptosporidium")

  expect_type(results, "list")
  expect_true("results" %in% names(results))
  expect_true("pts" %in% names(results$results))
  expect_true("C_w" %in% names(results$results$pts))
  expect_gt(nrow(results$results$pts), 0)
})
