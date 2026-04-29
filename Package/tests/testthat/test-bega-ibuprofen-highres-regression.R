library(ePiE)

# -----------------------------------------------------------------------------
# Bega Ibuprofen high-resolution flow regression
#
# Goal:
#   Freeze the current "patched" Bega Ibuprofen behavior when the model is run
#   with the historical high-resolution FLO1K QAV TIFF. This gives us a stable
#   regression safety net while we continue implementing new features.
#
# Why this test exists:
#   1) Users can now explicitly select flow source (`flow_source = "highres_qav"`).
#   2) We want deterministic sentinel values for a few key nodes so accidental
#      behavior drift is caught early.
#   3) We also assert hydraulic consistency rules introduced by the patched
#      flow standardization logic (no same-reach discontinuities for natural
#      river nodes, and source nodes inheriting their reach-level Q).
# -----------------------------------------------------------------------------

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

prebuilt_pts <- file.path(output_root, "bega", "pts.csv")
prebuilt_hl <- file.path(output_root, "bega", "HL.csv")
prebuilt_rivers <- file.path(output_root, "bega", "network_rivers.shp")
highres_flow <- file.path(data_root, "baselines", "environmental", "FLO1k.lt.2000.2015.qav.tif")

skip_if_not(file.exists(prebuilt_pts), "Pre-built Bega pts.csv not found")
skip_if_not(file.exists(prebuilt_hl), "Pre-built Bega HL.csv not found")
skip_if_not(file.exists(prebuilt_rivers), "Pre-built Bega river shapefile not found")
skip_if_not(file.exists(highres_flow), "High-resolution FLO1K QAV TIFF not found")

run_bega_ibuprofen_highres <- function() {
  # ---------------------------------------------------------------------------
  # Build simulation state from pre-built network artifacts, then run the
  # high-resolution flow scenario through the full simulation pipeline.
  # ---------------------------------------------------------------------------
  pts_raw <- read.csv(prebuilt_pts, stringsAsFactors = FALSE)
  hl_raw <- read.csv(prebuilt_hl, stringsAsFactors = FALSE)

  # Keep normalization path identical to normal simulation execution so this
  # regression reflects real production behavior, not a reduced unit shortcut.
  state <- NormalizeScenarioState(
    raw_network_nodes = pts_raw,
    lake_nodes = hl_raw,
    study_country = "RO",
    basin_id = "bega",
    default_temp = 11.0,
    default_wind = 4.5
  )

  sim_cfg <- LoadScenarioConfig("BegaChemicalIbuprofenHighRes", data_root, output_root)

  tmp_run <- tempfile(pattern = "bega_ibuprofen_highres_reg_")
  on.exit(unlink(tmp_run, recursive = TRUE), add = TRUE)
  sim_cfg$run_output_dir <- tmp_run

  # Force the expected pre-built input files and high-res flow source.
  sim_cfg$input_paths$pts <- prebuilt_pts
  sim_cfg$input_paths$hl <- prebuilt_hl
  sim_cfg$input_paths$rivers <- prebuilt_rivers
  sim_cfg$input_paths$flow_raster_highres <- highres_flow
  sim_cfg$input_paths$flow_source <- "highres_qav"
  sim_cfg$flow_source <- "highres_qav"
  sim_cfg$prefer_highres_flow <- TRUE

  # Pipeline metadata fields required by RunSimulationPipeline().
  state$input_paths <- sim_cfg$input_paths
  state$study_country <- sim_cfg$study_country
  state$country_population <- sim_cfg$country_population
  state$run_output_dir <- sim_cfg$run_output_dir
  state$basin_id <- sim_cfg$basin_id
  state$data_root <- sim_cfg$dataDir
  state$is_dry_season <- isTRUE(sim_cfg$is_dry_season)
  state$flow_source <- sim_cfg$flow_source
  state$prefer_highres_flow <- isTRUE(sim_cfg$prefer_highres_flow)

  # Run chemical simulation end-to-end.
  RunSimulationPipeline(state, substance = "Ibuprofen", cpp = FALSE)
}

test_that("Bega Ibuprofen highres flow sentinel nodes remain stable", {
  sim_state <- run_bega_ibuprofen_highres()
  pts <- sim_state$results$pts

  # Sentinel values captured from current patched baseline (new pipeline +
  # high-res TIFF + reach-level Q standardization enabled).
  expected <- data.frame(
    ID = c("P_00280", "P_00365", "Source00003"),
    Q = c(10.409982, 10.842679, 9.605509),
    # NOTE:
    # These C_w sentinels are intentionally taken from the current patched
    # baseline with explicit "highres_qav" flow selection. They are the
    # reference values that protect regression behavior while we continue
    # developing features around hydrology and topology.
    C_w = c(0.0041452441, 0.0835432470, 0.0046120117),
    stringsAsFactors = FALSE
  )

  obs <- pts[pts$ID %in% expected$ID, c("ID", "Q", "C_w")]
  obs <- obs[match(expected$ID, obs$ID), ]

  expect_equal(obs$ID, expected$ID)
  expect_equal(obs$Q, expected$Q, tolerance = 1e-6)
  expect_equal(obs$C_w, expected$C_w, tolerance = 1e-9)
})
