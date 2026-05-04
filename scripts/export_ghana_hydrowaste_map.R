#!/usr/bin/env Rscript
# Export a Ghana overview map of HydroWASTE WWTP locations.
#
# This is a poster helper. It does not change model inputs or outputs.
#
# Example:
#   Rscript scripts/export_ghana_hydrowaste_map.R \
#     --hydrowaste ../ePiE_old/HydroWASTE_v10/HydroWASTE_v10.csv \
#     --out Outputs/poster_input_layers/ghana_hydrowaste

parse_args <- function(args) {
  out <- list(
    hydrowaste = NULL,
    out = file.path("Outputs", "poster_input_layers", "ghana_hydrowaste"),
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
    } else if (arg == "--hydrowaste" || grepl("^--hydrowaste=", arg)) {
      out$hydrowaste <- read_value()
    } else if (arg == "--out" || grepl("^--out=", arg)) {
      out$out <- read_value()
    } else {
      stop("Unknown argument: ", arg)
    }

    i <- i + 1L
  }

  out
}

usage <- function() {
  cat(
    "Usage: Rscript scripts/export_ghana_hydrowaste_map.R [options]\n\n",
    "Exports a Ghana overview map of HydroWASTE WWTP points.\n",
    "The map is for poster explanation only. It does not change model inputs.\n\n",
    "Options:\n",
    "  --hydrowaste PATH     HydroWASTE_v10.csv path. If omitted, common local paths are searched.\n",
    "  --out PATH            Output folder. Default: Outputs/poster_input_layers/ghana_hydrowaste\n",
    "  --help                Show this help.\n",
    sep = ""
  )
}

require_namespace <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Required package is not installed: ", pkg, call. = FALSE)
  }
}

find_hydrowaste <- function(path = NULL) {
  candidates <- c(
    path,
    file.path("Inputs", "basins", "volta", "HydroWASTE_v10", "HydroWASTE_v10.csv"),
    file.path("Inputs", "HydroWASTE_v10", "HydroWASTE_v10.csv"),
    file.path("..", "ePiE_old", "HydroWASTE_v10", "HydroWASTE_v10.csv")
  )
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  candidates <- normalizePath(candidates, winslash = "/", mustWork = FALSE)
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0) {
    stop("HydroWASTE_v10.csv not found. Use --hydrowaste PATH.", call. = FALSE)
  }
  existing[[1]]
}

build_extent <- function() {
  coords <- rbind(
    c(-2.45, 4.45),
    c(0.85, 4.45),
    c(0.85, 7.15),
    c(-2.45, 7.15),
    c(-2.45, 4.45)
  )
  sf::st_as_sf(
    data.frame(name = "southern_ghana_extent"),
    geometry = sf::st_sfc(sf::st_polygon(list(coords)), crs = 4326)
  )
}

write_static_map <- function(points, map_extent, out_dir) {
  tmap::tmap_mode("plot")

  map_plot <- tmap::tm_basemap("CartoDB.Positron") +
    tmap::tm_shape(map_extent) +
    tmap::tm_polygons(fill = "white", fill_alpha = 0, col = "white", col_alpha = 0) +
    tmap::tm_shape(points) +
    tmap::tm_dots(
      fill = "#E31A1C",
      col = "white",
      lwd = 1.5,
      size = 0.75,
      fill_alpha = 0.9,
      fill.legend = tmap::tm_legend(title = "HydroWASTE WWTP")
    ) +
    tmap::tm_layout(
      bg.color = "white",
      frame = FALSE,
      legend.outside = TRUE,
      legend.outside.position = "right",
      legend.bg.color = "white",
      legend.bg.alpha = 0.95
    ) +
    tmap::tm_scalebar(
      breaks = c(0, 50, 100),
      text.size = 1.5,
      lwd = 2,
      position = c("left", "bottom")
    ) +
    tmap::tm_compass(
      type = "arrow",
      size = 2.5,
      text.size = 1.3,
      lwd = 1.6,
      position = c("right", "bottom")
    ) +
    tmap::tm_title("HydroWASTE WWTPs in Ghana", size = 1.5)

  png_path <- file.path(out_dir, "ghana_hydrowaste_wwtp_map.png")
  pdf_path <- file.path(out_dir, "ghana_hydrowaste_wwtp_map.pdf")
  tmap::tmap_save(map_plot, png_path, width = 6000, height = 4200, dpi = 300)
  tmap::tmap_save(map_plot, pdf_path, width = 12, height = 8.4, units = "in")
  c(png = png_path, pdf = pdf_path)
}

write_interactive_map <- function(points, map_extent, out_dir) {
  if (!requireNamespace("leaflet", quietly = TRUE) || !requireNamespace("htmlwidgets", quietly = TRUE)) {
    return(NULL)
  }

  bbox <- sf::st_bbox(map_extent)
  popup <- paste0(
    "<b>HydroWASTE ID:</b> ", points$WASTE_ID,
    "<br><b>Population served:</b> ", format(points$POP_SERVED, big.mark = ","),
    "<br><b>Treatment level:</b> ", points$LEVEL,
    "<br><b>Status:</b> ", points$STATUS
  )

  map <- leaflet::leaflet(points) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "Light") |>
    leaflet::addCircleMarkers(
      radius = 7,
      color = "white",
      weight = 1.5,
      fillColor = "#E31A1C",
      fillOpacity = 0.9,
      popup = popup
    ) |>
    leaflet::fitBounds(
      lng1 = bbox[["xmin"]],
      lat1 = bbox[["ymin"]],
      lng2 = bbox[["xmax"]],
      lat2 = bbox[["ymax"]]
  )

  html_path <- file.path(out_dir, "ghana_hydrowaste_wwtp_map.html")
  htmlwidgets::saveWidget(map, html_path, selfcontained = FALSE)
  html_path
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(args$help)) {
  usage()
  quit(status = 0)
}

for (pkg in c("sf", "tmap", "utils")) {
  require_namespace(pkg)
}

hydrowaste_path <- find_hydrowaste(args$hydrowaste)
out_dir <- normalizePath(args$out, winslash = "/", mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

hydrowaste <- utils::read.csv(hydrowaste_path, stringsAsFactors = FALSE)
required_cols <- c("CNTRY_ISO", "LAT_WWTP", "LON_WWTP", "WASTE_ID", "POP_SERVED", "LEVEL", "STATUS")
missing_cols <- setdiff(required_cols, names(hydrowaste))
if (length(missing_cols) > 0) {
  stop("HydroWASTE file is missing required columns: ", paste(missing_cols, collapse = ", "))
}

ghana <- hydrowaste[
  hydrowaste$CNTRY_ISO == "GHA" &
    is.finite(hydrowaste$LAT_WWTP) &
    is.finite(hydrowaste$LON_WWTP),
  ,
  drop = FALSE
]
if (nrow(ghana) == 0) {
  stop("No Ghana WWTP rows found in HydroWASTE file: ", hydrowaste_path, call. = FALSE)
}

points <- sf::st_as_sf(ghana, coords = c("LON_WWTP", "LAT_WWTP"), crs = 4326, remove = FALSE)
map_extent <- build_extent()

csv_path <- file.path(out_dir, "ghana_hydrowaste_wwtp_points.csv")
utils::write.csv(ghana, csv_path, row.names = FALSE)

static_paths <- write_static_map(points, map_extent, out_dir)
html_path <- write_interactive_map(points, map_extent, out_dir)

cat(
  "Ghana HydroWASTE WWTP map written to:\n  ", out_dir, "\n\n",
  "Input file:\n  ", hydrowaste_path, "\n\n",
  "Ghana WWTP points: ", nrow(ghana), "\n\n",
  "Outputs:\n",
  "  - ", basename(static_paths[["png"]]), "\n",
  "  - ", basename(static_paths[["pdf"]]), "\n",
  "  - ", basename(csv_path), "\n",
  if (!is.null(html_path)) paste0("  - ", basename(html_path), "\n") else "",
  sep = ""
)
