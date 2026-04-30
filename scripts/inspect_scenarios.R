#!/usr/bin/env Rscript
# Print or export scenario setup metadata.
#
# Examples:
#   Rscript scripts/inspect_scenarios.R
#   Rscript scripts/inspect_scenarios.R --scenario BegaPathogenCrypto
#   Rscript scripts/inspect_scenarios.R --csv Outputs/scenario_setup_audit.csv
#   Rscript scripts/inspect_scenarios.R --format long --csv Outputs/scenario_setup_audit_long.csv

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else "scripts/inspect_scenarios.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
pkg_dir <- file.path(repo_root, "Package")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(pkg_dir)) {
  pkgload::load_all(pkg_dir, quiet = TRUE)
} else {
  library(ePiE)
}

parse_args <- function(args) {
  out <- list(
    scenario = character(0),
    data_root = "Inputs",
    output_root = "Outputs",
    csv = NULL,
    format = "wide"
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
    } else if (arg == "--csv" || grepl("^--csv=", arg)) {
      out$csv <- read_value()
    } else if (arg == "--format" || grepl("^--format=", arg)) {
      out$format <- read_value()
    } else {
      stop("Unknown argument: ", arg)
    }
    i <- i + 1L
  }
  out
}

usage <- function() {
  cat(
    "Usage: Rscript scripts/inspect_scenarios.R [options]\n\n",
    "Options:\n",
    "  --scenario NAME       Scenario to inspect. Repeat for multiple scenarios.\n",
    "  --data-root PATH      Input data root. Default: Inputs\n",
    "  --output-root PATH    Output root. Default: Outputs\n",
    "  --format wide|long    Table shape. Default: wide\n",
    "  --csv PATH            Export table to CSV instead of only printing.\n",
    "  --help                Show this help.\n",
    sep = ""
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(args$help)) {
  usage()
  quit(status = 0)
}

InspectScenarioSetup(
  scenario = if (length(args$scenario) == 0) NULL else args$scenario,
  data_root = args$data_root,
  output_root = args$output_root,
  export_csv = args$csv,
  format = args$format
)
