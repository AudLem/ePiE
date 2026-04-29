#' Refactor RunSimulationPipeline
#'
#' Orchestrates the full simulation process, using an accumulating state list
#' to ensure consistency and enable checkpointing.
#'
#' @param state Pipeline state list from BuildNetworkPipeline.
#' @param substance Character. Substance to simulate.
#' @param checkpoint_dir Character. Optional directory to save simulation states.
#' @export
RunSimulationPipeline <- function(state, substance, checkpoint_dir = NULL, verbose = FALSE, cpp = FALSE) {
  message("--- Running Simulation Pipeline for: ", substance, " ---")
  
  sim_state <- state
  
  if (!is.null(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  # Accept lake data under any of these field names
  if (is.null(sim_state$HL_basin)) {
    hl_fallback <- if (!is.null(sim_state$HLL_basin)) sim_state$HLL_basin else sim_state$hl
    sim_state$HL_basin <- hl_fallback
  }

  # Accept points from state, or try fallback names
  if (is.null(sim_state$points)) {
    pts_fallback <- if (!is.null(sim_state$normalized_network_nodes)) sim_state$normalized_network_nodes else sim_state$pts
    sim_state$points <- pts_fallback
  }

  # Accept basin_id from state, or try to read it from points
  if (is.null(sim_state$basin_id) && !is.null(sim_state$points) && ("basin_id" %in% names(sim_state$points))) {
    sim_state$basin_id <- sim_state$points$basin_id[1]
  }

  # Accept study_country from state, or infer it from saved network nodes.
  # Older BuildNetworkPipeline() outputs did not always carry cfg metadata,
  # but source rows usually have rptMStateK populated by the network build.
  if (is.null(sim_state$study_country) || length(sim_state$study_country) == 0 || is.na(sim_state$study_country) || sim_state$study_country == "") {
    inferred_country <- NULL
    if (!is.null(sim_state$points) && ("rptMStateK" %in% names(sim_state$points))) {
      countries <- unique(stats::na.omit(as.character(sim_state$points$rptMStateK)))
      countries <- countries[nzchar(countries)]
      if (length(countries) > 0) inferred_country <- countries[1]
    }
    sim_state$study_country <- if (!is.null(inferred_country)) inferred_country else "UNKNOWN"
  }
  
  norm <- NormalizeScenarioState(
    raw_network_nodes = sim_state$points,
    lake_nodes = sim_state$HL_basin,
    study_country = sim_state$study_country,
    basin_id = sim_state$basin_id
  )
  sim_state$points <- norm$normalized_network_nodes
  sim_state$HL_basin <- norm$lake_nodes
  sim_state$hl <- norm$lake_nodes
  
  # --- Hydrology assignment ----------------------------------------------------
  # Use AssignHydrology() instead of calling AddFlowToBasinData() directly.
  # AssignHydrology() is the unified wrapper (21_AssignHydrology.R) that provides:
  #   1. Preferred raster selection (high-res FLO1K, dry-season qmi, etc.)
  #   2. GeoGLOWS per-segment discharge when discharge_gpkg_path is set
  #   3. Canal Q_model_m3s overrides (ApplyCanalDischargeOverrides)
  #   4. Fallback to NetCDF when primary raster extraction fails
  #   5. Dry-season scaling (multiply river discharge by 0.1)
  #   6. Unified river_discharge → Q column contract
  # Calling AddFlowToBasinData() directly would bypass items 3-6, meaning
  # canal overrides, fallback handling, and dry-season scaling would be skipped.
  # The dataDir defaults to the repo Inputs/ directory.
  # --------------------------------------------------------------------------------
  dataDir <- if (!is.null(sim_state$data_root)) sim_state$data_root else {
    repo <- tryCatch(rprojroot::find_root(rprojroot::is_git_root), error = function(e) NULL)
    if (!is.null(repo)) file.path(repo, "Inputs") else NULL
  }

  hydro_result <- AssignHydrology(
    network_nodes = sim_state$points,
    input_paths = sim_state$input_paths,
    dataDir = dataDir,
    basin_id = sim_state$basin_id,
    prefer_highres_flow = !is.null(sim_state$prefer_highres_flow) && sim_state$prefer_highres_flow,
    is_dry_season = !is.null(sim_state$is_dry_season) && sim_state$is_dry_season,
    flow_source = if (!is.null(sim_state$flow_source)) sim_state$flow_source else NULL,
    network_source = if (!is.null(sim_state$network_source)) sim_state$network_source else "hydrosheds",
    discharge_gpkg_path = sim_state$discharge_gpkg_path,
    simulation_year = sim_state$simulation_year,
    simulation_months = sim_state$simulation_months,
    discharge_aggregation = if (!is.null(sim_state$discharge_aggregation)) sim_state$discharge_aggregation else "mean"
  )
  sim_state$points <- hydro_result$network_nodes

  sim_state$transport_edges <- BuildTransportEdges(sim_state$points)
  sim_state$transport_branching <- HasTransportBranching(sim_state$transport_edges)

  if (isTRUE(sim_state$transport_branching)) {
    sim_state$points <- Set_upstream_points_from_edges(sim_state$points, sim_state$transport_edges)
  } else {
    sim_state$points <- Set_upstream_points_v2(sim_state$points)
  }
  
  sim_state <- InitializeSubstance(sim_state, substance)
  if (!is.null(checkpoint_dir)) saveRDS(sim_state, file.path(checkpoint_dir, "sim_init.rds"))
  
  is_pathogen <- !is.null(sim_state$pathogen_params)
  if (is_pathogen) {
    sim_state$results <- ComputeEnvConcentrations(
      basin_data = sim_state,
      chem = NULL,
      cons = NULL,
      verbose = verbose,
      cpp = cpp,
      substance_type = "pathogen",
      pathogen_params = sim_state$pathogen_params
    )
    } else {
    sim_state$results <- ComputeEnvConcentrations(
      basin_data = sim_state,
      chem = sim_state$chem,
      cons = sim_state$cons,
      verbose = verbose,
      cpp = cpp,
      substance_type = "chemical"
    )
  }

  if (!is.null(checkpoint_dir)) saveRDS(sim_state, file.path(checkpoint_dir, "sim_results.rds"))

  if (!is.null(sim_state$run_output_dir)) {
    tryCatch(
      write.csv(
        sim_state$results$pts,
        file.path(sim_state$run_output_dir, "simulation_results.csv"),
        row.names = FALSE
      ),
      error = function(e) {
        message("Note: simulation-results export skipped: ", e$message)
      }
    )

    tryCatch(
      ExportTransportEdges(
        transport_edges = sim_state$transport_edges,
        run_output_dir = sim_state$run_output_dir
      ),
      error = function(e) {
        message("Note: transport-edge export skipped: ", e$message)
      }
    )
  }
  
  # --- Export hydrology-enriched node table ------------------------------------
  # This must happen AFTER simulation because Q, V, and H are only computed
  # during the hydrology step (Select_hydrology_fast2, Phase 4). The network-
  # build stage (SaveNetworkArtifacts) runs before simulation and therefore
  # cannot contain these values. ExportHydrologyNodes() merges the simulation
  # hydrology (Q, V, H from sim_state$points) with the simulation results
  # (C_w, C_sd from sim_state$results$pts) into a single inspection table.
  # --------------------------------------------------------------------------------
  if (!is.null(sim_state$run_output_dir)) {
    tryCatch(
      ExportHydrologyNodes(
        sim_points = sim_state$points,
        sim_results = sim_state$results$pts,
        run_output_dir = sim_state$run_output_dir
      ),
      error = function(e) {
        message("Note: hydrology export skipped: ", e$message)
      }
    )
  }
  
  # Visualization
  if (!is.null(sim_state$run_output_dir)) {
    tryCatch(
      {
        is_pathogen <- !is.null(sim_state$pathogen_params)
        VisualizeConcentrations(
          simulation_results = sim_state$results$pts,
          run_output_dir = sim_state$run_output_dir,
          input_paths = sim_state$input_paths,
          target_substance = substance,
          basin_id = sim_state$basin_id,
          substance_type = if (is_pathogen) "pathogen" else "chemical",
          pathogen_name = if (is_pathogen) substance else NULL,
          open_map_output_in_browser = FALSE
        )
      },
      error = function(e) {
        message("Note: visualization skipped: ", e$message)
      }
    )
  }
  
  message(">>> Simulation complete.")
  return(sim_state)
}

#' Export Hydrology-Enriched Node Table
#'
#' Writes \code{hydrology_nodes.csv} containing hydraulic columns (Q, V, H)
#' and, when available, concentration columns (C_w, C_sd) merged from the
#' simulation results. This function must be called AFTER simulation because
#' Q, V, and H are only populated during the hydrology step
#' (\code{Select_hydrology_fast2}, Phase 4 — Manning-Strickler).
#'
#' During the network-build stage (\code{SaveNetworkArtifacts}), Q/V/H do not
#' yet exist, so the export is deferred to this post-simulation call.
#'
#' @param sim_points data.frame. Simulation points with Q, V, H columns.
#' @param sim_results data.frame. Simulation results with C_w, C_sd columns.
#' @param run_output_dir Character. Directory to write \code{hydrology_nodes.csv}.
#' @export
ExportHydrologyNodes <- function(sim_points, sim_results, run_output_dir) {
  if (is.null(sim_points) || nrow(sim_points) == 0) {
    message("ExportHydrologyNodes: no simulation points, skipping.")
    return(invisible(NULL))
  }
  if (!dir.exists(run_output_dir)) {
    dir.create(run_output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # --- Select hydrology columns --------------------------------------------------
  # Core hydraulic columns always attempted. These are populated by
  # Select_hydrology_fast2() during the simulation hydrology step:
  #   Q   — discharge (m^3/s). Rivers: raster-extracted. Canals: Q_model_m3s.
  #   V   — flow velocity (m/s). Manning-Strickler estimate (Phase 4).
  #   H   — water depth (m). Continuity: H = Q / (V * W).
  #   slope — terrain slope (degrees). Raster-extracted proxy for canals.
  # Canal-specific columns (NA for river nodes):
  #   Q_design_m3s — engineering design capacity from config.
  #   Q_model_m3s  — operational discharge after mass-balance scaling.
  # --------------------------------------------------------------------------------
  hydrology_cols <- c(
    "ID", "ID_nxt", "x", "y", "is_canal",
    "Q", "V", "H", "slope",
    "Q_design_m3s", "Q_model_m3s",
    "Q_role", "Q_parent_m3s", "Q_out_sum_m3s", "Q_residual_m3s"
  )
  hydrology_available <- intersect(hydrology_cols, names(sim_points))

  # --- Merge concentration columns from simulation results -----------------------
  # sim_results comes from ComputeEnvConcentrations() and contains C_w (water
  # concentration) and C_sd (sediment concentration) per node. We merge on ID
  # so that hydrology_nodes.csv provides a single-table inspection view.
  # --------------------------------------------------------------------------------
  concentration_cols <- c("ID", "C_w", "C_sd")
  conc_available <- intersect(concentration_cols, names(sim_results))

  if (length(conc_available) > 1) {
    # Merge concentration data only if ID is unique in simulation results.
    # For any duplicated IDs (e.g. multi-substance tables), keep a strict
    # one-row-per-node hydrology export and skip concentration merge.
    result_df <- sim_points[, hydrology_available, drop = FALSE]
    conc_df <- sim_results[, conc_available, drop = FALSE]
    dup_ids <- unique(conc_df$ID[duplicated(conc_df$ID)])
    if (length(dup_ids) == 0) {
      result_df <- merge(result_df, conc_df, by = "ID", all.x = TRUE, suffixes = c("", ".res"))
    } else {
      message("ExportHydrologyNodes: concentration merge skipped because ", length(dup_ids),
              " node IDs are duplicated in simulation results.")
    }
  } else {
    result_df <- sim_points[, hydrology_available, drop = FALSE]
  }

  # Reorder columns: ID first, then hydrology, then concentrations
  non_id_cols <- setdiff(names(result_df), "ID")
  hydro_order <- intersect(c("ID_nxt", "x", "y", "is_canal", "Q", "V", "H", "slope",
                              "Q_design_m3s", "Q_model_m3s",
                              "Q_role", "Q_parent_m3s", "Q_out_sum_m3s", "Q_residual_m3s",
                              "C_w", "C_sd"), non_id_cols)
  result_df <- result_df[, c("ID", hydro_order), drop = FALSE]

  hydrology_path <- file.path(run_output_dir, "hydrology_nodes.csv")
  write.csv(result_df, hydrology_path, row.names = FALSE)
  message("Hydrology-enriched output saved to: ", hydrology_path)

  # --- Diagnostic counts ---------------------------------------------------------
  canal_count <- sum(sim_points$is_canal == TRUE, na.rm = TRUE)
  river_count <- sum(sim_points$is_canal == FALSE, na.rm = TRUE)
  canal_with_q <- sum(!is.na(sim_points$Q_model_m3s), na.rm = TRUE)
  river_with_q <- sum(!is.na(sim_points$Q), na.rm = TRUE)
  message("  River nodes: ", river_count, " (with Q: ", river_with_q, ")",
          " | Canal nodes: ", canal_count,
          " | Canals with Q_model_m3s: ", canal_with_q)

  invisible(hydrology_path)
}
