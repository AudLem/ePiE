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
LoadPathogenParameters <- function(pathogen_name) {
  param_path <- system.file("pathogen_input", paste0(pathogen_name, ".R"),
                            package = "ePiE")
  if (param_path == "" || !file.exists(param_path)) {
    stop(sprintf("Pathogen parameter file not found: inst/pathogen_input/%s.R", pathogen_name))
  }

  env <- new.env(parent = baseenv())
  source(param_path, local = env)
  if (!exists("simulation_parameters", envir = env)) {
    stop(sprintf("Parameter file '%s.R' did not define 'simulation_parameters'.", pathogen_name))
  }

  params <- as.list(env$simulation_parameters)
  params <- ValidatePathogenParams(params)
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
ValidatePathogenParams <- function(params) {
  if (!is.list(params)) stop("Pathogen parameters must be a list.")
  if (is.null(params$type) || params$type != "pathogen") {
    stop("Parameter file must have type = 'pathogen'.")
  }
  missing <- setdiff(PATHOGEN_REQUIRED_PARAMS, names(params))
  if (length(missing) > 0) {
    stop(sprintf("Missing required pathogen parameters: %s", paste(missing, collapse = ", ")))
  }

  if (is.null(params$wwtp_primary_removal)) params$wwtp_primary_removal <- 0
  if (is.null(params$wwtp_secondary_removal)) params$wwtp_secondary_removal <- 0
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
ResolvePathogenParams <- function(params, total_population = NULL) {
  if (!is.null(total_population)) {
    params$total_population <- total_population
  }
  if (is.na(params$total_population) || is.null(params$total_population)) {
    stop("total_population must be provided (either in parameter file or at call time).")
  }
  params
}
