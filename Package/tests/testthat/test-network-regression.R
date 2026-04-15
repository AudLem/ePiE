library(ePiE)

gm_path <- testthat::test_path("golden_master", "gm_volta_wet_v1.26.rds")
skip_if_not(file.exists(gm_path), "Volta golden master file not found")

gm <- readRDS(gm_path)

test_that("Volta network topology matches golden master", {
  repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
  data_root <- file.path(repo_root, "Inputs")
  output_root <- file.path(repo_root, "Outputs")
  
  skip_if_not(dir.exists(data_root), "Volta data root not found")
  skip_if_not(dir.exists(file.path(data_root, "basins", "volta")), "Volta basin data not found")
  
  test_output_dir <- tempfile(pattern = "volta_gm_test_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)
  
  cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  cfg$run_output_dir <- test_output_dir
  
  set.seed(42)
  state <- BuildNetworkPipeline(cfg)
  
  expect_equal(nrow(state$points), gm$network_summary$n_points,
               info = "Number of points should match golden master")
  
  expect_equal(nrow(state$HL_basin), gm$network_summary$n_lakes,
               info = "Number of lakes should match golden master")
  
  if (!is.null(state$agglomeration_points)) {
    expect_equal(nrow(state$agglomeration_points), gm$network_summary$n_agglomerations,
                 info = "Number of agglomerations should match golden master")
  }
  
  if (!is.null(state$hydro_sheds_rivers_basin)) {
    expect_equal(nrow(state$hydro_sheds_rivers_basin), gm$network_summary$n_river_edges,
                 info = "Number of river edges should match golden master")
  }
})

test_that("Volta network point IDs match golden master", {
  repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
  data_root <- file.path(repo_root, "Inputs")
  output_root <- file.path(repo_root, "Outputs")
  
  skip_if_not(dir.exists(data_root), "Volta data root not found")
  skip_if_not(dir.exists(file.path(data_root, "basins", "volta")), "Volta basin data not found")
  
  test_output_dir <- tempfile(pattern = "volta_gm_ids_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)
  
  cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  cfg$run_output_dir <- test_output_dir
  
  set.seed(42)
  state <- BuildNetworkPipeline(cfg)
  
  expect_equal(state$points$ID, gm$points$ID,
               info = "Point IDs should match golden master")
  
  expect_equal(state$points$pt_type, gm$points$pt_type,
               info = "Point types should match golden master")
})

test_that("Volta network point coordinates match golden master", {
  repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
  data_root <- file.path(repo_root, "Inputs")
  output_root <- file.path(repo_root, "Outputs")
  
  skip_if_not(dir.exists(data_root), "Volta data root not found")
  skip_if_not(dir.exists(file.path(data_root, "basins", "volta")), "Volta basin data not found")
  
  test_output_dir <- tempfile(pattern = "volta_gm_coords_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)
  
  cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  cfg$run_output_dir <- test_output_dir
  
  set.seed(42)
  state <- BuildNetworkPipeline(cfg)
  
  coords_current <- sf::st_coordinates(state$points)
  coords_gm <- sf::st_coordinates(gm$points)
  
  expect_equal(coords_current, coords_gm,
               info = "Point coordinates should match golden master")
})

test_that("Volta lake connectivity matches golden master", {
  repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
  data_root <- file.path(repo_root, "Inputs")
  output_root <- file.path(repo_root, "Outputs")
  
  skip_if_not(dir.exists(data_root), "Volta data root not found")
  skip_if_not(dir.exists(file.path(data_root, "basins", "volta")), "Volta basin data not found")
  
  test_output_dir <- tempfile(pattern = "volta_gm_lake_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)
  
  cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  cfg$run_output_dir <- test_output_dir
  
  set.seed(42)
  state <- BuildNetworkPipeline(cfg)
  
  current_lake_nodes <- state$points[state$points$pt_type %in% c("LakeInlet", "LakeOutlet"), ]
  gm_lake_nodes <- gm$points[gm$points$pt_type %in% c("LakeInlet", "LakeOutlet"), ]
  
  expect_equal(nrow(current_lake_nodes), nrow(gm_lake_nodes),
               info = "Number of lake nodes should match golden master")
  
  if (nrow(current_lake_nodes) > 0) {
    expect_equal(current_lake_nodes$HL_ID_new, gm_lake_nodes$HL_ID_new,
                 info = "Lake IDs should match golden master")
    
    expect_equal(current_lake_nodes$ID_nxt, gm_lake_nodes$ID_nxt,
                 info = "Lake node connectivity should match golden master")
  }
})

test_that("Volta network topology is consistent with golden master", {
  repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
  data_root <- file.path(repo_root, "Inputs")
  output_root <- file.path(repo_root, "Outputs")
  
  skip_if_not(dir.exists(data_root), "Volta data root not found")
  skip_if_not(dir.exists(file.path(data_root, "basins", "volta")), "Volta basin data not found")
  
  test_output_dir <- tempfile(pattern = "volta_gm_topo_")
  on.exit(unlink(test_output_dir, recursive = TRUE), add = TRUE)
  
  cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
  cfg$run_output_dir <- test_output_dir
  
  set.seed(42)
  state <- BuildNetworkPipeline(cfg)
  
  expect_equal(state$points$ID_nxt, gm$points$ID_nxt,
               info = "Network topology (ID_nxt) should match golden master")
  
  expect_equal(state$points$LD, gm$points$LD,
               info = "Distance from source (LD) should match golden master")
})