# ==============================================================================
# Substance Abstraction Layer
# ==============================================================================
# This module provides the substance (pathogen) abstraction layer for ePiE.
# It loads, validates, and resolves pathogen-specific parameters from config
# files stored in inst/pathogen_input/, making them available to the simulation
# pipeline.
#
# The abstraction decouples pathogen-specific parameterisation from the core
# transport and decay engine, enabling multi-pathogen support without modifying
# simulation code.
#
# Workflow:
#   1. LoadPathogenParameters()  — sources a parameter file, returns a list
#   2. ValidatePathogenParams()  — ensures all required fields are present
#   3. ResolvePathogenParams()   — guarantees total_population is available
#
# TODO(MULTI-PATHOGEN): Extend to support chemicals alongside pathogens.
#   A chemical type would need different required parameters (e.g. half-life,
#   partition coefficients) and different validation rules.
# ==============================================================================

# --- Required pathogen parameters ------------------------------------------------
# These fields must be present in every pathogen parameter file.
#   prevalence_rate   : fraction of population shedding the pathogen       [-]
#   excretion_rate    : pathogen load excreted per infected person per year [org/year]
#   decay_rate_base   : base decay rate at reference temperature           [day^-1]
#   temp_corr_factor  : temperature correction factor (theta)              [-]
#   solar_rad_factor  : solar proportionality constant (kl)                [m^2 kJ^-1]
#   doc_attenuation   : DOC-specific light attenuation coefficient (kd)    [L mg^-1 m^-1]
#   settling_velocity : settling velocity of pathogen particles (v_s)      [m/day]
#
# TODO(MULTI-PATHOGEN): When adding chemicals, define a separate
#   CHEMICAL_REQUIRED_PARAMS constant and dispatch validation based on
#   params$type.
# ---------------------------------------------------------------------------------
PATHOGEN_REQUIRED_PARAMS <- c(
  "prevalence_rate", "excretion_rate",
  "decay_rate_base", "temp_corr_factor",
  "solar_rad_factor", "doc_attenuation",
  "settling_velocity"
)

#' Load Pathogen Simulation Parameters
#'
#' Sources and validates pathogen-specific parameters from an R file stored in
#' \code{inst/pathogen_input/}. The file must define a \code{simulation_parameters} list.
#'
#' @param pathogen_name Character. Name of the pathogen (matches an \code{.R} file in
#'   \code{inst/pathogen_input/}).
#' @return A validated list of pathogen simulation parameters, with a \code{name} field appended.
#' @export
# --- LoadPathogenParameters ------------------------------------------------------
# Sources a pathogen parameter file from inst/pathogen_input/<name>.R and returns
# a validated parameter list. The parameter file must define a variable called
#   simulation_parameters <- list(...)
# which is then extracted, validated, and augmented with the pathogen name.
#
# Parameters:
#   pathogen_name : Character. Name matching an .R file in inst/pathogen_input/
#
# Return: A validated list of pathogen simulation parameters with a `name` field.
# ---------------------------------------------------------------------------------
LoadPathogenParameters <- function(pathogen_name) {
  # Locate the parameter file in the installed package directory
  param_path <- system.file("pathogen_input", paste0(pathogen_name, ".R"),
                            package = "ePiE")

  # Verify the file exists in inst/pathogen_input/
  if (param_path == "" || !file.exists(param_path)) {
    stop(sprintf("Pathogen parameter file not found: inst/pathogen_input/%s.R", pathogen_name))
  }

  # Source into a sandboxed environment to avoid polluting the caller's namespace
  env <- new.env(parent = baseenv())
  source(param_path, local = env)

  # Ensure the file defines the expected variable
  if (!exists("simulation_parameters", envir = env)) {
    stop(sprintf("Parameter file '%s.R' did not define 'simulation_parameters'.", pathogen_name))
  }

  # Convert to a plain list for downstream consumption
  params <- as.list(env$simulation_parameters)

  # Validate required fields are present and fill optional defaults
  params <- ValidatePathogenParams(params)

  # Attach the pathogen name for traceability in downstream outputs
  params$name <- pathogen_name
  params
}

#' Validate Pathogen Parameter Set
#'
#' Checks that a parameter list has type \code{"pathogen"} and contains all required
#' fields. Fills optional WWTP-removal and population defaults when absent.
#'
#' @param params List. Candidate parameter set to validate.
#' @return The input \code{params} list, potentially with default values added.
#' @export
# --- ValidatePathogenParams ------------------------------------------------------
# Checks that a parameter list declares itself as type "pathogen" and contains
# all required fields (see PATHOGEN_REQUIRED_PARAMS). Fills in optional defaults
# for WWTP removal fractions and total_population when absent.
#
# Parameters:
#   params : List. Candidate parameter set loaded from a pathogen config file.
#
# Return: The input params list, potentially with default values added for
#   optional fields (wwtp_primary_removal, wwtp_secondary_removal, total_population).
#
# TODO(MULTI-PATHOGEN): Dispatch validation logic based on params$type to support
#   chemical parameter sets with different required fields.
# ---------------------------------------------------------------------------------
ValidatePathogenParams <- function(params) {
  # Basic type check
  if (!is.list(params)) stop("Pathogen parameters must be a list.")

  # Ensure the file declares itself as a pathogen parameter set
  if (is.null(params$type) || params$type != "pathogen") {
    stop("Parameter file must have type = 'pathogen'.")
  }

  # Identify any missing required parameters
  missing <- setdiff(PATHOGEN_REQUIRED_PARAMS, names(params))

  # Fail fast with an informative error listing all missing fields
  if (length(missing) > 0) {
    stop(sprintf("Missing required pathogen parameters: %s", paste(missing, collapse = ", ")))
  }

  # Fill optional WWTP removal defaults (0 = no removal if unspecified)
  if (is.null(params$wwtp_primary_removal)) params$wwtp_primary_removal <- 0
  if (is.null(params$wwtp_secondary_removal)) params$wwtp_secondary_removal <- 0

  # Population may be supplied later via ResolvePathogenParams()
  if (is.null(params$total_population)) params$total_population <- NA_real_

  params
}

#' Resolve Pathogen Population Parameter
#'
#' Ensures that \code{total_population} is available, either from the parameter file
#' or supplied at call time. Stops with an error if the value is still missing.
#'
#' @param params List. Pathogen parameter set (must contain \code{total_population} or accept it here).
#' @param total_population Numeric or \code{NULL}. Total population to assign if not already set.
#' @return The \code{params} list with \code{total_population} guaranteed to be non-NA.
#' @export
# --- ResolvePathogenParams -------------------------------------------------------
# Ensures that total_population is available for emission calculations. The value
# can come from the parameter file or be supplied at call time. This two-stage
# resolution allows parameter files to omit population (keeping them reusable
# across basins) while still enforcing its presence before simulation.
#
# Parameters:
#   params          : List. Pathogen parameter set (may or may not contain
#                     total_population).
#   total_population : Numeric or NULL. Total population to assign if not already
#                      set in the parameter file.
#
# Return: The params list with total_population guaranteed to be a valid number.
#
# TODO(MULTI-PATHOGEN): When chemical substances are added, this function may
#   need a parallel ResolveChemicalParams() or a conditional branch, since
#   chemicals typically do not require a population parameter.
# ---------------------------------------------------------------------------------
ResolvePathogenParams <- function(params, total_population = NULL) {
  # Override file value with runtime-supplied population (takes precedence)
  if (!is.null(total_population)) {
    params$total_population <- total_population
  }

  # Guard: total_population is required for downstream emission calculations
  if (is.na(params$total_population) || is.null(params$total_population)) {
    stop("total_population must be provided (either in parameter file or at call time).")
  }

  # Return the fully resolved parameter set
  params
}

#' Initialize Substance Simulation
#'
#' Initializes simulation state for a given substance, automatically detecting whether
#' it is a pathogen (parameter file in \code{inst/pathogen_input/}) or chemical
#' (defined in the chemical data Excel file). Loads appropriate parameters and
#' calculates emissions for chemicals.
#'
#' @param state List. Simulation state object containing input paths, nodes,
#'   study country, and population data.
#' @param substance Character. Name of the substance to initialize.
#' @return The updated \code{state} list with substance-specific parameters loaded.
#' @export
InitializeSubstance <- function(state, substance) {
  param_path <- system.file("pathogen_input", paste0(substance, ".R"),
                            package = "ePiE")
  is_pathogen <- (param_path != "" && file.exists(param_path))

  if (is_pathogen) {
    params <- LoadPathogenParameters(substance)
    params <- ResolvePathogenParams(params, total_population = state$country_population)
    state$pathogen_params <- params
  } else {
    chem_data <- readxl::read_excel(state$input_paths$chem_data)
    if ("substance" %in% names(chem_data)) {
      names(chem_data)[names(chem_data) == "substance"] <- "API"
    }
    selected_row <- chem_data[chem_data$API == substance, ][1, ]
    selected_row <- as.data.frame(selected_row)
    chem <- CompleteChemProperties(chem = selected_row)
    emission_result <- CalculateEmissions(network_nodes = state$points,
                                          chem = chem,
                                          study_country = state$study_country,
                                          target_substance = substance)
    state$chem <- chem
    state$cons <- emission_result$cons
  }

  state
}
