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

test_that("AssignPathogenEmissions falls back to WWTP load fields when total_population is zero", {
  params <- list(
    type = "pathogen",
    total_population = 1e6,
    prevalence_rate = 0.05,
    excretion_rate = 1e8
  )

  nodes <- data.frame(
    Pt_type = c("WWTP", "WWTP"),
    total_population = c(0, 0),
    uwwLoadEnt = c(1200, NA),
    uwwCapacit = c(NA, 3400),
    uwwPrimary = c(0, -1),
    uwwSeconda = c(0, -1),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::AssignPathogenEmissions(nodes, params)

  expect_equal(result$E_in[1], 1200 * 0.05 * 1e8)
  expect_equal(result$E_in[2], 3400 * 0.05 * 1e8)
})

test_that("ApplyPathogenDirectFractionOverrides defaults agglomerations to 1", {
  nodes <- data.frame(
    ID = c("SourceA", "NodeA"),
    Pt_type = c("Agglomerations", "node"),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::ApplyPathogenDirectFractionOverrides(nodes)

  expect_equal(result$f_pathogen_direct[1], 1)
  expect_equal(result$f_pathogen_direct[2], 0)
})

test_that("Volta pathogen scenarios store Akuse and Asutsuare direct fraction overrides", {
  data_root <- normalizePath(file.path(testthat::test_path(), "../../..", "Inputs"), mustWork = FALSE)
  output_root <- normalizePath(file.path(testthat::test_path(), "../../..", "Outputs"), mustWork = FALSE)
  cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

  overrides <- cfg$pathogen_direct_fraction_overrides
  expected_sources <- c(
    "Source00080", "Source00081", "Source00116", "Source00117",
    "Source00087", "Source00088"
  )

  expect_true(all(expected_sources %in% overrides$source_id))
  expect_true(all(overrides$f_pathogen_direct[match(expected_sources, overrides$source_id)] == 0.5))
  expect_true(all(c("x", "y", "place", "match_radius_m", "assumption_note") %in% names(overrides)))
  expect_true(all(overrides$match_radius_m[match(expected_sources, overrides$source_id)] == 200))
  expect_true(all(overrides$place[match(c("Source00080", "Source00087"), overrides$source_id)] == c("Akuse", "Asutsuare")))
})

test_that("ApplyPathogenDirectFractionOverrides applies configured source fractions", {
  nodes <- data.frame(
    ID = c("Source00080", "Source00117", "SourceOther", "RiverNode"),
    Pt_type = c("Agglomerations", "Agglomerations", "Agglomerations", "node"),
    stringsAsFactors = FALSE
  )
  overrides <- data.frame(
    source_id = c("Source00080", "Source00117"),
    f_pathogen_direct = c(0.5, 0.5),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::ApplyPathogenDirectFractionOverrides(nodes, overrides)

  expect_equal(result$f_pathogen_direct[result$ID == "Source00080"], 0.5)
  expect_equal(result$f_pathogen_direct[result$ID == "Source00117"], 0.5)
  expect_equal(result$f_pathogen_direct[result$ID == "SourceOther"], 1)
  expect_equal(result$f_pathogen_direct[result$ID == "RiverNode"], 0)
  expect_equal(result$f_pathogen_direct_basis[result$ID == "Source00080"], "source_id")
  expect_equal(result$f_pathogen_direct_basis[result$ID == "SourceOther"], "default")
  expect_equal(result$f_pathogen_direct_basis[result$ID == "RiverNode"], "not_applicable")
})

test_that("ApplyPathogenDirectFractionOverrides matches agglomerations by coordinate radius", {
  nodes <- data.frame(
    ID = c("DryNear", "DryFar", "WWTP1"),
    Pt_type = c("Agglomerations", "Agglomerations", "WWTP"),
    x = c(0.11820, 0.12500, 0.11820),
    y = c(6.10010, 6.10010, 6.10010),
    stringsAsFactors = FALSE
  )
  overrides <- data.frame(
    source_id = "WetSourceOnly",
    x = 0.118154238400,
    y = 6.100119087006,
    f_pathogen_direct = 0.5,
    match_radius_m = 200,
    place = "Akuse",
    stringsAsFactors = FALSE
  )

  result <- ePiE:::ApplyPathogenDirectFractionOverrides(nodes, overrides)

  expect_equal(result$f_pathogen_direct[result$ID == "DryNear"], 0.5)
  expect_equal(result$f_pathogen_direct_basis[result$ID == "DryNear"], "coordinate_radius")
  expect_equal(result$f_pathogen_direct_place[result$ID == "DryNear"], "Akuse")
  expect_equal(result$f_pathogen_direct[result$ID == "DryFar"], 1)
  expect_equal(result$f_pathogen_direct_basis[result$ID == "DryFar"], "default")
  expect_equal(result$f_pathogen_direct[result$ID == "WWTP1"], 0)
  expect_equal(result$f_pathogen_direct_basis[result$ID == "WWTP1"], "not_applicable")
})

test_that("Volta coordinate overrides match current dry Akuse and Asutsuare candidates", {
  data_root <- normalizePath(file.path(testthat::test_path(), "../../..", "Inputs"), mustWork = FALSE)
  output_root <- normalizePath(file.path(testthat::test_path(), "../../..", "Outputs"), mustWork = FALSE)
  cfg <- LoadScenarioConfig("VoltaDryPathogenCrypto", data_root, output_root)
  nodes <- data.frame(
    ID = c(
      "Source00032", "Source00033", "Source00069", "Source00070",
      "Source00039", "Source00040", "Source00071"
    ),
    Pt_type = rep("Agglomerations", 7),
    x = c(
      0.1174146, 0.1214002, 0.1269131, 0.1307737,
      0.1986336, 0.1991754, 0.1331458
    ),
    y = c(
      6.100622, 6.097165, 6.094508, 6.095945,
      6.090404, 6.092425, 6.097170
    ),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::ApplyPathogenDirectFractionOverrides(nodes, cfg$pathogen_direct_fraction_overrides)

  expected_matches <- c("Source00032", "Source00033", "Source00069", "Source00070", "Source00039", "Source00040")
  expect_equal(result$f_pathogen_direct[match(expected_matches, result$ID)], rep(0.5, 6))
  expect_equal(result$f_pathogen_direct_basis[match(expected_matches, result$ID)], rep("coordinate_radius", 6))
  expect_equal(result$f_pathogen_direct[result$ID == "Source00071"], 1)
})

test_that("AssignPathogenEmissions applies f_pathogen_direct only to agglomerations", {
  params <- list(
    type = "pathogen",
    total_population = 1e6,
    prevalence_rate = 0.10,
    excretion_rate = 1e6
  )
  nodes <- data.frame(
    ID = c("Source00080", "WWTP1"),
    Pt_type = c("Agglomerations", "WWTP"),
    total_population = c(1000, 1000),
    f_pathogen_direct = c(0.5, 0.5),
    uwwPrimary = c(NA, 0),
    uwwSeconda = c(NA, 0),
    stringsAsFactors = FALSE
  )

  result <- ePiE:::AssignPathogenEmissions(nodes, params)

  expect_equal(result$E_in[result$ID == "Source00080"], 1000 * 0.10 * 1e6 * 0.5)
  expect_equal(result$E_in[result$ID == "WWTP1"], 1000 * 0.10 * 1e6)
  expect_equal(result$f_pathogen_direct[result$ID == "WWTP1"], 0)
})

test_that("AssignPathogenEmissions does not use f_direct for pathogen emissions", {
  params <- list(
    type = "pathogen",
    total_population = 1e6,
    prevalence_rate = 0.20,
    excretion_rate = 1e5
  )
  nodes <- data.frame(
    ID = "SourceOther",
    Pt_type = "Agglomerations",
    total_population = 2000,
    f_direct = 0.1,
    stringsAsFactors = FALSE
  )

  result <- ePiE:::AssignPathogenEmissions(nodes, params)

  expect_equal(result$f_pathogen_direct, 1)
  expect_equal(result$E_in, 2000 * 0.20 * 1e5)
})
