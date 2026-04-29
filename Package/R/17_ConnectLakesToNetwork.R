#' Connect Lakes to Network
#'
#' Creates explicit lake inlet and outlet node pairs only for lakes with
#' credible directed river crossings. LakeIn and LakeOut nodes are placed on
#' lake boundaries; centroid fallback is intentionally forbidden because it
#' creates false hydraulic connections.
#'
#' @param points sf object. Network point nodes.
#' @param HL_basin sf object. In-basin lake polygons.
#' @param verbose Logical. Show detailed per-lake diagnostics.
#' @param transport_edges Optional edge table used for crossing detection.
#' @param lake_snap_tolerance_m Numeric. Diagnostic near-miss tolerance.
#' @param lake_snap_enabled Logical. Reserved for future explicit snapping.
#' @param lake_use_pour_point Logical. Prefer HydroLAKES pour point proximity
#'   when selecting among multiple exact outlets.
#' @param lake_require_inlet_and_outlet Logical. Require both for activation.
#' @return A named list with updated `points`, `lake_connections`, and
#'   `lake_connection_diagnostics`.
#' @export
ConnectLakesToNetwork <- function(points,
                                  HL_basin,
                                  verbose = TRUE,
                                  transport_edges = NULL,
                                  lake_snap_tolerance_m = 250,
                                  lake_snap_enabled = FALSE,
                                  lake_use_pour_point = TRUE,
                                  lake_require_inlet_and_outlet = TRUE) {
  message("--- Step 8b: Establishing Lake Connectivity ---")

  empty_connections <- function() {
    data.frame(
      Hylak_id = integer(0),
      lake_in_id = character(0),
      lake_out_id = character(0),
      inlet_upstream_id = character(0),
      outlet_downstream_id = character(0),
      inlet_x = numeric(0),
      inlet_y = numeric(0),
      outlet_x = numeric(0),
      outlet_y = numeric(0),
      crossing_method = character(0),
      inlet_snap_distance_m = numeric(0),
      outlet_snap_distance_m = numeric(0),
      confidence = character(0),
      n_inlets = integer(0),
      n_outlets = integer(0),
      stringsAsFactors = FALSE
    )
  }

  empty_diagnostics <- function() {
    data.frame(
      Hylak_id = integer(0),
      lake_name = character(0),
      active = logical(0),
      reason = character(0),
      exact_inlets = integer(0),
      exact_outlets = integer(0),
      tangential = integer(0),
      internal = integer(0),
      interior_nodes = integer(0),
      source_nodes_inside = integer(0),
      nearest_river_distance_m = numeric(0),
      stringsAsFactors = FALSE
    )
  }

  if (is.null(HL_basin) || nrow(HL_basin) == 0) {
    message(">>> No lakes found. Skipping.")
    points$lake_in <- 0
    points$lake_out <- 0
    points$HL_ID_new <- 0
    return(list(
      points = points,
      lake_connections = empty_connections(),
      lake_connection_diagnostics = empty_diagnostics()
    ))
  }

  if (isTRUE(lake_snap_enabled)) {
    warning("lake_snap_enabled is reserved for a future explicit snapping mode; current lake activation remains exact-boundary only.")
  }

  HL_basin <- EnsureSameCrs(points, HL_basin, "points", "HL_basin")
  points$lake_in <- 0
  points$lake_out <- 0
  points$HL_ID_new <- 0
  if ("Hylak_id" %in% names(points)) points$Hylak_id <- 0

  point_lake_lookup <- sf::st_intersects(points, HL_basin)
  crossing_data <- DetectLakeSegmentCrossings(
    points = points,
    HL_basin = HL_basin,
    crossing_distance_threshold = 10,
    verbose = verbose,
    transport_edges = transport_edges,
    include_canals = FALSE
  )

  source_types <- c("agglomeration", "agglomeration_lake", "WWTP")
  new_nodes <- list()
  rewire_ops <- list()
  remove_ids <- character(0)
  connection_rows <- list()
  diagnostic_rows <- list()

  get_pt_type <- function(idx) {
    if ("pt_type" %in% names(points)) return(as.character(points$pt_type[idx]))
    if ("Pt_type" %in% names(points)) return(as.character(points$Pt_type[idx]))
    rep("node", length(idx))
  }

  nearest_river_distance <- function(lake_idx) {
    river_mask <- if ("is_canal" %in% names(points)) {
      is.na(points$is_canal) | points$is_canal == FALSE
    } else {
      rep(TRUE, nrow(points))
    }
    river_points <- points[river_mask, ]
    if (nrow(river_points) == 0) return(NA_real_)
    tryCatch({
      min(as.numeric(sf::st_distance(sf::st_boundary(HL_basin[lake_idx, ]), river_points)), na.rm = TRUE)
    }, error = function(e) NA_real_)
  }

  outlet_by_pour_point <- function(outlet_crossings, lake_idx) {
    if (!isTRUE(lake_use_pour_point) ||
        !all(c("Pour_long", "Pour_lat") %in% names(HL_basin)) ||
        any(is.na(c(HL_basin$Pour_long[lake_idx], HL_basin$Pour_lat[lake_idx])))) {
      return(NULL)
    }

    pour_pt <- sf::st_sfc(
      sf::st_point(c(HL_basin$Pour_long[lake_idx], HL_basin$Pour_lat[lake_idx])),
      crs = 4326
    )
    pour_pt <- sf::st_transform(pour_pt, sf::st_crs(points))
    outlet_pts <- sf::st_as_sf(
      outlet_crossings,
      coords = c("crossing_x", "crossing_y"),
      crs = sf::st_crs(points),
      remove = FALSE
    )
    d <- as.numeric(sf::st_distance(outlet_pts, pour_pt))
    outlet_crossings[which.min(d), , drop = FALSE]
  }

  select_primary_outlet <- function(outlet_crossings, lake_idx) {
    by_pour <- outlet_by_pour_point(outlet_crossings, lake_idx)
    if (!is.null(by_pour)) return(by_pour)

    outlet_lds <- points$LD[match(outlet_crossings$upstream_id, points$ID)]
    outlet_lds[is.na(outlet_lds)] <- Inf
    outlet_crossings[which.min(outlet_lds), , drop = FALSE]
  }

  make_lake_node <- function(id, coord, lake_id, type, next_id, lake_in, lake_out) {
    row <- points[1, ]
    row$ID <- id
    row$ID_nxt <- next_id
    row$geometry <- sf::st_sfc(sf::st_point(coord), crs = sf::st_crs(points))
    row$lake_in <- lake_in
    row$lake_out <- lake_out
    row$HL_ID_new <- lake_id
    if ("Hylak_id" %in% names(row)) row$Hylak_id <- lake_id
    if ("pt_type" %in% names(row)) row$pt_type <- type
    if ("Pt_type" %in% names(row)) row$Pt_type <- type
    if ("node_type" %in% names(row)) row$node_type <- type
    if ("is_canal" %in% names(row)) row$is_canal <- FALSE
    if ("total_population" %in% names(row)) row$total_population <- 0
    if ("x" %in% names(row)) row$x <- coord[1]
    if ("y" %in% names(row)) row$y <- coord[2]
    if ("X" %in% names(row)) row$X <- coord[1]
    if ("Y" %in% names(row)) row$Y <- coord[2]
    if ("LD" %in% names(row)) row$LD <- 0
    for (distance_col in intersect(c("d_nxt", "dist_nxt", "distance_to_next", "canal_d_nxt_m"), names(row))) {
      row[[distance_col]] <- NA_real_
    }
    for (canal_col in intersect(c("canal_id", "canal_name", "canal_pt_type", "Q_design_m3s", "Q_model_m3s"), names(row))) {
      row[[canal_col]] <- NA
    }
    row
  }

  recompute_link_distances <- function(pts) {
    if (is.null(pts) || nrow(pts) == 0 || !all(c("ID", "ID_nxt") %in% names(pts))) {
      return(pts)
    }
    pts_proj <- if (sf::st_is_longlat(pts)) sf::st_transform(pts, GetUtmCrs(pts)) else pts
    coords <- sf::st_coordinates(pts_proj)
    downstream_idx <- match(pts$ID_nxt, pts$ID)
    dist_m <- rep(0, nrow(pts))
    has_next <- !is.na(downstream_idx)
    if (any(has_next)) {
      dist_m[has_next] <- sqrt(
        (coords[has_next, 1] - coords[downstream_idx[has_next], 1])^2 +
          (coords[has_next, 2] - coords[downstream_idx[has_next], 2])^2
      )
    }
    for (distance_col in intersect(c("d_nxt", "dist_nxt", "distance_to_next"), names(pts))) {
      pts[[distance_col]] <- dist_m
    }
    pts
  }

  add_diagnostic <- function(lake_id, lake_name, active, reason, inlets, outlets,
                             tangential, internal, interior_nodes, source_inside,
                             nearest_dist) {
    diagnostic_rows[[length(diagnostic_rows) + 1L]] <<- data.frame(
      Hylak_id = lake_id,
      lake_name = lake_name,
      active = active,
      reason = reason,
      exact_inlets = inlets,
      exact_outlets = outlets,
      tangential = tangential,
      internal = internal,
      interior_nodes = interior_nodes,
      source_nodes_inside = source_inside,
      nearest_river_distance_m = nearest_dist,
      stringsAsFactors = FALSE
    )
  }

  for (lake_id in unique(HL_basin$Hylak_id)) {
    lake_idx <- match(lake_id, HL_basin$Hylak_id)
    lake_name <- if ("Lake_name" %in% names(HL_basin) && !is.na(HL_basin$Lake_name[lake_idx])) {
      as.character(HL_basin$Lake_name[lake_idx])
    } else {
      paste0("Lake_", lake_id)
    }

    in_this_lake <- which(lengths(point_lake_lookup) > 0 &
                            vapply(point_lake_lookup, function(x) lake_idx %in% x, logical(1)))
    source_inside <- in_this_lake[get_pt_type(in_this_lake) %in% source_types]
    interior_nodes <- setdiff(in_this_lake, source_inside)

    crossings <- crossing_data$crossings[crossing_data$crossings$Hylak_id == lake_id, , drop = FALSE]
    inlet_crossings <- crossings[crossings$crossing_type == "inlet", , drop = FALSE]
    outlet_crossings <- crossings[crossings$crossing_type == "outlet", , drop = FALSE]
    tangential_n <- sum(crossings$crossing_type == "tangential")
    internal_n <- sum(crossings$crossing_type == "internal")
    nearest_dist <- nearest_river_distance(lake_idx)

    has_required <- nrow(inlet_crossings) > 0 && nrow(outlet_crossings) > 0
    active <- if (isTRUE(lake_require_inlet_and_outlet)) has_required else nrow(crossings) > 0

    if (!active) {
      reason <- if (nrow(crossings) == 0) {
        if (is.na(nearest_dist)) {
          "no_river_candidate"
        } else if (nearest_dist > lake_snap_tolerance_m) {
          "near_miss_above_tolerance"
        } else {
          "no_inlet_no_outlet"
        }
      } else if (nrow(inlet_crossings) == 0 && nrow(outlet_crossings) == 0 && tangential_n > 0) {
        "tangential_only"
      } else if (nrow(inlet_crossings) == 0) {
        "no_inlet"
      } else if (nrow(outlet_crossings) == 0) {
        "no_outlet"
      } else {
        "inactive"
      }

      add_diagnostic(
        lake_id, lake_name, FALSE, reason, nrow(inlet_crossings), nrow(outlet_crossings),
        tangential_n, internal_n, length(interior_nodes), length(source_inside), nearest_dist
      )
      if (verbose) message(">>> ", lake_name, ": skipped (", reason, ")")
      next
    }

    inlet_lds <- points$LD[match(inlet_crossings$upstream_id, points$ID)]
    inlet_lds[is.na(inlet_lds)] <- -Inf
    inlet_crossings <- inlet_crossings[order(inlet_lds, decreasing = TRUE), , drop = FALSE]
    primary_outlet <- select_primary_outlet(outlet_crossings, lake_idx)
    lake_out_id <- paste0("LakeOut_", lake_id)
    outlet_coord <- c(primary_outlet$crossing_x, primary_outlet$crossing_y)
    downstream_id <- if (primary_outlet$downstream_id %in% points$ID) primary_outlet$downstream_id else NA_character_

    outlet_row <- make_lake_node(
      id = lake_out_id,
      coord = outlet_coord,
      lake_id = lake_id,
      type = "LakeOutlet",
      next_id = downstream_id,
      lake_in = 0,
      lake_out = 1
    )
    new_nodes[[length(new_nodes) + 1L]] <- outlet_row

    inlet_ids <- character(nrow(inlet_crossings))
    for (i in seq_len(nrow(inlet_crossings))) {
      lake_in_id <- if (i == 1L) paste0("LakeIn_", lake_id) else paste0("LakeIn_", lake_id, "_", sprintf("%02d", i))
      inlet_ids[i] <- lake_in_id
      inlet_coord <- c(inlet_crossings$crossing_x[i], inlet_crossings$crossing_y[i])
      inlet_row <- make_lake_node(
        id = lake_in_id,
        coord = inlet_coord,
        lake_id = lake_id,
        type = "LakeInlet",
        next_id = lake_out_id,
        lake_in = 1,
        lake_out = 0
      )
      new_nodes[[length(new_nodes) + 1L]] <- inlet_row
      rewire_ops[[inlet_crossings$upstream_id[i]]] <- lake_in_id

      connection_rows[[length(connection_rows) + 1L]] <- data.frame(
        Hylak_id = lake_id,
        lake_in_id = lake_in_id,
        lake_out_id = lake_out_id,
        inlet_upstream_id = inlet_crossings$upstream_id[i],
        outlet_downstream_id = downstream_id,
        inlet_x = inlet_coord[1],
        inlet_y = inlet_coord[2],
        outlet_x = outlet_coord[1],
        outlet_y = outlet_coord[2],
        crossing_method = inlet_crossings$crossing_method[i],
        inlet_snap_distance_m = inlet_crossings$snap_distance_m[i],
        outlet_snap_distance_m = primary_outlet$snap_distance_m,
        confidence = inlet_crossings$confidence[i],
        n_inlets = nrow(inlet_crossings),
        n_outlets = nrow(outlet_crossings),
        stringsAsFactors = FALSE
      )
    }

    if (length(source_inside) > 0) {
      for (si in source_inside) {
        rewire_ops[[points$ID[si]]] <- inlet_ids[1]
        points$HL_ID_new[si] <- lake_id
        if ("Hylak_id" %in% names(points)) points$Hylak_id[si] <- lake_id
      }
    }

    if (length(interior_nodes) > 0) {
      remove_ids <- c(remove_ids, points$ID[interior_nodes])
    }

    add_diagnostic(
      lake_id, lake_name, TRUE, "connected_exact", nrow(inlet_crossings), nrow(outlet_crossings),
      tangential_n, internal_n, length(interior_nodes), length(source_inside), nearest_dist
    )
  }

  for (fid in names(rewire_ops)) {
    points$ID_nxt[points$ID == fid] <- rewire_ops[[fid]]
  }

  points <- points[!points$ID %in% remove_ids, ]
  if (length(new_nodes) > 0) {
    points <- rbind(points, do.call(rbind, new_nodes))
  }
  points <- recompute_link_distances(points)

  lake_connections <- if (length(connection_rows) > 0) do.call(rbind, connection_rows) else empty_connections()
  lake_connection_diagnostics <- if (length(diagnostic_rows) > 0) do.call(rbind, diagnostic_rows) else empty_diagnostics()

  if (nrow(lake_connection_diagnostics) > 0) {
    message(">>> Lake connectivity summary:")
    message("    Connected lakes (exact inlet + outlet): ", sum(lake_connection_diagnostics$active))
    message("    Skipped lakes: ", sum(!lake_connection_diagnostics$active))
    if (verbose && any(!lake_connection_diagnostics$active)) {
      skipped <- lake_connection_diagnostics[!lake_connection_diagnostics$active, , drop = FALSE]
      for (i in seq_len(nrow(skipped))) {
        message(sprintf("      Hylak_id %-11s: %s", skipped$Hylak_id[i], skipped$reason[i]))
      }
    }
  }

  message(">>> Lake connectivity updated. Run topology rebuild.")
  list(
    points = points,
    lake_connections = lake_connections,
    lake_connection_diagnostics = lake_connection_diagnostics
  )
}
