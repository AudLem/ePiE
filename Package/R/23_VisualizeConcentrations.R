VisualizeConcentrations <- function(simulation_results,
                                      run_output_dir,
                                      input_paths = list(),
                                      target_substance = NULL,
                                      basin_id = NULL,
                                      substance_type = "chemical",
                                      pathogen_name = NULL,
                                      open_map_output_in_browser = TRUE,
                                      show_interactive_map_preview = FALSE) {
  message("--- Step 6: Generating Simulation Visualizations ---")

  plots_dir <- file.path(run_output_dir, "plots")
  if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

  rivers <- NULL
  if ("rivers" %in% names(input_paths) && file.exists(input_paths$rivers)) {
    rivers <- tryCatch(sf::st_read(input_paths$rivers, quiet = TRUE), error = function(e) NULL)
  }

  lakes <- NULL
  lakes_path <- if ("lakes" %in% names(input_paths)) input_paths$lakes else NULL
  if (is.null(lakes_path) && !is.null(input_paths$rivers)) {
    potential_path <- file.path(dirname(input_paths$rivers), "network_lakes.shp")
    if (file.exists(potential_path)) lakes_path <- potential_path
  }
  if (!is.null(lakes_path) && file.exists(lakes_path)) {
    lakes <- tryCatch(sf::st_read(lakes_path, quiet = TRUE), error = function(e) NULL)
  }

  basin_shp <- NULL
  basin_path <- if ("basin" %in% names(input_paths)) input_paths$basin else NULL
  if (!is.null(basin_path) && file.exists(basin_path)) {
    basin_shp <- tryCatch(sf::st_read(basin_path, quiet = TRUE), error = function(e) NULL)
  }

  nodes_df <- if (is.data.frame(simulation_results)) {
    simulation_results
  } else if ("pts_env" %in% names(simulation_results)) {
    simulation_results$pts_env
  } else if ("simulation_results" %in% names(simulation_results)) {
    simulation_results$simulation_results
  } else {
    warning("Valid simulation nodes data frame not found. Skipping visualization.")
    return(invisible(NULL))
  }

  nodes_df$x <- as.numeric(nodes_df$x)
  nodes_df$y <- as.numeric(nodes_df$y)
  concentration_nodes_sf <- sf::st_as_sf(nodes_df, coords = c("x", "y"), crs = 4326, remove = FALSE)

  source_point_indices <- which(tolower(concentration_nodes_sf$Pt_type) %in% c("agglomeration", "agglomerations", "wwtp"))
  emission_nodes_sf <- concentration_nodes_sf[source_point_indices, ]

  create_popup_html <- function(map_data) {
    getv <- function(name) {
      if (name %in% names(map_data)) map_data[[name]] else rep(NA, nrow(map_data))
    }
    basin_vals <- if ("basin_id" %in% names(map_data)) getv("basin_id") else getv("basin_ID")
    units <- if (substance_type == "pathogen") "oocysts/L" else "\u00b5g/L"
    ids <- ifelse(is.na(getv("ID")), "", as.character(getv("ID")))
    types <- ifelse(is.na(getv("Pt_type")), "", as.character(getv("Pt_type")))
    basins <- ifelse(is.na(basin_vals), "", as.character(basin_vals))
    next_ids <- ifelse(is.na(getv("ID_nxt")), "", as.character(getv("ID_nxt")))
    qs <- ifelse(is.na(getv("Q")), 0, as.numeric(getv("Q")))
    cw <- ifelse(is.na(getv("C_w")), 0, as.numeric(getv("C_w")))
    removals <- ifelse(is.na(getv("WWTPremoval")), 0, as.numeric(getv("WWTPremoval")))
    pops <- ifelse(is.na(getv("total_population")), 0, as.numeric(getv("total_population")))
    sprintf(
      paste0(
        "<b>ID:</b> %s<br/>",
        "<b>Type:</b> %s<br/>",
        "<b>Basin:</b> %s<br/>",
        "<b>ID_nxt:</b> %s<br/>",
        "<b>Q:</b> %7.3f m3/s<br/>",
        "<b>C_w:</b> %7.3e %s<br/>",
        "<b>WWTP removal:</b> %7.4f<br/>",
        "<b>Total population:</b> %.0f"
      ),
      ids, types, basins, next_ids, qs, cw, units, removals, pops
    )
  }
  concentration_nodes_sf$popup_html <- create_popup_html(concentration_nodes_sf)
  if (nrow(emission_nodes_sf) > 0) emission_nodes_sf$popup_html <- create_popup_html(emission_nodes_sf)

  color_palette <- leaflet::colorNumeric(
    palette = c("#4B0055", "#105188", "#009297", "#00C278", "#CDE030", "#FDE333"),
    domain = concentration_nodes_sf$C_w,
    na.color = "transparent"
  )

  interactive_map <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "CartoDB.Positron") |>
    leaflet::addProviderTiles(leaflet::providers$OpenStreetMap, group = "OpenStreetMap")

  if (!is.null(basin_shp) && nrow(basin_shp) > 0) {
    interactive_map <- interactive_map |>
      leaflet::addPolygons(data = basin_shp, color = "black", weight = 1, fillColor = "grey", fillOpacity = 0.1, group = "basin")
  }

  if (!is.null(rivers) && nrow(rivers) > 0) {
    interactive_map <- interactive_map |>
      leaflet::addPolylines(data = rivers, color = "blue", weight = 1, opacity = 0.5, group = "rivers")
  }

  if (!is.null(lakes) && nrow(lakes) > 0) {
    interactive_map <- interactive_map |>
      leaflet::addPolygons(data = lakes, color = "blue", weight = 1, fillOpacity = 0.3, group = "lakes")
  }

  if (nrow(emission_nodes_sf) > 0) {
    interactive_map <- interactive_map |>
      leaflet::addCircleMarkers(
        data = emission_nodes_sf, lng = ~x, lat = ~y,
        radius = 4, stroke = FALSE, fillOpacity = 0.9,
        color = "red", group = "sources", popup = ~popup_html
      )
  }

  interactive_map <- interactive_map |>
    leaflet::addCircleMarkers(
      data = concentration_nodes_sf, lng = ~x, lat = ~y,
      radius = 3, stroke = FALSE, fillOpacity = 0.7,
      color = ~color_palette(C_w), group = "results", popup = ~popup_html
    ) |>
    leaflet::addLayersControl(
      baseGroups = c("CartoDB.Positron", "OpenStreetMap"),
      overlayGroups = c("basin", "rivers", "lakes", "sources", "results"),
      options = leaflet::layersControlOptions(collapsed = TRUE)
    )

  display_substance <- if (substance_type == "pathogen" && !is.null(pathogen_name)) pathogen_name else target_substance
  units <- if (substance_type == "pathogen") "oocysts/L" else "\u00b5g/L"
  basin_label <- if (!is.null(basin_id)) basin_id else "Unknown"

  map_title <- paste0("<b>Substance:</b> ", display_substance, " (", units, ") <br/>", "<b>Basin:</b> ", basin_label)
  tag_title <- htmltools::tags$div(
    htmltools::HTML(map_title),
    style = "background: white; padding: 10px; border-radius: 5px; box-shadow: 0 0 15px rgba(0,0,0,0.2);"
  )
  interactive_map <- interactive_map |>
    leaflet::addControl(html = tag_title, position = "bottomleft") |>
    leaflet::addLegend("topright", pal = color_palette, values = concentration_nodes_sf$C_w,
                       title = paste0(display_substance, " (", units, ")"), opacity = 1)

  map_html <- file.path(plots_dir, "concentration_map.html")
  message("Saving interactive map HTML: ", map_html)
  map_libdir <- paste0(tools::file_path_sans_ext(basename(map_html)), "_files")
  unlink(file.path(plots_dir, map_libdir), recursive = TRUE, force = TRUE)
  htmlwidgets::saveWidget(interactive_map, file = map_html, selfcontained = FALSE, libdir = map_libdir)

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive concentration map saved to:\n")
  cat(">>> ", normalizePath(map_html), "\n")
  invisible(interactive_map)
}
