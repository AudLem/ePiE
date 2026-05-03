#!/usr/bin/env Rscript
# Export aligned transparent GIS input layers for poster diagrams.
#
# The PNGs are designed for Inkscape: same extent, same pixel size,
# white page background by default, and no titles or legends.
#
# Example:
#   Rscript scripts/export_poster_input_layers.R \
#     --scenario VoltaWetNetwork \
#     --out Outputs/poster_input_layers/volta_akuse

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[1]) else "scripts/export_poster_input_layers.R"
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
pkg_dir <- file.path(repo_root, "Package")

if (requireNamespace("pkgload", quietly = TRUE) && dir.exists(pkg_dir)) {
  pkgload::load_all(pkg_dir, quiet = TRUE)
} else {
  library(ePiE)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

parse_args <- function(args) {
  out <- list(
    scenario = "VoltaWetNetwork",
    data_root = "Inputs",
    output_root = "Outputs",
    out = file.path("Outputs", "poster_input_layers", "volta_akuse"),
    width = 6000L,
    height = 4200L,
    background = "white",
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
      out$scenario <- read_value()
    } else if (arg == "--data-root" || grepl("^--data-root=", arg)) {
      out$data_root <- read_value()
    } else if (arg == "--output-root" || grepl("^--output-root=", arg)) {
      out$output_root <- read_value()
    } else if (arg == "--out" || grepl("^--out=", arg)) {
      out$out <- read_value()
    } else if (arg == "--width" || grepl("^--width=", arg)) {
      out$width <- as.integer(read_value())
    } else if (arg == "--height" || grepl("^--height=", arg)) {
      out$height <- as.integer(read_value())
    } else if (arg == "--background" || grepl("^--background=", arg)) {
      out$background <- read_value()
    } else {
      stop("Unknown argument: ", arg)
    }

    i <- i + 1L
  }

  if (is.na(out$width) || out$width <= 0) stop("--width must be a positive integer")
  if (is.na(out$height) || out$height <= 0) stop("--height must be a positive integer")
  if (!(out$background %in% c("white", "transparent"))) {
    stop("--background must be 'white' or 'transparent'")
  }
  out
}

usage <- function() {
  cat(
    "Usage: Rscript scripts/export_poster_input_layers.R [options]\n\n",
    "Exports aligned PNG input layers for Inkscape.\n",
    "The script builds network source-placement objects in memory only.\n",
    "It does not run simulations and does not regenerate model outputs.\n\n",
    "Options:\n",
    "  --scenario NAME       Network scenario. Default: VoltaWetNetwork\n",
    "  --data-root PATH      Input data root. Default: Inputs\n",
    "  --output-root PATH    Output root used by scenario config. Default: Outputs\n",
    "  --out PATH            Output folder for PNGs. Default: Outputs/poster_input_layers/volta_akuse\n",
    "  --width PX            PNG width. Default: 6000\n",
    "  --height PX           PNG height. Default: 4200\n",
    "  --background VALUE    Layer background: white or transparent. Default: white\n",
    "  --help                Show this help.\n",
    sep = ""
  )
}

get_fun <- function(name) {
  if (exists(name, mode = "function")) {
    get(name, mode = "function")
  } else {
    getFromNamespace(name, "ePiE")
  }
}

require_namespace <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Package required for poster layer export is not installed: ", pkg, call. = FALSE)
  }
}

has_rows <- function(x) {
  !is.null(x) && inherits(x, "sf") && nrow(x) > 0
}

transform_sf <- function(x, crs) {
  if (!has_rows(x)) return(NULL)
  sf::st_transform(sf::st_zm(x), crs)
}

expand_bbox <- function(bbox, width, height, pad_fraction = 0.04) {
  xmin <- as.numeric(bbox["xmin"])
  xmax <- as.numeric(bbox["xmax"])
  ymin <- as.numeric(bbox["ymin"])
  ymax <- as.numeric(bbox["ymax"])

  x_mid <- mean(c(xmin, xmax))
  y_mid <- mean(c(ymin, ymax))
  x_range <- (xmax - xmin) * (1 + pad_fraction)
  y_range <- (ymax - ymin) * (1 + pad_fraction)
  target_aspect <- width / height
  current_aspect <- x_range / y_range

  if (current_aspect < target_aspect) {
    x_range <- y_range * target_aspect
  } else {
    y_range <- x_range / target_aspect
  }

  c(
    xmin = x_mid - x_range / 2,
    xmax = x_mid + x_range / 2,
    ymin = y_mid - y_range / 2,
    ymax = y_mid + y_range / 2
  )
}

open_layer_png <- function(path, bbox, width, height, background = "transparent") {
  grDevices::png(
    filename = path,
    width = width,
    height = height,
    units = "px",
    bg = background,
    type = "cairo-png"
  )
  graphics::par(mar = c(0, 0, 0, 0), xaxs = "i", yaxs = "i")
  graphics::plot.new()
  graphics::plot.window(
    xlim = c(bbox["xmin"], bbox["xmax"]),
    ylim = c(bbox["ymin"], bbox["ymax"]),
    asp = 1
  )
  invisible(TRUE)
}

write_layer <- function(path, bbox, width, height, draw, background = "transparent") {
  open_layer_png(path, bbox, width, height, background)
  on.exit(grDevices::dev.off(), add = TRUE)
  draw()
  invisible(path)
}

plot_sf_geometry <- function(x, fill = NA, border = NA, lwd = 1, ...) {
  if (!has_rows(x)) return(invisible(FALSE))
  graphics::plot(sf::st_geometry(x), add = TRUE, col = fill, border = border, lwd = lwd, ...)
  invisible(TRUE)
}

plot_sf_lines <- function(x, col = "#2d94bd", lwd = 5) {
  if (!has_rows(x)) return(invisible(FALSE))
  graphics::plot(sf::st_geometry(x), add = TRUE, col = col, lwd = lwd)
  invisible(TRUE)
}

plot_sf_points <- function(x, pch = 21, fill = "#E31A1C", border = "white", cex = 1.7, lwd = 1.5) {
  if (!has_rows(x)) return(invisible(FALSE))
  graphics::plot(sf::st_geometry(x), add = TRUE, pch = pch, bg = fill, col = border, cex = cex, lwd = lwd)
  invisible(TRUE)
}

crop_terra_to_bbox <- function(r, bbox) {
  terra::crop(
    r,
    terra::ext(
      as.numeric(bbox["xmin"]),
      as.numeric(bbox["xmax"]),
      as.numeric(bbox["ymin"]),
      as.numeric(bbox["ymax"])
    )
  )
}

prepare_terra_layer <- function(r, target_crs_wkt, bbox, method = "bilinear") {
  if (is.null(r)) return(NULL)
  if (!identical(terra::crs(r), target_crs_wkt)) {
    r <- terra::project(r, target_crs_wkt, method = method)
  }
  crop_terra_to_bbox(r, bbox)
}

read_terra_raster <- function(path, layer = 1L) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  r <- terra::rast(path)
  r[[min(layer, terra::nlyr(r))]]
}

mask_raster_to_basin <- function(r, basin_target, target_crs_wkt, method = "bilinear") {
  if (is.null(r)) return(NULL)
  basin_source <- sf::st_transform(basin_target, terra::crs(r))
  crop_area <- sf::st_buffer(basin_source, dist = 1000)
  r <- terra::crop(r, terra::vect(crop_area))
  r <- terra::project(r, target_crs_wkt, method = method)
  terra::mask(r, terra::vect(basin_target))
}

plot_terra_raster <- function(r, palette, maxcell = 1000000L) {
  if (is.null(r)) return(invisible(FALSE))
  suppressWarnings(terra::plot(
    r,
    add = TRUE,
    axes = FALSE,
    legend = FALSE,
    col = palette,
    maxcell = maxcell
  ))
  invisible(TRUE)
}

resolve_discharge_raster_path <- function(cfg, data_root) {
  candidates <- c(
    cfg$flow_raster_path %||% character(0),
    cfg$input_paths$flow_raster %||% character(0),
    file.path(data_root, "baselines", "environmental", "FLO1K.30min.ts.1960.2015.qav.nc"),
    file.path(data_root, "baselines", "environmental", "FLO1k.lt.2000.2015.qav.tif")
  )

  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  candidates <- normalizePath(candidates, winslash = "/", mustWork = FALSE)
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0) NULL else existing[[1]]
}

build_layer_state <- function(cfg) {
  message("Building network layer objects in memory through Step 8...")
  get_fun("BuildNetworkPipeline")(
    cfg,
    stop_after_step = "08_integrate_points",
    diagnostics = NULL,
    interactive_diagnostics = FALSE
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(args$help)) {
  usage()
  quit(status = 0)
}

for (pkg in c("sf", "terra", "grDevices", "graphics")) {
  require_namespace(pkg)
}

cfg <- get_fun("LoadScenarioConfig")(args$scenario, args$data_root, args$output_root)
if (!is.null(cfg$substance_type) && cfg$substance_type %in% c("chemical", "pathogen")) {
  stop("Use a network scenario, not a simulation scenario: ", args$scenario, call. = FALSE)
}

out_dir <- normalizePath(args$out, winslash = "/", mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

state <- build_layer_state(cfg)
target_crs <- get_fun("GetUtmCrs")(state$Basin)
target_crs_wkt <- sf::st_crs(target_crs)$wkt

basin <- transform_sf(state$Basin, target_crs)
lakes <- transform_sf(state$HL_basin, target_crs)
selected_areas <- transform_sf(state$selected_agglomeration_areas, target_crs)

rivers_all <- state$hydro_sheds_rivers_basin
rivers <- rivers_all
if (has_rows(rivers) && "is_canal" %in% names(rivers)) {
  rivers <- rivers[is.na(rivers$is_canal) | !rivers$is_canal, , drop = FALSE]
}
rivers <- transform_sf(rivers, target_crs)

canals <- state$artificial_canals %||% NULL
if (!has_rows(canals) && has_rows(rivers_all) && "is_canal" %in% names(rivers_all)) {
  canals <- rivers_all[!is.na(rivers_all$is_canal) & rivers_all$is_canal, , drop = FALSE]
}
canals <- transform_sf(canals, target_crs)

source_points <- state$points
if (has_rows(source_points) && "pt_type" %in% names(source_points)) {
  source_points <- source_points[source_points$pt_type %in% c("agglomeration", "agglomeration_lake", "WWTP"), , drop = FALSE]
}
source_points <- transform_sf(source_points, target_crs)

map_bbox <- expand_bbox(sf::st_bbox(basin), args$width, args$height)

flow_dir <- tryCatch({
  prepare_terra_layer(terra::rast(state$dir), target_crs_wkt, map_bbox, method = "near")
}, error = function(e) {
  message("Skipping flow-direction raster: ", e$message)
  NULL
})

discharge_path <- resolve_discharge_raster_path(cfg, args$data_root)
discharge <- tryCatch({
  r <- read_terra_raster(discharge_path)
  r <- mask_raster_to_basin(r, basin, target_crs_wkt, method = "bilinear")
  crop_terra_to_bbox(r, map_bbox)
}, error = function(e) {
  message("Skipping discharge raster: ", e$message)
  NULL
})

population <- tryCatch({
  r <- read_terra_raster(cfg$pop_raster_path)
  r <- mask_raster_to_basin(r, basin, target_crs_wkt, method = "bilinear")
  crop_terra_to_bbox(r, map_bbox)
}, error = function(e) {
  message("Skipping population raster: ", e$message)
  NULL
})

grey_low <- grDevices::adjustcolor(grDevices::grey.colors(80, start = 0.95, end = 0.15), alpha.f = 0.30)
blue_low <- grDevices::adjustcolor(colorRampPalette(c("#EFF3FF", "#6BAED6", "#08519C"))(80), alpha.f = 0.34)
pop_grey <- grDevices::adjustcolor(grDevices::grey.colors(80, start = 0.96, end = 0.05), alpha.f = 0.34)

layer_paths <- c(
  canvas = file.path(out_dir, "00_canvas_white.png"),
  basin = file.path(out_dir, "01_basin_boundary.png"),
  flow_direction = file.path(out_dir, "02_flow_direction_grid.png"),
  discharge = file.path(out_dir, "03_discharge_raster.png"),
  rivers = file.path(out_dir, "04_rivers_wet.png"),
  canals = file.path(out_dir, "05_canals.png"),
  lakes = file.path(out_dir, "06_lakes.png"),
  population = file.path(out_dir, "07_population_raster.png"),
  selected_population = file.path(out_dir, "08_selected_agglomeration_pixels.png"),
  sources = file.path(out_dir, "09_emission_source_points.png"),
  preview = file.path(out_dir, "10_combined_stack_preview.png")
)

write_layer(layer_paths[["canvas"]], map_bbox, args$width, args$height, function() {
  graphics::rect(map_bbox["xmin"], map_bbox["ymin"], map_bbox["xmax"], map_bbox["ymax"], col = "white", border = NA)
}, background = "white")

write_layer(layer_paths[["basin"]], map_bbox, args$width, args$height, function() {
  plot_sf_geometry(basin, fill = NA, border = "#4D4D4D", lwd = 5)
}, background = args$background)

write_layer(layer_paths[["flow_direction"]], map_bbox, args$width, args$height, function() {
  plot_terra_raster(flow_dir, grey_low)
}, background = args$background)

write_layer(layer_paths[["discharge"]], map_bbox, args$width, args$height, function() {
  plot_terra_raster(discharge, blue_low)
}, background = args$background)

write_layer(layer_paths[["rivers"]], map_bbox, args$width, args$height, function() {
  plot_sf_lines(rivers, col = "#2d94bd", lwd = 5)
}, background = args$background)

write_layer(layer_paths[["canals"]], map_bbox, args$width, args$height, function() {
  plot_sf_lines(canals, col = "#e5c408", lwd = 7)
}, background = args$background)

write_layer(layer_paths[["lakes"]], map_bbox, args$width, args$height, function() {
  plot_sf_geometry(lakes, fill = grDevices::adjustcolor("#CFE8F3", alpha.f = 0.70), border = "#2C7FB8", lwd = 3)
}, background = args$background)

write_layer(layer_paths[["population"]], map_bbox, args$width, args$height, function() {
  plot_terra_raster(population, pop_grey)
}, background = args$background)

write_layer(layer_paths[["selected_population"]], map_bbox, args$width, args$height, function() {
  plot_sf_geometry(selected_areas, fill = grDevices::adjustcolor("#E31A1C", alpha.f = 0.70), border = NA, lwd = 1)
}, background = args$background)

write_layer(layer_paths[["sources"]], map_bbox, args$width, args$height, function() {
  plot_sf_points(source_points, fill = "#E31A1C", border = "white", cex = 2.2, lwd = 1.8)
}, background = args$background)

write_layer(layer_paths[["preview"]], map_bbox, args$width, args$height, function() {
  graphics::rect(map_bbox["xmin"], map_bbox["ymin"], map_bbox["xmax"], map_bbox["ymax"], col = "white", border = NA)
  plot_terra_raster(flow_dir, grDevices::adjustcolor(grDevices::grey.colors(80, start = 0.98, end = 0.35), alpha.f = 0.20))
  plot_terra_raster(discharge, grDevices::adjustcolor(colorRampPalette(c("#EFF3FF", "#9ECAE1", "#3182BD"))(80), alpha.f = 0.25))
  plot_terra_raster(population, grDevices::adjustcolor(grDevices::grey.colors(80, start = 0.96, end = 0.15), alpha.f = 0.28))
  plot_sf_geometry(selected_areas, fill = grDevices::adjustcolor("#E31A1C", alpha.f = 0.55), border = NA, lwd = 1)
  plot_sf_geometry(lakes, fill = grDevices::adjustcolor("#CFE8F3", alpha.f = 0.70), border = "#2C7FB8", lwd = 3)
  plot_sf_lines(rivers, col = "#2d94bd", lwd = 5)
  plot_sf_lines(canals, col = "#e5c408", lwd = 7)
  plot_sf_points(source_points, fill = "#E31A1C", border = "white", cex = 2.2, lwd = 1.8)
  plot_sf_geometry(basin, fill = NA, border = "#4D4D4D", lwd = 5)
}, background = "white")

cat(
  "Poster input layers written to:\n  ", out_dir, "\n\n",
  paste0("  - ", basename(layer_paths), collapse = "\n"),
  "\n",
  sep = ""
)
