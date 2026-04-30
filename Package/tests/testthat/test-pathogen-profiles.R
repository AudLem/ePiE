library(ePiE)

test_that("pathogen profile registry loads required area profiles", {
  profiles <- LoadPathogenProfileRegistry()

  expect_s3_class(profiles, "data.frame")
  expect_true(all(c("profile_set", "profile_id", "pathogen_name", "study_country") %in% names(profiles)))
  expect_true(all(c("ghana_ssa_screening", "romania_eu_screening") %in% profiles$profile_set))
  expect_equal(
    sort(unique(profiles$pathogen_name)),
    sort(c("campylobacter", "cryptosporidium", "giardia", "rotavirus"))
  )
})

test_that("strict pathogen profile resolution blocks missing regions", {
  expect_error(
    ResolvePathogenProfile(
      "cryptosporidium",
      study_country = "XX",
      pathogen_profile_policy = "strict"
    ),
    "No pathogen profile found"
  )
})

test_that("Bega and Volta pathogen profiles are explicit and different", {
  bega <- LoadPathogenParameters(
    "cryptosporidium",
    study_country = "RO",
    pathogen_profile_policy = "strict"
  )
  volta <- LoadPathogenParameters(
    "cryptosporidium",
    study_country = "GH",
    pathogen_profile_policy = "strict"
  )

  expect_equal(bega$pathogen_profile_set, "romania_eu_screening")
  expect_equal(volta$pathogen_profile_set, "ghana_ssa_screening")
  expect_equal(bega$pathogen_profile_country, "RO")
  expect_equal(volta$pathogen_profile_country, "GH")
  expect_lt(bega$prevalence_rate, volta$prevalence_rate)
  expect_true(nzchar(bega$pathogen_profile_prevalence_source_url))
  expect_true(nzchar(volta$pathogen_profile_prevalence_source_url))
})

test_that("scenario configs carry strict pathogen profile settings", {
  repo_root <- rprojroot::find_root(criterion = rprojroot::is_git_root)
  data_root <- file.path(repo_root, "Inputs")
  output_root <- file.path(repo_root, "Outputs")

  bega_cfg <- LoadScenarioConfig("BegaPathogenCrypto", data_root, output_root)
  volta_cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

  expect_equal(bega_cfg$pathogen_profile_policy, "strict")
  expect_equal(volta_cfg$pathogen_profile_policy, "strict")
  expect_equal(bega_cfg$pathogen_profile_set, "romania_eu_screening")
  expect_equal(volta_cfg$pathogen_profile_set, "ghana_ssa_screening")
})

test_that("InitializeSubstance attaches selected pathogen profile metadata", {
  state <- list(
    study_country = "RO",
    country_population = 19000000,
    pathogen_profile_policy = "strict"
  )

  result <- InitializeSubstance(state, "cryptosporidium")
  params <- result$pathogen_params

  expect_equal(params$pathogen_profile_set, "romania_eu_screening")
  expect_equal(params$pathogen_profile_country, "RO")
  expect_equal(params$total_population, 19000000)
  expect_equal(params$units, "oocysts/L")
})

test_that("AssignPathogenEmissions passes profile metadata to node outputs", {
  params <- LoadPathogenParameters(
    "cryptosporidium",
    study_country = "GH",
    pathogen_profile_policy = "strict"
  )
  params <- ResolvePathogenParams(params, total_population = 1000)

  nodes <- data.frame(
    Pt_type = c("agglomeration", "node"),
    total_population = c(100, 0),
    stringsAsFactors = FALSE
  )
  out <- ePiE:::AssignPathogenEmissions(nodes, params)

  expect_equal(out$pathogen_profile_set[1], "ghana_ssa_screening")
  expect_equal(out$pathogen_profile_country[1], "GH")
  expect_equal(out$pathogen_prevalence_rate[1], params$prevalence_rate)
  expect_gt(out$E_w[1], 0)
  expect_equal(out$E_w[2], 0)
})
