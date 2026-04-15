library(testthat)

context("Lake Connectivity Validation")

# Load checkpoint
checkpoint_path <- "Outputs/checkpoints/09_save_artifacts.rds"

test_that("Lake connectivity is correctly established", {
  skip_if(!file.exists(checkpoint_path), "No checkpoint found for connectivity tests")
  state <- readRDS(checkpoint_path)
  
  # Check expected connected lake count (Volta scenario)
  if (state$basin_id == "volta") {
    connected_lakes <- unique(state$points$HL_ID_new[state$points$HL_ID_new != 0])
    expected_ids <- c(1405722, 1405733, 180414, 1405735, 1405736, 1405738)
    
    expect_equal(length(connected_lakes), length(expected_ids), info = "Number of connected lakes mismatch")
    expect_true(all(expected_ids %in% connected_lakes), info = "Missing expected lake IDs")
  }
  
  # Check LakeIn/LakeOut consistency
  lake_inlets <- state$points[state$points$lake_in == 1, ]
  lake_outlets <- state$points[state$points$lake_out == 1, ]
  
  expect_equal(nrow(lake_inlets), nrow(lake_outlets), info = "LakeIn count != LakeOut count")
  
  # Validate each connected lake has a pair
  for (lid in unique(state$points$HL_ID_new[state$points$HL_ID_new != 0])) {
    inlets <- lake_inlets[lake_inlets$HL_ID_new == lid, ]
    outlets <- lake_outlets[lake_outlets$HL_ID_new == lid, ]
    
    expect_true(nrow(inlets) >= 1, paste("No inlet for lake", lid))
    expect_true(nrow(outlets) >= 1, paste("No outlet for lake", lid))
    
    # Check for coincident-node bug
    for (i in 1:nrow(inlets)) {
      for (j in 1:nrow(outlets)) {
        in_geom <- sf::st_coordinates(inlets[i, ])
        out_geom <- sf::st_coordinates(outlets[j, ])
        expect_false(all(in_geom == out_geom), paste("Coincident LakeIn/LakeOut nodes for lake", lid))
      }
    }
  }
})
