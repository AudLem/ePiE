#' Detect Lake-River Segment Crossings
#'
#' Identifies directed river passages through lake polygons. Crossings are
#' computed in a projected CRS so boundary distances are in meters, then
#' returned in the original point CRS for downstream node creation.
#'
#' A true hydraulic lake connection requires at least one inlet and one outlet.
#' Tangential contacts are retained as diagnostics but must not create
#' LakeIn/LakeOut routing nodes.
#'
#' @param points sf object. Network point nodes with `ID`, `ID_nxt`, and
#'   geometry.
#' @param HL_basin sf object. Lake polygons.
#' @param crossing_distance_threshold numeric. Boundary tolerance in meters.
#' @param verbose Logical. Print diagnostic messages.
#' @param transport_edges Optional data.frame. Directed edge table to use
#'   instead of `ID_nxt` links when available.
#' @param include_canals Logical. Include canal edges in lake matching. Defaults
#'   to `FALSE` because KIS canals are independent from rivers/lakes.
#' @return A list with crossing rows and summary counts.
#' @family lake-connection
#' @export
DetectLakeSegmentCrossings <- function(points,
                                       HL_basin,
                                       crossing_distance_threshold = 10,
                                       verbose = TRUE,
                                       transport_edges = NULL,
                                       include_canals = FALSE) {
  message("--- Detecting Lake-River Segment Crossings ---")

  empty_crossings <- function() {
    data.frame(
      Hylak_id = integer(0),
      crossing_type = character(0),
      segment_crossing_class = character(0),
      upstream_id = character(0),
      downstream_id = character(0),
      crossing_x = numeric(0),
      crossing_y = numeric(0),
      entry_x = numeric(0),
      entry_y = numeric(0),
      exit_x = numeric(0),
      exit_y = numeric(0),
      distance_from_boundary = numeric(0),
      snap_distance_m = numeric(0),
      confidence = character(0),
      crossing_method = character(0),
      n_boundary_points = integer(0),
      stringsAsFactors = FALSE
    )
  }

  empty_result <- function(lakes_count = 0, segment_count = 0) {
    list(
      crossings = empty_crossings(),
      segment_count = segment_count,
      lakes_with_crossings = 0,
      lakes_without_crossings = lakes_count,
      tangential_crossings = 0
    )
  }

  if (is.null(points) || nrow(points) == 0) {
    message(">>> Empty points input. Returning empty result.")
    lakes_count <- if (!is.null(HL_basin) && nrow(HL_basin) > 0) nrow(HL_basin) else 0
    return(empty_result(lakes_count = lakes_count))
  }
  if (is.null(HL_basin) || nrow(HL_basin) == 0) {
    message(">>> No lakes found. Returning empty result.")
    return(empty_result())
  }
  if (is.null(sf::st_crs(points))) stop("Points object has no CRS. Please assign a coordinate reference system.")
  if (is.null(sf::st_crs(HL_basin))) stop("HL_basin object has no CRS. Please assign a coordinate reference system.")

  output_crs <- sf::st_crs(points)
  HL_basin <- EnsureSameCrs(points, HL_basin, "points", "HL_basin")

  work_points <- points
  work_lakes <- HL_basin
  if (sf::st_is_longlat(work_points)) {
    work_crs <- GetUtmCrs(work_points)
    work_points <- sf::st_transform(work_points, work_crs)
    work_lakes <- sf::st_transform(work_lakes, work_crs)
  }
  work_crs <- sf::st_crs(work_points)

  if (verbose) message(">>> Input: ", nrow(points), " points, ", nrow(HL_basin), " lakes")

  point_df <- sf::st_drop_geometry(work_points)
  if (!all(c("ID", "ID_nxt") %in% names(point_df))) {
    message(">>> Points do not contain ID/ID_nxt. Returning empty result.")
    return(empty_result(lakes_count = nrow(HL_basin)))
  }
  if (!("is_canal" %in% names(point_df))) point_df$is_canal <- FALSE

  make_line <- function(from_idx, to_idx) {
    from_xy <- sf::st_coordinates(work_points[from_idx, ])[1, 1:2]
    to_xy <- sf::st_coordinates(work_points[to_idx, ])[1, 1:2]
    sf::st_linestring(rbind(from_xy, to_xy))
  }

  edge_rows <- list()
  if (!is.null(transport_edges) && nrow(transport_edges) > 0 &&
      all(c("from_id", "to_id") %in% names(transport_edges))) {
    for (i in seq_len(nrow(transport_edges))) {
      from_idx <- match(transport_edges$from_id[i], point_df$ID)
      to_idx <- match(transport_edges$to_id[i], point_df$ID)
      if (is.na(from_idx) || is.na(to_idx)) next
      edge_is_canal <- isTRUE(point_df$is_canal[from_idx]) || isTRUE(point_df$is_canal[to_idx])
      if (!include_canals && edge_is_canal) next
      edge_rows[[length(edge_rows) + 1L]] <- data.frame(
        upstream_id = as.character(point_df$ID[from_idx]),
        downstream_id = as.character(point_df$ID[to_idx]),
        from_idx = from_idx,
        to_idx = to_idx,
        stringsAsFactors = FALSE
      )
    }
  } else {
    valid_next <- !is.na(point_df$ID_nxt) & point_df$ID_nxt != ""
    for (from_idx in which(valid_next)) {
      to_idx <- match(point_df$ID_nxt[from_idx], point_df$ID)
      if (is.na(to_idx)) next
      edge_is_canal <- isTRUE(point_df$is_canal[from_idx]) || isTRUE(point_df$is_canal[to_idx])
      if (!include_canals && edge_is_canal) next
      edge_rows[[length(edge_rows) + 1L]] <- data.frame(
        upstream_id = as.character(point_df$ID[from_idx]),
        downstream_id = as.character(point_df$ID[to_idx]),
        from_idx = from_idx,
        to_idx = to_idx,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(edge_rows) == 0) {
    message(">>> No valid river segments found. Returning empty result.")
    return(empty_result(lakes_count = nrow(HL_basin)))
  }

  edge_df <- do.call(rbind, edge_rows)
  segment_geometries <- lapply(seq_len(nrow(edge_df)), function(i) make_line(edge_df$from_idx[i], edge_df$to_idx[i]))
  segments_sf <- sf::st_sf(edge_df, geometry = sf::st_sfc(segment_geometries, crs = work_crs))
  segment_count <- nrow(segments_sf)
  if (verbose) message(">>> Created ", segment_count, " directed river segments")

  lake_boundaries <- sf::st_boundary(work_lakes)

  coords_from_geometry <- function(geom) {
    coords <- tryCatch(sf::st_coordinates(geom), error = function(e) NULL)
    if (is.null(coords) || nrow(coords) == 0) return(matrix(numeric(0), ncol = 2))
    coords <- as.matrix(coords[, 1:2, drop = FALSE])
    coords[!duplicated(paste(round(coords[, 1], 6), round(coords[, 2], 6))), , drop = FALSE]
  }

  order_coords_along_segment <- function(coords, segment_geom) {
    if (nrow(coords) <= 1) return(coords)
    seg_coords <- sf::st_coordinates(segment_geom)[, 1:2, drop = FALSE]
    start <- seg_coords[1, ]
    finish <- seg_coords[nrow(seg_coords), ]
    direction <- finish - start
    denom <- sum(direction^2)
    if (!is.finite(denom) || denom <= 0) return(coords)
    t <- ((coords[, 1] - start[1]) * direction[1] + (coords[, 2] - start[2]) * direction[2]) / denom
    coords[order(t), , drop = FALSE]
  }

  to_output_coord <- function(coord) {
    p <- sf::st_sfc(sf::st_point(coord), crs = work_crs)
    as.numeric(sf::st_coordinates(sf::st_transform(p, output_crs))[1, 1:2])
  }

  point_inside <- function(point_idx, lake_idx) {
    tryCatch({
      rel <- sf::st_within(work_points[point_idx, ], work_lakes[lake_idx, ])
      length(rel[[1]]) > 0
    }, error = function(e) FALSE)
  }

  inside_length_m <- function(segment, lake) {
    tryCatch({
      inside <- suppressWarnings(sf::st_intersection(segment, lake))
      if (length(inside) == 0 || all(sf::st_is_empty(inside))) return(0)
      as.numeric(sum(sf::st_length(inside), na.rm = TRUE))
    }, error = function(e) 0)
  }

  crossing_row <- function(hylak_id, crossing_type, segment_class, upstream_id,
                           downstream_id, crossing_coord, entry_coord, exit_coord,
                           distance_m, n_boundary_points) {
    valid_coord <- function(coord) {
      is.numeric(coord) && length(coord) >= 2 && all(is.finite(coord[1:2]))
    }
    crossing_out <- to_output_coord(crossing_coord)
    entry_out <- if (valid_coord(entry_coord)) to_output_coord(entry_coord[1:2]) else c(NA_real_, NA_real_)
    exit_out <- if (valid_coord(exit_coord)) to_output_coord(exit_coord[1:2]) else c(NA_real_, NA_real_)
    data.frame(
      Hylak_id = hylak_id,
      crossing_type = crossing_type,
      segment_crossing_class = segment_class,
      upstream_id = as.character(upstream_id),
      downstream_id = as.character(downstream_id),
      crossing_x = crossing_out[1],
      crossing_y = crossing_out[2],
      entry_x = entry_out[1],
      entry_y = entry_out[2],
      exit_x = exit_out[1],
      exit_y = exit_out[2],
      distance_from_boundary = distance_m,
      snap_distance_m = 0,
      confidence = "exact_boundary",
      crossing_method = "directed_boundary_intersection",
      n_boundary_points = n_boundary_points,
      stringsAsFactors = FALSE
    )
  }

  all_crossings <- list()

  for (lake_idx in seq_len(nrow(work_lakes))) {
    hylak_id <- work_lakes$Hylak_id[lake_idx]
    lake_name <- if ("Lake_name" %in% names(work_lakes) && !is.na(work_lakes$Lake_name[lake_idx])) {
      work_lakes$Lake_name[lake_idx]
    } else {
      paste0("Lake_", hylak_id)
    }

    intersecting_segment_indices <- tryCatch({
      intersects <- sf::st_intersects(segments_sf, lake_boundaries[lake_idx, ])
      which(lengths(intersects) > 0)
    }, error = function(e) {
      if (verbose) message(">>> Error checking intersections for ", lake_name, ": ", e$message)
      integer(0)
    })

    if (length(intersecting_segment_indices) == 0) {
      if (verbose) message(">>> ", lake_name, ": no boundary-intersecting segments")
      next
    }

    lake_crossings <- list()
    for (seg_idx in intersecting_segment_indices) {
      segment <- segments_sf[seg_idx, ]
      upstream_id <- segment$upstream_id[1]
      downstream_id <- segment$downstream_id[1]
      upstream_inside <- point_inside(segment$from_idx[1], lake_idx)
      downstream_inside <- point_inside(segment$to_idx[1], lake_idx)
      line_inside_m <- inside_length_m(segment, work_lakes[lake_idx, ])

      boundary_intersection <- tryCatch(
        suppressWarnings(sf::st_intersection(segment, lake_boundaries[lake_idx, ])),
        error = function(e) NULL
      )
      if (is.null(boundary_intersection) || length(boundary_intersection) == 0 ||
          all(sf::st_is_empty(boundary_intersection))) {
        next
      }

      boundary_coords <- coords_from_geometry(boundary_intersection)
      boundary_coords <- order_coords_along_segment(boundary_coords, sf::st_geometry(segment)[[1]])
      n_boundary_points <- nrow(boundary_coords)
      if (n_boundary_points == 0) next

      first_crossing <- boundary_coords[1, ]
      last_crossing <- boundary_coords[n_boundary_points, ]
      distance_m <- tryCatch({
        p <- sf::st_sfc(sf::st_point(first_crossing), crs = work_crs)
        as.numeric(sf::st_distance(p, lake_boundaries[lake_idx, ])[1, 1])
      }, error = function(e) 0)

      if (!upstream_inside && downstream_inside) {
        lake_crossings[[length(lake_crossings) + 1L]] <- crossing_row(
          hylak_id, "inlet", "entering", upstream_id, downstream_id,
          first_crossing, first_crossing, NA, distance_m, n_boundary_points
        )
      } else if (upstream_inside && !downstream_inside) {
        lake_crossings[[length(lake_crossings) + 1L]] <- crossing_row(
          hylak_id, "outlet", "exiting", upstream_id, downstream_id,
          first_crossing, NA, first_crossing, distance_m, n_boundary_points
        )
      } else if (!upstream_inside && !downstream_inside &&
                 line_inside_m > crossing_distance_threshold &&
                 n_boundary_points >= 2) {
        lake_crossings[[length(lake_crossings) + 1L]] <- crossing_row(
          hylak_id, "inlet", "through_lake", upstream_id, downstream_id,
          first_crossing, first_crossing, last_crossing, distance_m, n_boundary_points
        )
        lake_crossings[[length(lake_crossings) + 1L]] <- crossing_row(
          hylak_id, "outlet", "through_lake", upstream_id, downstream_id,
          last_crossing, first_crossing, last_crossing, distance_m, n_boundary_points
        )
      } else if (upstream_inside && downstream_inside) {
        lake_crossings[[length(lake_crossings) + 1L]] <- crossing_row(
          hylak_id, "internal", "internal", upstream_id, downstream_id,
          first_crossing, NA, NA, distance_m, n_boundary_points
        )
      } else {
        lake_crossings[[length(lake_crossings) + 1L]] <- crossing_row(
          hylak_id, "tangential", "tangential", upstream_id, downstream_id,
          first_crossing, NA, NA, distance_m, n_boundary_points
        )
      }
    }

    if (length(lake_crossings) > 0) {
      all_crossings <- c(all_crossings, lake_crossings)
      if (verbose) message(">>> ", lake_name, ": ", length(lake_crossings), " crossing row(s) detected")
    }
  }

  crossings_df <- if (length(all_crossings) > 0) do.call(rbind, all_crossings) else empty_crossings()
  lakes_with_crossings <- if (nrow(crossings_df) > 0) length(unique(crossings_df$Hylak_id)) else 0
  lakes_without_crossings <- nrow(HL_basin) - lakes_with_crossings
  tangential_crossings <- if (nrow(crossings_df) > 0) sum(crossings_df$crossing_type == "tangential") else 0

  message(">>> Summary: ", nrow(crossings_df), " total crossing rows, ",
          lakes_with_crossings, " lakes with crossings, ",
          lakes_without_crossings, " lakes without crossings, ",
          tangential_crossings, " tangential crossings")

  invisible(list(
    crossings = crossings_df,
    segment_count = segment_count,
    lakes_with_crossings = lakes_with_crossings,
    lakes_without_crossings = lakes_without_crossings,
    tangential_crossings = tangential_crossings
  ))
}
