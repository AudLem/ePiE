library(testthat)

test_that("Pipeline generation is deterministic", {
  # Define a minimal config for Volta/Bega
  # This assumes we have a working config loader
  cfg <- VoltaBasinConfig(data_root = "../Inputs")
  
  # Ensure we have a clean output directory for this test
  tmp_dir <- "Outputs/test_determinism"
  cfg$run_output_dir <- tmp_dir
  
  # Run pipeline twice
  message("Running first pipeline pass...")
  state1 <- BuildNetworkPipeline(cfg)
  
  message("Running second pipeline pass...")
  state2 <- BuildNetworkPipeline(cfg)
  
  # Compare critical artifacts
  expect_identical(state1$pts, state2$pts, info = "Points data differ between runs")
  expect_identical(state1$HL_basin, state2$HL_basin, info = "Lake data differ between runs")
  expect_identical(state1$lines, state2$lines, info = "River lines differ between runs")
})
