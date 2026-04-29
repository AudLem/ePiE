library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

skip_if_not(dir.exists(data_root), "Volta data root not found")
skip_if_not(dir.exists(file.path(data_root, "basins", "volta")), "Volta basin data not found")

has_all_volta_data <- all(file.exists(
  file.path(data_root, "basins", "volta", "small_sub_basin_volta_dissolved.shp"),
  file.path(data_root, "basins", "volta", "cropped_lakes_Akuse_no_kpong.shp"),
  file.path(data_root, "baselines", "hydrosheds", "af_riv_30s", "af_riv_30s.shp"),
  file.path(data_root, "baselines", "hydrosheds", "af_dir_30s_grid", "af_dir_30s", "af_dir_30s", "w001001.adf"),
  file.path(data_root, "baselines", "environmental", "GHS_POP_E2025_GLOBE_R2023A_54009_100_V1_0_R9_C19.tif"),
  file.path(data_root, "basins", "volta", "KIS_canals.shp"),
  file.path(data_root, "basins", "volta", "slope_Volta_sub_basin.tif")
))
skip_if_not(has_all_volta_data, "Not all Volta data files present")

test_that("BuildNetworkPipeline completes for Volta wet season", {
  test_output_dir <- tempfile(pattern = "volta_wet_build_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)

  cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
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
  expect_gt(nrow(pts), 100)
  expect_true("ID" %in% names(pts))
  expect_true("ID_nxt" %in% names(pts))
  expect_true("x" %in% names(pts))
  expect_true("y" %in% names(pts))
  expect_true("d_nxt" %in% names(pts))
  expect_true("pt_type" %in% names(pts))
  expect_true("total_population" %in% names(pts))
  expect_true("T_AIR" %in% names(pts))
  expect_true("Wind" %in% names(pts))
  expect_true("slope" %in% names(pts))

  canal_pts <- pts[!is.na(pts$is_canal) & pts$is_canal %in% c(TRUE, "TRUE", 1), , drop = FALSE]
  expect_gt(nrow(canal_pts), 0)
  expect_true(all(!is.na(canal_pts$Q_model_m3s)))
  expect_lte(max(canal_pts$Q_model_m3s, na.rm = TRUE), 7.2)
  expect_true(all(canal_pts$Q_source %in% c("section_head_tail_interpolation", "mass_balance_scaled_branch")))
  expect_true(any(canal_pts$canal_pt_type == "CANAL_BRANCH", na.rm = TRUE))
  expect_false(any(canal_pts$Q_source == "operational_chainage_anchor_interpolation", na.rm = TRUE))

  shp_file <- file.path(test_output_dir, "network_rivers.shp")
  expect_true(file.exists(shp_file))

  expect_true(all(pts$x >= -2 & pts$x <= 2),
              info = "x coordinates should be in WGS84 longitude range for Volta (Ghana)")
  expect_true(all(pts$y >= 5 & pts$y <= 12),
              info = "y coordinates should be in WGS84 latitude range for Volta (Ghana)")
  expect_false(any(pts$x > 100 | pts$y > 90),
              info = "Coordinates must not be in UTM — map rendering requires WGS84")

  map_file <- file.path(test_output_dir, "plots", "interactive_network_map.html")
  expect_true(file.exists(map_file), info = "Interactive network map HTML should be generated")
  map_html <- readLines(map_file, warn = FALSE)
  expect_true(any(grepl("Network Nodes", map_html)),
              info = "Network nodes layer must be present in map")
  expect_true(any(grepl("agglomeration", map_html, ignore.case = TRUE)),
              info = "Agglomeration nodes must be present in map")
})

test_that("RunSimulationPipeline produces chemical results on freshly built Volta network", {
  build_dir <- tempfile(pattern = "volta_wet_build_sim_")
  on.exit(unlink(build_dir, recursive = TRUE), add = TRUE)

  net_cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  net_cfg$run_output_dir <- build_dir
  state <- BuildNetworkPipeline(net_cfg)

  sim_dir <- tempfile(pattern = "volta_wet_chem_")
  on.exit(unlink(sim_dir, recursive = TRUE), add = TRUE)

  sim_cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
  sim_cfg$run_output_dir <- sim_dir
  sim_cfg$input_paths$pts <- file.path(build_dir, "pts.csv")
  sim_cfg$input_paths$hl <- file.path(build_dir, "HL.csv")
  sim_cfg$input_paths$rivers <- file.path(build_dir, "network_rivers.shp")
  state[names(sim_cfg)] <- sim_cfg

  results <- RunSimulationPipeline(state, substance = "Ibuprofen")

  expect_type(results, "list")
  expect_true("pts" %in% names(results))
  expect_equal(nrow(results$pts), nrow(read.csv(file.path(build_dir, "pts.csv"))))
})
