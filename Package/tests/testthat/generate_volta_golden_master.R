library(ePiE)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")
gm_dir <- file.path(repo_root, "Package", "tests", "testthat", "golden_master")

if (!dir.exists(gm_dir)) {
  dir.create(gm_dir, recursive = TRUE)
}

message("Building Volta wet network for golden master v1.26...")
cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
test_output_dir <- tempfile(pattern = "volta_gm_")
cfg$run_output_dir <- test_output_dir

set.seed(42)
state <- BuildNetworkPipeline(cfg)

gm <- list(
  version = "v1.26",
  basin_id = "VoltaWet",
  timestamp = Sys.time(),
  network_version = "v1.26",
  description = "Volta wet network golden master with multi-inlet lake fix and simplification changes",
  points = state$points,
  hydro_sheds_rivers_basin = state$hydro_sheds_rivers_basin,
  HL_basin = state$HL_basin,
  agglomeration_points = state$agglomeration_points,
  lines = state$lines,
  network_summary = list(
    n_points = nrow(state$points),
    n_lakes = nrow(state$HL_basin),
    n_agglomerations = if (!is.null(state$agglomeration_points)) nrow(state$agglomeration_points) else 0,
    n_river_edges = if (!is.null(state$hydro_sheds_rivers_basin)) nrow(state$hydro_sheds_rivers_basin) else 0
  )
)

gm_path <- file.path(gm_dir, "gm_volta_wet_v1.26.rds")
saveRDS(gm, gm_path)

message("Golden master saved to: ", gm_path)
message("Network summary:")
message("  Points: ", gm$network_summary$n_points)
message("  Lakes: ", gm$network_summary$n_lakes)
message("  Agglomerations: ", gm$network_summary$n_agglomerations)
message("  River edges: ", gm$network_summary$n_river_edges)

unlink(test_output_dir, recursive = TRUE)