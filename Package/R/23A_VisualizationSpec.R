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
    concentration_palette = c("#2C7BB6", "#00A6A6", "#1A9850", "#FFD92F", "#F46D43", "#B2182B", "#762A83"),
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

buildTopologyEdges <- function(nodes, transport_edges = NULL) {
  if (!is.null(transport_edges) && nrow(transport_edges) > 0) {
    edge_sf <- TransportEdgesToSf(transport_edges, nodes)
    if (!is.null(edge_sf) && nrow(edge_sf) > 0) {
      return(edge_sf)
    }
  }

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
  pathogen_direct_lines <- if ("f_pathogen_direct" %in% names(map_data)) {
    direct_vals <- suppressWarnings(as.numeric(getv("f_pathogen_direct")))
    direct_vals <- ifelse(is.na(direct_vals), 0, direct_vals)
    sprintf("<b>Pathogen direct fraction:</b> %7.3f<br/>", direct_vals)
  } else {
    rep("", nrow(map_data))
  }

  sprintf(
    paste0(
      "<b>ID:</b> %s<br/>",
      "<b>Type:</b> %s<br/>",
      "<b>Basin:</b> %s<br/>",
      "<b>ID_nxt:</b> %s<br/>",
      "<b>Q:</b> %7.3f m3/s<br/>",
      "<b>C_w:</b> %7.3e %s<br/>",
      "<b>WWTP removal:</b> %7.4f<br/>",
      "%s",
      "<b>Total population:</b> %.0f"
    ),
    ids, types, basins, next_ids, qs, cw, units, removals,
    pathogen_direct_lines, pops
  )
}

createConcentrationSegmentPopupHtml <- function(segment_data, units) {
  getv <- function(name) {
    if (name %in% names(segment_data)) segment_data[[name]] else rep(NA, nrow(segment_data))
  }

  from_ids <- ifelse(is.na(getv("from_id")), "", as.character(getv("from_id")))
  to_ids <- ifelse(is.na(getv("to_id")), "", as.character(getv("to_id")))
  edge_types <- ifelse(is.na(getv("edge_type")), "", as.character(getv("edge_type")))
  is_canal <- ifelse(is.na(getv("is_canal")), FALSE, as.logical(getv("is_canal")))
  c_w <- ifelse(is.na(getv("C_w")), 0, as.numeric(getv("C_w")))
  q_vals <- ifelse(is.na(getv("Q_segment_m3s")), NA_real_, as.numeric(getv("Q_segment_m3s")))
  dist_vals <- ifelse(is.na(getv("dist_m")), NA_real_, as.numeric(getv("dist_m")))

  sprintf(
    paste0(
      "<b>From:</b> %s<br/>",
      "<b>To:</b> %s<br/>",
      "<b>Edge type:</b> %s<br/>",
      "<b>Canal:</b> %s<br/>",
      "<b>C_w:</b> %7.3e %s<br/>",
      "<b>Q:</b> %7.3f m3/s<br/>",
      "<b>Distance:</b> %7.1f m"
    ),
    from_ids, to_ids, edge_types, ifelse(is_canal, "TRUE", "FALSE"),
    c_w, units, q_vals, dist_vals
  )
}

buildConcentrationSegments <- function(nodes_df, edge_sf, units) {
  if (is.null(edge_sf) || nrow(edge_sf) == 0 ||
      !all(c("ID", "C_w", "C_w_map") %in% names(nodes_df)) ||
      !all(c("from_id", "to_id") %in% names(edge_sf))) {
    return(NULL)
  }

  segments <- edge_sf
  from_idx <- match(segments$from_id, nodes_df$ID)
  to_idx <- match(segments$to_id, nodes_df$ID)
  keep <- !is.na(from_idx) & !is.na(to_idx)
  if ("dist_m" %in% names(segments)) {
    dist_vals <- suppressWarnings(as.numeric(segments$dist_m))
    keep <- keep & (is.na(dist_vals) | !is.finite(dist_vals) | dist_vals > 0)
  }
  if (!any(keep)) {
    return(NULL)
  }

  segments <- segments[keep, , drop = FALSE]
  from_idx <- from_idx[keep]

  if (!"edge_type" %in% names(segments)) segments$edge_type <- "reach"
  if (!"is_canal" %in% names(segments)) {
    segments$is_canal <- if ("is_canal" %in% names(nodes_df)) as.logical(nodes_df$is_canal[from_idx]) else FALSE
  }
  segments$is_canal[is.na(segments$is_canal)] <- FALSE

  if (!"dist_m" %in% names(segments)) segments$dist_m <- NA_real_

  q_from_edge <- if ("Q_from_m3s" %in% names(segments)) {
    suppressWarnings(as.numeric(segments$Q_from_m3s))
  } else {
    rep(NA_real_, nrow(segments))
  }
  q_from_node <- if ("Q" %in% names(nodes_df)) {
    suppressWarnings(as.numeric(nodes_df$Q[from_idx]))
  } else {
    rep(NA_real_, nrow(segments))
  }

  segments$C_w <- suppressWarnings(as.numeric(nodes_df$C_w[from_idx]))
  segments$C_w_map <- suppressWarnings(as.numeric(nodes_df$C_w_map[from_idx]))
  segments$Q_segment_m3s <- ifelse(is.na(q_from_edge), q_from_node, q_from_edge)
  segments$segment_value_source <- "upstream_node_C_w"
  segments$segment_weight <- ifelse(segments$is_canal, 5, 4)
  segments$popup_html <- createConcentrationSegmentPopupHtml(segments, units)

  segments
}

inferPathogenUnits <- function(nodes_df, pathogen_name = NULL, pathogen_units = NULL) {
  if (!is.null(pathogen_units) && length(pathogen_units) > 0 && !is.na(pathogen_units[[1]]) && nzchar(pathogen_units[[1]])) {
    return(as.character(pathogen_units[[1]]))
  }
  if ("concentration_units" %in% names(nodes_df)) {
    units <- unique(stats::na.omit(as.character(nodes_df$concentration_units)))
    units <- units[nzchar(units)]
    if (length(units) > 0) return(units[1])
  }
  if (!is.null(pathogen_name) && length(pathogen_name) > 0 && !is.na(pathogen_name[[1]]) && nzchar(pathogen_name[[1]])) {
    units <- tryCatch({
      params <- LoadPathogenParameters(as.character(pathogen_name[[1]]))
      if (!is.null(params$units)) as.character(params$units) else NA_character_
    }, error = function(e) NA_character_)
    if (!is.na(units) && nzchar(units)) return(units)
  }
  "pathogen units/L"
}

readRunProvenanceForMap <- function(run_output_dir) {
  path <- if (!is.null(run_output_dir)) file.path(run_output_dir, "run_provenance_summary.csv") else NULL
  if (is.null(path) || !file.exists(path)) return(list())
  prov <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(prov) || !all(c("key", "value") %in% names(prov))) return(list())
  stats::setNames(as.list(prov$value), prov$key)
}

enrichConcentrationNodesFromNetwork <- function(nodes_df, input_paths = list()) {
  pts_path <- if (!is.null(input_paths) && "pts" %in% names(input_paths)) input_paths$pts else NULL
  if (is.null(pts_path) || !file.exists(pts_path) || !("ID" %in% names(nodes_df))) {
    return(nodes_df)
  }

  network_nodes <- tryCatch(read.csv(pts_path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(network_nodes) || !("ID" %in% names(network_nodes))) {
    return(nodes_df)
  }

  display_cols <- intersect(
    c(
      "total_population", "Inh", "uwwLoadEnt", "uwwCapacit", "f_STP",
      "f_pathogen_direct", "uwwPrimary", "uwwSeconda", "display_pt_type",
      "junction_role"
    ),
    names(network_nodes)
  )
  if (length(display_cols) == 0) {
    return(nodes_df)
  }

  match_idx <- match(nodes_df$ID, network_nodes$ID)
  for (col in display_cols) {
    source_vals <- network_nodes[[col]][match_idx]
    if (!(col %in% names(nodes_df))) {
      nodes_df[[col]] <- source_vals
    } else {
      if (is.numeric(nodes_df[[col]]) || is.integer(nodes_df[[col]])) {
        use_source <- is.na(nodes_df[[col]]) & !is.na(source_vals)
      } else {
        use_source <- (is.na(nodes_df[[col]]) | !nzchar(as.character(nodes_df[[col]]))) & !is.na(source_vals)
      }
      nodes_df[[col]][use_source] <- source_vals[use_source]
    }
  }

  nodes_df
}

firstNonEmptyMapValue <- function(..., default = "") {
  values <- unlist(list(...), use.names = FALSE)
  values <- unique(stats::na.omit(as.character(values)))
  values <- values[nzchar(values)]
  if (length(values) == 0) default else values[1]
}

BuildConcentrationMapSpec <- function(simulation_results,
                                      run_output_dir = NULL,
                                      input_paths = list(),
                                      target_substance = NULL,
                                      basin_id = NULL,
                                      substance_type = "chemical",
                                      pathogen_name = NULL,
                                      pathogen_units = NULL,
                                      map_scale = "auto",
                                      map_variant = NULL,
                                      binned_breaks = NULL,
                                      binned_labels = NULL,
                                      write_legacy_map = TRUE,
                                      provenance_label_mode = "concise_visible") {
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

  nodes_df <- enrichConcentrationNodesFromNetwork(nodes_df, input_paths = input_paths)

  nodes_df$x <- as.numeric(nodes_df$x)
  nodes_df$y <- as.numeric(nodes_df$y)
  nodes_df$C_w <- as.numeric(nodes_df$C_w)

  is_pathogen_map <- identical(substance_type, "pathogen")
  units <- if (is_pathogen_map) {
    inferPathogenUnits(nodes_df, pathogen_name = pathogen_name, pathogen_units = pathogen_units)
  } else {
    "\u00b5g/L"
  }

  # Pathogen values commonly span many orders of magnitude. Map variants make
  # the scale explicit while popups and output tables keep original units.
  nodes_df$C_w_map <- nodes_df$C_w
  requested_scale <- if (is.null(map_scale) || length(map_scale) == 0) "auto" else tolower(as.character(map_scale[[1]]))
  if (requested_scale == "log") requested_scale <- "log10"
  if (!requested_scale %in% c("auto", "linear", "log10")) requested_scale <- "auto"
  active_map_scale <- "linear"
  if (identical(requested_scale, "log10") || (identical(requested_scale, "auto") && is_pathogen_map)) {
    nodes_df$C_w_map <- NA_real_
    positive_cw <- is.finite(nodes_df$C_w) & nodes_df$C_w > 0
    if (any(positive_cw)) {
      nodes_df$C_w_map[positive_cw] <- log10(nodes_df$C_w[positive_cw])
      log_floor <- min(nodes_df$C_w_map[positive_cw], na.rm = TRUE) - 1
      zero_cw <- is.finite(nodes_df$C_w) & nodes_df$C_w <= 0
      nodes_df$C_w_map[zero_cw] <- log_floor
      active_map_scale <- "log10"
    }
  }

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

  transport_edges <- NULL
  if (!is.null(run_output_dir)) {
    transport_path <- file.path(run_output_dir, "transport_edges.csv")
    if (file.exists(transport_path)) {
      transport_edges <- tryCatch(
        read.csv(transport_path, stringsAsFactors = FALSE),
        error = function(e) NULL
      )
    }
  }

  topology_edges <- buildTopologyEdges(nodes_df, transport_edges = transport_edges)
  topology_split <- if (is.null(topology_edges) || nrow(topology_edges) == 0) {
    list(rivers = NULL, canals = NULL)
  } else {
    splitRiverAndCanalLayers(topology_edges)
  }
  concentration_segments <- buildConcentrationSegments(nodes_df, topology_edges, units)

  source_mask <- tolower(concentration_nodes_sf$Pt_type) %in% c("agglomeration", "agglomerations", "wwtp")
  source_mask[is.na(source_mask)] <- FALSE
  emission_nodes_sf <- concentration_nodes_sf[source_mask, , drop = FALSE]

  display_substance <- if (substance_type == "pathogen" && !is.null(pathogen_name)) {
    pathogen_name
  } else {
    target_substance
  }
  basin_label <- if (!is.null(basin_id)) basin_id else "Unknown"
  legend_units <- if (identical(active_map_scale, "log10")) paste0(units, ", log scale") else units
  legend_title <- paste0(display_substance, " (", legend_units, ")")
  style <- ePieVisualizationStyle()
  provenance <- readRunProvenanceForMap(run_output_dir)
  q_source_label <- firstNonEmptyMapValue(
    provenance$canal_q_reference_short,
    if ("Q_reference_short" %in% names(nodes_df)) nodes_df$Q_reference_short else NULL,
    default = "not applicable"
  )
  q_regime <- firstNonEmptyMapValue(
    provenance$canal_q_regime,
    if ("Q_regime" %in% names(nodes_df)) nodes_df$Q_regime else NULL,
    default = "not specified"
  )
  q_period <- firstNonEmptyMapValue(
    provenance$canal_q_data_period,
    if ("Q_data_period" %in% names(nodes_df)) nodes_df$Q_data_period else NULL,
    default = "unknown period"
  )
  pathogen_profile_label <- firstNonEmptyMapValue(
    provenance$pathogen_profile_label,
    if ("pathogen_profile_label" %in% names(nodes_df)) nodes_df$pathogen_profile_label else NULL,
    default = ""
  )
  pathogen_profile_region <- firstNonEmptyMapValue(
    provenance$pathogen_profile_region,
    if ("pathogen_profile_region" %in% names(nodes_df)) nodes_df$pathogen_profile_region else NULL,
    default = ""
  )
  pathogen_profile_line <- if (is_pathogen_map && nzchar(pathogen_profile_label)) {
    paste0("<b>Pathogen profile:</b> ", pathogen_profile_label,
           if (nzchar(pathogen_profile_region)) paste0(" | ", pathogen_profile_region) else "",
           "<br>")
  } else {
    ""
  }
  scale_label <- if (identical(active_map_scale, "log10")) "log10" else "linear"
  variant_label <- if (!is.null(map_variant) && nzchar(as.character(map_variant))) as.character(map_variant) else scale_label
  display_scale_label <- if (!identical(variant_label, scale_label)) variant_label else scale_label
  binned_scale <- if (identical(variant_label, "linear_binned")) {
    binned_values <- if (!is.null(concentration_segments) && nrow(concentration_segments) > 0 &&
                         "C_w" %in% names(concentration_segments)) {
      concentration_segments$C_w
    } else {
      nodes_df$C_w
    }
    BuildConcentrationBinnedScale(
      binned_values,
      breaks = binned_breaks,
      labels = binned_labels
    )
  } else {
    NULL
  }

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
    concentration_segments = concentration_segments,
    concentration_segments_plot = if (!is.null(concentration_segments) && nrow(concentration_segments) > 0) {
      concentration_segments[is.finite(concentration_segments$C_w_map), , drop = FALSE]
    } else {
      NULL
    },
    concentration_nodes = concentration_nodes_sf,
    source_nodes = emission_nodes_sf,
    concentration_nodes_plot = concentration_nodes_sf[!is.na(concentration_nodes_sf$C_w_map), , drop = FALSE],
    layer_source = if (has_fallback_lines) "fallback" else if (!is.null(topology_edges) && nrow(topology_edges) > 0) "topology" else "none",
    display_substance = display_substance,
    units = units,
    map_scale = active_map_scale,
    map_variant = variant_label,
    binned_scale = binned_scale,
    map_value_column = "C_w_map",
    map_filename = paste0("concentration_map_", variant_label, ".html"),
    segment_map_filename = paste0("concentration_segments_map_", variant_label, ".html"),
    static_map_filename = paste0("static_concentration_map_", variant_label, ".png"),
    write_legacy_map = isTRUE(write_legacy_map),
    basin_label = basin_label,
    legend_title = legend_title,
    map_title_html = paste0(
      "<b>Substance:</b> ", display_substance, " (", units, ")<br>",
      "<b>Basin:</b> ", basin_label, "<br>",
      "<b>Scale:</b> ", display_scale_label, "<br>",
      pathogen_profile_line,
      "<b>Canal Q:</b> ", q_source_label, " | ", q_regime, " | ", q_period, "<br>",
      "<small>Generated: ", format(Sys.Date(), "%Y-%m-%d"), " | ",
      "Basemap: check attribution in bottom-right corner</small>"
    ),
    map_title_text = paste(display_substance, "-", basin_label, "-", display_scale_label)
  )
}
