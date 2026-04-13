library(ePiE)

test_that("LoadPathogenParameters loads and validates rotavirus", {
  params <- LoadPathogenParameters("rotavirus")
  expect_equal(params$type, "pathogen")
  expect_equal(params$name, "rotavirus")
  expect_equal(params$prevalence_rate, 0.06)
  expect_equal(params$excretion_rate, 1e12)
  expect_true(params$decay_rate_base > 0)
  expect_equal(params$units, "viral particles/L")
})

test_that("rotavirus decays faster than cryptosporidium at 20C", {
  rota <- LoadPathogenParameters("rotavirus")
  crypto <- LoadPathogenParameters("cryptosporidium")
  K_T_rota <- ePiE:::calc_temp_decay(rota$decay_rate_base, 20, rota$temp_corr_factor)
  K_T_crypto <- ePiE:::calc_temp_decay(crypto$decay_rate_base, 20, crypto$temp_corr_factor)
  expect_true(K_T_rota > K_T_crypto)
})

test_that("rotavirus decays slower than campylobacter at 20C", {
  rota <- LoadPathogenParameters("rotavirus")
  campy <- LoadPathogenParameters("campylobacter")
  K_T_rota <- ePiE:::calc_temp_decay(rota$decay_rate_base, 20, rota$temp_corr_factor)
  K_T_campy <- ePiE:::calc_temp_decay(campy$decay_rate_base, 20, campy$temp_corr_factor)
  expect_true(K_T_rota < K_T_campy)
})

test_that("rotavirus settles slower than cryptosporidium (virus vs oocyst)", {
  rota <- LoadPathogenParameters("rotavirus")
  crypto <- LoadPathogenParameters("cryptosporidium")
  expect_true(rota$settling_velocity < crypto$settling_velocity)
})

test_that("rotavirus decay formulas produce reasonable k values", {
  rota <- LoadPathogenParameters("rotavirus")
  K_T <- ePiE:::calc_temp_decay(rota$decay_rate_base, 25, rota$temp_corr_factor)
  expect_true(K_T > 0)
  expect_true(K_T < 10)
  K_S <- ePiE:::calc_sedimentation_decay(rota$settling_velocity, 1.5)
  expect_true(K_S > 0)
  expect_true(K_S < 10)
})

test_that("rotavirus parameters include units field", {
  params <- LoadPathogenParameters("rotavirus")
  expect_true("units" %in% names(params))
  expect_equal(params$units, "viral particles/L")
})
