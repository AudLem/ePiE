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
  
  safe_plot_geometry <- function(layer, ...) {
    if (is.null(layer) || nrow(layer) == 0) return(invisible(FALSE))
    tryCatch(
      {
        plot(sf::st_geometry(layer), ...)
        TRUE
      },
      error = function(e) {
        message("Note: static geometry plot skipped: ", e$message)
        FALSE
      }
    )
  }

  normalize_polygons_local <- function(layer) {
    if (is.null(layer) || nrow(layer) == 0) return(layer)
    layer <- sf::st_transform(sf::st_make_valid(layer), crs = 4326)
    layer <- tryCatch(sf::st_collection_extract(layer, "POLYGON"), error = function(e) layer)
    gt <- as.character(sf::st_geometry_type(layer, by_geometry = TRUE))
    keep <- gt %in% c("POLYGON", "MULTIPOLYGON")
    layer <- layer[keep, , drop = FALSE]
    if (nrow(layer) == 0) return(NULL)
    layer <- tryCatch(sf::st_cast(layer, "MULTIPOLYGON"), error = function(e) layer)
    layer
  }
  normalize_lines_local <- function(layer) {
    if (is.null(layer) || nrow(layer) == 0) return(layer)
    layer <- sf::st_transform(sf::st_zm(sf::st_make_valid(layer)), crs = 4326)
    layer <- tryCatch(sf::st_collection_extract(layer, "LINESTRING"), error = function(e) layer)
    gt <- as.character(sf::st_geometry_type(layer, by_geometry = TRUE))
    keep <- gt %in% c("LINESTRING", "MULTILINESTRING")
    layer <- layer[keep, , drop = FALSE]
    if (nrow(layer) == 0) return(NULL)
    layer <- tryCatch(sf::st_cast(layer, "MULTILINESTRING"), error = function(e) layer)
    if (nrow(layer) == 0) return(NULL)
    layer
  }
  Basin <- normalize_polygons_local(Basin)
  points <- sf::st_transform(sf::st_make_valid(points), crs = 4326)
  points <- AnnotateDisplayJunctions(points)
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

  pt_labels <- if (!is.null(points) && "display_pt_type" %in% names(points)) {
    as.character(points$display_pt_type)
  } else if (!is.null(points) && "pt_type" %in% names(points)) {
    as.character(points$pt_type)
  } else {
    rep("node", nrow(points))
  }
  
  # Map 'WWTP' type if it exists in node_type but pt_type is just 'node'
  if ("node_type" %in% names(points)) {
    is_wwtp <- !is.na(points$node_type) & points$node_type == "WWTP"
    pt_labels[is_wwtp] <- "WWTP"
  }

  all_types <- c("node", "START", "MOUTH", "JNCT", "Hydro_Lake", "LakeInlet", "LakeOutlet",
                 "agglomeration", "agglomeration_lake", "WWTP",
                 "CANAL_START", "CANAL_NODE", "CANAL_BRANCH", "CANAL_JUNCTION", "CANAL_END")
  all_colors <- c("#666666", "#33a02c", "#e31a1c", "#ff7f00", "#1f78b4", "#6baed6", "#08519c",
                  "#e6ab02", "#b2df8a", "#d95f02",
                  "#00acc1", "#4dd0e1", "#00838f", "#006064", "#80deea")
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
    # Use basin boundaries in leaflet to avoid GEOMETRYCOLLECTION polygon
    # serialization failures in some sf/leaflet combinations.
    basin_boundaries <- tryCatch(sf::st_boundary(Basin), error = function(e) NULL)
    if (!is.null(basin_boundaries)) {
      m <- tryCatch(
        m |> leaflet::addPolylines(data = basin_boundaries, color = "black", weight = 1.5, opacity = 0.9, group = "Basin"),
        error = function(e) {
          message("Note: skipping Basin layer: ", e$message)
          m
        }
      )
    }
  }

  if (!is.null(rivers) && nrow(rivers) > 0) {
    m <- m |> leaflet::addPolylines(data = rivers, color = "#2171b5", weight = 1.5, opacity = 0.7, group = "Rivers")
  }

  if (!is.null(canals) && nrow(canals) > 0) {
    m <- m |> leaflet::addPolylines(data = canals, color = "#00bcd4", weight = 2.5, opacity = 0.8, group = "Canals")
  }

  if (!is.null(lakes) && nrow(lakes) > 0) {
    # Render lakes as boundaries to keep map generation robust on problematic
    # GEOMETRYCOLLECTION polygons while preserving visible lake layer.
    lake_boundaries <- tryCatch(sf::st_boundary(lakes), error = function(e) NULL)
    if (!is.null(lake_boundaries)) {
      m <- tryCatch(
        m |> leaflet::addPolylines(data = lake_boundaries, color = "#2171b5", weight = 1.5, opacity = 0.9, group = "Lakes"),
        error = function(e) {
          message("Note: skipping Lakes layer: ", e$message)
          m
        }
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
    
    q_display_vals <- if ("Q_model_m3s" %in% names(points)) {
      if ("Q_role" %in% names(points) && "Q_parent_m3s" %in% names(points)) {
        ifelse(!is.na(points$Q_role) & points$Q_role == "parent_branch_available" & !is.na(points$Q_parent_m3s),
               points$Q_parent_m3s,
               points$Q_model_m3s)
      } else {
        points$Q_model_m3s
      }
    } else {
      rep(NA_real_, nrow(points))
    }

    pt_popups <- paste0("<b>ID:</b> ", points$ID,
                        "<br><b>Type:</b> ", pt_labels,
                        if ("pt_type" %in% names(points)) paste0("<br><b>Model type:</b> ", points$pt_type) else "",
                        if ("junction_role" %in% names(points)) paste0("<br><b>Junction role:</b> ", ifelse(is.na(points$junction_role), "", points$junction_role)) else "",
                        if ("ID_nxt" %in% names(points)) paste0("<br><b>Next:</b> ", ifelse(is.na(points$ID_nxt), "", points$ID_nxt)) else "",
                        if ("canal_d_nxt_m" %in% names(points)) paste0("<br><b>Dist to next:</b> ", round(points$canal_d_nxt_m, 1), " m") else "",
                        if ("chainage_m" %in% names(points)) paste0("<br><b>Chainage:</b> ", round(points$chainage_m, 1), " m") else "",
                        if ("Q_model_m3s" %in% names(points)) paste0("<br><b>Q:</b> ", ifelse(is.na(q_display_vals), "", round(q_display_vals, 3)), " m3/s") else "",
                        pop_vals,
                        source_vals)
    
    # Differentiate size: key nodes (START/MOUTH/WWTP/Agglom) are larger
    pt_radius <- ifelse(pt_labels %in% c("WWTP", "agglomeration", "agglomeration_lake", "START", "MOUTH"), 5, 3)
    pt_weight <- ifelse(pt_labels %in% c("WWTP", "agglomeration", "agglomeration_lake", "START", "MOUTH"), 2, 1)
    is_branch <- pt_labels == "CANAL_BRANCH"
    is_branch[is.na(is_branch)] <- FALSE

    non_branch_idx <- which(!is_branch)
    if (length(non_branch_idx) > 0) {
      m <- m |> leaflet::addCircleMarkers(
        lng = pt_coords[non_branch_idx, 1], lat = pt_coords[non_branch_idx, 2],
        radius = pt_radius[non_branch_idx], weight = pt_weight[non_branch_idx], fillOpacity = 0.8,
        color = pt_colors[non_branch_idx], fillColor = pt_colors[non_branch_idx],
        popup = pt_popups[non_branch_idx], group = "Network Nodes"
      )
    }

    branch_idx <- which(is_branch)
    if (length(branch_idx) > 0) {
      m <- m |> leaflet::addCircleMarkers(
        lng = pt_coords[branch_idx, 1], lat = pt_coords[branch_idx, 2],
        radius = 6.5, weight = 3, fillOpacity = 1,
        color = pt_colors[branch_idx], fillColor = pt_colors[branch_idx],
        popup = pt_popups[branch_idx], group = "Network Nodes"
      )
    }
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
      overlayGroups = c("Basin", "Rivers", "Canals", "Lakes", "Network Nodes"),
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
          point_fill <- if ("display_pt_type" %in% names(points)) "display_pt_type" else "pt_type"
          m_view <- m_view + tmap::tm_shape(points) + tmap::tm_dots(fill = point_fill, fill.scale = tmap::tm_scale_categorical(values = "Set1"), size = 0.5)
        }
        
        m_view <- m_view + tmap::tm_scalebar() + tmap::tm_compass() + tmap::tm_title(paste("Network -", basin_id))
        tmap::tmap_save(m_view, file.path(plots_dir, "interactive_tmap_map.html"))
      },
      error = function(e) {
        message("Note: tmap interactive map skipped: ", e$message)
        message("      (This is an upstream tmap limitation when saving interactive maps with small multiples)")
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
        safe_plot_geometry(Basin, col = "lightgrey", border = "darkgrey", main = paste("Network Overview -", basin_id))
        safe_plot_geometry(rivers, col = "blue", add = TRUE)
        safe_plot_geometry(canals, col = "cyan", lwd = 2, add = TRUE)
        safe_plot_geometry(HL_basin, col = "lightblue", add = TRUE)
        dev.off()
      }
    )
  }

  if (requireNamespace("tmap", quietly = TRUE)) {
    tryCatch(
      {
        tmap::tmap_mode("plot")
        m <- tmap::tm_shape(hydro_sheds_rivers_basin) + tmap::tm_lines(col = "grey", lwd = 1.5) +
             tmap::tm_shape(points) + tmap::tm_dots(fill = if ("display_pt_type" %in% names(points)) "display_pt_type" else "pt_type", 
                                             fill.scale = tmap::tm_scale_categorical(values = "viridis"), size = 0.5,
                                             fill.legend = tmap::tm_legend(title = "Node Type")) +
             tmap::tm_scalebar() + tmap::tm_compass() +
             tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Node Types -", basin_id))
        tmap::tmap_save(m, file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, dpi = 150)
      },
      error = function(e) {
        png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
        safe_plot_geometry(hydro_sheds_rivers_basin, col = "grey", main = paste("Node Types -", basin_id))
        tryCatch(plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE), error = function(e2) NULL)
        dev.off()
      }
    )
  } else {
    png(file.path(plots_dir, "static_node_types.png"), width = 1200, height = 1000, res = 150)
    safe_plot_geometry(hydro_sheds_rivers_basin, col = "grey", main = paste("Node Types -", basin_id))
    tryCatch(plot(points["pt_type"], pch = 16, cex = 0.8, add = TRUE), error = function(e2) NULL)
    dev.off()
  }

  if (!is.null(agglomeration_points)) {
    if (requireNamespace("tmap", quietly = TRUE)) {
      tryCatch(
        {
          tmap::tmap_mode("plot")
          m <- tmap::tm_shape(Basin) + tmap::tm_polygons(fill = NA, col = "grey", lwd = 1.5) +
               tmap::tm_shape(hydro_sheds_rivers_basin) + tmap::tm_lines(col = "lightblue", lwd = 1.5) +
               tmap::tm_shape(agglomeration_points) + tmap::tm_dots(col = "red", size = 0.8, shape = 18, fill.legend = tmap::tm_legend(title = "Agglomeration")) +
                tmap::tm_scalebar() + tmap::tm_compass() +
                tmap::tm_layout(bg.color = "white", frame = FALSE) + tmap::tm_title(paste("Agglomerations -", basin_id))
          tmap::tmap_save(m, file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, dpi = 150)
        },
        error = function(e) {
          png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
          safe_plot_geometry(Basin, border = "grey", main = paste("Agglomerations -", basin_id))
          safe_plot_geometry(hydro_sheds_rivers_basin, col = "lightblue", add = TRUE)
          safe_plot_geometry(agglomeration_points, col = "red", pch = 18, add = TRUE)
          dev.off()
        }
      )
    } else {
      png(file.path(plots_dir, "static_agglomerations.png"), width = 1200, height = 1000, res = 150)
      safe_plot_geometry(Basin, border = "grey", main = paste("Agglomerations -", basin_id))
      safe_plot_geometry(hydro_sheds_rivers_basin, col = "lightblue", add = TRUE)
      safe_plot_geometry(agglomeration_points, col = "red", pch = 18, add = TRUE)
      dev.off()
    }
  }

  message("Visualization complete.")
  cat("\n[CHECKPOINT] Interactive network map saved to:\n")
  cat(">>> ", normalizePath(interactive_map_path), "\n")
  invisible(m)
}

GenerateNetworkMapFallback <- function(Basin,
                                       hydro_sheds_rivers_basin,
                                       points,
                                       HL_basin = NULL,
                                       run_output_dir,
                                       basin_id) {
  plots_dir <- file.path(run_output_dir, "plots")
  if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

  normalize_line_layer <- function(layer) {
    if (is.null(layer)) return(NULL)
    sf_obj <- tryCatch(sf::st_as_sf(layer), error = function(e) NULL)
    if (is.null(sf_obj) || nrow(sf_obj) == 0) return(NULL)
    sf_obj <- tryCatch(sf::st_transform(sf::st_zm(sf::st_make_valid(sf_obj)), crs = 4326), error = function(e) NULL)
    if (is.null(sf_obj) || nrow(sf_obj) == 0) return(NULL)
    sf_obj <- tryCatch(sf::st_collection_extract(sf_obj, "LINESTRING"), error = function(e) sf_obj)
    gt <- as.character(sf::st_geometry_type(sf_obj, by_geometry = TRUE))
    sf_obj <- sf_obj[gt %in% c("LINESTRING", "MULTILINESTRING"), , drop = FALSE]
    if (nrow(sf_obj) == 0) return(NULL)
    tryCatch(sf::st_cast(sf_obj, "MULTILINESTRING"), error = function(e) sf_obj)
  }

  pts <- sf::st_transform(sf::st_make_valid(points), crs = 4326)
  pts <- AnnotateDisplayJunctions(pts)
  pts_df <- sf::st_drop_geometry(pts)

  rivers <- normalize_line_layer(hydro_sheds_rivers_basin)

  lake_boundaries <- NULL
  if (!is.null(HL_basin) && nrow(HL_basin) > 0) {
    lakes <- sf::st_transform(sf::st_make_valid(HL_basin), crs = 4326)
    lake_boundaries <- tryCatch(sf::st_boundary(lakes), error = function(e) NULL)
    lake_boundaries <- normalize_line_layer(lake_boundaries)
  }


  pt_labels <- if ("display_pt_type" %in% names(pts_df)) {
    as.character(pts_df$display_pt_type)
  } else if ("pt_type" %in% names(pts_df)) {
    as.character(pts_df$pt_type)
  } else {
    rep("node", nrow(pts_df))
  }
  if ("node_type" %in% names(pts_df)) {
    is_wwtp <- !is.na(pts_df$node_type) & pts_df$node_type == "WWTP"
    pt_labels[is_wwtp] <- "WWTP"
  }
  all_types <- c("node", "START", "MOUTH", "JNCT", "Hydro_Lake", "LakeInlet", "LakeOutlet",
                 "agglomeration", "agglomeration_lake", "WWTP",
                 "CANAL_START", "CANAL_NODE", "CANAL_BRANCH", "CANAL_JUNCTION", "CANAL_END")
  all_colors <- c("#666666", "#33a02c", "#e31a1c", "#ff7f00", "#1f78b4", "#6baed6", "#08519c",
                  "#e6ab02", "#b2df8a", "#d95f02",
                  "#00acc1", "#4dd0e1", "#00838f", "#006064", "#80deea")
  names(all_colors) <- all_types
  pt_pal <- leaflet::colorFactor(palette = all_colors, domain = all_types, na.color = "#999999")

  q_display_vals <- if ("Q_model_m3s" %in% names(pts_df)) {
    if ("Q_role" %in% names(pts_df) && "Q_parent_m3s" %in% names(pts_df)) {
      ifelse(!is.na(pts_df$Q_role) & pts_df$Q_role == "parent_branch_available" & !is.na(pts_df$Q_parent_m3s),
             pts_df$Q_parent_m3s,
             pts_df$Q_model_m3s)
    } else {
      pts_df$Q_model_m3s
    }
  } else {
    rep(NA_real_, nrow(pts_df))
  }

  pt_popups <- paste0(
    "<b>ID:</b> ", pts_df$ID,
    "<br><b>Type:</b> ", pt_labels,
    if ("pt_type" %in% names(pts_df)) paste0("<br><b>Model type:</b> ", pts_df$pt_type) else "",
    if ("junction_role" %in% names(pts_df)) paste0("<br><b>Junction role:</b> ", ifelse(is.na(pts_df$junction_role), "", pts_df$junction_role)) else "",
    if ("ID_nxt" %in% names(pts_df)) paste0("<br><b>Next:</b> ", ifelse(is.na(pts_df$ID_nxt), "", pts_df$ID_nxt)) else "",
    if ("canal_d_nxt_m" %in% names(pts_df)) paste0("<br><b>Dist to next:</b> ", round(pts_df$canal_d_nxt_m, 1), " m") else "",
    if ("chainage_m" %in% names(pts_df)) paste0("<br><b>Chainage:</b> ", round(pts_df$chainage_m, 1), " m") else "",
    if ("Q_model_m3s" %in% names(pts_df)) paste0("<br><b>Q:</b> ", ifelse(is.na(q_display_vals), "", round(q_display_vals, 3)), " m3/s") else ""
  )

  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE, attributionControl = FALSE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "Light") |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldStreetMap, group = "Streets & Buildings") |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite") |>
    leaflet::addProviderTiles(leaflet::providers$OpenTopoMap, group = "Topographic")

  if (!is.null(rivers) && nrow(rivers) > 0) {
    m <- m |> leaflet::addPolylines(data = rivers, color = "#2171b5", weight = 1.5, opacity = 0.7, group = "Rivers")
  }
  if (!is.null(lake_boundaries)) {
    m <- m |> leaflet::addPolylines(data = lake_boundaries, color = "#2171b5", weight = 1.5, opacity = 0.9, group = "Lakes")
  }
  rad <- ifelse(pt_labels %in% c("WWTP", "agglomeration", "agglomeration_lake", "START", "MOUTH"), 5, 3)
  wgt <- ifelse(pt_labels %in% c("WWTP", "agglomeration", "agglomeration_lake", "START", "MOUTH"), 2, 1)
  m <- m |>
    leaflet::addCircleMarkers(data = pts, radius = rad, weight = wgt, fillOpacity = 0.8,
                              color = pt_pal(pt_labels), fillColor = pt_pal(pt_labels),
                              popup = pt_popups, group = "Network Nodes") |>
    leaflet::addLegend("topright", pal = pt_pal, values = pt_labels, title = "Node Type") |>
    leaflet::addLayersControl(
      baseGroups = c("Light", "Streets & Buildings", "Satellite", "Topographic"),
      overlayGroups = c("Rivers", "Lakes", "Network Nodes"),
      options = leaflet::layersControlOptions(collapsed = TRUE)
    )

  html_path <- file.path(plots_dir, "interactive_network_map.html")
  lib_path <- file.path(plots_dir, "interactive_network_map_files")
  if (dir.exists(lib_path)) unlink(lib_path, recursive = TRUE, force = TRUE)
  htmlwidgets::saveWidget(m, html_path, selfcontained = FALSE, libdir = lib_path)
  message("Fallback network map saved to: ", html_path)
  invisible(html_path)
}
