#!/usr/bin/env Rscript

library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

cat("=== Regenerating Bega Golden Master ===\n")

cfg_bega <- LoadScenarioConfig("BegaNetwork", data_root, output_root)
test_output_dir <- tempfile(pattern = "bega_gm_update_")
cfg_bega$run_output_dir <- test_output_dir

set.seed(42)
state_bega <- BuildNetworkPipeline(cfg_bega, stop_after_step = "09_save_artifacts")

gm_bega <- list(
  network_summary = list(
    n_points = nrow(state_bega$points),
    n_lakes = nrow(state_bega$HL_basin),
    n_river_edges = nrow(state_bega$hydro_sheds_rivers_basin),
    n_agglomerations = if (!is.null(state_bega$agglomeration_points)) nrow(state_bega$agglomeration_points) else 0
  ),
  points = state_bega$points
)

gm_path <- file.path(repo_root, "Package/tests/testthat/golden_master/gm_bega_network_v1.26.rds")
saveRDS(gm_bega, gm_path)

cat("Bega golden master saved to:", gm_path, "\n")
cat("  Points:", gm_bega$network_summary$n_points, "\n")
cat("  Lakes:", gm_bega$network_summary$n_lakes, "\n")
cat("  River edges:", gm_bega$network_summary$n_river_edges, "\n")
