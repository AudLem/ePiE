# ==============================================================================
# Scenario setup inspection and template helpers
# ==============================================================================
# This file provides user-facing utilities for auditing scenario configuration
# before running a network or simulation. The inspector reports configured inputs,
# units, selected source registries, and the code modules where the relevant
# formula logic lives. It does not read or validate generated run outputs.
# ==============================================================================

ScenarioInspectorValue <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) return(default)
  x <- x[[1]]
  if (length(x) == 0 || is.na(x)) return(default)
  x <- as.character(x)
  if (!nzchar(x)) default else x
}

ScenarioInspectorCollapse <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) return(default)
  x <- as.character(x)
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0) default else paste(unique(x), collapse = " | ")
}

ScenarioInspectorPath <- function(x) {
  x <- ScenarioInspectorValue(x)
  if (is.na(x)) return(NA_character_)
  normalizePath(x, winslash = "/", mustWork = FALSE)
}

ScenarioInspectorFileExists <- function(x) {
  x <- ScenarioInspectorValue(x)
  if (is.na(x) || !nzchar(x)) return(FALSE)
  file.exists(x)
}

ScenarioFormulaRegistry <- function() {
  data.frame(
    subsystem = c(
      "scenario_config", "network_pipeline", "simulation_pipeline",
      "hydrology", "hydrology", "transport", "transport",
      "pathogen_loading", "pathogen_emissions", "chemical_loading",
      "chemical_emissions", "chemical_fate", "visualization"
    ),
    file = c(
      "Package/R/30_LoadScenarioConfig.R",
      "Package/R/31_BuildNetworkPipeline.R",
      "Package/R/32_RunSimulationPipeline.R",
      "Package/R/21_AssignHydrology.R",
      "Package/R/01_AddFlowToBasinData.R",
      "Package/R/22_TransportEdges.R",
      "Package/R/02_ComputeEnvConcentrations.R",
      "Package/R/00_substance_abstraction.R",
      "Package/R/02_PathogenModel.R",
      "Package/R/00_substance_abstraction.R",
      "Package/R/22_CalculateEmissions.R",
      "Package/R/Set_local_parameters_custom_removal_fast3.R | Package/R/SimpleTreat4_0.R",
      "Package/R/23A_VisualizationSpec.R"
    ),
    role = c(
      "loads basin/scenario config and scientific defaults",
      "builds node network and source placement",
      "assigns hydrology, transport, substance, and outputs",
      "selects flow source and calls Q/V/H assignment",
      "computes river/canal Q, velocity, and depth",
      "builds canonical transport_edges.csv routing table",
      "routes contaminant load and computes C_w",
      "loads pathogen/chemical parameter sources",
      "computes pathogen emissions and profile metadata",
      "loads chemical workbook rows",
      "computes chemical emissions from WWTP/source data",
      "computes chemical fate/removal parameters",
      "builds map labels, units, and provenance blocks"
    ),
    stringsAsFactors = FALSE
  )
}

ScenarioFormulaFilesFor <- function(substance_type) {
  registry <- ScenarioFormulaRegistry()
  common <- c("scenario_config", "network_pipeline", "simulation_pipeline",
              "hydrology", "transport", "visualization")
  specific <- if (identical(substance_type, "pathogen")) {
    c("pathogen_loading", "pathogen_emissions")
  } else if (identical(substance_type, "chemical")) {
    c("chemical_loading", "chemical_emissions", "chemical_fate")
  } else {
    character(0)
  }
  rows <- registry$subsystem %in% c(common, specific)
  paste(paste0(registry$subsystem[rows], "=", registry$file[rows]), collapse = "; ")
}

ScenarioExpectedOutputs <- function(cfg) {
  substance_type <- ScenarioInspectorValue(cfg$substance_type, "network")
  if (identical(substance_type, "network")) {
    base <- c(
      "pts.csv",
      "HL.csv",
      "network_rivers.shp",
      "transport_edges.csv",
      "lake_connections.csv",
      "lake_connection_diagnostics.csv",
      "run_provenance_summary.csv",
      "plots/interactive_network_map.html"
    )
    if (isTRUE(cfg$enable_canals) || !is.na(ScenarioInspectorValue(cfg$canal_q_source_id))) {
      base <- c(base, "canal_q_assignment_summary.csv")
    }
    return(paste(base, collapse = " | "))
  }

  base <- c(
    "simulation_results.csv",
    "hydrology_nodes.csv",
    "transport_edges.csv",
    "run_provenance_summary.csv",
    "plots/concentration_map.html",
    "plots/concentration_map_linear.html",
    "plots/concentration_map_log10.html"
  )
  if (identical(ScenarioInspectorValue(cfg$substance_type), "pathogen")) {
    base <- c(base, "pathogen_provenance_summary.csv")
  }
  if (isTRUE(cfg$enable_canals) || !is.na(ScenarioInspectorValue(cfg$canal_q_source_id))) {
    base <- c(base, "canal_q_assignment_summary.csv")
  }
  paste(base, collapse = " | ")
}

ScenarioInputSummary <- function(input_paths) {
  if (is.null(input_paths) || length(input_paths) == 0) return(NA_character_)
  pieces <- vapply(names(input_paths), function(nm) {
    value <- input_paths[[nm]]
    if (is.null(value) || length(value) == 0) return(NA_character_)
    paste0(nm, "=", paste(as.character(value), collapse = "|"))
  }, character(1))
  pieces <- pieces[!is.na(pieces) & nzchar(pieces)]
  if (length(pieces) == 0) NA_character_ else paste(pieces, collapse = "; ")
}

InspectCanalQSource <- function(cfg) {
  empty <- list(
    canal_q_source_label = NA_character_,
    canal_q_reference_short = NA_character_,
    canal_q_reference_url = NA_character_,
    canal_q_publication_year = NA_character_,
    canal_q_data_period = NA_character_,
    canal_q_value_origin = NA_character_,
    canal_q_derivation_rule = NA_character_
  )
  source_id <- ScenarioInspectorValue(cfg$canal_q_source_id)
  source_table <- ScenarioInspectorValue(cfg$canal_q_source_table)
  if (is.na(source_id) || is.na(source_table) || !file.exists(source_table)) {
    return(empty)
  }

  table <- tryCatch(utils::read.csv(source_table, stringsAsFactors = FALSE),
                    error = function(e) NULL)
  if (is.null(table) || !("source_id" %in% names(table))) return(empty)
  rows <- table[as.character(table$source_id) == source_id, , drop = FALSE]
  if (nrow(rows) == 0) return(empty)

  first <- function(field) {
    if (!(field %in% names(rows))) return(NA_character_)
    ScenarioInspectorCollapse(rows[[field]])
  }
  data_period <- paste(
    ScenarioInspectorValue(rows$data_year_start),
    ScenarioInspectorValue(rows$data_year_end),
    sep = "-"
  )
  if (identical(data_period, "NA-NA")) data_period <- NA_character_

  list(
    canal_q_source_label = first("source_label"),
    canal_q_reference_short = first("reference_short"),
    canal_q_reference_url = first("reference_url"),
    canal_q_publication_year = first("publication_year"),
    canal_q_data_period = data_period,
    canal_q_value_origin = first("value_origin"),
    canal_q_derivation_rule = first("derivation_rule")
  )
}

InspectPathogenSetup <- function(cfg) {
  empty <- list(
    pathogen_profile_id_resolved = NA_character_,
    pathogen_profile_label = NA_character_,
    pathogen_profile_region = NA_character_,
    pathogen_profile_confidence = NA_character_,
    pathogen_units = NA_character_,
    pathogen_prevalence_rate = NA_real_,
    pathogen_excretion_rate = NA_real_,
    pathogen_decay_rate_base = NA_real_,
    pathogen_temp_corr_factor = NA_real_,
    pathogen_solar_rad_factor = NA_real_,
    pathogen_doc_attenuation = NA_real_,
    pathogen_settling_velocity = NA_real_,
    pathogen_wwtp_primary_removal = NA_real_,
    pathogen_wwtp_secondary_removal = NA_real_,
    pathogen_prevalence_source = NA_character_,
    pathogen_prevalence_url = NA_character_,
    pathogen_excretion_source = NA_character_,
    pathogen_excretion_url = NA_character_,
    pathogen_wwtp_source = NA_character_,
    pathogen_wwtp_url = NA_character_,
    pathogen_publication_year = NA_character_,
    pathogen_data_period = NA_character_,
    pathogen_notes = NA_character_,
    pathogen_parameter_file = NA_character_,
    pathogen_profile_registry = NA_character_
  )
  if (!identical(ScenarioInspectorValue(cfg$substance_type), "pathogen")) return(empty)

  pathogen_name <- ScenarioInspectorValue(cfg$pathogen_name, ScenarioInspectorValue(cfg$target_substance))
  param_file <- system.file("pathogen_input", paste0(pathogen_name, ".R"), package = "ePiE")
  profile_file <- ScenarioInspectorValue(
    cfg$pathogen_profile_path,
    system.file("pathogen_profiles", "pathogen_profiles.R", package = "ePiE")
  )

  params <- tryCatch(
    LoadPathogenParameters(
      pathogen_name,
      pathogen_profile_set = cfg$pathogen_profile_set,
      pathogen_profile_id = cfg$pathogen_profile_id,
      study_country = cfg$study_country,
      pathogen_profile_policy = cfg$pathogen_profile_policy %||% "strict",
      pathogen_profile_path = cfg$pathogen_profile_path
    ),
    error = function(e) {
      warning("Could not resolve pathogen profile for scenario `",
              ScenarioInspectorValue(cfg$scenario_name, cfg$target_substance),
              "`: ", conditionMessage(e), call. = FALSE)
      NULL
    }
  )
  if (is.null(params)) {
    empty$pathogen_parameter_file <- ScenarioInspectorPath(param_file)
    empty$pathogen_profile_registry <- ScenarioInspectorPath(profile_file)
    return(empty)
  }

  value <- function(name, default = NA_character_) {
    ScenarioInspectorValue(params[[name]], default)
  }
  number <- function(name) {
    suppressWarnings(as.numeric(params[[name]][[1]] %||% NA_real_))
  }

  list(
    pathogen_profile_id_resolved = value("pathogen_profile_id"),
    pathogen_profile_label = value("pathogen_profile_label"),
    pathogen_profile_region = value("pathogen_profile_region"),
    pathogen_profile_confidence = value("pathogen_profile_confidence"),
    pathogen_units = value("units"),
    pathogen_prevalence_rate = number("prevalence_rate"),
    pathogen_excretion_rate = number("excretion_rate"),
    pathogen_decay_rate_base = number("decay_rate_base"),
    pathogen_temp_corr_factor = number("temp_corr_factor"),
    pathogen_solar_rad_factor = number("solar_rad_factor"),
    pathogen_doc_attenuation = number("doc_attenuation"),
    pathogen_settling_velocity = number("settling_velocity"),
    pathogen_wwtp_primary_removal = number("wwtp_primary_removal"),
    pathogen_wwtp_secondary_removal = number("wwtp_secondary_removal"),
    pathogen_prevalence_source = value("pathogen_profile_prevalence_source_short"),
    pathogen_prevalence_url = value("pathogen_profile_prevalence_source_url"),
    pathogen_excretion_source = value("pathogen_profile_excretion_source_short"),
    pathogen_excretion_url = value("pathogen_profile_excretion_source_url"),
    pathogen_wwtp_source = value("pathogen_profile_wwtp_source_short"),
    pathogen_wwtp_url = value("pathogen_profile_wwtp_source_url"),
    pathogen_publication_year = value("pathogen_profile_publication_year"),
    pathogen_data_period = value("pathogen_profile_data_period"),
    pathogen_notes = value("pathogen_profile_notes"),
    pathogen_parameter_file = ScenarioInspectorPath(param_file),
    pathogen_profile_registry = ScenarioInspectorPath(profile_file)
  )
}

InspectChemicalSetup <- function(cfg) {
  empty <- list(
    chemical_units = NA_character_,
    chemical_data_file = NA_character_,
    chemical_data_exists = FALSE,
    chemical_row_found = NA,
    chemical_reference = "Oldenkamp et al. 2018 supplementary chemical data",
    chemical_reference_file = ScenarioInspectorPath(system.file("chem_input", "SI_Oldenkamp2018.pdf", package = "ePiE"))
  )
  if (!identical(ScenarioInspectorValue(cfg$substance_type), "chemical")) return(empty)

  chem_file <- ScenarioInspectorValue(cfg$input_paths$chem_data, cfg$chem_data_path)
  target <- ScenarioInspectorValue(cfg$target_substance)
  row_found <- NA
  if (!is.na(chem_file) && file.exists(chem_file) && requireNamespace("readxl", quietly = TRUE)) {
    row_found <- tryCatch({
      chem_data <- readxl::read_excel(chem_file)
      if ("substance" %in% names(chem_data) && !("API" %in% names(chem_data))) {
        names(chem_data)[names(chem_data) == "substance"] <- "API"
      }
      "API" %in% names(chem_data) && any(as.character(chem_data$API) == target, na.rm = TRUE)
    }, error = function(e) NA)
  }

  list(
    chemical_units = "ug/L",
    chemical_data_file = ScenarioInspectorPath(chem_file),
    chemical_data_exists = ScenarioInspectorFileExists(chem_file),
    chemical_row_found = row_found,
    chemical_reference = empty$chemical_reference,
    chemical_reference_file = empty$chemical_reference_file
  )
}

InspectOneScenarioSetup <- function(scenario_name, data_root, output_root) {
  cfg <- LoadScenarioConfig(scenario_name, data_root, output_root)
  cfg$scenario_name <- scenario_name
  substance_type <- ScenarioInspectorValue(cfg$substance_type, "network")
  canal <- InspectCanalQSource(cfg)
  pathogen <- InspectPathogenSetup(cfg)
  chemical <- InspectChemicalSetup(cfg)

  row <- c(
    list(
      scenario = scenario_name,
      basin_id = ScenarioInspectorValue(cfg$basin_id),
      study_country = ScenarioInspectorValue(cfg$study_country),
      substance_type = substance_type,
      target_substance = ScenarioInspectorValue(cfg$target_substance),
      pathogen_name = ScenarioInspectorValue(cfg$pathogen_name),
      concentration_units = if (identical(substance_type, "pathogen")) {
        pathogen$pathogen_units
      } else if (identical(substance_type, "chemical")) {
        chemical$chemical_units
      } else {
        NA_character_
      },
      is_dry_season = isTRUE(cfg$is_dry_season),
      run_output_dir = ScenarioInspectorPath(cfg$run_output_dir),
      data_root = ScenarioInspectorPath(data_root),
      output_root = ScenarioInspectorPath(output_root),
      input_paths = ScenarioInputSummary(cfg$input_paths),
      pts_file = ScenarioInspectorPath(cfg$input_paths$pts),
      hl_file = ScenarioInspectorPath(cfg$input_paths$hl),
      rivers_file = ScenarioInspectorPath(cfg$input_paths$rivers),
      basin_file = ScenarioInspectorPath(cfg$input_paths$basin %||% cfg$basin_shp_path),
      lake_file = ScenarioInspectorPath(cfg$lakes_shp_path),
      canal_file = ScenarioInspectorPath(cfg$canal_shp_path),
      population_raster = ScenarioInspectorPath(cfg$pop_raster_path),
      wwtp_file = ScenarioInspectorPath(cfg$wwtp_csv_path),
      hydrowaste_file = ScenarioInspectorPath(cfg$hydrowaste_csv_path),
      flow_source = ScenarioInspectorValue(cfg$flow_source, ScenarioInspectorValue(cfg$input_paths$flow_source)),
      flow_raster = ScenarioInspectorPath(cfg$input_paths$flow_raster %||% cfg$flow_raster_path),
      flow_raster_highres = ScenarioInspectorPath(cfg$input_paths$flow_raster_highres %||% cfg$flow_raster_highres_path),
      discharge_gpkg = ScenarioInspectorPath(cfg$discharge_gpkg_path),
      prefer_highres_flow = isTRUE(cfg$prefer_highres_flow),
      slope_raster = ScenarioInspectorPath(cfg$slope_raster_path),
      wind_raster = ScenarioInspectorPath(cfg$wind_raster_path),
      temp_raster = ScenarioInspectorPath(cfg$temp_raster_path),
      enable_lakes = isTRUE(cfg$enable_lakes),
      lake_transport_mode = ScenarioInspectorValue(cfg$lake_transport_mode),
      lake_snap_enabled = isTRUE(cfg$lake_snap_enabled),
      lake_require_inlet_and_outlet = if (is.null(cfg$lake_require_inlet_and_outlet)) NA else isTRUE(cfg$lake_require_inlet_and_outlet),
      enable_canals = isTRUE(cfg$enable_canals),
      connect_canals_to_rivers = if (is.null(cfg$connect_canals_to_rivers)) NA else isTRUE(cfg$connect_canals_to_rivers),
      canal_q_source_id = ScenarioInspectorValue(cfg$canal_q_source_id),
      canal_q_regime = ScenarioInspectorValue(cfg$canal_q_regime),
      canal_q_source_table = ScenarioInspectorPath(cfg$canal_q_source_table),
      canal_tail_flow_fraction = suppressWarnings(as.numeric(cfg$canal_tail_flow_fraction %||% NA_real_)),
      canal_discharge_table = ScenarioInspectorPath(cfg$canal_discharge_table),
      use_cpp = isTRUE(cfg$use_cpp),
      branch_solver_behavior = "branched transport uses R edge-aware solver; ID_nxt is compatibility metadata",
      transport_routing_artifact = "transport_edges.csv",
      visualization_variants = ScenarioInspectorCollapse(cfg$visualization_variants),
      provenance_label_mode = ScenarioInspectorValue(cfg$provenance_label_mode),
      formula_files = ScenarioFormulaFilesFor(substance_type),
      expected_outputs = ScenarioExpectedOutputs(cfg)
    ),
    canal,
    pathogen,
    chemical
  )

  as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
}

ScenarioSetupToLong <- function(wide) {
  if (nrow(wide) == 0) return(data.frame())
  rows <- vector("list", nrow(wide) * (ncol(wide) - 1L))
  idx <- 0L
  fields <- setdiff(names(wide), "scenario")
  section_for <- function(field) {
    if (grepl("^pathogen_", field)) return("pathogen")
    if (grepl("^chemical_", field)) return("chemical")
    if (grepl("^canal_", field)) return("canal")
    if (grepl("^lake_", field)) return("lake")
    if (grepl("flow|raster|hydrology|slope|wind|temp", field)) return("hydrology")
    if (grepl("file|paths|dir|root", field)) return("inputs_outputs")
    if (grepl("formula|transport|solver", field)) return("formula_transport")
    "scenario"
  }
  for (i in seq_len(nrow(wide))) {
    for (field in fields) {
      idx <- idx + 1L
      rows[[idx]] <- data.frame(
        scenario = as.character(wide$scenario[i]),
        section = section_for(field),
        field = field,
        value = as.character(wide[[field]][i]),
        stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  out$value[is.na(out$value)] <- ""
  out
}

PrintScenarioSetupTable <- function(df, format) {
  if (identical(format, "long")) {
    print(utils::head(df, 80), row.names = FALSE)
    if (nrow(df) > 80) {
      cat("... ", nrow(df) - 80, " more rows. Use export_csv to save the full table.\n", sep = "")
    }
    return(invisible(NULL))
  }

  screen_cols <- intersect(
    c("scenario", "basin_id", "study_country", "substance_type",
      "target_substance", "concentration_units", "flow_source",
      "canal_q_source_id", "pathogen_profile_id_resolved",
      "lake_transport_mode", "run_output_dir"),
    names(df)
  )
  print(df[, screen_cols, drop = FALSE], row.names = FALSE)
  invisible(NULL)
}

#' Inspect Scenario Setup
#'
#' Builds a scenario-audit table from the configured scenario registry. The
#' function reports configured inputs, units, source registries, reference URLs,
#' and formula/code modules. It does not run the model or inspect generated
#' outputs.
#'
#' @param scenario Optional character vector of scenario names. \code{NULL}
#'   inspects every scenario returned by \code{ListScenarios()}.
#' @param data_root Character root for input data.
#' @param output_root Character root for generated outputs.
#' @param export_csv Optional CSV path. When supplied, the table is written.
#' @param format Character. \code{"wide"} for one row per scenario or
#'   \code{"long"} for one row per scenario field.
#' @return The audit table, invisibly after printing or exporting.
#' @export
InspectScenarioSetup <- function(scenario = NULL,
                                 data_root = "Inputs",
                                 output_root = "Outputs",
                                 export_csv = NULL,
                                 format = "wide") {
  format <- match.arg(format, c("wide", "long"))
  scenarios <- if (is.null(scenario) || length(scenario) == 0) {
    ListScenarios()
  } else {
    as.character(scenario)
  }
  unknown <- setdiff(scenarios, ListScenarios())
  if (length(unknown) > 0) {
    stop("Unknown scenario(s): ", paste(unknown, collapse = ", "),
         ". Available scenarios: ", paste(ListScenarios(), collapse = ", "))
  }

  rows <- lapply(scenarios, InspectOneScenarioSetup,
                 data_root = data_root, output_root = output_root)
  wide <- do.call(rbind, rows)
  out <- if (identical(format, "long")) ScenarioSetupToLong(wide) else wide

  if (!is.null(export_csv) && nzchar(as.character(export_csv))) {
    export_csv <- normalizePath(as.character(export_csv), winslash = "/", mustWork = FALSE)
    dir.create(dirname(export_csv), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(out, export_csv, row.names = FALSE)
    cat("Scenario setup audit written to: ", export_csv, "\n", sep = "")
  } else {
    PrintScenarioSetupTable(out, format)
  }

  invisible(out)
}

ScenarioTemplateName <- function(name) {
  if (is.null(name) || length(name) != 1 || is.na(name) || !nzchar(as.character(name))) {
    stop("`name` must be one non-empty scenario function name.")
  }
  name <- as.character(name)
  if (!grepl("^[A-Za-z][A-Za-z0-9_.]*$", name)) {
    stop("Scenario name must be a valid simple R function name: ", name)
  }
  name
}

ScenarioTemplateBasinFunction <- function(basin_id) {
  basin_id <- tolower(ScenarioInspectorValue(basin_id))
  if (identical(basin_id, "bega")) return("BegaBasinConfig")
  if (identical(basin_id, "volta")) return("VoltaBasinConfig")
  if (identical(basin_id, "volta_geoglows")) return("VoltaGeoGLOWSConfig")
  stop("Unsupported basin_id: ", basin_id,
       ". Use one of: bega, volta, volta_geoglows.")
}

RenderScenarioTemplate <- function(name, basin_id, substance_type, target_substance, copy_from) {
  name <- ScenarioTemplateName(name)
  substance_type <- match.arg(as.character(substance_type), c("chemical", "pathogen", "network"))
  target_substance <- ScenarioInspectorValue(target_substance, "")
  if (identical(substance_type, "network")) target_substance <- ""
  output_slug <- tolower(gsub("[^A-Za-z0-9]+", "_", name))

  if (!is.null(copy_from) && nzchar(as.character(copy_from))) {
    copy_from <- as.character(copy_from)
    return(paste0(
      name, " <- function(data_root, output_root) {\n",
      "  # Template copied from an existing scenario. Review every scientific\n",
      "  # choice below before adding this scenario to ListScenarios().\n",
      "  cfg <- LoadScenarioConfig(\"", copy_from, "\", data_root, output_root)\n",
      "  cfg$substance_type <- \"", substance_type, "\"\n",
      if (identical(substance_type, "pathogen")) paste0(
        "  cfg$target_substance <- \"", target_substance, "\"\n",
        "  cfg$pathogen_name <- \"", target_substance, "\"\n",
        "  cfg$pathogen_profile_set <- cfg$pathogen_profile_set # area-specific profile set\n",
        "  cfg$pathogen_profile_policy <- \"strict\"\n"
      ) else if (identical(substance_type, "chemical")) paste0(
        "  cfg$target_substance <- \"", target_substance, "\"\n",
        "  cfg$input_paths$chem_data <- cfg$input_paths$chem_data # chemical workbook\n"
      ) else "",
      "  cfg$flow_source <- cfg$flow_source # configured, highres_qav, qav, qmi, or geoglows\n",
      "  cfg$lake_transport_mode <- cfg$lake_transport_mode # legacy_pass_through or cstr\n",
      "  cfg$canal_q_source_id <- cfg$canal_q_source_id # required when canals are enabled\n",
      "  cfg$run_output_dir <- file.path(output_root, \"", output_slug, "\")\n",
      "  cfg\n",
      "}\n"
    ))
  }

  basin_fun <- ScenarioTemplateBasinFunction(basin_id)
  paste0(
    name, " <- function(data_root, output_root) {\n",
    "  # New scenario template. Fill in scientific choices explicitly before use.\n",
    "  bc <- ", basin_fun, "(data_root)\n",
    "  list(\n",
    "    basin_id = bc$basin_id,\n",
    "    study_country = bc$study_country,\n",
    "    substance_type = \"", substance_type, "\",\n",
    if (identical(substance_type, "pathogen")) paste0(
      "    target_substance = \"", target_substance, "\",\n",
      "    pathogen_name = \"", target_substance, "\",\n",
      "    pathogen_profile_set = bc$pathogen_profile_set,\n",
      "    pathogen_profile_policy = \"strict\",\n"
    ) else if (identical(substance_type, "chemical")) paste0(
      "    target_substance = \"", target_substance, "\",\n"
    ) else "",
    "    is_dry_season = FALSE,\n",
    "    flow_source = if (!is.null(bc$flow_source_default)) bc$flow_source_default else NULL,\n",
    "    lake_transport_mode = if (!is.null(bc$lake_transport_mode_default)) bc$lake_transport_mode_default else \"cstr\",\n",
    "    canal_q_source_id = if (!is.null(bc$canal_q_source_id)) bc$canal_q_source_id else NULL,\n",
    "    run_output_dir = file.path(output_root, \"", output_slug, "\"),\n",
    "    input_paths = list(\n",
    "      pts = file.path(output_root, bc$basin_id, \"pts.csv\"),\n",
    "      hl = file.path(output_root, bc$basin_id, \"HL.csv\"),\n",
    "      rivers = file.path(output_root, bc$basin_id, \"network_rivers.shp\"),\n",
    "      basin = bc$basin_shp_path,\n",
    if (identical(substance_type, "chemical")) "      chem_data = bc$chem_data_path,\n" else "",
    "      flow_raster = bc$flow_raster_path\n",
    "    ),\n",
    "    enable_lakes = TRUE,\n",
    "    enable_canals = !is.null(bc$canal_shp_path),\n",
    "    dataDir = data_root,\n",
    "    country_population = bc$country_population\n",
    "  )\n",
    "}\n"
  )
}

#' Create Scenario Template
#'
#' Prints or writes a conservative scenario constructor template. The helper is
#' intentionally not a full scenario wizard: the generated template still needs
#' scientific review before it is added to the scenario registry.
#'
#' @param name New scenario function name.
#' @param basin_id Basin key: \code{"bega"}, \code{"volta"}, or
#'   \code{"volta_geoglows"}.
#' @param substance_type \code{"chemical"}, \code{"pathogen"}, or
#'   \code{"network"}.
#' @param target_substance Chemical or pathogen name.
#' @param copy_from Optional existing scenario to use as the structural base.
#' @param output_file Optional file path. If \code{NULL}, prints to screen only.
#' @param overwrite Logical. Whether an existing \code{output_file} may be
#'   overwritten.
#' @return Template text, invisibly.
#' @export
CreateScenarioTemplate <- function(name,
                                   basin_id = NULL,
                                   substance_type = NULL,
                                   target_substance = NULL,
                                   copy_from = NULL,
                                   output_file = NULL,
                                   overwrite = FALSE) {
  if (!is.null(copy_from) && nzchar(as.character(copy_from))) {
    if (!(as.character(copy_from) %in% ListScenarios())) {
      stop("Unknown copy_from scenario: ", copy_from,
           ". Available scenarios: ", paste(ListScenarios(), collapse = ", "))
    }
    base_cfg <- LoadScenarioConfig(as.character(copy_from), "Inputs", "Outputs")
    if (is.null(basin_id) || !nzchar(as.character(basin_id))) {
      basin_id <- if (!is.null(base_cfg$network_source) &&
                      identical(as.character(base_cfg$network_source), "geoglows")) {
        "volta_geoglows"
      } else {
        base_cfg$basin_id
      }
    }
    if (is.null(substance_type) || !nzchar(as.character(substance_type))) {
      substance_type <- base_cfg$substance_type %||% "network"
    }
    if (is.null(target_substance) || !nzchar(as.character(target_substance))) {
      target_substance <- base_cfg$target_substance %||% base_cfg$pathogen_name %||% NULL
    }
  }
  if (is.null(basin_id) || !nzchar(as.character(basin_id))) {
    stop("`basin_id` is required when `copy_from` is not supplied.")
  }
  if (is.null(substance_type) || !nzchar(as.character(substance_type))) {
    stop("`substance_type` is required when `copy_from` is not supplied.")
  }
  text <- RenderScenarioTemplate(
    name = name,
    basin_id = basin_id,
    substance_type = substance_type,
    target_substance = target_substance,
    copy_from = copy_from
  )

  if (!is.null(output_file) && nzchar(as.character(output_file))) {
    output_file <- normalizePath(as.character(output_file), winslash = "/", mustWork = FALSE)
    if (file.exists(output_file) && !isTRUE(overwrite)) {
      stop("Refusing to overwrite existing scenario template: ", output_file)
    }
    dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
    writeLines(text, output_file, useBytes = TRUE)
    cat("Scenario template written to: ", output_file, "\n", sep = "")
  } else {
    cat(text)
  }

  invisible(text)
}
