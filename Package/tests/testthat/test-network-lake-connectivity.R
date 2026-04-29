library(testthat)

context("Lake Connectivity Validation")

# Load checkpoint
checkpoint_path <- "Outputs/checkpoints/09_save_artifacts.rds"

test_that("Lake connectivity is correctly established", {
  skip_if(!file.exists(checkpoint_path), "No checkpoint found for connectivity tests")
  state <- readRDS(checkpoint_path)
  
  # Check LakeIn/LakeOut consistency. A lake may now have multiple physical
  # boundary inlets feeding one primary outlet, so counts do not need to match.
  lake_inlets <- state$points[state$points$lake_in == 1, ]
  lake_outlets <- state$points[state$points$lake_out == 1, ]

  # Validate each connected lake has at least one boundary inlet and outlet.
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

  # Strict lake routing must not create LakeIn/LakeOut nodes for skipped lakes.
  if (!is.null(state$lake_connection_diagnostics) && nrow(state$lake_connection_diagnostics) > 0) {
    skipped <- state$lake_connection_diagnostics[!state$lake_connection_diagnostics$active, , drop = FALSE]
    for (i in seq_len(nrow(skipped))) {
      lid <- skipped$Hylak_id[i]
      expect_false(any(grepl(paste0("^LakeIn_", lid, "(?:_|$)"), state$points$ID)),
                   info = paste("Skipped lake unexpectedly has inlet node:", lid))
      expect_false(paste0("LakeOut_", lid) %in% state$points$ID,
                   info = paste("Skipped lake unexpectedly has outlet node:", lid))
    }
  }
})
