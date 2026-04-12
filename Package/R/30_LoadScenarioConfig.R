LoadScenarioConfig <- function(scenario_name, data_root, output_root) {
  basin_dir <- system.file("config", "basins", package = "ePiE")
  scenario_dir <- system.file("config", "scenarios", package = "ePiE")
  if (basin_dir == "" || scenario_dir == "") stop("Cannot find inst/config in ePiE package")

  cfg_env <- new.env(parent = parent.frame())
  for (f in list.files(basin_dir, pattern = "\\.R$", full.names = TRUE)) source(f, local = cfg_env)
  for (f in list.files(scenario_dir, pattern = "\\.R$", full.names = TRUE)) source(f, local = cfg_env)

  fn_name <- scenario_name
  if (!exists(fn_name, envir = cfg_env, mode = "function")) {
    available <- sort(c(
      "VoltaWetNetwork", "VoltaDryNetwork", "BegaNetwork",
      "VoltaWetChemicalIbuprofen", "VoltaDryChemicalIbuprofen",
      "VoltaWetPathogenCrypto", "VoltaDryPathogenCrypto",
      "BegaChemicalIbuprofen", "BegaPathogenCrypto"
    ))
    stop(
      "Unknown scenario: '", scenario_name, "'.\n",
      "Available scenarios:\n  ", paste(available, collapse = "\n  ")
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

ListScenarios <- function() {
  c(
    "VoltaWetNetwork", "VoltaDryNetwork", "BegaNetwork",
    "VoltaWetChemicalIbuprofen", "VoltaDryChemicalIbuprofen",
    "VoltaWetPathogenCrypto", "VoltaDryPathogenCrypto",
    "BegaChemicalIbuprofen", "BegaPathogenCrypto"
  )
}
