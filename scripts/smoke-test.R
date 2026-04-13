#!/usr/bin/env Rscript
# smoke-test.R - Verify ePiE installation and data integrity
#
# Usage:
#   Rscript scripts/smoke-test.R [DATA_ROOT] [OUTPUT_ROOT]
#
# Exits with code 0 on success, 1 on failure.

args <- commandArgs(trailingOnly = TRUE)

pass <- function(msg) cat(sprintf("  [PASS] %s\n", msg))
fail <- function(msg) {
  cat(sprintf("  [FAIL] %s\n", msg))
  if (!exists("n_fail")) n_fail <- 0L
  n_fail <<- n_fail + 1L
}
warn <- function(msg) cat(sprintf("  [WARN] %s\n", msg))

n_fail <- 0L

repo_root <- if (length(args) >= 1) args[1] else {
  tryCatch(normalizePath("."), error = function(e) ".")
}
output_root <- if (length(args) >= 2) args[2] else repo_root

cat(">>> ePiE Smoke Test\n")
cat(sprintf("    Repo root:   %s\n", normalizePath(repo_root, mustWork = FALSE)))
cat(sprintf("    Output root: %s\n", normalizePath(output_root, mustWork = FALSE)))
cat("\n")

# --- 1. Package loads ---
cat("[1/6] Loading ePiE package...\n")
tryCatch({
  library(ePiE)
  pass("library(ePiE) loaded successfully")
}, error = function(e) {
  fail(paste("library(ePiE) failed:", e$message))
})
cat("\n")

# --- 2. ListScenarios ---
cat("[2/6] Checking scenario registry...\n")
if (exists("ListScenarios", where = asNamespace("ePiE"))) {
  scenarios <- ePiE::ListScenarios()
  n_scenarios <- length(scenarios)
  if (n_scenarios >= 28) {
    pass(sprintf("ListScenarios() returned %d scenarios", n_scenarios))
  } else {
    fail(sprintf("Expected >= 28 scenarios, got %d", n_scenarios))
  }
} else {
  fail("ListScenarios() not found in ePiE namespace")
}
cat("\n")

# --- 3. LoadScenarioConfig ---
cat("[3/6] Loading scenario config...\n")
tryCatch({
  cfg <- ePiE::LoadScenarioConfig(
    "VoltaWetChemicalIbuprofen",
    data_root = file.path(repo_root, "Inputs"),
    output_root = file.path(output_root, "Outputs")
  )
  if (is.list(cfg) && !is.null(cfg$basin_id)) {
    pass(sprintf("LoadScenarioConfig() works — basin_id=%s", cfg$basin_id))
  } else {
    fail("LoadScenarioConfig() returned unexpected structure")
  }
}, error = function(e) {
  fail(paste("LoadScenarioConfig() failed:", e$message))
})
cat("\n")

# --- 4. Pathogen parameter files ---
cat("[4/6] Loading pathogen parameter files...\n")
pathogen_files <- c("cryptosporidium", "giardia", "rotavirus", "campylobacter")
for (pf in pathogen_files) {
  tryCatch({
    pkg_file <- system.file("pathogen_input", paste0(pf, ".R"), package = "ePiE")
    if (nchar(pkg_file) == 0) {
      fail(sprintf("%s.R not found in inst/pathogen_input", pf))
      next
    }
    source(pkg_file, local = TRUE)
    if (exists("simulation_parameters") && is.list(simulation_parameters)) {
      pass(sprintf("%s parameter file loaded (%d fields)", pf, length(simulation_parameters)))
      rm(simulation_parameters)
    } else {
      fail(sprintf("%s parameter file did not define simulation_parameters", pf))
    }
  }, error = function(e) {
    fail(sprintf("%s failed: %s", pf, e$message))
  })
}
cat("\n")

# --- 5. Data file presence ---
cat("[5/6] Checking data file presence...\n")
data_root <- file.path(repo_root, "Inputs")
out_root <- file.path(output_root, "Outputs")

required_files <- list(
  basins = list(
    list(path = "basins/volta/small_sub_basin_volta_dissolved.shp", desc = "Volta river shapefile"),
    list(path = "basins/volta/geoglows/streams_in_volta_basin.gpkg", desc = "GeoGLOWS streams"),
    list(path = "basins/bega/bega_basin.shp", desc = "Bega basin shapefile")
  ),
  user = list(
    list(path = "user/chem_Oldenkamp2018_SI.xlsx", desc = "Chemical properties"),
    list(path = "user/EEF_points_updated.csv", desc = "EEF points")
  ),
  outputs = list(
    list(path = "volta_wet/pts.csv", desc = "Volta wet network"),
    list(path = "volta_dry/pts.csv", desc = "Volta dry network"),
    list(path = "volta_geoglows_wet/pts.csv", desc = "Volta GeoGLOWS network"),
    list(path = "bega/pts.csv", desc = "Bega network")
  )
)

for (group in names(required_files)) {
  for (item in required_files[[group]]) {
    root_dir <- if (group == "outputs") out_root else data_root
    full_path <- file.path(root_dir, item$path)
    if (file.exists(full_path)) {
      pass(item$desc)
    } else {
      warn(sprintf("%s — not found at %s", item$desc, item$path))
    }
  }
}
cat("\n")

# --- 6. Optional: check pre-built network C_w > 0 ---
cat("[6/6] Checking pre-built network results (optional)...\n")
pts_path <- file.path(out_root, "volta_wet", "pts.csv")
if (file.exists(pts_path)) {
  tryCatch({
    pts <- read.csv(pts_path, stringsAsFactors = FALSE)
    if ("C_w" %in% names(pts)) {
      n_positive <- sum(pts$C_w > 0, na.rm = TRUE)
      n_total <- nrow(pts)
      if (n_positive > 0) {
        pass(sprintf("C_w > 0 at %d/%d nodes in volta_wet network", n_positive, n_total))
      } else {
        warn("All C_w values are 0 or NA in volta_wet network")
      }
    } else {
      warn("No C_w column in volta_wet/pts.csv")
    }
  }, error = function(e) {
    warn(paste("Could not read volta_wet/pts.csv:", e$message))
  })
} else {
  warn("volta_wet/pts.csv not found — skipping network check")
}
cat("\n")

# --- Summary ---
cat(">>> Summary\n")
if (n_fail == 0L) {
  cat("    All tests passed.\n")
  quit(status = 0)
} else {
  cat(sprintf("    %d test(s) FAILED.\n", n_fail))
  quit(status = 1)
}
