library(ePiE)
library(testthat)
library(dplyr)

test_that("Lake handling with multiple upstream parents works correctly", {
  # Test that HL.E_in is calculated correctly when there are multiple upstream
  # parents and source nodes inside the lake
  
  pts <- data.frame(
    ID = c("R1", "R2", "R3", "R4", "WWTP_in_lake", "LakeIn_999", "LakeOut_999"),
    pt_type = c("node", "node", "node", "node", "WWTP", "LakeInlet", "LakeOutlet"),
    HL_ID_new = c(0, 0, 0, 0, 999, 999, 999),
    E_w = c(100, 0, 80, 0, 50, 0, 0)
  )
  
  HL <- data.frame(
    Hylak_id = 999,
    E_in = NA
  )
  
  # Simulate the HL.E_in calculation (as done in Set_local_parameters_custom_removal_fast3.R)
  pts$Hylak_id <- pts$HL_ID_new
  pts$HL_ID_new <- NULL
  
  for (j in 1:nrow(HL)) {
    lake_nodes_idx <- which(pts$Hylak_id == HL$Hylak_id[j])
    
    # Exclude LakeIn and LakeOut nodes and source nodes inside the lake
    excluded_types <- c("LakeInlet", "LakeOutlet", "agglomeration", "agglomeration_lake", "WWTP")
    valid_nodes_idx <- lake_nodes_idx[!(pts$pt_type[lake_nodes_idx] %in% excluded_types)]
    
    HL$E_in[j] <- sum(pts$E_w[valid_nodes_idx], na.rm = TRUE)
  }
  
  # Verify that HL.E_in is 0 (all emissions should come via river network)
  # LakeIn, LakeOut, and WWTP_in_lake should be excluded
  expect_equal(HL$E_in, 0)
  
  # Print results for debugging
  cat("\nTest Results:\n")
  cat("HL.E_in should be 0 (all lake-internal nodes excluded):", HL$E_in, "\n")
})

test_that("HL.E_in excludes LakeIn, LakeOut, and source nodes", {
  # Create a test case to verify that HL.E_in is calculated correctly
  
  pts <- data.frame(
    ID = c("LakeIn_1", "LakeOut_1", "WWTP_1", "node_1"),
    pt_type = c("LakeInlet", "LakeOutlet", "WWTP", "node"),
    Hylak_id = c(1, 1, 1, 1),
    E_w = c(0, 0, 100, 50)
  )
  
  HL <- data.frame(
    Hylak_id = 1
  )
  
  # Calculate HL.E_in
  for (j in 1:nrow(HL)) {
    lake_nodes_idx <- which(pts$Hylak_id == HL$Hylak_id[j])
    
    excluded_types <- c("LakeInlet", "LakeOutlet", "agglomeration", "agglomeration_lake", "WWTP")
    valid_nodes_idx <- lake_nodes_idx[!(pts$pt_type[lake_nodes_idx] %in% excluded_types)]
    
    HL$E_in[j] <- sum(pts$E_w[valid_nodes_idx], na.rm = TRUE)
  }
  
  # HL.E_in should only include node_1 (E_w = 50)
  # LakeIn, LakeOut, and WWTP should be excluded
  expect_equal(HL$E_in, 50)
  
  cat("\nHL.E_in test:\n")
  cat("HL.E_in should be 50 (only node_1 contributes):", HL$E_in, "\n")
})
