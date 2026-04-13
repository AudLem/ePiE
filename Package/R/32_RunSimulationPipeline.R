#' Run Simulation Pipeline
#'
#' Orchestrates the full simulation: loads a pre-built network, normalises state,
#' assigns hydrology, prepares emissions, then runs the concentration engine for
#' either chemicals or pathogens. Produces concentration maps automatically.
#'
#' @param cfg Named list. Configuration produced by \code{LoadScenarioConfig}.
#' @return A named list with \code{pts} (data.frame with concentrations in \code{C_w}).
#' @export

# ==============================================================================
# Main Simulation Orchestrator
# ==============================================================================
# This function is the top-level entry point for running a single-basin
# concentration simulation. It chains together five pipeline stages:
#
#   Stage 1 — Load inputs:  chemical properties, network nodes, lake data
#   Stage 2 — Normalize:    clean / harmonise node attributes (temp, wind, etc.)
#   Stage 3 — Hydrology:    assign river flow, velocity, depth to every node
#   Stage 4 — Emissions:    compute per-node emission loads (chemical or pathogen)
#   Stage 5 — Engine:       route emissions downstream, applying decay / removal
#
# After computation, results (C_w per node) are written to CSV and an HTML
# concentration map is generated via VisualizeConcentrations().
#
# The pipeline supports both chemical substances and pathogens via the
# cfg$substance_type flag ("chemical" vs. "pathogen").
#
# Related formula references:
#   Emissions:  P6 (WWTP load), P7 (WWTP removal), P8 (agglomeration load)
#   Transport:  P10 (river decay), P11 (lake CSTR)
#
# TODO(MULTI-PATHOGEN): To simulate multiple pathogens in one run, this pipeline
#   should loop over a list of pathogen parameter sets and call the engine
#   once per pathogen, aggregating results. Currently only one substance per run.
#
# TODO(SEASONAL): The pipeline currently runs for a single hydrological condition.
#   Seasonal scenarios require looping over months with different flow, temp,
#   and prevalence parameters (GAP 3).
# ==============================================================================

# ------------------------------------------------------------------------------
# RunSimulationPipeline
# ------------------------------------------------------------------------------
# Purpose:  Orchestrate the full ePiE concentration simulation for one basin
#           and one substance (chemical or pathogen).
# Parameters:
#   cfg — named list produced by LoadScenarioConfig(), containing:
#     $basin_id, $target_substance, $substance_type, $pathogen_name,
#     $run_output_dir, $study_country, $default_temp, $default_wind,
#     $input_paths (list: chem_data, pts, hl), $dataDir,
#     $prefer_highres_flow, $is_dry_season, $use_cpp,
#     $simulation_parameters, $country_population
# Return:   Named list with $pts (data.frame of concentrations) and $hl (lakes).
# ------------------------------------------------------------------------------
RunSimulationPipeline <- function(cfg) {
  # --- Detect network-only mode: no input_paths means build network from scratch ---
  is_network_only <- is.null(cfg$input_paths) || !is.list(cfg$input_paths)

  if (is_network_only) {
    return(BuildNetworkPipeline(cfg))
  }

  # --- Display name: use pathogen name for pathogens, otherwise chemical name ---
  display_substance <- if (!is.null(cfg$substance_type) && cfg$substance_type == "pathogen" && !is.null(cfg$pathogen_name)) {
    cfg$pathogen_name
  } else {
    cfg$target_substance
  }

  # --- Startup banner ---
  message("====================================================")
  message("STARTING SIMULATION FOR: ", cfg$basin_id)
  message("Target substance: ", display_substance)
  message("Output Directory: ", cfg$run_output_dir)
  message("====================================================")

  # --- Default to chemical mode if substance_type is not specified ---
  if (is.null(cfg$substance_type)) cfg$substance_type <- "chemical"

  # --- Ensure output directory exists ---
  if (!dir.exists(cfg$run_output_dir)) dir.create(cfg$run_output_dir, recursive = TRUE)

  # ==================================================================
  # STAGE 1: Load input data (chemical properties, network, lakes)
  # ==================================================================

  # Load chemical property sheet and select the row matching the target substance.
  # The column is standardised to "API" (Active Pharmaceutical Ingredient).
  chem_data <- openxlsx::read.xlsx(cfg$input_paths$chem_data)
  api_col <- "API"
  if ("substance" %in% names(chem_data)) {
    names(chem_data)[names(chem_data) == "substance"] <- "API"
  }
  selected_row <- chem_data[chem_data$API == cfg$target_substance, ][1, ]

  # CompleteChemProperties fills in derived physicochemical fields
  # (e.g. K_ow, K_oc, degradation rates) needed by the concentration engine.
  chem <- CompleteChemProperties(chem = selected_row)
  if (!("Inh" %in% names(chem))) chem$Inh <- 0

  # Load river network nodes (point sources + river junctions).
  # total_population is required for pathogen emission calculations (P6/P8).
  pts_raw <- read.csv(cfg$input_paths$pts, stringsAsFactors = FALSE)
  if (!("total_population" %in% names(pts_raw))) pts_raw$total_population <- 0

  # Load lake/hyrolake data if available; otherwise create an empty table.
  # Lakes are modelled as continuously-stirred tank reactors (CSTR, Formula P11).
  if (file.exists(cfg$input_paths$hl)) {
    HL <- read.csv(cfg$input_paths$hl, stringsAsFactors = FALSE)
  } else {
    HL <- data.frame(Hylak_id = integer(0), basin_id = character(0), Vol_total = numeric(0), k = numeric(0), input_emission = numeric(0), fin = integer(0))
  }
  message("Loaded ", nrow(pts_raw), " nodes and ", nrow(HL), " lakes.")

  # ==================================================================
  # STAGE 2: Normalize network state
  # ==================================================================
  # Harmonises raw node attributes: assigns default temperature/wind where
  # missing, resolves column name inconsistencies, and ensures all required
  # fields exist. Temperature is used downstream for pathogen decay (P2).
  # Wind speed affects volatilisation for chemicals.
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

  # ==================================================================
  # STAGE 3: Assign hydrology (flow, velocity, depth)
  # ==================================================================
  # Attaches river discharge Q, velocity v, and depth H to each node.
  # These fields are needed for:
  #   - Travel time computation (travel_time = length / v)
  #   - Chemical removal processes (volatilisation, sedimentation)
  #   - Pathogen decay formulas (P3, P5 require depth; P2 requires temp)
  # The function supports both high-resolution and standard flow datasets,
  # and can select dry-season flow statistics when requested.
  #
  # TODO(SEASONAL): Currently selects a single flow regime (mean or dry-season).
  #   To support monthly time-steps, this stage would need to loop over
  #   12 monthly flow rasters and run the engine for each month.
  # TODO(DIFFUSE-EMISSION): Diffuse runoff contributions to river flow are
  #   not yet included. Future work could add a runoff component based on
  #   land cover and precipitation data.
  step_03 <- AssignHydrology(
    network_nodes = network_nodes,
    input_paths = cfg$input_paths,
    dataDir = cfg$dataDir,
    basin_id = cfg$basin_id,
    prefer_highres_flow = isTRUE(cfg$prefer_highres_flow),
    is_dry_season = isTRUE(cfg$is_dry_season),
    network_source = if (!is.null(cfg$network_source)) cfg$network_source else "hydrosheds",
    discharge_gpkg_path = cfg$discharge_gpkg_path,
    simulation_year = cfg$simulation_year,
    simulation_months = cfg$simulation_months,
    discharge_aggregation = if (!is.null(cfg$discharge_aggregation)) cfg$discharge_aggregation else "mean"
  )
  network_nodes <- step_03$network_nodes

  # ==================================================================
  # STAGE 4: Calculate emissions
  # ==================================================================
  # Computes per-node emission loads (E_w) based on the substance type.
  # For chemicals: pharmaceutical consumption data × excretion fraction.
  # For pathogens: population × prevalence × excretion (P6, P7, P8).
  #
  # The returned $cons data.frame contains consumption statistics used in
  # the concentration engine to partition emissions across the network.
  #
  # TODO(MULTI-PATHOGEN): This stage currently handles one substance at a time.
  #   To support co-simulated pathogens, loop over pathogen parameter sets.
  # TODO(DIFFUSE-EMISSION): Only point-source emissions (WWTP + agglomerations)
  #   are modelled. Diffuse agricultural runoff is not yet implemented (GAP 2).
  step_04 <- CalculateEmissions(
    network_nodes = network_nodes,
    chem = chem,
    study_country = cfg$study_country,
    target_substance = cfg$target_substance
  )
  cons <- step_04$cons

  # --- Assign basin ID and build upstream topology ---
  # Set_upstream_points_v2 identifies each node's upstream neighbour, enabling
  # the concentration engine to route loads from headwaters to outlet.
  network_nodes$basin_id <- cfg$basin_id
  network_nodes <- Set_upstream_points_v2(network_nodes)
  basin_data <- list(pts = network_nodes, hl = lake_nodes)

  # --- Expose lake data globally for downstream functions ---
  # Some internal functions (e.g. lake CSTR mixing in ComputeEnvConcentrations)
  # expect HL in the global environment. We save/restore it via on.exit to
  # avoid polluting the caller's environment.
  had_global_HL <- exists("HL", envir = .GlobalEnv, inherits = FALSE)
  if (had_global_HL) old_global_HL <- get("HL", envir = .GlobalEnv, inherits = FALSE)
  assign("HL", lake_nodes, envir = .GlobalEnv)
  on.exit({
    if (had_global_HL) assign("HL", old_global_HL, envir = .GlobalEnv)
    else if (exists("HL", envir = .GlobalEnv, inherits = FALSE)) rm("HL", envir = .GlobalEnv)
  }, add = TRUE)

  # --- Load pathogen-specific parameters (if running in pathogen mode) ---
  # Pathogen parameters (prevalence, excretion rate, decay constants, etc.)
  # are stored in inst/pathogen_input/<pathogen_name>.R. The file defines a
  # simulation_parameters list read via source().
  #
  # TODO(MULTI-PATHOGEN): To support multiple pathogens, loop over a vector
  #   of pathogen names, loading each parameter file and running the engine
  #   separately for each pathogen. Results would need unique output columns
  #   or separate output files per pathogen.
  parameters <- cfg$simulation_parameters
  if (is.null(parameters) && !is.null(cfg$pathogen_name)) {
    param_path <- system.file("pathogen_input", paste0(cfg$pathogen_name, ".R"), package = "ePiE")
    if (file.exists(param_path)) {
      source(param_path)
      parameters <- simulation_parameters
      parameters$total_population <- cfg$country_population
      parameters$name <- cfg$pathogen_name
    }
  }

  # ==================================================================
  # STAGE 5: Run concentration engine
  # ==================================================================
  # The core computation: routes emissions downstream, applying chemical
  # removal (biodegradation, volatilisation, sorption) or pathogen decay
  # (temperature, solar, sedimentation — Formulas P1-P5) along each river
  # reach. Lakes are modelled as CSTRs (Formula P11).
  #
  # Result: each node receives a C_w value (mg/L for chemicals, oocysts/L
  # for pathogens).
  #
  # References:
  #   River transport — Formula P10: C_down = C * exp(-k * travel_time)
  #   Lake CSTR       — Formula P11: C_lake = E / (Q + k*V)
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

  # ==================================================================
  # OUTPUT: Write results to CSV
  # ==================================================================
  # Save node concentrations (pts) and lake concentrations (hl) to the
  # run output directory. File names include basin ID and substance name
  # for traceability.
  substance_name <- if (cfg$substance_type == "pathogen" && !is.null(parameters$name)) {
    parameters$name
  } else {
    cfg$target_substance
  }
  write.csv(results$pts, file.path(cfg$run_output_dir, paste0("results_pts_", cfg$basin_id, "_", substance_name, ".csv")), row.names = FALSE)
  if (!is.null(results$hl)) {
    write.csv(results$hl, file.path(cfg$run_output_dir, paste0("results_hl_", cfg$basin_id, "_", substance_name, ".csv")), row.names = FALSE)
  }

  # --- Generate HTML concentration map ---
  # VisualizeConcentrations produces an interactive leaflet map showing
  # C_w values along the river network. Wrapped in tryCatch so that a
  # visualization failure does not abort the pipeline.
  tryCatch({
    VisualizeConcentrations(
      simulation_results = results$pts,
      run_output_dir = cfg$run_output_dir,
      input_paths = cfg$input_paths,
      target_substance = cfg$target_substance,
      basin_id = cfg$basin_id,
      substance_type = cfg$substance_type,
      pathogen_name = cfg$pathogen_name,
      pathogen_units = if (!is.null(parameters$units)) parameters$units else NULL,
      open_map_output_in_browser = FALSE
    )
  }, error = function(e) {
    message("Visualization skipped: ", e$message)
  })

  message("====================================================")
  message("SIMULATION COMPLETED SUCCESSFULLY")
  message("====================================================")

  # Return results invisibly so the pipeline can be used programmatically
  invisible(results)
}
