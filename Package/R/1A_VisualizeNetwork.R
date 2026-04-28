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

  normalize_polygons_local <- function(layer) {
    if (is.null(layer) || nrow(layer) == 0) return(layer)
    layer <- sf::st_transform(sf::st_make_valid(layer), crs = 4326)
    geom_types <- unique(as.character(sf::st_geometry_type(layer)))
    if (any(grepl("GEOMETRYCOLLECTION|MULTI", geom_types)) || length(geom_types) > 1) {
      layer <- tryCatch(
        sf::st_cast(sf::st_collection_extract(layer, "POLYGON"), "MULTIPOLYGON"),
        error = function(e) {
          tryCatch(sf::st_cast(layer, "MULTIPOLYGON"), error = function(e2) layer)
        }
      )
    }
    if (nrow(layer) == 0) return(NULL)
    layer
  }
  normalize_lines_local <- function(layer) {
    if (is.null(layer) || nrow(layer) == 0) return(layer)
    layer <- sf::st_transform(sf::st_zm(sf::st_make_valid(layer)), crs = 4326)
    layer <- tryCatch(sf::st_collection_extract(layer, "LINESTRING"), error = function(e) layer)
    layer <- tryCatch(sf::st_cast(layer, "MULTILINESTRING"), error = function(e) layer)
    if (nrow(layer) == 0) return(NULL)
    layer
  }
  Basin <- normalize_polygons_local(Basin)
  points <- sf::st_transform(sf::st_make_valid(points), crs = 4326)
  if (!is.null(HL_basin)) HL_basin <- normalize_polygons_local(HL_basin)

  rivers <- natural_rivers
  if (is.null(rivers)) rivers <- hydro_sheds_rivers_basin
  if (!is.null(rivers)) rivers <- normalize_lines_local(rivers)

  canals <- artificial_canals
  if (!is.null(canals)) {
    canals <- normalize_lines_local(canals)
    if (!is.null(rivers) && "is_canal" %in% names(rivers)) {
      rivers <- rivers[!rivers$is_canal, ]
    }
  } else if (!is.null(rivers) && "is_canal" %in% names(rivers)) {
    canal_mask <- !is.na(rivers$is_canal) & rivers$is_canal
    canals <- rivers[canal_mask, ]
    rivers <- rivers[!canal_mask, ]
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
  
  # Map 'WWTP' type if it exists in node_type but pt_type is just 'node'
  if ("node_type" %in% names(points)) {
    is_wwtp <- !is.na(points$node_type) & points$node_type == "WWTP"
    pt_labels[is_wwtp] <- "WWTP"
  }

  all_types <- c("node", "START", "MOUTH", "JNCT", "Hydro_Lake", "LakeInlet", "LakeOutlet", "agglomeration", "agglomeration_lake", "WWTP")
  all_colors <- c("#666666", "#33a02c", "#e31a1c", "#ff7f00", "#1f78b4", "#6baed6", "#08519c", "#e6ab02", "#b2df8a", "#d95f02")
  names(all_colors) <- all_types
  pt_pal <- leaflet::colorFactor(palette = all_colors, domain = all_types, na.color = "#999999")

  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE, attributionControl = FALSE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "Light") |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldStreetMap, group = "Streets & Buildings") |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite") |>
    leaflet::addProviderTiles(leaflet::providers$OpenTopoMap, group = "Topographic") |>
    leaflet::addControl(html = htmltools::tags$div(
      htmltools::HTML("<small>&copy; Esri | CARTO | OpenStreetMap | OpenTopoMap</small>"),
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

  topology_edges <- buildTopologyEdges(sf::st_drop_geometry(points))
  if (!is.null(topology_edges) && nrow(topology_edges) > 0) {
    topology_split <- splitRiverAndCanalLayers(topology_edges)
    if (!is.null(topology_split$rivers) && nrow(topology_split$rivers) > 0) {
      m <- m |> leaflet::addPolylines(
        data = topology_split$rivers,
        color = "#08306b",
        weight = 3,
        opacity = 0.65,
        group = "River Topology Links"
      )
    }
    if (!is.null(topology_split$canals) && nrow(topology_split$canals) > 0) {
      m <- m |> leaflet::addPolylines(
        data = topology_split$canals,
        color = "#00838f",
        weight = 3.5,
        opacity = 0.75,
        group = "Canal Topology Links"
      )
    }
  }

  if (!is.null(pt_coords) && nrow(pt_coords) > 0) {
    pt_colors <- pt_pal(pt_labels)
    pop_vals <- if ("total_population" %in% names(points)) {
      ifelse(!is.na(points$total_population), paste0("<br><b>Pop:</b> ", format(points$total_population, big.mark=",")), "")
    } else {
      rep("", nrow(points))
    }
    source_vals <- if ("source_db" %in% names(points)) {
      ifelse(!is.na(points$source_db), paste0("<br><b>Source:</b> ", points$source_db), "")
    } else {
      rep("", nrow(points))
    }
    
    pt_popups <- paste0("<b>ID:</b> ", points$ID,
                        "<br><b>Type:</b> ", pt_labels,
                        if ("ID_nxt" %in% names(points)) paste0("<br><b>Next:</b> ", ifelse(is.na(points$ID_nxt), "", points$ID_nxt)) else "",
                        if ("canal_d_nxt_m" %in% names(points)) paste0("<br><b>Dist to next:</b> ", round(points$canal_d_nxt_m, 1), " m") else "",
                        if ("chainage_m" %in% names(points)) paste0("<br><b>Chainage:</b> ", round(points$chainage_m, 1), " m") else "",
                        if ("Q_model_m3s" %in% names(points)) paste0("<br><b>Q model:</b> ", round(points$Q_model_m3s, 3), " m3/s") else "",
                        pop_vals,
                        source_vals)
    
    # Differentiate size: key nodes (START/MOUTH/WWTP/Agglom) are larger
    pt_radius <- ifelse(pt_labels %in% c("WWTP", "agglomeration", "agglomeration_lake", "START", "MOUTH"), 5, 3)
    pt_weight <- ifelse(pt_labels %in% c("WWTP", "agglomeration", "agglomeration_lake", "START", "MOUTH"), 2, 1)

    m <- m |> leaflet::addCircleMarkers(
      lng = pt_coords[, 1], lat = pt_coords[, 2],
      radius = pt_radius, weight = pt_weight, fillOpacity = 0.8,
      color = pt_colors, fillColor = pt_colors,
      popup = pt_popups, group = "Network Nodes"
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
      overlayGroups = c("Basin", "Rivers", "Canals", "River Topology Links", "Canal Topology Links", "Lakes", "Network Nodes"),
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
        map_style <- ePieVisualizationStyle()
        
        m_view <- tmap::tm_shape(Basin) + tmap::tm_polygons(fill = "lightgrey", col = "darkgrey", lwd = 1.5)
        
        if (!is.null(rivers) && nrow(rivers) > 0) {
          m_view <- m_view + tmap::tm_shape(rivers) + tmap::tm_lines(col = map_style$colors$river, lwd = 1.5)
        }
        
        if (!is.null(canals) && nrow(canals) > 0) {
          m_view <- m_view + tmap::tm_shape(canals) + tmap::tm_lines(col = map_style$colors$canal, lwd = 2.5)
        }
        
        if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
          m_view <- m_view + tmap::tm_shape(HL_basin) + tmap::tm_polygons(fill = "lightblue", col = map_style$colors$lake_border, fill_alpha = 0.7)
        }
        
        if (!is.null(points) && nrow(points) > 0) {
          m_view <- m_view + tmap::tm_shape(points) + tmap::tm_dots(fill = "pt_type", palette = "Set1", size = 0.5)
        }
        
        m_view <- m_view + tmap::tm_scalebar() + tmap::tm_compass() + tmap::tm_title(paste("Network -", basin_id))
        tmap::tmap_save(m_view, file.path(plots_dir, "interactive_tmap_map.html"))
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
        map_style <- ePieVisualizationStyle()
        
        m_static <- tmap::tm_layout(bg.color = "white", frame = FALSE) + 
                    tmap::tm_title(paste("Network Overview -", basin_id))
        
        if (!is.null(Basin) && nrow(Basin) > 0) {
          m_static <- m_static + tmap::tm_shape(Basin) + tmap::tm_polygons(fill = "lightgrey", col = "darkgrey")
        }
        
        if (!is.null(rivers) && nrow(rivers) > 0) {
          m_static <- m_static + tmap::tm_shape(rivers) + tmap::tm_lines(col = map_style$colors$river, lwd = 1.5)
        }
        
        if (!is.null(canals) && nrow(canals) > 0) {
          m_static <- m_static + tmap::tm_shape(canals) + tmap::tm_lines(col = map_style$colors$canal, lwd = 2.5)
        }
        
        if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
          m_static <- m_static + tmap::tm_shape(HL_basin) + tmap::tm_polygons(fill = "lightblue", col = map_style$colors$lake_border)
        }
        
        m_static <- m_static + tmap::tm_scalebar() + tmap::tm_compass()
        
        tmap::tmap_save(m_static, file.path(plots_dir, "static_network_overview.png"), width = 1200, height = 1000, dpi = 150)
      },
      error = function(e) {
        png(file.path(plots_dir, "static_network_overview.png"), width = 1200, height = 1000, res = 150)
        plot(sf::st_geometry(Basin), col = "lightgrey", border = "darkgrey", main = paste("Network Overview -", basin_id))
        if (!is.null(rivers)) plot(sf::st_geometry(rivers), col = "blue", add = TRUE)
        if (!is.null(canals)) plot(sf::st_geometry(canals), col = "cyan", lwd = 2, add = TRUE)
        if (!is.null(HL_basin) && nrow(HL_basin) > 0) plot(sf::st_geometry(HL_basin), col = "lightblue", add = TRUE)
        dev.off()
      }
    )
  }

  if (requireNamespace("tmap", quietly = TRUE)) {
    tryCatch(
      {
        tmap::tmap_mode("plot")
        m <- tmap::tm_shape(hydro_sheds_rivers_basin) + tmap::tm_lines(col = "grey", lwd = 1.5) +
             tmap::tm_shape(points) + tmap::tm_dots(fill = "pt_type", palette = "viridis", size = 0.5, title = "Node Type") +
             tmap::tm_scalebar() + tmap::tm_compass() +
             tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Node Types -", basin_id))
        tmap::tmap_save(m, file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, dpi = 150)
      },
      error = function(e) {
        png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
        plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "grey", main = paste("Node Types -", basin_id))
        plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE)
        dev.off()
      }
    )
  } else {
    png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
    plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "grey", main = paste("Node Types -", basin_id))
    plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE)
    dev.off()
  }

  if (!is.null(agglomeration_points)) {
    if (requireNamespace("tmap", quietly = TRUE)) {
      tryCatch(
        {
          tmap::tmap_mode("plot")
          m <- tmap::tm_shape(Basin) + tmap::tm_polygons(fill = NA, col = "grey", lwd = 1.5) +
               tmap::tm_shape(hydro_sheds_rivers_basin) + tmap::tm_lines(col = "lightblue", lwd = 1.5) +
               tmap::tm_shape(agglomeration_points) + tmap::tm_dots(col = "red", size = 0.8, shape = 18, title = "Agglomeration") +
                tmap::tm_scalebar() + tmap::tm_compass() +
                tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Agglomerations -", basin_id))
          tmap::tmap_save(m, file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, dpi = 150)
        },
        error = function(e) {
          png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
          plot(sf::st_geometry(Basin), border = "grey", main = paste("Agglomerations -", basin_id))
          plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "lightblue", add = TRUE)
          plot(sf::st_geometry(agglomeration_points), col = "red", pch = 18, add = TRUE)
          dev.off()
        }
      )
    } else {
      png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
      plot(sf::st_geometry(Basin), border = "grey", main = paste("Agglomerations -", basin_id))
      plot(sf::st_geometry(hydro_sheds_rivers_basin), col = "lightblue", add = TRUE)
      plot(sf::st_geometry(agglomeration_points), col = "red", pch = 18, add = TRUE)
      dev.off()
    }
  }

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive network map saved to:\n")
  cat(">>> ", normalizePath(interactive_map_path), "\n")
  invisible(m)
}
