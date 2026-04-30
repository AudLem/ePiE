library(ePiE)

test_that("InspectScenarioSetup returns one wide row per configured scenario", {
  df <- NULL
  capture.output({
    df <- InspectScenarioSetup(data_root = "Inputs", output_root = "Outputs")
  })

  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), length(ListScenarios()))
  expect_true(all(c("scenario", "substance_type", "formula_files", "expected_outputs") %in% names(df)))
  expect_true("transport_edges.csv" %in% df$transport_routing_artifact)
})

test_that("InspectScenarioSetup reports Bega pathogen profile and units", {
  df <- NULL
  capture.output({
    df <- InspectScenarioSetup("BegaPathogenCrypto", data_root = "Inputs", output_root = "Outputs")
  })

  expect_equal(df$basin_id, "bega")
  expect_equal(df$study_country, "RO")
  expect_equal(df$substance_type, "pathogen")
  expect_equal(df$concentration_units, "oocysts/L")
  expect_equal(df$pathogen_profile_id_resolved, "romania_eu_cryptosporidium_screening")
  expect_match(df$pathogen_profile_registry, "pathogen_profiles.R", fixed = TRUE)
  expect_match(df$formula_files, "Package/R/02_PathogenModel.R", fixed = TRUE)
})

test_that("InspectScenarioSetup reports Volta canal Q and chemical setup", {
  df <- NULL
  capture.output({
    df <- InspectScenarioSetup("VoltaWetChemicalIbuprofen", data_root = "Inputs", output_root = "Outputs")
  })

  expect_equal(df$basin_id, "volta")
  expect_equal(df$substance_type, "chemical")
  expect_equal(df$concentration_units, "ug/L")
  expect_equal(df$canal_q_source_id, "jica_2012_peak")
  expect_match(df$canal_q_reference_url, "openjicareport.jica.go.jp", fixed = TRUE)
  expect_match(df$chemical_data_file, "chem_Oldenkamp2018_SI.xlsx", fixed = TRUE)
  expect_match(df$formula_files, "Package/R/22_CalculateEmissions.R", fixed = TRUE)
})

test_that("InspectScenarioSetup long format and CSV export work", {
  csv <- tempfile(fileext = ".csv")
  df <- InspectScenarioSetup(
    "BegaPathogenCrypto",
    data_root = "Inputs",
    output_root = "Outputs",
    export_csv = csv,
    format = "long"
  )

  expect_true(file.exists(csv))
  expect_true(all(c("scenario", "section", "field", "value") %in% names(df)))
  expect_true(any(df$field == "pathogen_profile_id_resolved"))
  exported <- utils::read.csv(csv, stringsAsFactors = FALSE)
  expect_equal(nrow(exported), nrow(df))
})

test_that("InspectScenarioSetup rejects unknown scenarios clearly", {
  expect_error(
    InspectScenarioSetup("NotAScenario", data_root = "Inputs", output_root = "Outputs"),
    "Unknown scenario"
  )
})

test_that("inspect_scenarios.R writes a CSV from the command line", {
  script_path <- if (file.exists("scripts/inspect_scenarios.R")) {
    "scripts/inspect_scenarios.R"
  } else {
    file.path("..", "..", "..", "scripts", "inspect_scenarios.R")
  }
  skip_if_not(file.exists(script_path))
  rscript <- file.path(R.home("bin"), "Rscript")
  csv <- tempfile(fileext = ".csv")
  out <- system2(
    rscript,
    c(script_path, "--scenario", "BegaPathogenCrypto", "--csv", csv),
    stdout = TRUE,
    stderr = TRUE
  )

  expect_null(attr(out, "status"))
  expect_true(file.exists(csv))
  exported <- utils::read.csv(csv, stringsAsFactors = FALSE)
  expect_equal(nrow(exported), 1)
  expect_equal(exported$scenario, "BegaPathogenCrypto")
})

test_that("CreateScenarioTemplate prints, writes, and protects templates", {
  text <- NULL
  printed <- capture.output({
    text <- CreateScenarioTemplate("MyScenario", copy_from = "VoltaWetPathogenCrypto")
  })
  expect_match(paste(printed, collapse = "\n"), "VoltaWetPathogenCrypto", fixed = TRUE)
  expect_match(text, "cryptosporidium", fixed = TRUE)

  output_file <- tempfile(fileext = ".R")
  CreateScenarioTemplate(
    "MyBegaCrypto",
    basin_id = "bega",
    substance_type = "pathogen",
    target_substance = "cryptosporidium",
    output_file = output_file
  )
  expect_true(file.exists(output_file))
  expect_error(
    CreateScenarioTemplate(
      "MyBegaCrypto",
      basin_id = "bega",
      substance_type = "pathogen",
      target_substance = "cryptosporidium",
      output_file = output_file
    ),
    "Refusing to overwrite"
  )
})
