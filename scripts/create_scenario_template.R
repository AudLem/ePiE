#!/usr/bin/env Rscript
# Print or write a scenario constructor template.
#
# Examples:
#   Rscript scripts/create_scenario_template.R --name MyScenario --copy-from VoltaWetPathogenCrypto
#   Rscript scripts/create_scenario_template.R --name MyBegaCrypto --basin bega --type pathogen --target cryptosporidium
#   Rscript scripts/create_scenario_template.R --name MyScenario --copy-from VoltaWetPathogenCrypto --output-file /tmp/my_scenario.R

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else "scripts/create_scenario_template.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
pkg_dir <- file.path(repo_root, "Package")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(pkg_dir)) {
  pkgload::load_all(pkg_dir, quiet = TRUE)
} else {
  library(ePiE)
}

parse_args <- function(args) {
  out <- list(
    name = NULL,
    basin = NULL,
    type = NULL,
    target = NULL,
    copy_from = NULL,
    output_file = NULL,
    overwrite = FALSE,
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
    } else if (arg == "--name" || grepl("^--name=", arg)) {
      out$name <- read_value()
    } else if (arg %in% c("--basin", "--basin-id") || grepl("^--basin(\\-id)?=", arg)) {
      out$basin <- read_value()
    } else if (arg %in% c("--type", "--substance-type") || grepl("^--(type|substance-type)=", arg)) {
      out$type <- read_value()
    } else if (arg %in% c("--target", "--target-substance") || grepl("^--(target|target-substance)=", arg)) {
      out$target <- read_value()
    } else if (arg == "--copy-from" || grepl("^--copy-from=", arg)) {
      out$copy_from <- read_value()
    } else if (arg == "--output-file" || grepl("^--output-file=", arg)) {
      out$output_file <- read_value()
    } else if (arg == "--overwrite") {
      out$overwrite <- TRUE
    } else {
      stop("Unknown argument: ", arg)
    }
    i <- i + 1L
  }
  out
}

usage <- function() {
  cat(
    "Usage: Rscript scripts/create_scenario_template.R --name NAME [options]\n\n",
    "Options:\n",
    "  --name NAME              New scenario function name. Required.\n",
    "  --copy-from NAME         Existing scenario used as structural base.\n",
    "  --basin bega|volta|volta_geoglows  Required unless --copy-from is used.\n",
    "  --type chemical|pathogen|network    Required unless --copy-from is used.\n",
    "  --target NAME            Chemical or pathogen name.\n",
    "  --output-file PATH       Write template to this file. Default: print only.\n",
    "  --overwrite              Allow replacing an existing output file.\n",
    "  --help                   Show this help.\n",
    sep = ""
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(args$help)) {
  usage()
  quit(status = 0)
}
if (is.null(args$name)) {
  usage()
  stop("--name is required.", call. = FALSE)
}

CreateScenarioTemplate(
  name = args$name,
  basin_id = args$basin,
  substance_type = args$type,
  target_substance = args$target,
  copy_from = args$copy_from,
  output_file = args$output_file,
  overwrite = args$overwrite
)
