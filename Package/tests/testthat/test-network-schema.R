library(testthat)

context("Network Schema Validation")

# Load a checkpoint if available for testing
checkpoint_path <- "Outputs/checkpoints/09_save_artifacts.rds"

test_that("Network schema is consistent after pipeline execution", {
  skip_if(!file.exists(checkpoint_path), "No checkpoint found to test schema")
  state <- readRDS(checkpoint_path)
  
  # Check for mandatory topology
  expect_consistent_schema(state)
  
  # Validate network integrity
  expect_valid_network(state)
  
  # Validate coordinate bounds (sanity check)
  # Volta: x[-2, 2], y[5, 12]
  # Bega: x[24, 30], y[44, 48]
  if (state$basin_id == "volta") {
    expect_true(all(state$points$x >= -2 && state$points$x <= 2), "Volta longitude out of bounds")
    expect_true(all(state$points$y >= 5 && state$points$y <= 12), "Volta latitude out of bounds")
  }

  # No duplicate IDs
  expect_equal(length(unique(state$points$ID)), nrow(state$points), info = "Duplicate IDs found in points")

  # ID_nxt consistency (dangling edges)
  # Check if all non-NA ID_nxt are in points$ID
  dangling <- state$points$ID_nxt[!is.na(state$points$ID_nxt) & !(state$points$ID_nxt %in% state$points$ID)]
  expect_equal(length(dangling), 0, info = paste("Dangling edges detected:", paste(unique(head(dangling)), collapse=",")))

  # lake_in / lake_out consistency
  testthat::expect_true("lake_in" %in% names(state$points))
  testthat::expect_true("lake_out" %in% names(state$points))
})
