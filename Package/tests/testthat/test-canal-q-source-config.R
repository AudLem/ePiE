library(ePiE)
library(testthat)

test_that("Volta configs expose default and legacy canal Q sources", {
  cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")
  expect_equal(cfg$canal_q_source_id, "jica_2012_peak")
  expect_equal(cfg$canal_q_regime, "peak")
  expect_true(file.exists(cfg$canal_q_source_table))
  expect_true(all(c("linear", "log10") %in% cfg$visualization_variants))

  legacy_cfg <- LoadScenarioConfig("VoltaWetNetworkLegacyCanalQ", "Inputs", "Outputs")
  expect_equal(legacy_cfg$canal_q_source_id, "legacy_nllc_sllc")
  expect_equal(legacy_cfg$canal_q_regime, "operational")
  expect_true(grepl("volta_wet_legacy_q$", legacy_cfg$run_output_dir))
})

test_that("canal Q source registry selection is explicit and validated", {
  registry <- system.file("config", "canal_q_sources", "kis_canal_q_sources.csv", package = "ePiE")
  canals <- data.frame(
    id = c(1, 2, 3),
    canal_name = c("Akuse Main Canal", "NLLC", "SLLC"),
    stringsAsFactors = FALSE
  )

  jica <- ePiE:::AssignCanalDischargeFromSource(
    canals,
    list(canal_q_source_table = registry, canal_q_source_id = "jica_2012_peak")
  )
  expect_equal(jica$q_head, c(7.20, 0.46, 3.88), tolerance = 1e-6)
  expect_true(all(jica$canal_q_source_id == "jica_2012_peak"))
  expect_true(all(grepl("JICA", jica$canal_q_reference_short)))

  legacy <- ePiE:::AssignCanalDischargeFromSource(
    canals,
    list(canal_q_source_table = registry, canal_q_source_id = "legacy_nllc_sllc")
  )
  expect_equal(legacy$q_head, c(7.20, 2.07, 2.04), tolerance = 1e-6)
  expect_true(all(legacy$canal_q_source_id == "legacy_nllc_sllc"))

  expect_error(
    ePiE:::AssignCanalDischargeFromSource(
      canals,
      list(canal_q_source_table = registry, canal_q_source_id = "missing_source")
    ),
    "Unknown canal_q_source_id"
  )
})
