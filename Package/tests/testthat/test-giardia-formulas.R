library(ePiE)

test_that("LoadPathogenParameters loads and validates giardia", {
  params <- LoadPathogenParameters("giardia")
  expect_equal(params$type, "pathogen")
  expect_equal(params$name, "giardia")
  expect_equal(params$prevalence_rate, 0.07)
  expect_equal(params$excretion_rate, 1e9)
  expect_true(params$decay_rate_base > 0)
  expect_equal(params$units, "cysts/L")
})

test_that("giardia decays faster than cryptosporidium at 20C", {
  giardia <- LoadPathogenParameters("giardia")
  crypto <- LoadPathogenParameters("cryptosporidium")
  K_T_giardia <- ePiE:::calc_temp_decay(giardia$decay_rate_base, 20, giardia$temp_corr_factor)
  K_T_crypto <- ePiE:::calc_temp_decay(crypto$decay_rate_base, 20, crypto$temp_corr_factor)
  expect_true(K_T_giardia > K_T_crypto)
})

test_that("giardia cysts settle faster than cryptosporidium oocysts", {
  giardia <- LoadPathogenParameters("giardia")
  crypto <- LoadPathogenParameters("cryptosporidium")
  expect_true(giardia$settling_velocity > crypto$settling_velocity)
})

test_that("giardia WWTP removal is between crypto and campylobacter", {
  giardia <- LoadPathogenParameters("giardia")
  crypto <- LoadPathogenParameters("cryptosporidium")
  campy <- LoadPathogenParameters("campylobacter")
  expect_true(giardia$wwtp_primary_removal >= crypto$wwtp_primary_removal)
  expect_true(giardia$wwtp_primary_removal <= campy$wwtp_primary_removal)
})

test_that("giardia decay formulas produce reasonable k values", {
  giardia <- LoadPathogenParameters("giardia")
  K_T <- ePiE:::calc_temp_decay(giardia$decay_rate_base, 25, giardia$temp_corr_factor)
  expect_true(K_T > 0)
  expect_true(K_T < 10)
  K_S <- ePiE:::calc_sedimentation_decay(giardia$settling_velocity, 1.5)
  expect_true(K_S > 0)
  expect_true(K_S < 10)
})

test_that("giardia parameters include units field", {
  params <- LoadPathogenParameters("giardia")
  expect_true("units" %in% names(params))
  expect_equal(params$units, "cysts/L")
})
