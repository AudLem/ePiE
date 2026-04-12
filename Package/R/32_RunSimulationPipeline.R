RunSimulationPipeline <- function(cfg) {
  display_substance <- if (!is.null(cfg$substance_type) && cfg$substance_type == "pathogen" && !is.null(cfg$pathogen_name)) {
    cfg$pathogen_name
  } else {
    cfg$target_substance
  }

  message("====================================================")
  message("STARTING SIMULATION FOR: ", cfg$basin_id)
  message("Target substance: ", display_substance)
  message("Output Directory: ", cfg$run_output_dir)
  message("====================================================")

  if (is.null(cfg$substance_type)) cfg$substance_type <- "chemical"

  if (!dir.exists(cfg$run_output_dir)) dir.create(cfg$run_output_dir, recursive = TRUE)

  chem_data <- openxlsx::read.xlsx(cfg$input_paths$chem_data)
  api_col <- "API"
  if ("substance" %in% names(chem_data)) {
    names(chem_data)[names(chem_data) == "substance"] <- "API"
  }
  selected_row <- chem_data[chem_data$API == cfg$target_substance, ][1, ]
  chem <- CompleteChemProperties(chem = selected_row)
  if (!("Inh" %in% names(chem))) chem$Inh <- 0

  pts_raw <- read.csv(cfg$input_paths$pts, stringsAsFactors = FALSE)
  if (!("total_population" %in% names(pts_raw))) pts_raw$total_population <- 0

  if (file.exists(cfg$input_paths$hl)) {
    HL <- read.csv(cfg$input_paths$hl, stringsAsFactors = FALSE)
  } else {
    HL <- data.frame(Hylak_id = integer(0), basin_id = character(0), Vol_total = numeric(0), k = numeric(0), input_emission = numeric(0), fin = integer(0))
  }
  message("Loaded ", nrow(pts_raw), " nodes and ", nrow(HL), " lakes.")

  step_02 <- NormalizeScenarioState(
    raw_network_nodes = pts_raw,
    lake_nodes = HL,
    study_country = cfg$study_country,
    basin_id = cfg$basin_id,
    default_temp = cfg$default_temp,
    default_wind = cfg$default_wind
  )
  network_nodes <- step_02$normalized_network_nodes
  lake_nodes <- step_02$lake_nodes

  step_03 <- AssignHydrology(
    network_nodes = network_nodes,
    input_paths = cfg$input_paths,
    dataDir = cfg$dataDir,
    basin_id = cfg$basin_id,
    prefer_highres_flow = isTRUE(cfg$prefer_highres_flow),
    is_dry_season = isTRUE(cfg$is_dry_season)
  )
  network_nodes <- step_03$network_nodes

  step_04 <- CalculateEmissions(
    network_nodes = network_nodes,
    chem = chem,
    study_country = cfg$study_country,
    target_substance = cfg$target_substance
  )
  cons <- step_04$cons

  network_nodes$basin_id <- cfg$basin_id
  network_nodes <- Set_upstream_points_v2(network_nodes)
  basin_data <- list(pts = network_nodes, hl = lake_nodes)

  had_global_HL <- exists("HL", envir = .GlobalEnv, inherits = FALSE)
  if (had_global_HL) old_global_HL <- get("HL", envir = .GlobalEnv, inherits = FALSE)
  assign("HL", lake_nodes, envir = .GlobalEnv)
  on.exit({
    if (had_global_HL) assign("HL", old_global_HL, envir = .GlobalEnv)
    else if (exists("HL", envir = .GlobalEnv, inherits = FALSE)) rm("HL", envir = .GlobalEnv)
  }, add = TRUE)

  parameters <- cfg$simulation_parameters
  if (is.null(parameters) && !is.null(cfg$pathogen_name)) {
    param_path <- system.file("pathogen_input", paste0(cfg$pathogen_name, ".R"), package = "ePiE")
    if (file.exists(param_path)) {
      source(param_path)
      parameters <- simulation_parameters
      parameters$total_population <- cfg$country_population
    }
  }

  message("Executing concentration engine...")
  results <- ComputeEnvConcentrations(
    basin_data = basin_data,
    chem = chem,
    cons = cons,
    verbose = FALSE,
    cpp = isTRUE(cfg$use_cpp),
    substance_type = cfg$substance_type,
    pathogen_params = parameters
  )

  substance_name <- if (cfg$substance_type == "pathogen" && !is.null(parameters$name)) {
    parameters$name
  } else {
    cfg$target_substance
  }
  write.csv(results$pts, file.path(cfg$run_output_dir, paste0("results_pts_", cfg$basin_id, "_", substance_name, ".csv")), row.names = FALSE)
  if (!is.null(results$hl)) {
    write.csv(results$hl, file.path(cfg$run_output_dir, paste0("results_hl_", cfg$basin_id, "_", substance_name, ".csv")), row.names = FALSE)
  }

  tryCatch({
    VisualizeConcentrations(
      simulation_results = results$pts,
      run_output_dir = cfg$run_output_dir,
      input_paths = cfg$input_paths,
      target_substance = cfg$target_substance,
      basin_id = cfg$basin_id,
      substance_type = cfg$substance_type,
      pathogen_name = cfg$pathogen_name,
      open_map_output_in_browser = FALSE
    )
  }, error = function(e) {
    message("Visualization skipped: ", e$message)
  })

  message("====================================================")
  message("SIMULATION COMPLETED SUCCESSFULLY")
  message("====================================================")

  invisible(results)
}
