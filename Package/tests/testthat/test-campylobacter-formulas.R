library(ePiE)

test_that("LoadPathogenParameters loads and validates campylobacter", {
  params <- LoadPathogenParameters("campylobacter")
  expect_equal(params$type, "pathogen")
  expect_equal(params$name, "campylobacter")
  expect_equal(params$prevalence_rate, 0.11)
  expect_equal(params$excretion_rate, 1e11)
  expect_true(params$decay_rate_base > 0)
  expect_equal(params$units, "CFU/L")
})

test_that("campylobacter decays faster than cryptosporidium at 20C", {
  campy <- LoadPathogenParameters("campylobacter")
  crypto <- LoadPathogenParameters("cryptosporidium")

  K_T_campy <- ePiE:::calc_temp_decay(campy$decay_rate_base, 20, campy$temp_corr_factor)
  K_T_crypto <- ePiE:::calc_temp_decay(crypto$decay_rate_base, 20, crypto$temp_corr_factor)

  expect_true(K_T_campy > K_T_crypto)
})

test_that("campylobacter WWTP removal is higher than cryptosporidium", {
  campy <- LoadPathogenParameters("campylobacter")
  crypto <- LoadPathogenParameters("cryptosporidium")

  expect_true(campy$wwtp_primary_removal > crypto$wwtp_primary_removal)
  expect_true(campy$wwtp_secondary_removal > crypto$wwtp_secondary_removal)
})

test_that("campylobacter decay formulas produce reasonable k values", {
  campy <- LoadPathogenParameters("campylobacter")

  K_T <- ePiE:::calc_temp_decay(campy$decay_rate_base, 25, campy$temp_corr_factor)
  expect_true(K_T > 0)
  expect_true(K_T < 10)

  K_S <- ePiE:::calc_sedimentation_decay(campy$settling_velocity, 1.5)
  expect_true(K_S > 0)
  expect_true(K_S < 10)
})

test_that("campylobacter parameters include units field", {
  params <- LoadPathogenParameters("campylobacter")
  expect_true("units" %in% names(params))
  expect_equal(params$units, "CFU/L")
})

test_that("cryptosporidium falls back to oocysts/L when units field absent", {
  crypto <- LoadPathogenParameters("cryptosporidium")
  units <- if (!is.null(crypto$units)) crypto$units else "oocysts/L"
  expect_equal(units, "oocysts/L")
})
