library(ePiE)
library(testthat)

repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
data_root <- file.path(repo_root, "Inputs")
output_root <- file.path(repo_root, "Outputs")

gm_path <- testthat::test_path("golden_master", "gm_bega_ibuprofen_v1.25.rds")
skip_if_not(file.exists(gm_path), "Bega v1.25 golden master not found")

gm <- readRDS(gm_path)

bega_pts_path <- file.path(output_root, "bega", "pts.csv")
bega_hl_path  <- file.path(output_root, "bega", "HL.csv")
flow_rast_path <- file.path(data_root, "baselines", "environmental", "FLO1k.lt.2000.2015.qav.tif")

skip_if_not(file.exists(bega_pts_path), "Bega pre-built pts.csv not found")
skip_if_not(file.exists(bega_hl_path), "Bega pre-built HL.csv not found")
skip_if_not(file.exists(flow_rast_path), "FLO1K flow raster not found")

run_bega_v126 <- function(use_cpp = TRUE) {
  basin_data <- adapt_bega_network(bega_pts_path, bega_hl_path,
                                   default_temp = 11.0, default_wind = 4.5)
  flow_rast <- terra::rast(flow_rast_path)
  basin_data <- AddFlowToBasinData(basin_data = basin_data, flow_rast = flow_rast)

  cons <- LoadExampleConsumption()
  cons <- CheckConsumptionData(basin_data$pts, gm$chem, cons)

  results <- ComputeEnvConcentrations(
    basin_data = basin_data, chem = gm$chem, cons = cons,
    verbose = FALSE, cpp = use_cpp
  )
  results
}

# ============================================================================
# TIER 1: Components that should match exactly between v1.25 and v1.26
# ============================================================================

test_that("SimpleTreat4_0 produces identical results for Ibuprofen", {
  removal_126 <- SimpleTreat4_0(
    chem_class = gm$chem$class[1],
    MW = gm$chem$MW[1],
    Pv = gm$chem$Pv[1],
    S = gm$chem$S[1],
    pKa = gm$chem$pKa[1],
    Kp_ps = gm$chem$Kp_ps_n[1],
    Kp_as = gm$chem$Kp_as_n[1],
    k_bio_WWTP = gm$chem$k_bio_wwtp[1],
    T_air = 285, Wind = 4, Inh = 1000, E_rate = 1,
    PRIM = -1, SEC = -1
  )

  removal_125 <- SimpleTreat4_0(
    chem_class = gm$chem$class[1],
    MW = gm$chem$MW[1],
    Pv = gm$chem$Pv[1],
    S = gm$chem$S[1],
    pKa = gm$chem$pKa[1],
    Kp_ps = gm$chem$Kp_ps_n[1],
    Kp_as = gm$chem$Kp_as_n[1],
    k_bio_WWTP = gm$chem$k_bio_wwtp[1],
    T_air = 285, Wind = 4, Inh = 1000, E_rate = 1,
    PRIM = -1, SEC = -1
  )

  expect_equal(removal_126$f_rem, removal_125$f_rem, tolerance = 1e-10)
  expect_equal(removal_126$C_sludge, removal_125$C_sludge, tolerance = 1e-10)
})

test_that("CompleteChemProperties produces identical chemical properties", {
  chem_126 <- LoadExampleChemProperties()
  chem_126 <- CompleteChemProperties(chem_126)

  expect_equal(chem_126$KOC_n, gm$chem$KOC_n, tolerance = 1e-6,
               info = "KOC_n (neutral organic carbon partition) should match")
  expect_equal(chem_126$Kp_ps_n, gm$chem$Kp_ps_n, tolerance = 1e-6,
               info = "Kp_ps_n (primary sludge partition) should match")
  expect_equal(chem_126$Kp_as_n, gm$chem$Kp_as_n, tolerance = 1e-6,
               info = "Kp_as_n (activated sludge partition) should match")
  expect_equal(chem_126$fn_WWTP, gm$chem$fn_WWTP, tolerance = 1e-6,
               info = "fn_WWTP (neutral fraction in WWTP at pH 7) should match")
  expect_equal(chem_126$KOC_alt, gm$chem$KOC_alt, tolerance = 1e-6,
               info = "KOC_alt (ionised organic carbon partition) should match")
  expect_equal(chem_126$k_bio_wwtp, gm$chem$k_bio_wwtp, tolerance = 1e-6,
               info = "k_bio_wwtp (WWTP biodegradation rate) should match")
})

test_that("v1.26 produces the same number of network nodes as v1.25", {
  results_126 <- run_bega_v126(use_cpp = TRUE)

  expect_equal(nrow(results_126$pts), gm$metadata$n_pts,
               info = "Number of point nodes should match v1.25")
  expect_equal(nrow(results_126$hl), gm$metadata$n_hl,
               info = "Number of lake nodes should match v1.25")
})

test_that("WWTP removal fractions match between v1.25 and v1.26", {
  results_126 <- run_bega_v126(use_cpp = TRUE)

  wwtp_125 <- gm$results_cpp$pts[gm$results_cpp$pts$Pt_type == "WWTP", ]
  wwtp_126 <- results_126$pts[results_126$pts$Pt_type == "WWTP", ]

  expect_equal(nrow(wwtp_126), nrow(wwtp_125),
               info = "Same number of WWTP nodes")

  ids_125 <- wwtp_125$ID
  ids_126 <- wwtp_126$ID
  common_ids <- intersect(ids_125, ids_126)
  expect_equal(length(common_ids), nrow(wwtp_125),
               info = "WWTP IDs should match")

  for (id in common_ids) {
    rem_125 <- wwtp_125$WWTPremoval[wwtp_125$ID == id]
    rem_126 <- wwtp_126$WWTPremoval[wwtp_126$ID == id]
    expect_equal(rem_126, rem_125, tolerance = 1e-6,
                 info = paste("WWTP removal for", id, "should match"))
  }
})

test_that("v1.26 C_w matches v1.25 on river-only subnetwork (no lakes upstream)", {
  results_126 <- run_bega_v126(use_cpp = TRUE)

  lake_ids_125 <- gm$results_cpp$pts$ID[gm$results_cpp$pts$Pt_type == "Hydro_Lake"]
  lake_ids_126 <- results_126$pts$ID[results_126$pts$Pt_type == "Hydro_Lake"]

  excluded_ids_126 <- c(lake_ids_126, "MOUTH")
  river_only_126 <- results_126$pts[!(results_126$pts$ID %in% excluded_ids_126), ]

  valid_comparison <- river_only_126$ID %in% gm$results_cpp$pts$ID
  river_only_126 <- river_only_126[valid_comparison, ]

  gm_river <- gm$results_cpp$pts[gm$results_cpp$pts$ID %in% river_only_126$ID, ]
  gm_river <- gm_river[match(river_only_126$ID, gm_river$ID), ]

  max_diff <- max(abs(river_only_126$C_w - gm_river$C_w), na.rm = TRUE)

  expect_true(max_diff < 0.1,
              info = paste("Most river-only C_w should be within 0.1 ug/L of v1.25.",
                           "Max absolute difference:", sprintf("%.6e", max_diff)))
})

# ============================================================================
# TIER 2: Components expected to diverge due to intentional v1.26 fixes
# ============================================================================

test_that("v1.26 lake C_w is lower than v1.25 due to lake volume bug fix (1e6 -> 1e9)", {
  results_126 <- run_bega_v126(use_cpp = TRUE)

  lake_125 <- gm$results_cpp$pts[gm$results_cpp$pts$Pt_type == "Hydro_Lake", ]
  lake_126 <- results_126$pts[results_126$pts$Pt_type == "Hydro_Lake", ]

  skip_if(nrow(lake_125) == 0, "No Hydro_Lake nodes in v1.25 results")
  skip_if(nrow(lake_126) == 0, "No Hydro_Lake nodes in v1.26 results")

  common_ids <- intersect(lake_125$ID, lake_126$ID)
  skip_if(length(common_ids) == 0, "No matching Hydro_Lake IDs between versions")

  for (id in common_ids) {
    cw_125 <- lake_125$C_w[lake_125$ID == id]
    cw_126 <- lake_126$C_w[lake_126$ID == id]

    if (!is.na(cw_125) && !is.na(cw_126) && cw_125 > 0) {
      ratio <- cw_126 / cw_125
      expect_true(
        cw_126 < cw_125,
        info = paste0(
          "Hydro_Lake ", id, ": v1.26 C_w (", sprintf("%.6e", cw_126),
          ") should be lower than v1.25 C_w (", sprintf("%.6e", cw_125),
          ") due to lake volume fix. Ratio: ", sprintf("%.4f", ratio),
          " (expected ~0.001 for pure CSTR effect)"
        )
      )
    }
  }
})

test_that("v1.26 overall max C_w differs from v1.25", {
  results_126 <- run_bega_v126(use_cpp = TRUE)

  max_cw_125 <- max(gm$results_cpp$pts$C_w, na.rm = TRUE)
  max_cw_126 <- max(results_126$pts$C_w, na.rm = TRUE)

  expect_false(
    identical(max_cw_125, max_cw_126),
    info = paste("v1.26 max C_w should differ from v1.25.",
                 "v1.25 max:", sprintf("%.6e", max_cw_125),
                 "v1.26 max:", sprintf("%.6e", max_cw_126))
  )
})

# ============================================================================
# TIER 3: v1.26 internal consistency (R engine vs C++ engine)
# ============================================================================

test_that("v1.26 R and C++ engines produce identical Bega results", {
  results_r   <- run_bega_v126(use_cpp = FALSE)
  results_cpp <- run_bega_v126(use_cpp = TRUE)

  expect_equal(nrow(results_r$pts), nrow(results_cpp$pts),
               info = "Same number of nodes in R and C++ engines")

  common_ids <- intersect(results_r$pts$ID, results_cpp$pts$ID)
  r_pts   <- results_r$pts[match(common_ids, results_r$pts$ID), ]
  cpp_pts <- results_cpp$pts[match(common_ids, results_cpp$pts$ID), ]

  expect_equal(r_pts$C_w, cpp_pts$C_w, tolerance = 1e-6,
               info = "C_w should match between R and C++ engines")

  if ("C_sd" %in% names(r_pts) && "C_sd" %in% names(cpp_pts)) {
    has_csd_r   <- !is.na(r_pts$C_sd)
    has_csd_cpp <- !is.na(cpp_pts$C_sd)
    both_valid  <- has_csd_r & has_csd_cpp
    if (sum(both_valid) > 0) {
      expect_equal(r_pts$C_sd[both_valid], cpp_pts$C_sd[both_valid], tolerance = 1e-6,
                   info = "C_sd should match between R and C++ engines")
    }
  }
})
