ePieVisualizationStyle <- function() {
  list(
    colors = list(
      basin_fill = "#d9d9d9",
      basin_border = "#2b2b2b",
      river = "#2171b5",
      canal = "#00bcd4",
      lake_fill = "#6baed6",
      lake_border = "#2171b5",
      source_fill = "#e31a1c",
      source_outline = "#8b0000"
    ),
    concentration_palette = c("#4B0055", "#105188", "#009297", "#00C278", "#CDE030", "#FDE333"),
    line_widths = list(
      basin = 1.5,
      river = 2,
      canal = 3,
      fallback_river = 1.5,
      fallback_canal = 2.5,
      lake = 1
    ),
    point_sizes = list(
      concentration = 3,
      source = 5,
      concentration_tmap = 0.28,
      source_tmap = 0.55
    ),
    fill_opacity = list(
      basin = 0.1,
      lake = 0.4,
      concentration = 0.7,
      source = 1
    ),
    overlay_groups = c("Basin", "Rivers", "Canals", "Lakes", "Sources", "Concentrations"),
    base_groups = c("Light", "Streets & Buildings", "Satellite", "Topographic")
  )
}

readVisualizationLayer <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return(NULL)
  }
  tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
}

normalizePolygonLayer <- function(layer) {
  if (is.null(layer) || nrow(layer) == 0) {
    return(layer)
  }

  layer <- sf::st_transform(sf::st_make_valid(layer), crs = 4326)
  geom_types <- unique(as.character(sf::st_geometry_type(layer)))
  if ("GEOMETRYCOLLECTION" %in% geom_types) {
    layer <- tryCatch(
      sf::st_collection_extract(layer, "POLYGON"),
      error = function(e) layer
    )
  }
  if (nrow(layer) == 0) {
    return(NULL)
  }
  layer
}

normalizeLineLayer <- function(layer) {
  if (is.null(layer) || nrow(layer) == 0) {
    return(layer)
  }

  layer <- sf::st_transform(sf::st_zm(layer), crs = 4326)
  layer <- sf::st_make_valid(layer)
  geom_types <- unique(as.character(sf::st_geometry_type(layer)))
  if ("GEOMETRYCOLLECTION" %in% geom_types) {
    layer <- tryCatch(
      sf::st_collection_extract(layer, "LINESTRING"),
      error = function(e) layer
    )
  }
  if (nrow(layer) == 0) {
    return(NULL)
  }
  layer
}

buildTopologyEdges <- function(nodes) {
  required_cols <- c("ID", "ID_nxt", "x", "y")
  if (!all(required_cols %in% names(nodes))) {
    return(NULL)
  }

  valid_nodes <- nodes[!is.na(nodes$ID) & !is.na(nodes$x) & !is.na(nodes$y), , drop = FALSE]
  if (nrow(valid_nodes) == 0) {
    return(NULL)
  }

  downstream_idx <- match(valid_nodes$ID_nxt, valid_nodes$ID)
  edge_idx <- which(!is.na(valid_nodes$ID_nxt) & !is.na(downstream_idx))
  if (length(edge_idx) == 0) {
    return(NULL)
  }

  edge_dx <- valid_nodes$x[edge_idx] - valid_nodes$x[downstream_idx[edge_idx]]
  edge_dy <- valid_nodes$y[edge_idx] - valid_nodes$y[downstream_idx[edge_idx]]
  edge_dist <- sqrt(edge_dx^2 + edge_dy^2)
  keep_edges <- is.finite(edge_dist) & edge_dist > 1e-12
  edge_idx <- edge_idx[keep_edges]
  edge_dist <- edge_dist[keep_edges]
  if (length(edge_idx) == 0) {
    return(NULL)
  }

  edge_geoms <- lapply(edge_idx, function(i) {
    j <- downstream_idx[i]
    sf::st_linestring(matrix(
      c(valid_nodes$x[i], valid_nodes$x[j], valid_nodes$y[i], valid_nodes$y[j]),
      ncol = 2
    ))
  })

  edge_df <- data.frame(
    from_id = valid_nodes$ID[edge_idx],
    to_id = valid_nodes$ID_nxt[edge_idx],
    dist_deg = edge_dist,
    stringsAsFactors = FALSE
  )

  from_type <- if ("pt_type" %in% names(valid_nodes)) valid_nodes$pt_type[edge_idx] else NA_character_
  to_type <- if ("pt_type" %in% names(valid_nodes)) valid_nodes$pt_type[downstream_idx[edge_idx]] else NA_character_
  logical_types <- c("agglomeration", "agglomeration_lake", "WWTP", "LakeInlet", "LakeOutlet")
  edge_df$from_type <- from_type
  edge_df$to_type <- to_type
  edge_df$is_logical_connector <- (
    edge_df$from_type %in% logical_types |
      edge_df$to_type %in% logical_types |
      grepl("^Lake(In|Out)_", edge_df$from_id) |
      grepl("^Lake(In|Out)_", edge_df$to_id)
  )

  if ("is_canal" %in% names(valid_nodes)) {
    edge_df$is_canal <- as.logical(valid_nodes$is_canal[edge_idx])
    edge_df$is_canal[is.na(edge_df$is_canal)] <- FALSE
  } else {
    edge_df$is_canal <- FALSE
  }

  sf::st_as_sf(edge_df, geometry = sf::st_sfc(edge_geoms, crs = 4326))
}

splitRiverAndCanalLayers <- function(layer) {
  if (is.null(layer) || nrow(layer) == 0) {
    return(list(rivers = NULL, canals = NULL))
  }

  layer <- normalizeLineLayer(layer)
  if (is.null(layer) || nrow(layer) == 0) {
    return(list(rivers = NULL, canals = NULL))
  }
  if (!"is_canal" %in% names(layer)) {
    return(list(rivers = layer, canals = NULL))
  }

  if ("is_logical_connector" %in% names(layer)) {
    layer <- layer[!is.na(layer$is_logical_connector) & !layer$is_logical_connector, , drop = FALSE]
    if (nrow(layer) == 0) {
      return(list(rivers = NULL, canals = NULL))
    }
  }

  canal_mask <- !is.na(layer$is_canal) & as.logical(layer$is_canal)
  list(
    rivers = layer[!canal_mask, ],
    canals = layer[canal_mask, ]
  )
}

createConcentrationPopupHtml <- function(map_data, units) {
  getv <- function(name) {
    if (name %in% names(map_data)) map_data[[name]] else rep(NA, nrow(map_data))
  }

  basin_vals <- if ("basin_id" %in% names(map_data)) getv("basin_id") else getv("basin_ID")
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

BuildConcentrationMapSpec <- function(simulation_results,
                                      input_paths = list(),
                                      target_substance = NULL,
                                      basin_id = NULL,
                                      substance_type = "chemical",
                                      pathogen_name = NULL,
                                      pathogen_units = NULL) {
  nodes_df <- if (is.data.frame(simulation_results)) {
    simulation_results
  } else if ("pts_env" %in% names(simulation_results)) {
    simulation_results$pts_env
  } else if ("simulation_results" %in% names(simulation_results)) {
    simulation_results$simulation_results
  } else {
    warning("Valid simulation nodes data frame not found. Skipping visualization.")
    return(NULL)
  }

  nodes_df$x <- as.numeric(nodes_df$x)
  nodes_df$y <- as.numeric(nodes_df$y)
  concentration_nodes_sf <- sf::st_as_sf(nodes_df, coords = c("x", "y"), crs = 4326, remove = FALSE)

  rivers_layer <- NULL
  if ("rivers" %in% names(input_paths)) {
    rivers_layer <- readVisualizationLayer(input_paths$rivers)
  }
  split_layers <- splitRiverAndCanalLayers(rivers_layer)

  lakes_path <- if ("lakes" %in% names(input_paths)) input_paths$lakes else NULL
  if (is.null(lakes_path) && !is.null(input_paths$rivers)) {
    potential_path <- file.path(dirname(input_paths$rivers), "network_lakes.shp")
    if (file.exists(potential_path)) {
      lakes_path <- potential_path
    }
  }

  basin_path <- if ("basin" %in% names(input_paths)) input_paths$basin else NULL
  basin_shp <- normalizePolygonLayer(readVisualizationLayer(basin_path))
  lakes <- normalizePolygonLayer(readVisualizationLayer(lakes_path))

  topology_edges <- buildTopologyEdges(nodes_df)
  topology_split <- if (is.null(topology_edges) || nrow(topology_edges) == 0) {
    list(rivers = NULL, canals = NULL)
  } else {
    splitRiverAndCanalLayers(topology_edges)
  }

  source_mask <- tolower(concentration_nodes_sf$Pt_type) %in% c("agglomeration", "agglomerations", "wwtp")
  source_mask[is.na(source_mask)] <- FALSE
  emission_nodes_sf <- concentration_nodes_sf[source_mask, , drop = FALSE]

  units <- if (substance_type == "pathogen") {
    if (!is.null(pathogen_units)) pathogen_units else "oocysts/L"
  } else {
    "\u00b5g/L"
  }
  display_substance <- if (substance_type == "pathogen" && !is.null(pathogen_name)) {
    pathogen_name
  } else {
    target_substance
  }
  basin_label <- if (!is.null(basin_id)) basin_id else "Unknown"
  legend_title <- paste0(display_substance, " (", units, ")")
  style <- ePieVisualizationStyle()

  concentration_nodes_sf$popup_html <- createConcentrationPopupHtml(concentration_nodes_sf, units)
  if (nrow(emission_nodes_sf) > 0) {
    emission_nodes_sf$popup_html <- createConcentrationPopupHtml(emission_nodes_sf, units)
  }

  has_fallback_lines <- (!is.null(split_layers$rivers) && nrow(split_layers$rivers) > 0) ||
    (!is.null(split_layers$canals) && nrow(split_layers$canals) > 0)

  # Prefer authoritative river/canal geometry when available.
  # Topology edges remain the fallback for runs missing line shapefiles.
  rivers_layer_final <- if (has_fallback_lines) split_layers$rivers else topology_split$rivers
  canals_layer_final <- if (has_fallback_lines) split_layers$canals else topology_split$canals

  list(
    style = style,
    basin = basin_shp,
    lakes = lakes,
    fallback_rivers = split_layers$rivers,
    fallback_canals = split_layers$canals,
    topology_edges = topology_edges,
    rivers = rivers_layer_final,
    canals = canals_layer_final,
    concentration_nodes = concentration_nodes_sf,
    source_nodes = emission_nodes_sf,
    concentration_nodes_plot = concentration_nodes_sf[!is.na(concentration_nodes_sf$C_w), , drop = FALSE],
    layer_source = if (has_fallback_lines) "fallback" else if (!is.null(topology_edges) && nrow(topology_edges) > 0) "topology" else "none",
    display_substance = display_substance,
    units = units,
    basin_label = basin_label,
    legend_title = legend_title,
    map_title_html = paste0(
      "<b>Substance:</b> ", display_substance, " (", units, ")<br>",
      "<b>Basin:</b> ", basin_label, "<br>",
      "<small>Generated: ", format(Sys.Date(), "%Y-%m-%d"), " | ",
      "Basemap: check attribution in bottom-right corner</small>"
    ),
    map_title_text = paste(display_substance, "-", basin_label)
  )
}
