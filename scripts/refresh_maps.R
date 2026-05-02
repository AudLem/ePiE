#!/usr/bin/env Rscript
# Regenerate concentration maps from existing simulation_results.csv files.
#
# This is a map-only development helper. It does not run hydrology, emissions,
# transport, or any simulation formula.
#
# Examples:
#   Rscript scripts/refresh_maps.R --scenario BegaPathogenCrypto
#   Rscript scripts/refresh_maps.R --scenario VoltaWetChemicalIbuprofen --variant linear
#   Rscript scripts/refresh_maps.R --scenario BegaPathogenCrypto --variant linear,log10 --open

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else "scripts/refresh_maps.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
pkg_dir <- file.path(repo_root, "Package")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(pkg_dir)) {
  pkgload::load_all(pkg_dir, quiet = TRUE)
} else {
  library(ePiE)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
normalize_visualization_variants <- getFromNamespace("NormalizeVisualizationVariants", "ePiE")
build_concentration_binned_scale <- getFromNamespace("BuildConcentrationBinnedScale", "ePiE")

parse_args <- function(args) {
  out <- list(
    scenario = character(0),
    data_root = "Inputs",
    output_root = "Outputs",
    results = NULL,
    variant = character(0),
    open = FALSE,
    help = FALSE
  )

  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    read_value <- function() {
      if (grepl("=", arg, fixed = TRUE)) {
        sub("^[^=]+=", "", arg)
      } else {
        i <<- i + 1L
        if (i > length(args)) stop("Missing value after ", arg)
        args[[i]]
      }
    }

    if (arg %in% c("-h", "--help")) {
      out$help <- TRUE
    } else if (arg == "--scenario" || grepl("^--scenario=", arg)) {
      out$scenario <- c(out$scenario, read_value())
    } else if (arg == "--data-root" || grepl("^--data-root=", arg)) {
      out$data_root <- read_value()
    } else if (arg == "--output-root" || grepl("^--output-root=", arg)) {
      out$output_root <- read_value()
    } else if (arg == "--results" || grepl("^--results=", arg)) {
      out$results <- read_value()
    } else if (arg == "--variant" || grepl("^--variant=", arg)) {
      out$variant <- c(out$variant, unlist(strsplit(read_value(), ",", fixed = TRUE)))
    } else if (arg == "--open") {
      out$open <- TRUE
    } else {
      stop("Unknown argument: ", arg)
    }
    i <- i + 1L
  }

  out$variant <- trimws(out$variant)
  out$variant <- out$variant[nzchar(out$variant)]
  out
}

usage <- function() {
  cat(
    "Usage: Rscript scripts/refresh_maps.R --scenario NAME [options]\n\n",
    "Regenerates concentration maps from an existing simulation_results.csv.\n",
    "It does not rerun the simulation.\n\n",
    "Options:\n",
    "  --scenario NAME       Simulation scenario to refresh. Repeat for multiple scenarios.\n",
    "  --data-root PATH      Input data root. Default: Inputs\n",
    "  --output-root PATH    Output root. Default: Outputs\n",
    "  --results PATH        Override results CSV. Only valid with one scenario.\n",
    "  --variant LIST        Comma-separated map variants: linear,log10,auto,linear_binned.\n",
    "                        Default: scenario visualization_variants.\n",
    "  --open                Open the primary map after writing it.\n",
    "  --help                Show this help.\n",
    sep = ""
  )
}

first_non_empty <- function(values) {
  values <- values[!is.na(values) & nzchar(as.character(values))]
  if (length(values) == 0) NULL else as.character(values[[1]])
}

load_refresh_context <- function(scenario_name, args) {
  cfg <- LoadScenarioConfig(
    scenario_name,
    data_root = args$data_root,
    output_root = args$output_root
  )

  if (is.null(cfg$substance_type) || !(cfg$substance_type %in% c("chemical", "pathogen"))) {
    stop("Scenario is not a simulation scenario: ", scenario_name)
  }

  results_path <- args$results %||% file.path(cfg$run_output_dir, "simulation_results.csv")
  if (!file.exists(results_path)) {
    stop(
      "Missing simulation results for ", scenario_name, ": ", results_path, "\n",
      "Run the simulation once before using refresh_maps.R."
    )
  }

  results <- read.csv(results_path, stringsAsFactors = FALSE)
  if (!("C_w" %in% names(results))) {
    stop("Results file has no C_w column: ", results_path)
  }

  pathogen_units <- NULL
  if (identical(cfg$substance_type, "pathogen")) {
    if ("concentration_units" %in% names(results)) {
      pathogen_units <- first_non_empty(results$concentration_units)
    }
    if (is.null(pathogen_units)) pathogen_units <- cfg$pathogen_units %||% NULL
  }

  variants <- if (length(args$variant) > 0) {
    args$variant
  } else {
    cfg$visualization_variants %||% c("linear", "log10")
  }
  variants <- normalize_visualization_variants(variants, cfg$substance_type)

  list(
    scenario_name = scenario_name,
    cfg = cfg,
    results = results,
    pathogen_units = pathogen_units,
    variants = variants
  )
}

build_shared_binned_scales <- function(contexts) {
  scales <- list()
  needs_binned <- vapply(contexts, function(context) {
    identical(context$cfg$substance_type, "pathogen") &&
      "linear_binned" %in% context$variants
  }, logical(1))
  if (!any(needs_binned)) {
    return(scales)
  }

  pathogen_keys <- vapply(contexts, function(context) {
    tolower(context$cfg$pathogen_name %||% context$cfg$target_substance %||% "")
  }, character(1))

  for (pathogen_key in unique(pathogen_keys[needs_binned])) {
    group_idx <- which(needs_binned & pathogen_keys == pathogen_key)
    combined_values <- unlist(lapply(contexts[group_idx], function(context) context$results$C_w), use.names = FALSE)
    scale <- build_concentration_binned_scale(combined_values)
    for (idx in group_idx) {
      scales[[contexts[[idx]]$scenario_name]] <- scale
    }
    message(
      "Binned scale for ", pathogen_key, ": ",
      length(scale$labels), " classes from combined saved results."
    )
  }

  scales
}

refresh_one_context <- function(context, args, binned_scale = NULL) {
  message("Refreshing maps for scenario: ", context$scenario_name)

  cfg <- context$cfg

  VisualizeConcentrations(
    simulation_results = context$results,
    run_output_dir = cfg$run_output_dir,
    input_paths = cfg$input_paths %||% list(),
    target_substance = cfg$target_substance,
    basin_id = cfg$basin_id,
    substance_type = cfg$substance_type,
    pathogen_name = cfg$pathogen_name %||% NULL,
    pathogen_units = context$pathogen_units,
    visualization_variants = context$variants,
    binned_breaks = binned_scale$breaks %||% NULL,
    binned_labels = binned_scale$labels %||% NULL,
    provenance_label_mode = cfg$provenance_label_mode %||% "concise_visible",
    open_map_output_in_browser = isTRUE(args$open),
    show_interactive_map_preview = FALSE
  )

  message("Map refresh complete: ", file.path(cfg$run_output_dir, "plots"))
  invisible(TRUE)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(args$help)) {
  usage()
  quit(status = 0)
}

if (length(args$scenario) == 0) {
  usage()
  stop("At least one --scenario is required.", call. = FALSE)
}
if (!is.null(args$results) && length(args$scenario) > 1) {
  stop("--results can only be used with one --scenario.", call. = FALSE)
}

contexts <- lapply(args$scenario, load_refresh_context, args = args)
binned_scales <- build_shared_binned_scales(contexts)

for (context in contexts) {
  refresh_one_context(
    context,
    args,
    binned_scale = binned_scales[[context$scenario_name]]
  )
}

message("All requested maps refreshed.")
