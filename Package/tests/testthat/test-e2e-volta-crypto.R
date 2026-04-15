library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")
prebuilt_network <- file.path(output_root, "volta_wet")

skip_if_not(dir.exists(data_root), "Volta data root not found")
skip_if_not(file.exists(file.path(prebuilt_network, "pts.csv")), "Pre-built Volta wet network not found")

test_that("LoadScenarioConfig resolves VoltaWetPathogenCrypto correctly", {
  cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
  expect_equal(cfg$basin_id, "volta")
  expect_equal(cfg$substance_type, "pathogen")
  expect_equal(cfg$pathogen_name, "cryptosporidium")
  expect_true(file.exists(cfg$input_paths$pts))
  expect_true(file.exists(cfg$input_paths$chem_data))
})

test_that("NormalizeScenarioState processes Volta wet pts.csv correctly", {
  pts_raw <- read.csv(file.path(prebuilt_network, "pts.csv"), stringsAsFactors = FALSE)
  HL <- read.csv(file.path(prebuilt_network, "HL.csv"), stringsAsFactors = FALSE)

  result <- NormalizeScenarioState(
    raw_network_nodes = pts_raw,
    lake_nodes = HL,
    study_country = "GH",
    basin_id = "volta",
    default_temp = 27.5,
    default_wind = 4.5
  )

  expect_type(result, "list")
  expect_true("normalized_network_nodes" %in% names(result))
  expect_true("lake_nodes" %in% names(result))
  nodes <- result$normalized_network_nodes
  expect_gte(nrow(nodes), 340)
  expect_true("T_AIR" %in% names(nodes))
  expect_true("Wind" %in% names(nodes))
  expect_true("Pt_type" %in% names(nodes))
  expect_true("Dist_down" %in% names(nodes))
  expect_true("node_id" %in% names(nodes))
})

test_that("AssignHydrology assigns flow to Volta nodes", {
  pts_raw <- read.csv(file.path(prebuilt_network, "pts.csv"), stringsAsFactors = FALSE)
  HL <- read.csv(file.path(prebuilt_network, "HL.csv"), stringsAsFactors = FALSE)

  normalized <- NormalizeScenarioState(pts_raw, HL, "GH", "volta", 27.5, 4.5)
  nodes <- normalized$normalized_network_nodes

  cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

  hydro_result <- AssignHydrology(
    network_nodes = nodes,
    input_paths = cfg$input_paths,
    dataDir = data_root,
    basin_id = "volta",
    prefer_highres_flow = FALSE,
    is_dry_season = FALSE
  )

  expect_type(hydro_result, "list")
  expect_true("network_nodes" %in% names(hydro_result))
  nodes_hydro <- hydro_result$network_nodes
  expect_true("Q" %in% names(nodes_hydro))
  expect_true("river_discharge" %in% names(nodes_hydro))
  expect_true(all(nodes_hydro$Q > 0))
})

test_that("CalculateEmissions produces consumption data for GH", {
  pts_raw <- read.csv(file.path(prebuilt_network, "pts.csv"), stringsAsFactors = FALSE)
  HL <- read.csv(file.path(prebuilt_network, "HL.csv"), stringsAsFactors = FALSE)

  normalized <- NormalizeScenarioState(pts_raw, HL, "GH", "volta", 27.5, 4.5)
  nodes <- normalized$normalized_network_nodes

  cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
  hydro_result <- AssignHydrology(nodes, cfg$input_paths, data_root, "volta")
  nodes_hydro <- hydro_result$network_nodes

  chem_data <- openxlsx::read.xlsx(cfg$input_paths$chem_data)
  if ("substance" %in% names(chem_data)) names(chem_data)[names(chem_data) == "substance"] <- "API"
  selected_row <- chem_data[chem_data$API == cfg$target_substance, ][1, ]
  chem <- CompleteChemProperties(chem = selected_row)

  emission_result <- CalculateEmissions(nodes_hydro, chem, "GH", cfg$target_substance)
  expect_true("cons" %in% names(emission_result))
  expect_s3_class(emission_result$cons, "data.frame")
})

test_that("Full RunSimulationPipeline produces positive pathogen concentrations for Volta Cryptosporidium wet", {
  build_dir <- tempfile(pattern = "volta_crypto_build_")
  on.exit(unlink(build_dir, recursive = TRUE), add = TRUE)

  net_cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  net_cfg$run_output_dir <- build_dir
  state <- BuildNetworkPipeline(net_cfg)

  test_output_dir <- tempfile(pattern = "volta_crypto_e2e_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)

  cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
  cfg$run_output_dir <- test_output_dir
  cfg$input_paths$pts <- file.path(build_dir, "pts.csv")
  cfg$input_paths$hl <- file.path(build_dir, "HL.csv")
  cfg$input_paths$rivers <- file.path(build_dir, "network_rivers.shp")

  results <- RunSimulationPipeline(state, substance = "cryptosporidium")

  expect_type(results, "list")
  expect_true("pts" %in% names(results))

  pts_out <- results$pts
  expect_true("C_w" %in% names(pts_out))
  n_positive <- sum(pts_out$C_w > 0, na.rm = TRUE)
  expect_gt(n_positive, 100)

  result_file <- file.path(test_output_dir, "results_pts_volta_cryptosporidium.csv")
  expect_true(file.exists(result_file))

  saved <- read.csv(result_file, stringsAsFactors = FALSE)
  expect_equal(nrow(saved), nrow(pts_out))
})
