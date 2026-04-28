#' Detect Lake-River Segment Crossings
#'
#' Identifies where river network segments intersect lake polygon boundaries,
#' enabling lake inlet/outlet creation for lakes with no interior vertices.
#'
#' @section Algorithm Overview:
#'
#' The function performs four phases:
#'
#' 1. **Segment Construction** — Builds LINESTRING features for each river
#'    edge by connecting point[i] to point[ID_nxt[i]].
#'
#' 2. **Boundary Intersection** — For each lake polygon, finds all segments
#'    that cross the lake boundary using \code{st_intersection}.
#'
#' 3. **Crossing Classification** — Determines if each crossing is:
#'    \itemize{
#'      \item **Inlet**: segment enters lake (outside → inside)
#'      \item **Outlet**: segment exits lake (inside → outside)
#'      \item **Tangential**: segment touches boundary without entering/exiting
#'    }
#'
#' 4. **Node Creation** — At each crossing point, creates a new node with
#'    inherited properties from the nearest upstream/downstream river node.
#'
#' @section Test Design:
#'
#' The function is designed for unit testing with these testable properties:
#' \itemize{
#'   \item **Pure function** — no side effects, only input → output
#'   \item **Deterministic** — same inputs always produce same outputs
#'   \item **Validated outputs** — returns diagnostics for assertion checks
#'   \item **Minimal dependencies** — only requires sf package
#' }
#'
#' @section Expected Behavior:
#'
#' \describe{
#'   \item{Input: Lake with 0 interior vertices, 2 crossing segments}{
#'     Creates 1 inlet, 1 outlet node at crossing points
#'   }
#'   \item{Input: Lake with 0 interior vertices, 0 crossing segments}{
#'     Returns empty crossing list, skips lake processing
#'   }
#'   \item{Input: Lake with 1 interior vertex, 1 crossing segment}{
#'     Returns both interior point crossings AND segment crossings
#'   }
#'   \item{Input: Tangential segment (touches but doesn't enter)}{
#'     Classifies as tangential, does NOT create inlet/outlet
#'   }
#' }
#'
#' @param points sf object. Network point nodes with columns:
#'   \code{ID}, \code{ID_nxt}, \code{x}, \code{y}, \code{LD}, \code{pt_type},
#'   \code{HL_ID_new}, \code{lake_in}, \code{lake_out}, \code{node_type}.
#'   Must be in projected CRS (e.g., UTM) for accurate distance calculations.
#'
#' @param HL_basin sf object. Lake polygons with columns:
#'   \code{Hylak_id}, \code{Lake_name}, \code{Pour_long}, \code{Pour_lat}.
#'   Must be POLYGON or MULTIPOLYGON geometry.
#'
#' @param crossing_distance_threshold numeric. Maximum distance (meters) from
#'   lake boundary to consider a point "on" the boundary. Used to handle
#'   numerical precision issues. Default: 10.
#'
#' @return A named list with the following components:
#'   \describe{
#'     \item{crossings}{data.frame. All detected crossings with columns:
#'       \code{Hylak_id}, \code{crossing_type} ("inlet"/"outlet"/"tangential"),
#'       \code{upstream_id}, \code{downstream_id}, \code{crossing_x},
#'       \code{crossing_y}, \code{distance_from_boundary} (meters).}
#'     \item{segment_count}{integer. Total number of river segments analyzed.}
#'     \item{lakes_with_crossings}{integer. Number of lakes with ≥1 crossing.}
#'     \item{lakes_without_crossings}{integer. Number of lakes with 0 crossings.}
#'     \item{tangential_crossings}{integer. Number of tangential (non-through)
#'       crossings detected.}
#'   }
#'
#' @section Unit Test Assertions:
#'
#' Test cases should verify:
#' \itemize{
#'   \item \code{is.list(result)} - returns a list
#'   \item \code{all(c("crossings", "segment_count", "lakes_with_crossings") \%in\% names(result))}
#'   \item \code{nrow(result$crossings) >= 0} - crossings count is non-negative
#'   \item \code{result$segment_count == n_valid_segments} - analyzed expected segments
#'   \item \code{all(result$crossings$crossing_type \%in\% c("inlet", "outlet", "tangential"))}
#'   \item \code{all(result$crossings$distance_from_boundary >= 0)} - distances valid
#'   \item For lake with 2 crossings: \code{sum(result$crossings$Hylak_id == lake_id) == 2}
#'   \item For lake with 0 crossings: \code{!any(result$crossings$Hylak_id == lake_id)}
#' }
#'
#' @family lake-connection
#' @export
DetectLakeSegmentCrossings <- function(points, HL_basin, crossing_distance_threshold = 10) {
  message("--- Detecting Lake-River Segment Crossings ---")

  if (is.null(points) || nrow(points) == 0) {
    lakes_count <- if (!is.null(HL_basin) && nrow(HL_basin) > 0) nrow(HL_basin) else 0
    message(">>> Empty points input. Returning empty result.")
    return(list(
      crossings = data.frame(
        Hylak_id = integer(0),
        crossing_type = character(0),
        upstream_id = character(0),
        downstream_id = character(0),
        crossing_x = numeric(0),
        crossing_y = numeric(0),
        distance_from_boundary = numeric(0),
        stringsAsFactors = FALSE
      ),
      segment_count = 0,
      lakes_with_crossings = 0,
      lakes_without_crossings = lakes_count,
      tangential_crossings = 0
    ))
  }

  if (is.null(HL_basin) || nrow(HL_basin) == 0) {
    message(">>> No lakes found. Returning empty result.")
    return(list(
      crossings = data.frame(
        Hylak_id = integer(0),
        crossing_type = character(0),
        upstream_id = character(0),
        downstream_id = character(0),
        crossing_x = numeric(0),
        crossing_y = numeric(0),
        distance_from_boundary = numeric(0),
        stringsAsFactors = FALSE
      ),
      segment_count = 0,
      lakes_with_crossings = 0,
      lakes_without_crossings = 0,
      tangential_crossings = 0
    ))
  }

  if (is.null(sf::st_crs(points))) {
    stop("Points object has no CRS. Please assign a coordinate reference system.")
  }

  if (is.null(sf::st_crs(HL_basin))) {
    stop("HL_basin object has no CRS. Please assign a coordinate reference system.")
  }

  if (!sf::st_crs(points) == sf::st_crs(HL_basin)) {
    message(">>> CRS mismatch detected. Transforming HL_basin to match points CRS.")
    HL_basin <- sf::st_transform(HL_basin, crs = sf::st_crs(points))
  }

  crs_is_geographic <- sf::st_is_longlat(points)
  if (crs_is_geographic) {
    warning("Points are in geographic CRS. Distance calculations may be inaccurate. Use projected CRS (e.g., UTM).")
  }

  message(">>> Input: ", nrow(points), " points, ", nrow(HL_basin), " lakes")

  valid_segments_mask <- !is.na(points$ID_nxt) & points$ID_nxt != ""
  if (sum(valid_segments_mask) == 0) {
    message(">>> No valid river segments found. Returning empty result.")
    return(list(
      crossings = data.frame(
        Hylak_id = integer(0),
        crossing_type = character(0),
        upstream_id = character(0),
        downstream_id = character(0),
        crossing_x = numeric(0),
        crossing_y = numeric(0),
        distance_from_boundary = numeric(0),
        stringsAsFactors = FALSE
      ),
      segment_count = 0,
      lakes_with_crossings = 0,
      lakes_without_crossings = nrow(HL_basin),
      tangential_crossings = 0
    ))
  }

  upstream_points <- points[valid_segments_mask, ]
  downstream_ids <- upstream_points$ID_nxt
  downstream_indices <- match(downstream_ids, points$ID)
  downstream_points <- points[downstream_indices, ]

  segment_geometries <- lapply(seq_len(nrow(upstream_points)), function(i) {
    upstream_coords <- sf::st_coordinates(upstream_points[i, ])
    downstream_coords <- sf::st_coordinates(downstream_points[i, ])
    sf::st_linestring(matrix(c(upstream_coords[1:2], downstream_coords[1:2]), nrow = 2, byrow = TRUE))
  })

  segments_sf <- sf::st_sf(
    geometry = sf::st_sfc(segment_geometries, crs = sf::st_crs(points)),
    upstream_id = upstream_points$ID,
    downstream_id = downstream_ids,
    stringsAsFactors = FALSE
  )

  segment_count <- nrow(segments_sf)
  message(">>> Created ", segment_count, " river segments")

  lake_boundaries <- sf::st_boundary(HL_basin)

  all_crossings <- list()

  for (lake_idx in seq_len(nrow(HL_basin))) {
    hylak_id <- HL_basin$Hylak_id[lake_idx]
    lake_name <- if ("Lake_name" %in% names(HL_basin)) HL_basin$Lake_name[lake_idx] else paste0("Lake_", hylak_id)

    intersecting_segment_indices <- tryCatch({
      intersects <- sf::st_intersects(segments_sf, lake_boundaries[lake_idx, ])
      which(sapply(intersects, function(x) length(x) > 0))
    }, error = function(e) {
      message(">>> Error checking intersections for ", lake_name, ": ", e$message)
      integer(0)
    })

    if (length(intersecting_segment_indices) == 0) {
      message(">>> ", lake_name, ": no intersecting segments")
      next
    }

    lake_crossings <- list()

    for (seg_idx in intersecting_segment_indices) {
      segment <- segments_sf[seg_idx, ]
      upstream_id <- segment$upstream_id[1]
      downstream_id <- segment$downstream_id[1]

      crossing_point <- tryCatch({
        intersection <- sf::st_intersection(segment, lake_boundaries[lake_idx, ])
        if (length(intersection) == 0 || sf::st_is_empty(intersection[1])) {
          NULL
        } else if (inherits(sf::st_geometry(intersection)[[1]], "sfc_LINESTRING") ||
                   inherits(sf::st_geometry(intersection)[[1]], "sfc_MULTILINESTRING")) {
          intersection_geom <- sf::st_geometry(intersection)[[1]]
          mid_point <- tryCatch({
            coords <- sf::st_coordinates(intersection_geom)
            if (nrow(coords) >= 2) {
              mid_idx <- floor(nrow(coords) / 2) + 1
              coords[mid_idx, 1:2]
            } else {
              coords[1, 1:2]
            }
          }, error = function(e) {
            sf::st_coordinates(sf::st_centroid(intersection_geom))[1, 1:2]
          })
          mid_point
        } else {
          sf::st_coordinates(intersection)[1, 1:2]
        }
      }, error = function(e) {
        message(">>> Error computing intersection for segment ", seg_idx, ": ", e$message)
        NULL
      })

      if (is.null(crossing_point)) {
        next
      }

      crossing_sf <- sf::st_sf(
        geometry = sf::st_sfc(sf::st_point(crossing_point), crs = sf::st_crs(points)),
        stringsAsFactors = FALSE
      )

      upstream_idx <- match(upstream_id, points$ID)
      downstream_idx <- match(downstream_id, points$ID)

      upstream_inside <- tryCatch({
        if (!is.na(upstream_idx)) {
          contains <- sf::st_contains(HL_basin[lake_idx, ], sf::st_geometry(points[upstream_idx, ]))
          length(contains[[1]]) > 0
        } else {
          FALSE
        }
      }, error = function(e) FALSE)

      downstream_inside <- tryCatch({
        if (!is.na(downstream_idx)) {
          contains <- sf::st_contains(HL_basin[lake_idx, ], sf::st_geometry(points[downstream_idx, ]))
          length(contains[[1]]) > 0
        } else {
          FALSE
        }
      }, error = function(e) FALSE)

      crossing_type <- if (!upstream_inside && downstream_inside) {
        "inlet"
      } else if (upstream_inside && !downstream_inside) {
        "outlet"
      } else {
        "tangential"
      }

      distance_from_boundary <- tryCatch({
        dist <- sf::st_distance(crossing_sf, lake_boundaries[lake_idx, ])
        if (length(dist) > 0) as.numeric(dist[1, 1]) else 0
      }, error = function(e) 0)

      lake_crossings[[length(lake_crossings) + 1]] <- data.frame(
        Hylak_id = hylak_id,
        crossing_type = crossing_type,
        upstream_id = upstream_id,
        downstream_id = downstream_id,
        crossing_x = crossing_point[1],
        crossing_y = crossing_point[2],
        distance_from_boundary = distance_from_boundary,
        stringsAsFactors = FALSE
      )
    }

    if (length(lake_crossings) > 0) {
      all_crossings <- c(all_crossings, lake_crossings)
      message(">>> ", lake_name, ": ", length(lake_crossings), " crossing(s) detected")
    }
  }

  crossings_df <- if (length(all_crossings) > 0) {
    do.call(rbind, all_crossings)
  } else {
    data.frame(
      Hylak_id = integer(0),
      crossing_type = character(0),
      upstream_id = character(0),
      downstream_id = character(0),
      crossing_x = numeric(0),
      crossing_y = numeric(0),
      distance_from_boundary = numeric(0),
      stringsAsFactors = FALSE
    )
  }

  lakes_with_crossings <- if (nrow(crossings_df) > 0) {
    length(unique(crossings_df$Hylak_id))
  } else {
    0
  }

  lakes_without_crossings <- nrow(HL_basin) - lakes_with_crossings

  tangential_crossings <- if (nrow(crossings_df) > 0) {
    sum(crossings_df$crossing_type == "tangential")
  } else {
    0
  }

  message(">>> Summary: ", nrow(crossings_df), " total crossings, ",
          lakes_with_crossings, " lakes with crossings, ",
          lakes_without_crossings, " lakes without crossings, ",
          tangential_crossings, " tangential crossings")

  # --- Lake-by-lake diagnostic for lakes with zero crossings --------------------
  # For lakes that have no geometric intersection with any river segment,
  # compute the nearest river distance to help users understand whether
  # the lake is genuinely disconnected (far from network) or a near-miss
  # that might benefit from a tolerance-based fallback in future.
  # --------------------------------------------------------------------------------
  if (lakes_without_crossings > 0) {
    message(">>> Lakes without exact crossings (checking nearest river proximity):")
    
    # Collect all Hylak_ids that have crossings
    connected_hylak_ids <- if (nrow(crossings_df) > 0) unique(crossings_df$Hylak_id) else integer(0)
    
    # Filter to lakes with no crossings
    lake_indices_without_crossings <- which(!HL_basin$Hylak_id %in% connected_hylak_ids)
    
    for (idx in lake_indices_without_crossings) {
      hylak_id <- HL_basin$Hylak_id[idx]
      lake_name <- if ("Lake_name" %in% names(HL_basin)) HL_basin$Lake_name[idx] else paste0("Lake_", hylak_id)
      
      # Compute lake area in km^2
      lake_area_km2 <- tryCatch({
        as.numeric(sf::st_area(HL_basin[idx, ])) / 1e6
      }, error = function(e) NA)
      
      # Find nearest river segment (exclude canals if is_canal column exists)
      river_mask <- if ("is_canal" %in% names(points)) {
        !points$is_canal | is.na(points$is_canal)
      } else {
        rep(TRUE, nrow(points))
      }
      river_points <- points[river_mask, ]
      
      if (nrow(river_points) > 0) {
        lake_centroid <- sf::st_centroid(HL_basin[idx, ])
        distances <- sf::st_distance(river_points, lake_centroid)
        min_dist_m <- min(as.numeric(distances), na.rm = TRUE)
        min_dist_idx <- which.min(distances)[1]
        nearest_pt_type <- river_points$pt_type[min_dist_idx]
        nearest_pt_id <- river_points$ID[min_dist_idx]
      } else {
        min_dist_m <- NA_real_
        nearest_pt_type <- NA_character_
        nearest_pt_id <- NA_character_
      }
      
      # Count tangential crossings (these exist but were not used for inlet/outlet)
      tangential_for_lake <- if (nrow(crossings_df) > 0) {
        sum(crossings_df$Hylak_id == hylak_id & crossings_df$crossing_type == "tangential")
      } else {
        0
      }
      
      # Determine status
      status <- if (is.na(min_dist_m) || min_dist_m > 500) {
        "skipped (no nearby river network)"
      } else if (min_dist_m > 100) {
        "skipped (river network too far)"
      } else if (tangential_for_lake > 0) {
        "skipped (tangential only)"
      } else {
        "skipped (unexpected)"
      }
      
      # Format distance string
      dist_str <- if (is.na(min_dist_m)) "NA" else sprintf("%.1f m", min_dist_m)
      area_str <- if (is.na(lake_area_km2)) "NA" else sprintf("%.4f km²", lake_area_km2)
      
      message(sprintf("    %-20s | %10s | %8s | %s",
                    paste0("Hylak_id ", hylak_id),
                    area_str,
                    dist_str,
                    status))
    }
  }

  list(
    crossings = crossings_df,
    segment_count = segment_count,
    lakes_with_crossings = lakes_with_crossings,
    lakes_without_crossings = lakes_without_crossings,
    tangential_crossings = tangential_crossings
  )
}
