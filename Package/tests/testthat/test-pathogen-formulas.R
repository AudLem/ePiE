library(ePiE)

test_that("calc_temp_decay matches Vermeulen 2019 K_T formula", {
  K4 <- 0.0051
  theta <- 0.158
  expect_equal(ePiE:::calc_temp_decay(K4, 20, theta), K4 * exp(theta * 16), tolerance = 1e-10)
  expect_equal(ePiE:::calc_temp_decay(K4, 4, theta), K4, tolerance = 1e-10)
  expect_equal(ePiE:::calc_temp_decay(K4, 0, theta), K4 * exp(theta * (-4)), tolerance = 1e-10)
})

test_that("calc_light_attenuation returns kd * C_DOC", {
  expect_equal(ePiE:::calc_light_attenuation(5, 9.831), 5 * 9.831, tolerance = 1e-10)
  expect_equal(ePiE:::calc_light_attenuation(0, 9.831), 0)
})

test_that("calc_solar_decay handles zero depth gracefully", {
  result <- ePiE:::calc_solar_decay(solar_rad = 1000, kl = 4.798e-4, ke = 49.155, depth = 0)
  expect_equal(result, 0)
})

test_that("calc_solar_decay computes correct K_R", {
  depth <- 2.0
  ke <- 49.155
  kl <- 4.798e-4
  I <- 1000
  expected <- (I / (ke * depth)) * (1 - exp(-ke * depth)) * kl
  result <- ePiE:::calc_solar_decay(solar_rad = I, kl = kl, ke = ke, depth = depth)
  expect_equal(result, expected, tolerance = 1e-10)
})

test_that("calc_sedimentation_decay handles zero depth gracefully", {
  expect_equal(ePiE:::calc_sedimentation_decay(0.1, 0), 0)
})

test_that("calc_sedimentation_decay computes correct K_S", {
  expect_equal(ePiE:::calc_sedimentation_decay(0.1, 2.0), 0.05, tolerance = 1e-10)
})

test_that("calc_total_dissipation_rate converts day-1 to s-1", {
  K_T <- 0.01
  K_R <- 0.005
  K_S <- 0.0025
  expected <- (K_T + K_R + K_S) / 86400
  expect_equal(ePiE:::calc_total_dissipation_rate(K_T, K_R, K_S), expected, tolerance = 1e-10)
})

test_that("LoadPathogenParameters loads and validates cryptosporidium", {
  params <- LoadPathogenParameters("cryptosporidium")
  expect_equal(params$type, "pathogen")
  expect_equal(params$name, "cryptosporidium")
  expect_equal(params$prevalence_rate, 0.05)
  expect_true(params$decay_rate_base > 0)
})

test_that("LoadPathogenParameters fails for unknown pathogen", {
  expect_error(LoadPathogenParameters("nonexistent_pathogen"), "not found")
})

test_that("ResolvePathogenParams requires total_population", {
  params <- LoadPathogenParameters("cryptosporidium")
  params$total_population <- NA_real_
  expect_error(ResolvePathogenParams(params), "total_population")
})
