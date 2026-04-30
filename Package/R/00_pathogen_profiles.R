# ==============================================================================
# Area-specific pathogen profile registry
# ==============================================================================
# Pathogen biology (decay, settling, display units) is loaded from
# inst/pathogen_input/<pathogen>.R. Emission assumptions that depend on place,
# period, sanitation context, or literature source are resolved here from
# inst/pathogen_profiles/pathogen_profiles.R.
#
# Scenario runs use strict profile resolution so a Romanian basin cannot
# silently reuse a Ghana/Sub-Saharan-Africa emission setup.
# ==============================================================================

PATHOGEN_PROFILE_REQUIRED_FIELDS <- c(
  "profile_set", "profile_id", "pathogen_name", "study_country", "region",
  "prevalence_rate", "excretion_rate", "wwtp_primary_removal",
  "wwtp_secondary_removal", "units", "prevalence_source_short",
  "prevalence_source_url", "excretion_source_short", "excretion_source_url"
)

#' Load Pathogen Profile Registry
#'
#' Returns the packaged table of area-specific pathogen emission profiles.
#' Each row is one pathogen/profile combination with numeric assumptions and
#' citation metadata.
#'
#' @param profile_path Optional path to a custom registry R file. The file must
#'   define \code{pathogen_profiles}.
#' @return data.frame with profile rows.
#' @export
LoadPathogenProfileRegistry <- function(profile_path = NULL) {
  if (is.null(profile_path) || !nzchar(as.character(profile_path))) {
    profile_path <- system.file("pathogen_profiles", "pathogen_profiles.R", package = "ePiE")
  }
  if (profile_path == "" || !file.exists(profile_path)) {
    stop("Pathogen profile registry not found: inst/pathogen_profiles/pathogen_profiles.R")
  }

  env <- new.env(parent = baseenv())
  source(profile_path, local = env)
  if (!exists("pathogen_profiles", envir = env)) {
    stop("Pathogen profile registry must define `pathogen_profiles`.")
  }

  profiles <- as.data.frame(env$pathogen_profiles, stringsAsFactors = FALSE)
  missing <- setdiff(PATHOGEN_PROFILE_REQUIRED_FIELDS, names(profiles))
  if (length(missing) > 0) {
    stop("Pathogen profile registry is missing required columns: ",
         paste(missing, collapse = ", "))
  }
  profiles
}

NormalizePathogenProfilePolicy <- function(policy) {
  policy <- if (is.null(policy) || length(policy) == 0 || is.na(policy[[1]]) || !nzchar(as.character(policy[[1]]))) {
    "strict"
  } else {
    tolower(as.character(policy[[1]]))
  }
  if (policy %in% c("warn", "fallback", "fallback_warning")) return("fallback_warning")
  if (policy %in% c("legacy", "legacy_unprofiled")) return("legacy")
  if (policy != "strict") {
    stop("Unknown pathogen_profile_policy: ", policy,
         ". Use 'strict', 'fallback_warning', or 'legacy'.")
  }
  policy
}

DefaultPathogenProfileSet <- function(study_country) {
  country <- toupper(as.character(study_country %||% ""))
  if (identical(country, "GH")) return("ghana_ssa_screening")
  if (identical(country, "RO")) return("romania_eu_screening")
  NA_character_
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

RequireProfileField <- function(row, field, profile_label) {
  value <- row[[field]]
  if (length(value) == 0 || is.na(value[[1]]) || !nzchar(as.character(value[[1]]))) {
    stop("Pathogen profile `", profile_label, "` is missing required metadata field: ", field)
  }
  value[[1]]
}

ValidateResolvedPathogenProfile <- function(profile) {
  profile_label <- if ("profile_id" %in% names(profile)) as.character(profile$profile_id[[1]]) else "<unknown>"
  numeric_fields <- c("prevalence_rate", "excretion_rate", "wwtp_primary_removal", "wwtp_secondary_removal")
  for (field in numeric_fields) {
    value <- suppressWarnings(as.numeric(profile[[field]][[1]]))
    if (!is.finite(value) || value < 0) {
      stop("Pathogen profile `", profile_label, "` has invalid numeric field: ", field)
    }
  }
  for (field in c("prevalence_source_short", "prevalence_source_url",
                  "excretion_source_short", "excretion_source_url",
                  "wwtp_source_short", "wwtp_source_url")) {
    RequireProfileField(profile, field, profile_label)
  }
  invisible(TRUE)
}

#' Resolve Pathogen Profile
#'
#' Selects one profile for a pathogen and basin/scenario. Explicit
#' \code{pathogen_profile_id} has highest priority, then \code{pathogen_profile_set},
#' then the default profile set for \code{study_country}. Strict mode fails if
#' no profile can be resolved.
#'
#' @param pathogen_name Character pathogen key.
#' @param pathogen_profile_set Optional profile set such as
#'   \code{"ghana_ssa_screening"}.
#' @param pathogen_profile_id Optional exact profile id.
#' @param study_country ISO country code used for default profile selection.
#' @param pathogen_profile_policy \code{"strict"}, \code{"fallback_warning"}, or
#'   \code{"legacy"}.
#' @param profile_path Optional custom registry path.
#' @return One-row data.frame profile, or \code{NULL} in legacy mode.
#' @export
ResolvePathogenProfile <- function(pathogen_name,
                                   pathogen_profile_set = NULL,
                                   pathogen_profile_id = NULL,
                                   study_country = NULL,
                                   pathogen_profile_policy = "strict",
                                   profile_path = NULL) {
  pathogen_name <- tolower(as.character(pathogen_name[[1]]))
  policy <- NormalizePathogenProfilePolicy(pathogen_profile_policy)

  if (policy == "legacy" &&
      (is.null(pathogen_profile_set) || !nzchar(as.character(pathogen_profile_set[[1]]))) &&
      (is.null(pathogen_profile_id) || !nzchar(as.character(pathogen_profile_id[[1]]))) &&
      (is.null(study_country) || !nzchar(as.character(study_country[[1]])))) {
    return(NULL)
  }

  profiles <- LoadPathogenProfileRegistry(profile_path)
  profiles$pathogen_name <- tolower(as.character(profiles$pathogen_name))
  profiles$study_country <- toupper(as.character(profiles$study_country))

  selected <- profiles[profiles$pathogen_name == pathogen_name, , drop = FALSE]
  if (!is.null(pathogen_profile_id) && nzchar(as.character(pathogen_profile_id[[1]]))) {
    selected <- selected[selected$profile_id == as.character(pathogen_profile_id[[1]]), , drop = FALSE]
  } else {
    resolved_set <- if (!is.null(pathogen_profile_set) && nzchar(as.character(pathogen_profile_set[[1]]))) {
      as.character(pathogen_profile_set[[1]])
    } else {
      DefaultPathogenProfileSet(study_country)
    }
    if (!is.na(resolved_set) && nzchar(resolved_set)) {
      selected <- selected[selected$profile_set == resolved_set, , drop = FALSE]
    } else if (!is.null(study_country) && nzchar(as.character(study_country[[1]]))) {
      selected <- selected[selected$study_country == toupper(as.character(study_country[[1]])), , drop = FALSE]
    } else {
      selected <- selected[FALSE, , drop = FALSE]
    }
  }

  if (nrow(selected) == 0 && policy == "fallback_warning") {
    warning("No area-specific pathogen profile found for ", pathogen_name,
            "; falling back to legacy pathogen_input values.")
    return(NULL)
  }
  if (nrow(selected) == 0) {
    stop(
      "No pathogen profile found for pathogen='", pathogen_name, "', country='",
      as.character(study_country %||% ""), "', profile_set='",
      as.character(pathogen_profile_set %||% ""), "', profile_id='",
      as.character(pathogen_profile_id %||% ""), "'. Strict pathogen profile ",
      "selection prevents reusing parameters from the wrong region."
    )
  }
  if (nrow(selected) > 1) {
    stop("Pathogen profile selection is ambiguous for ", pathogen_name, ": ",
         paste(selected$profile_id, collapse = ", "))
  }

  ValidateResolvedPathogenProfile(selected)
  selected
}

ApplyPathogenProfile <- function(params, profile) {
  if (is.null(profile)) {
    params$pathogen_profile_policy <- "legacy"
    params$pathogen_profile_id <- NA_character_
    params$pathogen_profile_set <- NA_character_
    return(params)
  }

  numeric_fields <- c("prevalence_rate", "excretion_rate", "wwtp_primary_removal", "wwtp_secondary_removal")
  for (field in numeric_fields) {
    params[[field]] <- as.numeric(profile[[field]][[1]])
  }
  params$units <- as.character(profile$units[[1]])

  metadata_fields <- setdiff(names(profile), numeric_fields)
  for (field in metadata_fields) {
    params[[paste0("pathogen_profile_", field)]] <- as.character(profile[[field]][[1]])
  }
  params$pathogen_profile_id <- as.character(profile$profile_id[[1]])
  params$pathogen_profile_set <- as.character(profile$profile_set[[1]])
  params$pathogen_profile_label <- as.character(profile$profile_label[[1]])
  params$pathogen_profile_region <- as.character(profile$region[[1]])
  params$pathogen_profile_country <- as.character(profile$study_country[[1]])
  params$pathogen_profile_confidence <- as.character(profile$profile_confidence[[1]])
  params$pathogen_profile_notes <- as.character(profile$profile_notes[[1]])
  params$pathogen_profile_policy <- "strict"
  params
}
