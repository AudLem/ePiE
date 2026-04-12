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

  rivers <- natural_rivers
  if (is.null(rivers)) rivers <- hydro_sheds_rivers_basin

  canals <- artificial_canals
  if (is.null(canals) && !is.null(rivers) && "is_canal" %in% names(rivers)) {
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

  safe_mapview <- function(obj, name, ...) {
    if (is.null(obj) || nrow(obj) == 0) {
      message("    - Layer '", name, "' is empty. Skipping.")
      return(NULL)
    }
    obj <- sf::st_zm(obj)
    obj <- sf::st_make_valid(obj)
    obj <- obj[!sf::st_is_empty(obj), ]
    if (nrow(obj) == 0) return(NULL)
    message("    - Adding layer '", name, "' (", nrow(obj), " features)")
    tryCatch({
      mapview::mapview(obj, layer.name = name, ...)
    }, error = function(e) {
      message("    ! Error adding layer '", name, "': ", e$message)
      NULL
    })
  }

  lake_outlets <- if (!is.null(points) && "lake_out" %in% names(points)) points[points$lake_out == 1, ] else NULL

  m_basin <- safe_mapview(Basin, "Basin", color = "black", col.regions = "grey", alpha.regions = 0.05)
  m <- if (is.null(m_basin)) mapview::mapview() else m_basin

  m_riv <- safe_mapview(rivers, "Natural Rivers", color = "blue", lwd = 2)
  if (!is.null(m_riv)) m <- m + m_riv

  m_can <- safe_mapview(canals, "Artificial Canals", color = "cyan", lwd = 3)
  if (!is.null(m_can)) m <- m + m_can

  m_lak <- safe_mapview(lakes, "Lakes", color = "royalblue", col.regions = "royalblue", alpha.regions = 0.4)
  if (!is.null(m_lak)) m <- m + m_lak

  m_pts <- safe_mapview(points, "Network Nodes", zcol = "pt_type")
  if (!is.null(m_pts)) m <- m + m_pts

  m_out <- safe_mapview(lake_outlets, "Lake Outlets (Hydro_Lake)", col.regions = "darkblue", cex = 4)
  if (!is.null(m_out)) m <- m + m_out

  if (!is.null(agglomerations) && nrow(agglomerations) > 0) {
    if ("node_type" %in% names(agglomerations)) {
      m_agg <- safe_mapview(agglomerations, "Agglomerations", zcol = "node_type", cex = 3)
    } else {
      m_agg <- safe_mapview(agglomerations, "Agglomerations", col.regions = "red", cex = 3)
    }
    if (!is.null(m_agg)) m <- m + m_agg
  }

  map_title <- paste0("<b>Basin:</b> ", basin_id)
  tag_title <- htmltools::tags$div(
    htmltools::HTML(map_title),
    style = "background: white; padding: 10px; border-radius: 5px; box-shadow: 0 0 15px rgba(0,0,0,0.2);"
  )
  m@map <- m@map |>
    leaflet::addControl(html = tag_title, position = "topleft")

  interactive_map_path <- file.path(plots_dir, "interactive_network_map.html")
  interactive_map_libdir <- file.path(plots_dir, "interactive_network_map_files")
  if (dir.exists(interactive_map_libdir)) unlink(interactive_map_libdir, recursive = TRUE, force = TRUE)
  tryCatch(
    {
      htmlwidgets::saveWidget(widget = m@map, file = interactive_map_path, selfcontained = TRUE)
    },
    error = function(e) {
      message("Note: self-contained export failed (", e$message, "). Falling back to sidecar HTML export.")
      tryCatch(
        {
          htmlwidgets::saveWidget(widget = m@map, file = interactive_map_path, selfcontained = FALSE, libdir = interactive_map_libdir)
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
