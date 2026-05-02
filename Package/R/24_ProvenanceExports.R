#' Export Run Provenance
#'
#' Writes compact run-level metadata so scientific choices are visible outside
#' the R objects. The fields are intentionally simple key/value pairs for easy
#' checking in spreadsheets and release reviews.
ExportRunProvenance <- function(run_output_dir,
                                points = NULL,
                                cfg = list(),
                                input_paths = list(),
                                map_scale = NULL) {
  if (is.null(run_output_dir) || !nzchar(run_output_dir)) return(invisible(NULL))
  if (!dir.exists(run_output_dir)) dir.create(run_output_dir, recursive = TRUE, showWarnings = FALSE)

  point_df <- if (!is.null(points) && inherits(points, "sf")) sf::st_drop_geometry(points) else points
  canal_rows <- if (!is.null(point_df) && "is_canal" %in% names(point_df)) {
    point_df[point_df$is_canal %in% TRUE, , drop = FALSE]
  } else {
    data.frame()
  }

  first_nonempty <- function(values, default = NA_character_) {
    values <- unique(stats::na.omit(as.character(values)))
    values <- values[nzchar(values)]
    if (length(values) == 0) default else values[1]
  }
  cfg_value <- function(name, default = NA_character_) {
    if (!is.null(cfg[[name]]) && length(cfg[[name]]) > 0) as.character(cfg[[name]][[1]]) else default
  }
  pathogen_direct_override_sources <- function() {
    overrides <- cfg$pathogen_direct_fraction_overrides
    if (is.null(overrides) || !all(c("source_id", "f_pathogen_direct") %in% names(overrides))) {
      return(NA_character_)
    }
    paste(paste0(overrides$source_id, "=", overrides$f_pathogen_direct), collapse = "|")
  }

  provenance <- data.frame(
    key = c(
      "generated_date",
      "basin_id",
      "run_output_dir",
      "pathogen_profile_set",
      "pathogen_profile_id",
      "pathogen_profile_label",
      "pathogen_profile_region",
      "pathogen_profile_country",
      "pathogen_profile_confidence",
      "pathogen_prevalence_rate",
      "pathogen_excretion_rate",
      "pathogen_direct_fraction_overrides",
      "pathogen_prevalence_source",
      "pathogen_excretion_source",
      "canal_q_source_id",
      "canal_q_reference_short",
      "canal_q_reference_url",
      "canal_q_regime",
      "canal_q_data_period",
      "canal_q_season",
      "map_scale",
      "flow_raster",
      "rivers_layer",
      "basin_layer"
    ),
    value = c(
      format(Sys.Date(), "%Y-%m-%d"),
      cfg_value("basin_id", first_nonempty(point_df$basin_id)),
      run_output_dir,
      cfg_value("pathogen_profile_set", first_nonempty(point_df$pathogen_profile_set)),
      cfg_value("pathogen_profile_id", first_nonempty(point_df$pathogen_profile_id)),
      first_nonempty(point_df$pathogen_profile_label),
      first_nonempty(point_df$pathogen_profile_region),
      first_nonempty(point_df$pathogen_profile_country),
      first_nonempty(point_df$pathogen_profile_confidence),
      first_nonempty(point_df$pathogen_prevalence_rate),
      first_nonempty(point_df$pathogen_excretion_rate),
      pathogen_direct_override_sources(),
      first_nonempty(point_df$pathogen_prevalence_source),
      first_nonempty(point_df$pathogen_excretion_source),
      cfg_value("canal_q_source_id", first_nonempty(canal_rows$Q_source_id)),
      first_nonempty(canal_rows$Q_reference_short),
      first_nonempty(canal_rows$Q_reference_url),
      cfg_value("canal_q_regime", first_nonempty(canal_rows$Q_regime)),
      first_nonempty(canal_rows$Q_data_period),
      first_nonempty(canal_rows$Q_season),
      if (!is.null(map_scale)) paste(map_scale, collapse = "|") else cfg_value("map_scale"),
      if (!is.null(input_paths$flow_raster)) input_paths$flow_raster else NA_character_,
      if (!is.null(input_paths$rivers)) input_paths$rivers else NA_character_,
      if (!is.null(input_paths$basin)) input_paths$basin else NA_character_
    ),
    stringsAsFactors = FALSE
  )

  path <- file.path(run_output_dir, "run_provenance_summary.csv")
  write.csv(provenance, path, row.names = FALSE)
  invisible(path)
}

#' Export Pathogen Provenance
#'
#' Writes the selected pathogen profile and source metadata for a simulation.
#' This is intentionally separate from the compact run key/value file so users
#' can inspect the full profile in a spreadsheet.
ExportPathogenProvenance <- function(pathogen_params, run_output_dir) {
  if (is.null(pathogen_params) || is.null(run_output_dir) || !nzchar(run_output_dir)) {
    return(invisible(NULL))
  }
  if (!dir.exists(run_output_dir)) dir.create(run_output_dir, recursive = TRUE, showWarnings = FALSE)

  fields <- c(
    "name",
    "pathogen_profile_set",
    "pathogen_profile_id",
    "pathogen_profile_label",
    "pathogen_profile_region",
    "pathogen_profile_country",
    "pathogen_profile_confidence",
    "prevalence_rate",
    "excretion_rate",
    "wwtp_primary_removal",
    "wwtp_secondary_removal",
    "units",
    "pathogen_profile_prevalence_basis",
    "pathogen_profile_excretion_basis",
    "pathogen_profile_prevalence_source_short",
    "pathogen_profile_prevalence_source_url",
    "pathogen_profile_excretion_source_short",
    "pathogen_profile_excretion_source_url",
    "pathogen_profile_wwtp_source_short",
    "pathogen_profile_wwtp_source_url",
    "pathogen_profile_publication_year",
    "pathogen_profile_data_period",
    "pathogen_profile_notes"
  )

  value_for <- function(field) {
    value <- pathogen_params[[field]]
    if (is.null(value) || length(value) == 0) return(NA_character_)
    paste(as.character(value), collapse = "|")
  }

  out <- data.frame(
    parameter = fields,
    value = vapply(fields, value_for, character(1)),
    stringsAsFactors = FALSE
  )
  path <- file.path(run_output_dir, "pathogen_provenance_summary.csv")
  write.csv(out, path, row.names = FALSE)
  invisible(path)
}

#' Export Canal Q Assignment Summary
#'
#' Summarises the final node-level canal discharge assignment by canal section.
#' It records the selected source, citation, regime, direct/derived status, and
#' min/max/head/tail Q values used by the network.
ExportCanalQAssignmentSummary <- function(points, run_output_dir) {
  if (is.null(points) || nrow(points) == 0 || is.null(run_output_dir)) return(invisible(NULL))
  df <- if (inherits(points, "sf")) sf::st_drop_geometry(points) else points
  if (!("is_canal" %in% names(df)) || !any(df$is_canal %in% TRUE, na.rm = TRUE)) {
    return(invisible(NULL))
  }
  if (!dir.exists(run_output_dir)) dir.create(run_output_dir, recursive = TRUE, showWarnings = FALSE)

  canal_df <- df[df$is_canal %in% TRUE, , drop = FALSE]
  canal_df <- canal_df[!is.na(canal_df$canal_name) & nzchar(as.character(canal_df$canal_name)), , drop = FALSE]
  if (nrow(canal_df) == 0) return(invisible(NULL))

  first_nonempty <- function(values) {
    values <- unique(stats::na.omit(as.character(values)))
    values <- values[nzchar(values)]
    if (length(values) == 0) NA_character_ else paste(values, collapse = " | ")
  }

  split_rows <- split(canal_df, canal_df$canal_name)
  summary_rows <- lapply(split_rows, function(x) {
    x <- x[order(x$chainage_m, x$canal_idx), , drop = FALSE]
    q <- as.numeric(x$Q_model_m3s)
    data.frame(
      canal_name = as.character(x$canal_name[1]),
      n_nodes = nrow(x),
      chainage_min_m = suppressWarnings(min(as.numeric(x$chainage_m), na.rm = TRUE)),
      chainage_max_m = suppressWarnings(max(as.numeric(x$chainage_m), na.rm = TRUE)),
      Q_head_m3s = q[which.min(as.numeric(x$chainage_m))],
      Q_tail_m3s = q[which.max(as.numeric(x$chainage_m))],
      Q_min_m3s = suppressWarnings(min(q, na.rm = TRUE)),
      Q_max_m3s = suppressWarnings(max(q, na.rm = TRUE)),
      q_source_id = first_nonempty(x$Q_source_id),
      q_reference_short = first_nonempty(x$Q_reference_short),
      q_reference_url = first_nonempty(x$Q_reference_url),
      q_regime = first_nonempty(x$Q_regime),
      q_data_period = first_nonempty(x$Q_data_period),
      q_season = first_nonempty(x$Q_season),
      q_value_origin = first_nonempty(x$Q_value_origin),
      q_derivation_rule = first_nonempty(x$Q_derivation_rule),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, summary_rows)
  for (col in c("chainage_min_m", "chainage_max_m", "Q_head_m3s", "Q_tail_m3s", "Q_min_m3s", "Q_max_m3s")) {
    out[[col]][!is.finite(out[[col]])] <- NA_real_
  }

  path <- file.path(run_output_dir, "canal_q_assignment_summary.csv")
  write.csv(out, path, row.names = FALSE)
  invisible(path)
}
