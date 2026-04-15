VisualizeConcentrations <- function(simulation_results,
                                      run_output_dir,
                                      input_paths = list(),
                                      target_substance = NULL,
                                      basin_id = NULL,
                                      substance_type = "chemical",
                                      pathogen_name = NULL,
                                      pathogen_units = NULL,
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
    units <- if (substance_type == "pathogen") {
      if (!is.null(pathogen_units)) pathogen_units else "oocysts/L"
    } else "\u00b5g/L"
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

  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE, attributionControl = FALSE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "Light",
      options = leaflet::tileOptions(attribution = "&copy; CARTO &copy; OpenStreetMap contributors")) |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldStreetMap, group = "Streets & Buildings",
      options = leaflet::tileOptions(attribution = "&copy; Esri, HERE, Garmin, OpenStreetMap")) |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite",
      options = leaflet::tileOptions(attribution = "&copy; Esri, Maxar, Earthstar Geographics")) |>
    leaflet::addProviderTiles(leaflet::providers$OpenTopoMap, group = "Topographic",
      options = leaflet::tileOptions(attribution = "&copy; OpenTopoMap (CC-BY-SA)")) |>
    leaflet::addControl(html = htmltools::tags$div(
      htmltools::HTML("<small>&copy; Esri (WorldImagery/WorldStreetMap) | CARTO | OpenStreetMap | OpenTopoMap</small>"),
      style = "background: rgba(255,255,255,0.7); padding: 2px 6px; font-size: 10px;"
    ), position = "bottomright")

  if (!is.null(basin_shp) && nrow(basin_shp) > 0) {
    m <- m |> leaflet::addPolygons(data = basin_shp, color = "black", weight = 1.5, fillColor = "grey", fillOpacity = 0.1, group = "Basin")
  }

  if (!is.null(rivers) && nrow(rivers) > 0) {
    m <- m |> leaflet::addPolylines(data = rivers, color = "#2171b5", weight = 1.5, opacity = 0.7, group = "Rivers")
  }

  if (!is.null(lakes) && nrow(lakes) > 0) {
    m <- m |> leaflet::addPolygons(data = lakes, color = "#2171b5", weight = 1, fillColor = "#6baed6", fillOpacity = 0.4, group = "Lakes")
  }

  if (nrow(emission_nodes_sf) > 0) {
    m <- m |> leaflet::addCircleMarkers(
      data = emission_nodes_sf, lng = ~x, lat = ~y,
      radius = 4, weight = 1, fillOpacity = 0.9,
      color = "#e31a1c", fillColor = "#e31a1c",
      popup = ~popup_html, group = "Sources"
    )
  }

  m <- m |> leaflet::addCircleMarkers(
    data = concentration_nodes_sf, lng = ~x, lat = ~y,
    radius = 3, weight = 1, fillOpacity = 0.7,
    color = ~color_palette(C_w), fillColor = ~color_palette(C_w),
    popup = ~popup_html, group = "Concentrations"
  )

  display_substance <- if (substance_type == "pathogen" && !is.null(pathogen_name)) pathogen_name else target_substance
  units <- if (substance_type == "pathogen") {
    if (!is.null(pathogen_units)) pathogen_units else "oocysts/L"
  } else "\u00b5g/L"
  basin_label <- if (!is.null(basin_id)) basin_id else "Unknown"

  map_title <- paste0("<b>Substance:</b> ", display_substance, " (", units, ")<br>",
                       "<b>Basin:</b> ", basin_label, "<br>",
                       "<small>Generated: ", format(Sys.Date(), "%Y-%m-%d"), " | ",
                       "Basemap: check attribution in bottom-right corner</small>")
  tag_title <- htmltools::tags$div(
    htmltools::HTML(map_title),
    style = "background: white; padding: 8px 12px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.2); font-size: 14px;"
  )

  m <- m |>
    leaflet::addControl(html = tag_title, position = "bottomleft") |>
    leaflet::addLegend("topright", pal = color_palette, values = concentration_nodes_sf$C_w,
                       title = paste0(display_substance, " (", units, ")"), opacity = 1) |>
    leaflet::addLayersControl(
      baseGroups = c("Light", "Streets & Buildings", "Satellite", "Topographic"),
      overlayGroups = c("Basin", "Rivers", "Lakes", "Sources", "Concentrations"),
      options = leaflet::layersControlOptions(collapsed = TRUE)
    )

  map_html <- file.path(plots_dir, "concentration_map.html")
  message("Saving interactive map HTML: ", map_html)
  map_libdir <- paste0(tools::file_path_sans_ext(basename(map_html)), "_files")
  unlink(file.path(plots_dir, map_libdir), recursive = TRUE, force = TRUE)
  htmlwidgets::saveWidget(m, file = map_html, selfcontained = FALSE, libdir = map_libdir)

  if (requireNamespace("tmap", quietly = TRUE)) {
    tmap::tmap_mode("plot")
    m <- tmap::tm_layout(bg.color = "white", frame = FALSE,
                         legend.position = c("right", "bottom"),
                         legend.bg.color = "white", legend.bg.alpha = 0.9)
    
    if (!is.null(basin_shp) && nrow(basin_shp) > 0) {
      m <- m + tmap::tm_shape(basin_shp) + tmap::tm_polygons(fill = "lightgrey", col = "darkgrey", lwd = 1.5)
    }
    
    if (!is.null(rivers) && nrow(rivers) > 0) {
      m <- m + tmap::tm_shape(rivers) + tmap::tm_lines(col = "#2171b5", lwd = 1.5)
    }
    
    if (!is.null(lakes) && nrow(lakes) > 0) {
      m <- m + tmap::tm_shape(lakes) + tmap::tm_polygons(fill = "lightblue", col = "#2171b5", fill_alpha = 0.7)
    }
    
    m <- m + tmap::tm_shape(emission_nodes_sf) + tmap::tm_dots(col = "#e31a1c", size = 0.8)
    concentration_pts_plot <- concentration_nodes_sf[!is.na(concentration_nodes_sf$C_w), ]
    if (nrow(concentration_pts_plot) > 0) {
      m <- m + tmap::tm_shape(concentration_pts_plot) + tmap::tm_dots(fill = "C_w", palette = "viridis", size = 0.5)
    }
    m <- m + tmap::tm_scalebar() + tmap::tm_compass() +
         tmap::tm_title(paste(display_substance, "-", basin_label))
    
    static_map_png <- file.path(plots_dir, "static_concentration_map.png")
    tmap::tmap_save(m, static_map_png, width = 1200, height = 1000, dpi = 300)
    message("Static concentration map (PNG) saved to: ", static_map_png)
  }

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive concentration map saved to:\n")
  cat(">>> ", normalizePath(map_html), "\n")
  invisible(m)
}
