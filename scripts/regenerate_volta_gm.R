#!/usr/bin/env Rscript

library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

cat("=== Regenerating Volta Wet Golden Master ===\n")

cfg_volta <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
test_output_dir <- tempfile(pattern = "volta_gm_update_")
cfg_volta$run_output_dir <- test_output_dir

set.seed(42)
state_volta <- BuildNetworkPipeline(cfg_volta, stop_after_step = "09_save_artifacts")

gm_volta <- list(
  network_summary = list(
    n_points = nrow(state_volta$points),
    n_lakes = nrow(state_volta$HL_basin),
    n_river_edges = nrow(state_volta$hydro_sheds_rivers_basin),
    n_agglomerations = if (!is.null(state_volta$agglomeration_points)) nrow(state_volta$agglomeration_points) else 0
  ),
  points = state_volta$points
)

gm_path <- file.path(repo_root, "Package/tests/testthat/golden_master/gm_volta_wet_v1.26.rds")
saveRDS(gm_volta, gm_path)

cat("Volta wet golden master saved to:", gm_path, "\n")
cat("  Points:", gm_volta$network_summary$n_points, "\n")
cat("  Lakes:", gm_volta$network_summary$n_lakes, "\n")
cat("  River edges:", gm_volta$network_summary$n_river_edges, "\n")
