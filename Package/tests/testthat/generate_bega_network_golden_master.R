library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")
gm_dir <- file.path(repo_root, "Package", "tests", "testthat", "golden_master")

if (!dir.exists(gm_dir)) {
  dir.create(gm_dir, recursive = TRUE)
}

message("Building Bega network for golden master v1.26...")
cfg <- LoadScenarioConfig("BegaNetwork", data_root, output_root)
test_output_dir <- tempfile(pattern = "bega_gm_")
cfg$run_output_dir <- test_output_dir

set.seed(42)
state <- BuildNetworkPipeline(cfg, stop_after_step = "09_save_artifacts")

gm <- list(
  version = "v1.26",
  basin_id = "bega",
  timestamp = Sys.time(),
  network_version = "v1.26",
  description = "Bega network golden master",
  points = state$points,
  HL_basin = state$HL_basin,
  hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
  agglomeration_points = state$agglomeration_points,
  lines = state$lines,
  Basin = state$Basin,
  network_summary = list(
    n_points = nrow(state$points),
    n_lakes = nrow(state$HL_basin),
    n_agglomerations = if (!is.null(state$agglomeration_points)) nrow(state$agglomeration_points) else 0,
    n_river_edges = if (!is.null(state$lines)) nrow(state$lines) else 0
  )
)

gm_path <- file.path(gm_dir, "gm_bega_network_v1.26.rds")
saveRDS(gm, gm_path)

message("Golden master saved to: ", gm_path)
message("Network summary:")
message("  Points: ", gm$network_summary$n_points)
message("  Lakes: ", gm$network_summary$n_lakes)
message("  Agglomerations: ", gm$network_summary$n_agglomerations)
message("  River edges: ", gm$network_summary$n_river_edges)

unlink(test_output_dir, recursive = TRUE)
