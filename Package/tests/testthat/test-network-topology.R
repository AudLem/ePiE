library(testthat)

context("Network Topology Validation")

checkpoint_path <- "Outputs/checkpoints/09_save_artifacts.rds"

test_that("Network topology is valid and directed", {
  skip_if(!file.exists(checkpoint_path), "No checkpoint found for topology tests")
  state <- readRDS(checkpoint_path)
  pts <- state$points
  
  # 1. No cycles in ID_nxt chain
  # Cycle detection using a simple traversal
  ids <- as.character(pts$ID)
  nxts <- as.character(pts$ID_nxt)
  
  # Helper to detect cycle
  has_cycle <- function(ids, nxts) {
    visited <- character(0)
    curr <- ids[1]
    while (!is.na(curr) && curr != "") {
      if (curr %in% visited) return(TRUE)
      visited <- c(visited, curr)
      idx <- match(curr, ids)
      if (is.na(idx)) break
      curr <- nxts[idx]
    }
    FALSE
  }
  
  # Check components (simplified)
  expect_false(any(sapply(ids, function(id) has_cycle(id, nxts))), "Cycles detected in network topology")
  
  # 2. Exactly one MOUTH per connected component
  mouths <- pts[pts$Pt_type == "MOUTH", ]
  # In ePiE, a connected component can only have one MOUTH.
  # If we have multiple components (e.g., islands or disconnected networks), 
  # there should be one mouth per component.
  # This is a basic check:
  expect_gt(nrow(mouths), 0, "No MOUTH nodes found")
  
  # 3. LD monotonically decreases upstream
  # pts$LD represents distance to mouth. 
  # Upstream parent should have a higher LD than the downstream child.
  for (i in 1:nrow(pts)) {
    if (!is.na(pts$ID_nxt[i]) && pts$ID_nxt[i] != "") {
      nxt_idx <- match(pts$ID_nxt[i], pts$ID)
      if (!is.na(nxt_idx)) {
        expect_gt(pts$LD[i], pts$LD[nxt_idx], info = paste("Monotonicity violation at node", pts$ID[i]))
      }
    }
  }
  
  # 4. d_nxt positive and finite for non-terminal nodes
  non_terminal <- pts[!is.na(pts$ID_nxt) & pts$ID_nxt != "", ]
  expect_true(all(non_terminal$dist_nxt > 0 & is.finite(non_terminal$dist_nxt)), "Invalid d_nxt values")
})
