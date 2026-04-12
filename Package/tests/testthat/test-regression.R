library(ePiE)

gm_path <- testthat::test_path("golden_master", "gm_ouse_ibuprofen_r_v1.25.rds")
skip_if_not(file.exists(gm_path), "Golden master file not found")

gm <- readRDS(gm_path)

test_that("SimpleTreat 4.0 produces stable results for Ibuprofen", {
  removal <- SimpleTreat4_0(
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
  expect_equal(removal$f_rem, gm$removal$f_rem, tolerance = 1e-6)
  expect_equal(removal$C_sludge, gm$removal$C_sludge, tolerance = 1e-6)
})

test_that("CompleteChemProperties produces stable chem table", {
  chem <- LoadExampleChemProperties()
  chem <- CompleteChemProperties(chem = chem)
  expect_equal(ncol(chem), ncol(gm$chem))
  expect_equal(chem$KOC_n, gm$chem$KOC_n, tolerance = 1e-6)
  expect_equal(chem$Kp_ps_n, gm$chem$Kp_ps_n, tolerance = 1e-6)
  expect_equal(chem$Kp_as_n, gm$chem$Kp_as_n, tolerance = 1e-6)
  expect_equal(chem$fn_WWTP, gm$chem$fn_WWTP, tolerance = 1e-6)
})

test_that("R engine produces stable concentration results for Ouse/Ibuprofen", {
  cons <- LoadExampleConsumption()
  basins <- LoadEuropeanBasins()
  basins <- SelectBasins(basins_data = basins, basin_ids = c(107287))
  cons <- CheckConsumptionData(basins$pts, gm$chem, cons)
  flow_avg <- LoadLongTermFlow("average")
  basins_avg <- AddFlowToBasinData(basin_data = basins, flow_rast = flow_avg)
  results <- ComputeEnvConcentrations(
    basin_data = basins_avg, chem = gm$chem, cons = cons,
    verbose = FALSE, cpp = FALSE
  )

  expect_s3_class(results$pts, "data.frame")
  expect_equal(nrow(results$pts), nrow(gm$results_r$pts))
  expect_equal(results$pts$C_w, gm$results_r$pts$C_w, tolerance = 1e-6)
  if (!is.null(results$hl) && nrow(results$hl) > 0) {
    expect_equal(results$hl$C_w, gm$results_r$hl$C_w, tolerance = 1e-6)
  }
})

test_that("C++ engine produces stable concentration results for Ouse/Ibuprofen", {
  cons <- LoadExampleConsumption()
  basins <- LoadEuropeanBasins()
  basins <- SelectBasins(basins_data = basins, basin_ids = c(107287))
  cons <- CheckConsumptionData(basins$pts, gm$chem, cons)
  flow_avg <- LoadLongTermFlow("average")
  basins_avg <- AddFlowToBasinData(basin_data = basins, flow_rast = flow_avg)
  results <- ComputeEnvConcentrations(
    basin_data = basins_avg, chem = gm$chem, cons = cons,
    verbose = FALSE, cpp = TRUE
  )

  expect_s3_class(results$pts, "data.frame")
  expect_equal(nrow(results$pts), nrow(gm$results_cpp$pts))
  expect_equal(results$pts$C_w, gm$results_cpp$pts$C_w, tolerance = 1e-6)
})

test_that("R and C++ engines produce identical results", {
  expect_equal(gm$results_r$pts$C_w, gm$results_cpp$pts$C_w, tolerance = 1e-10)
  expect_equal(gm$results_r$pts$ID, gm$results_cpp$pts$ID)
})
