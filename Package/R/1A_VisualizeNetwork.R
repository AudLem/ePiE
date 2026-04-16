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
  if (!is.null(canals)) {
    canals <- sf::st_transform(sf::st_zm(sf::st_make_valid(canals)), crs = 4326)
    canal_col <- intersect(c("is_canal", "is_canl"), names(rivers))
    if (length(canal_col) > 0) {
      rivers <- rivers[is.na(rivers[[canal_col]]) | !rivers[[canal_col]], ]
    }
  } else {
    canal_col <- intersect(c("is_canal", "is_canl"), names(rivers))
    if (length(canal_col) > 0) {
      canal_mask <- !is.na(rivers[[canal_col]]) & rivers[[canal_col]] == TRUE
      canals <- rivers[canal_mask, ]
      rivers <- rivers[!canal_mask, ]
    }
  }

  # Deduplicate river segments: keep only the longest segment per ARCID
  # st_intersection can split rivers into multiple pieces at the basin border,
  # causing duplicate visual lines. Keeping the longest preserves the full geometry.
  if (!is.null(rivers) && nrow(rivers) > 1 && "ARCID" %in% names(rivers)) {
    dup_arcids <- rivers$ARCID[duplicated(rivers$ARCID) & !is.na(rivers$ARCID)]
    if (length(dup_arcids) > 0) {
      lengths <- as.numeric(sf::st_length(rivers))
      keep <- rep(TRUE, nrow(rivers))
      for (arcid in unique(dup_arcids)) {
        idx <- which(rivers$ARCID == arcid)
        longest <- idx[which.max(lengths[idx])]
        idx <- setdiff(idx, longest)
        keep[idx] <- FALSE
      }
      rivers <- rivers[keep, ]
    }
  }

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

  all_types <- c("node", "START", "MOUTH", "JNCT", "Hydro_Lake", "LakeInlet", "LakeOutlet", "agglomeration", "agglomeration_lake")
  all_colors <- c("#666666", "#33a02c", "#e31a1c", "#ff7f00", "#1f78b4", "#6baed6", "#08519c", "#e6ab02", "#b2df8a")
  names(all_colors) <- all_types
  pt_pal <- leaflet::colorFactor(palette = all_colors, domain = all_types, na.color = "#999999")

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
    pop_vals <- if ("total_population" %in% names(points)) {
      ifelse(!is.na(points$total_population), paste0("<br><b>Pop:</b> ", points$total_population), "")
    } else {
      rep("", nrow(points))
    }
    pt_popups <- paste0("<b>ID:</b> ", points$ID,
                        "<br><b>Type:</b> ", pt_labels,
                        pop_vals)
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

  map_title <- paste0("<b>Basin:</b> ", basin_id, " <small>(Network)</small><br>",
                       "<small>Generated: ", format(Sys.Date(), "%Y-%m-%d"), " | ",
                       "Basemap: check attribution in bottom-right corner</small>")
  tag_title <- htmltools::tags$div(
    htmltools::HTML(map_title),
    style = "background: white; padding: 8px 12px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.2); font-size: 14px;"
  )

  m <- m |>
    leaflet::addControl(html = tag_title, position = "bottomleft") |>
    leaflet::addLegend("topright", pal = pt_pal, values = pt_labels, title = "Node Type") |>
    leaflet::addLayersControl(
      baseGroups = c("Light", "Streets & Buildings", "Satellite", "Topographic"),
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

  if (requireNamespace("tmap", quietly = TRUE)) {
    tryCatch(
      {
        tmap::tmap_mode("view")
        m <- tmap::tm_shape(Basin) + tmap::tm_polygons(fill = "lightgrey", col = "darkgrey", lwd = 1.5)
        if (!is.null(rivers) && nrow(rivers) > 0) {
          m <- m + tmap::tm_shape(rivers) + tmap::tm_lines(col = "#2171b5", lwd = 1.5)
        }
        if (!is.null(canals) && nrow(canals) > 0) {
          m <- m + tmap::tm_shape(canals) + tmap::tm_lines(col = "#00bcd4", lwd = 2.5)
        }
        if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
          m <- m + tmap::tm_shape(HL_basin) + tmap::tm_polygons(fill = "lightblue", col = "#2171b5", fill_alpha = 0.7)
        }
        if (!is.null(points) && nrow(points) > 0) {
          m <- m + tmap::tm_shape(points) + tmap::tm_dots(fill = "pt_type", palette = "viridis", size = 0.5)
        }
        m <- m + tmap::tm_scalebar() + tmap::tm_compass() + tmap::tm_title(paste("Network -", basin_id))
        tmap::tmap_save(m, file.path(plots_dir, "interactive_tmap_map.html"))
      },
      error = function(e) {
        message("Note: tmap interactive map skipped: ", e$message)
      }
    )
  }

  if (requireNamespace("tmap", quietly = TRUE)) {
    tryCatch(
      {
        tmap::tmap_mode("plot")
        m <- tmap::tm_shape(Basin) + tmap::tm_polygons(fill = "lightgrey", col = "darkgrey")
        if (!is.null(rivers) && nrow(rivers) > 0) {
          m <- m + tmap::tm_shape(rivers) + tmap::tm_lines(col = "blue", lwd = 1.5)
        }
        if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
          m <- m + tmap::tm_shape(HL_basin) + tmap::tm_polygons(fill = "lightblue", col = "#2171b5")
        }
        m <- m + tmap::tm_scalebar() + tmap::tm_compass() +
             tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Network Overview -", basin_id))
        tmap::tmap_save(m, file.path(plots_dir, "static_network_overview.png"), width = 1200, height = 1000, dpi = 150)
      },
      error = function(e) {
        png(file.path(plots_dir, "static_network_overview.png"), width = 1200, height = 1000, res = 150)
        plot(sf::st_geometry(Basin), col = "lightgrey", border = "darkgrey", main = paste("Network Overview -", basin_id))
        if (!is.null(rivers) && nrow(rivers) > 0) {
          plot(sf::st_geometry(rivers), col = "blue", add = TRUE)
        }
        if (!is.null(HL_basin) && nrow(HL_basin) > 0) plot(sf::st_geometry(HL_basin), col = "lightblue", add = TRUE)
        dev.off()
      }
    )
  } else {
    png(file.path(plots_dir, "static_network_overview.png"), width = 1200, height = 1000, res = 150)
    plot(sf::st_geometry(Basin), col = "lightgrey", border = "darkgrey", main = paste("Network Overview -", basin_id))
    if (!is.null(rivers) && nrow(rivers) > 0) {
      plot(sf::st_geometry(rivers), col = "blue", add = TRUE)
    }
    if (!is.null(HL_basin) && nrow(HL_basin) > 0) plot(sf::st_geometry(HL_basin), col = "lightblue", add = TRUE)
    dev.off()
  }

  if (requireNamespace("tmap", quietly = TRUE)) {
    tryCatch(
      {
        tmap::tmap_mode("plot")
        m <- tmap::tm_shape(points) + tmap::tm_dots(fill = "pt_type", palette = "viridis", size = 0.5, title = "Node Type")
        if (!is.null(rivers) && nrow(rivers) > 0) {
          m <- m + tmap::tm_shape(rivers) + tmap::tm_lines(col = "grey", lwd = 1.5)
        }
        m <- m + tmap::tm_scalebar() + tmap::tm_compass() +
              tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Node Types -", basin_id))
        tmap::tmap_save(m, file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, dpi = 150)
      },
      error = function(e) {
        png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
        if (!is.null(rivers) && nrow(rivers) > 0) {
          plot(sf::st_geometry(rivers), col = "grey", main = paste("Node Types -", basin_id))
        }
        plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE)
        dev.off()
      }
    )
  } else {
    png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
    if (!is.null(rivers) && nrow(rivers) > 0) {
      plot(sf::st_geometry(rivers), col = "grey", main = paste("Node Types -", basin_id))
    }
    plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE)
    dev.off()
  }

  if (!is.null(agglomeration_points)) {
    if (requireNamespace("tmap", quietly = TRUE)) {
      tryCatch(
        {
          tmap::tmap_mode("plot")
          m <- tmap::tm_shape(Basin) + tmap::tm_polygons(fill = NA, col = "grey", lwd = 1.5) +
               tmap::tm_shape(agglomeration_points) + tmap::tm_dots(col = "red", size = 0.8, shape = 18, title = "Agglomeration")
          if (!is.null(rivers) && nrow(rivers) > 0) {
            m <- m + tmap::tm_shape(rivers) + tmap::tm_lines(col = "lightblue", lwd = 1.5)
          }
          m <- m + tmap::tm_scalebar() + tmap::tm_compass() +
                 tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Agglomerations -", basin_id))
          tmap::tmap_save(m, file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, dpi = 150)
        },
        error = function(e) {
          png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
          plot(sf::st_geometry(Basin), border = "grey", main = paste("Agglomerations -", basin_id))
          if (!is.null(rivers) && nrow(rivers) > 0) {
            plot(sf::st_geometry(rivers), col = "lightblue", add = TRUE)
          }
          plot(sf::st_geometry(agglomeration_points), col = "red", pch = 18, add = TRUE)
          dev.off()
        }
      )
    } else {
      png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
      plot(sf::st_geometry(Basin), border = "grey", main = paste("Agglomerations -", basin_id))
      if (!is.null(rivers) && nrow(rivers) > 0) {
        plot(sf::st_geometry(rivers), col = "lightblue", add = TRUE)
      }
      plot(sf::st_geometry(agglomeration_points), col = "red", pch = 18, add = TRUE)
      dev.off()
    }
  }

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive network map saved to:\n")
  cat(">>> ", normalizePath(interactive_map_path), "\n")
  invisible(m)
}
