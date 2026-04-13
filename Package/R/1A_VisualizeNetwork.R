VisualizeNetwork <- function(Basin,
                               hydro_sheds_rivers_basin,
                               points,
                               HL_basin = NULL,
                               run_output_dir,
                               basin_id,
                               agglomeration_points = NULL,
                               natural_rivers = NULL,
                               artificial_canals = NULL,
                               open_map_output_in_browser = TRUE,
                               show_interactive_map_preview = FALSE) {
  message("--- Step 10: Generating Visualizations ---")

  plots_dir <- file.path(run_output_dir, "plots")
  if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

  Basin <- sf::st_transform(sf::st_make_valid(Basin), crs = 4326)
  points <- sf::st_transform(sf::st_make_valid(points), crs = 4326)
  if (!is.null(HL_basin)) HL_basin <- sf::st_transform(sf::st_make_valid(HL_basin), crs = 4326)

  rivers <- natural_rivers
  if (is.null(rivers)) rivers <- hydro_sheds_rivers_basin
  if (!is.null(rivers)) rivers <- sf::st_transform(sf::st_zm(sf::st_make_valid(rivers)), crs = 4326)

  canals <- artificial_canals
  if (is.null(canals) && !is.null(rivers) && "is_canal" %in% names(rivers)) {
    canal_mask <- !is.na(rivers$is_canal) & rivers$is_canal
    canals <- rivers[canal_mask, ]
    rivers <- rivers[!canal_mask, ]
  }
  if (!is.null(canals)) canals <- sf::st_transform(sf::st_zm(sf::st_make_valid(canals)), crs = 4326)

  lakes <- HL_basin
  agglomerations <- if (!is.null(points) && "node_type" %in% names(points)) {
    points[!is.na(points$node_type) & points$node_type %in% c("agglomeration", "agglomeration_lake"), ]
  } else {
    agglomeration_points
  }
  lake_outlets <- if (!is.null(points) && "lake_out" %in% names(points)) points[points$lake_out == 1, ] else NULL

  pt_coords <- if (!is.null(points)) as.data.frame(sf::st_coordinates(points)) else NULL
  agg_coords <- if (!is.null(agglomerations) && nrow(agglomerations) > 0) as.data.frame(sf::st_coordinates(agglomerations)) else NULL
  out_coords <- if (!is.null(lake_outlets) && nrow(lake_outlets) > 0) as.data.frame(sf::st_coordinates(lake_outlets)) else NULL

  pt_labels <- if (!is.null(points) && "pt_type" %in% names(points)) as.character(points$pt_type) else rep("node", nrow(points))
  agg_labels <- if (!is.null(agglomerations) && "node_type" %in% names(agglomerations)) as.character(agglomerations$node_type) else rep("agglomeration", nrow(agglomerations))

  all_types <- c("node", "START", "MOUTH", "JNCT", "Hydro_Lake", "agglomeration", "agglomeration_lake")
  all_colors <- c("#666666", "#33a02c", "#e31a1c", "#ff7f00", "#1f78b4", "#e6ab02", "#b2df8a")
  names(all_colors) <- all_types
  pt_pal <- leaflet::colorFactor(palette = all_colors, domain = all_types, na.color = "#999999")

  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "CartoDB Light") |>
    leaflet::addProviderTiles(leaflet::providers$OpenStreetMap, group = "OpenStreetMap") |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite")

  if (!is.null(Basin) && nrow(Basin) > 0) {
    m <- m |> leaflet::addPolygons(data = Basin, color = "black", weight = 1.5, fillColor = "grey", fillOpacity = 0.1, group = "Basin")
  }

  if (!is.null(rivers) && nrow(rivers) > 0) {
    m <- m |> leaflet::addPolylines(data = rivers, color = "#2171b5", weight = 1.5, opacity = 0.7, group = "Rivers")
  }

  if (!is.null(canals) && nrow(canals) > 0) {
    m <- m |> leaflet::addPolylines(data = canals, color = "#00bcd4", weight = 2.5, opacity = 0.8, group = "Canals")
  }

  if (!is.null(lakes) && nrow(lakes) > 0) {
    m <- m |> leaflet::addPolygons(data = lakes, color = "#2171b5", weight = 1, fillColor = "#6baed6", fillOpacity = 0.4, group = "Lakes")
  }

  if (!is.null(pt_coords) && nrow(pt_coords) > 0) {
    pt_colors <- pt_pal(pt_labels)
    pt_popups <- paste0("<b>ID:</b> ", points$ID,
                        "<br><b>Type:</b> ", pt_labels,
                        if ("total_population" %in% names(points)) paste0("<br><b>Pop:</b> ", points$total_population) else "")
    m <- m |> leaflet::addCircleMarkers(
      lng = pt_coords[, 1], lat = pt_coords[, 2],
      radius = 3, weight = 1, fillOpacity = 0.8,
      color = pt_colors, fillColor = pt_colors,
      popup = pt_popups, group = "Network Nodes"
    )
  }

  if (!is.null(out_coords) && nrow(out_coords) > 0) {
    m <- m |> leaflet::addCircleMarkers(
      lng = out_coords[, 1], lat = out_coords[, 2],
      radius = 6, weight = 2, fillOpacity = 0.9,
      color = "#08306b", fillColor = "#2171b5", group = "Lake Outlets"
    )
  }

  if (!is.null(agg_coords) && nrow(agg_coords) > 0) {
    agg_popups <- paste0("<b>Type:</b> ", agg_labels,
                         if (!is.null(agglomerations) && "total_population" %in% names(agglomerations)) paste0("<br><b>Pop:</b> ", agglomerations$total_population) else "")
    m <- m |> leaflet::addCircleMarkers(
      lng = agg_coords[, 1], lat = agg_coords[, 2],
      radius = 4, weight = 1, fillOpacity = 0.7,
      color = "#e6ab02", fillColor = "#e6ab02",
      popup = agg_popups, group = "Agglomerations"
    )
  }

  map_title <- paste0("<b>Basin:</b> ", basin_id, " <small>(Network)</small>")
  tag_title <- htmltools::tags$div(
    htmltools::HTML(map_title),
    style = "background: white; padding: 8px 12px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.2); font-size: 14px;"
  )

  m <- m |>
    leaflet::addControl(html = tag_title, position = "bottomleft") |>
    leaflet::addLegend("topright", pal = pt_pal, values = pt_labels, title = "Node Type") |>
    leaflet::addLayersControl(
      baseGroups = c("CartoDB Light", "OpenStreetMap", "Satellite"),
      overlayGroups = c("Basin", "Rivers", "Canals", "Lakes", "Network Nodes", "Lake Outlets", "Agglomerations"),
      options = leaflet::layersControlOptions(collapsed = TRUE)
    )

  interactive_map_path <- file.path(plots_dir, "interactive_network_map.html")
  interactive_map_libdir <- file.path(plots_dir, "interactive_network_map_files")
  if (dir.exists(interactive_map_libdir)) unlink(interactive_map_libdir, recursive = TRUE, force = TRUE)
  tryCatch(
    {
      htmlwidgets::saveWidget(widget = m, file = interactive_map_path, selfcontained = TRUE)
    },
    error = function(e) {
      message("Note: self-contained export failed (", e$message, "). Falling back to sidecar HTML export.")
      tryCatch(
        {
          htmlwidgets::saveWidget(widget = m, file = interactive_map_path, selfcontained = FALSE, libdir = interactive_map_libdir)
        },
        error = function(e2) {
          message("Note: interactive HTML export failed: ", e2$message)
        }
      )
    }
  )

  png(file.path(plots_dir, "static_network_overview.png"), width = 1200, height = 1000, res = 150)
  plot(sf::st_geometry(Basin), col = "lightgrey", border = "darkgrey", main = paste("Network Overview -", basin_id))
  plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "blue", add = TRUE)
  if (!is.null(HL_basin) && nrow(HL_basin) > 0) plot(sf::st_geometry(HL_basin), col = "lightblue", add = TRUE)
  dev.off()

  png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
  plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "grey", main = paste("Node Types -", basin_id))
  plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE)
  dev.off()

  if (!is.null(agglomeration_points)) {
    png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
    plot(sf::st_geometry(Basin), border = "grey", main = paste("Agglomerations -", basin_id))
    plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "lightblue", add = TRUE)
    plot(sf::st_geometry(agglomeration_points), col = "red", pch = 18, add = TRUE)
    dev.off()
  }

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive network map saved to:\n")
  cat(">>> ", normalizePath(interactive_map_path), "\n")
  invisible(m)
}
