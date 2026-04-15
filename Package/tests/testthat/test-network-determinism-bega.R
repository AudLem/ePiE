library(testthat)
library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

skip_if_not(dir.exists(data_root), "Bega data root not found")

has_bega_build_data <- all(file.exists(
  file.path(data_root, "basins", "bega", "bega_basin.shp"),
  file.path(data_root, "basins", "bega", "HL_crop2.shp"),
  file.path(data_root, "baselines", "hydrosheds", "eu_riv_30s", "eu_riv_30s.shp"),
  file.path(data_root, "baselines", "hydrosheds", "eu_dir_30s_grid", "eu_dir_30s", "eu_dir_30s", "w001001.adf"),
  file.path(data_root, "basins", "bega", "PAGER_mean_slope_Danube.tif"),
  file.path(data_root, "user", "EEF_points_updated.csv"),
  file.path(data_root, "user", "chem_Oldenkamp2018_SI.xlsx")
))

test_that("Bega pipeline generation is deterministic", {
  skip_if_not(has_bega_build_data, "Not all Bega build data files present")

  cfg <- LoadScenarioConfig("BegaNetwork", data_root, output_root)

  tmp_dir <- tempfile(pattern = "bega_determinism_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  cfg$run_output_dir <- tmp_dir

  message("Running first Bega pipeline pass...")
  state1 <- BuildNetworkPipeline(cfg, stop_after_step = "09_save_artifacts")

  message("Running second Bega pipeline pass...")
  state2 <- BuildNetworkPipeline(cfg, stop_after_step = "09_save_artifacts")

  expect_identical(state1$points, state2$points, info = "Points data differ between Bega runs")
  expect_identical(state1$HL_basin, state2$HL_basin, info = "Lake data differ between Bega runs")
  expect_identical(state1$lines, state2$lines, info = "River lines differ between Bega runs")
})