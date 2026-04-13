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

test_that("calc_solar_decay handles NA depth gracefully", {
  result <- ePiE:::calc_solar_decay(solar_rad = 1000, kl = 4.798e-4, ke = 49.155, depth = NA)
  expect_equal(result, 0)
})

test_that("calc_sedimentation_decay handles zero depth gracefully", {
  expect_equal(ePiE:::calc_sedimentation_decay(0.1, 0), 0)
})

test_that("calc_sedimentation_decay handles NA depth gracefully", {
  result <- ePiE:::calc_sedimentation_decay(0.1, NA)
  expect_equal(result, 0)
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

test_that("cryptosporidium has units field", {
  params <- LoadPathogenParameters("cryptosporidium")
  expect_equal(params$units, "oocysts/L")
})

test_that("LoadPathogenParameters fails for unknown pathogen", {
  expect_error(LoadPathogenParameters("nonexistent_pathogen"), "not found")
})

test_that("ResolvePathogenParams requires total_population", {
  params <- LoadPathogenParameters("cryptosporidium")
  params$total_population <- NA_real_
  expect_error(ResolvePathogenParams(params), "total_population")
})

test_that("ResolvePathogenParams succeeds with valid total_population", {
  params <- LoadPathogenParameters("cryptosporidium")
  params$total_population <- 1e6
  resolved <- ResolvePathogenParams(params)
  expect_equal(resolved$total_population, 1e6)
  expect_false(is.na(resolved$wwtp_primary_removal))
  expect_false(is.na(resolved$wwtp_secondary_removal))
})

test_that("AssignPathogenEmissions uses per-node population for WWTPs", {
  params <- list(
    type = "pathogen",
    total_population = 1e6,
    prevalence_rate = 0.05,
    excretion_rate = 1e8
  )

  # 2 WWTPs with local populations (total 800k)
  nodes <- data.frame(
    Pt_type = c("WWTP", "WWTP", "Agglomerations"),
    total_population = c(500000, 300000, 200000),
    f_STP = c(0.9, 0.85, 0),
    uwwPrimary = c(-1, -1, NA),
    uwwSeconda = c(-1, -1, NA),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::AssignPathogenEmissions(nodes, params)

  # WWTP1: 500000 * 0.05 * 1e8 = 2.5e12
  expect_equal(result$E_in[1], 2.5e12)
  # WWTP2: 300000 * 0.05 * 1e8 = 1.5e12
  expect_equal(result$E_in[2], 1.5e12)
  # Agglomeration: 200000 * 0.05 * 1e8 = 1.0e12
  expect_equal(result$E_in[3], 1.0e12)

  # Total emission = 2.5e12 + 1.5e12 + 1.0e12 = 5.0e12 = total_pop * prev * exc
  total_emission <- sum(result$E_in)
  expected_total <- 1e6 * 0.05 * 1e8
  expect_equal(total_emission, expected_total)
})

test_that("AssignPathogenEmissions does not overcount with multiple WWTPs", {
  params <- list(
    type = "pathogen",
    total_population = 1e6,
    prevalence_rate = 0.10,
    excretion_rate = 1e9
  )

  # 3 WWTPs each serving 300k people (total served = 900k, 100k unsewered)
  nodes <- data.frame(
    Pt_type = c("WWTP", "WWTP", "WWTP", "Agglomerations"),
    total_population = c(300000, 300000, 300000, 100000),
    f_STP = c(0.9, 0.9, 0.9, 0),
    uwwPrimary = c(-1, -1, -1, NA),
    uwwSeconda = c(-1, -1, -1, NA),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::AssignPathogenEmissions(nodes, params)

  # Each WWTP: 300000 * 0.10 * 1e9 = 3e13
  expect_equal(result$E_in[1], 3e13)
  expect_equal(result$E_in[2], 3e13)
  expect_equal(result$E_in[3], 3e13)

  # Agglomeration: 100000 * 0.10 * 1e9 = 1e13
  expect_equal(result$E_in[4], 1e13)

  # Total must equal basin production: 1e6 * 0.10 * 1e9 = 1e14
  expect_equal(sum(result$E_in), 1e14)
})

test_that("AssignPathogenEmissions handles nodes without total_population", {
  params <- list(
    type = "pathogen",
    total_population = 1e6,
    prevalence_rate = 0.05,
    excretion_rate = 1e8
  )

  nodes <- data.frame(
    Pt_type = c("WWTP", "node"),
    f_STP = c(0.9, NA),
    uwwPrimary = c(-1, NA),
    uwwSeconda = c(-1, NA),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::AssignPathogenEmissions(nodes, params)

  # Falls back to total_population for WWTP when per-node pop is missing
  expect_equal(result$E_in[1], 1e6 * 0.05 * 1e8)
  # Non-source node stays at 0
  expect_equal(result$E_in[2], 0)
})
