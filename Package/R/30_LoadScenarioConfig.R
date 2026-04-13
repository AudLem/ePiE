#' Load Scenario Configuration
#'
#' Sources all basin and scenario config files from \code{inst/config/}, then
#' calls the scenario constructor matching \code{scenario_name} to produce a
#' ready-to-use configuration list.
#'
#' @param scenario_name Character. Name of the scenario function (e.g. \code{"VoltaWetNetwork"}).
#' @param data_root Character. Root directory of basin and baseline data.
#' @param output_root Character. Root directory for pipeline outputs.
#' @return A named list of scenario configuration parameters.
#' @export
LoadScenarioConfig <- function(scenario_name, data_root, output_root) {
  basin_dir <- system.file("config", "basins", package = "ePiE")
  scenario_dir <- system.file("config", "scenarios", package = "ePiE")
  if (basin_dir == "" || scenario_dir == "") stop("Cannot find inst/config in ePiE package")

  cfg_env <- new.env(parent = parent.frame())
  for (f in list.files(basin_dir, pattern = "\\.R$", full.names = TRUE)) source(f, local = cfg_env)
  for (f in list.files(scenario_dir, pattern = "\\.R$", full.names = TRUE)) source(f, local = cfg_env)

  fn_name <- scenario_name
  all_scenarios <- sort(c(
    "VoltaWetNetwork", "VoltaDryNetwork", "BegaNetwork",
    "VoltaGeoGLOWSNetwork",
    "VoltaWetChemicalIbuprofen", "VoltaDryChemicalIbuprofen",
    "VoltaWetPathogenCrypto", "VoltaDryPathogenCrypto",
    "VoltaWetPathogenCampylobacter", "VoltaDryPathogenCampylobacter",
    "BegaChemicalIbuprofen", "BegaPathogenCrypto", "BegaPathogenCampylobacter",
    "VoltaGeoGLOWSWetChemicalIbuprofen", "VoltaGeoGLOWSDryChemicalIbuprofen",
    "VoltaGeoGLOWSWetPathogenCrypto", "VoltaGeoGLOWSDryPathogenCrypto",
    "VoltaGeoGLOWSWetPathogenCampylobacter", "VoltaGeoGLOWSDryPathogenCampylobacter",
    "VoltaWetPathogenGiardia", "VoltaDryPathogenGiardia",
    "VoltaGeoGLOWSWetPathogenGiardia", "VoltaGeoGLOWSDryPathogenGiardia",
    "BegaPathogenGiardia"
  ))
  if (!exists(fn_name, envir = cfg_env, mode = "function")) {
    stop(
      "Unknown scenario: '", scenario_name, "'.\n",
      "Available scenarios:\n  ", paste(all_scenarios, collapse = "\n  ")
    )
  }

  fn <- get(fn_name, envir = cfg_env, mode = "function")
  cfg <- fn(data_root, output_root)

  path_fields <- names(cfg)[grepl("_path$|_dir$|_raster$|_shp$", names(cfg))]
  for (f in path_fields) {
    if (is.character(cfg[[f]]) && length(cfg[[f]]) == 1) {
      cfg[[f]] <- normalizePath(cfg[[f]], winslash = "/", mustWork = FALSE)
    }
  }
  if (!is.null(cfg$input_paths)) {
    for (k in names(cfg$input_paths)) {
      if (is.character(cfg$input_paths[[k]]) && length(cfg$input_paths[[k]]) == 1) {
        cfg$input_paths[[k]] <- normalizePath(cfg$input_paths[[k]], winslash = "/", mustWork = FALSE)
      }
    }
  }

  cfg
}

#' List Available Scenarios
#'
#' Returns a character vector of all named scenarios that can be passed to
#' \code{LoadScenarioConfig}.
#'
#' @return Character vector of scenario names.
#' @export
ListScenarios <- function() {
  sort(c(
    "VoltaWetNetwork", "VoltaDryNetwork", "BegaNetwork",
    "VoltaGeoGLOWSNetwork",
    "VoltaWetChemicalIbuprofen", "VoltaDryChemicalIbuprofen",
    "VoltaWetPathogenCrypto", "VoltaDryPathogenCrypto",
    "VoltaWetPathogenCampylobacter", "VoltaDryPathogenCampylobacter",
    "BegaChemicalIbuprofen", "BegaPathogenCrypto", "BegaPathogenCampylobacter",
    "VoltaGeoGLOWSWetChemicalIbuprofen", "VoltaGeoGLOWSDryChemicalIbuprofen",
    "VoltaGeoGLOWSWetPathogenCrypto", "VoltaGeoGLOWSDryPathogenCrypto",
    "VoltaGeoGLOWSWetPathogenCampylobacter", "VoltaGeoGLOWSDryPathogenCampylobacter",
    "VoltaWetPathogenGiardia", "VoltaDryPathogenGiardia",
    "VoltaGeoGLOWSWetPathogenGiardia", "VoltaGeoGLOWSDryPathogenGiardia",
    "BegaPathogenGiardia"
  ))
}
