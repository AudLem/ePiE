#' Map WWTP Locations to Network
#'
#' Reads WWTP data from a CSV file, filters by basin extent, and snaps each
#' plant to the nearest river segment for inclusion in the network.
#'
#' @param Basin sf object. Basin boundary polygon.
#' @param hydro_sheds_rivers_basin sf object. Clipped river network.
#' @param agglomeration_points sf object or \code{NULL}. Agglomeration source points.
#' @param river_segments_sf sf object or \code{NULL}. River segment geometries for snapping.
#' @param wwtp_csv_path Character or \code{NULL}. Path to the WWTP CSV data file.
#' @return A named list with \code{points} (sf points including WWTP nodes).
#' @export
MapWWTPLocations <- function(Basin,
                               hydro_sheds_rivers_basin,
                               agglomeration_points = NULL,
                               river_segments_sf = NULL,
                               wwtp_csv_path = NULL,
                               diagnostics_level = NULL,
                               diagnostics_dir = NULL) {
  message("--- Step 6: Processing WWTP Sources ---")
  if (!is.null(Basin)) Basin <- sf::st_zm(Basin)
  if (!is.null(hydro_sheds_rivers_basin)) hydro_sheds_rivers_basin <- sf::st_zm(hydro_sheds_rivers_basin)
  if (!is.null(river_segments_sf) && inherits(river_segments_sf, "sf")) river_segments_sf <- sf::st_zm(river_segments_sf)

  if (!is.null(wwtp_csv_path) && file.exists(wwtp_csv_path)) {
    message("Loading WWTP points from: ", wwtp_csv_path)
    wwtp_raw <- read.csv(wwtp_csv_path, stringsAsFactors = FALSE)

    lon_col <- if ("uwwLongi_1" %in% names(wwtp_raw)) "uwwLongi_1" else if ("X" %in% names(wwtp_raw)) "X" else NULL
    lat_col <- if ("uwwLatit_1" %in% names(wwtp_raw)) "uwwLatit_1" else if ("Y" %in% names(wwtp_raw)) "Y" else NULL

    if (is.null(lon_col) || is.null(lat_col)) {
      warning("Could not identify coordinate columns in WWTP CSV. Skipping.")
    } else {
      wwtp_raw <- wwtp_raw[!is.na(wwtp_raw[[lon_col]]) & !is.na(wwtp_raw[[lat_col]]), ]
      if (nrow(wwtp_raw) == 0) {
        warning("No valid coordinates found in WWTP CSV. Skipping.")
      } else {
        wwtp_sf <- sf::st_as_sf(wwtp_raw, coords = c(lon_col, lat_col), crs = 4326)
        wwtp_sf <- EnsureSameCrs(Basin, wwtp_sf, "Basin", "WWTPs")
        wwtp_in_basin <- wwtp_sf[sf::st_intersects(wwtp_sf, Basin, sparse = FALSE)[, 1], ]

        if (nrow(wwtp_in_basin) > 0) {
          message("Found ", nrow(wwtp_in_basin), " WWTP points in basin.")
          current_utm_crs <- GetUtmCrs(Basin)
          wwtp_utm <- sf::st_transform(wwtp_in_basin, current_utm_crs)

          needs_segments <- is.null(river_segments_sf) ||
            (inherits(river_segments_sf, "sf") && nrow(river_segments_sf) == 0) ||
            (inherits(river_segments_sf, "sf") && is.na(sf::st_crs(river_segments_sf)))
          if (needs_segments) {
            rivers_utm <- sf::st_transform(hydro_sheds_rivers_basin, current_utm_crs)
            river_segments_list <- lapply(seq_len(nrow(rivers_utm)), function(i) {
              BreakLinestringIntoSegments(rivers_utm[i, ]$geometry, rivers_utm[i, ]$ARCID, current_utm_crs)
            })
            river_segments_sf <- do.call(rbind, river_segments_list)
          }

          river_segments_sf <- EnsureSameCrs(wwtp_utm, river_segments_sf, "wwtp_utm", "river_segments")
          nearest_idx <- sf::st_nearest_feature(wwtp_utm, river_segments_sf)

          wwtp_points <- wwtp_utm
          wwtp_points$nearest_segment_id <- river_segments_sf$segment_id[nearest_idx]
          wwtp_points$ARCID_val <- river_segments_sf$original_id[nearest_idx]
          basin_arcids <- hydro_sheds_rivers_basin$ARCID
          wwtp_points$L1 <- match(wwtp_points$ARCID_val, basin_arcids)
          wwtp_points$node_type <- "WWTP"
          if (!("total_population" %in% names(wwtp_points))) wwtp_points$total_population <- 0

          snapped_geoms <- vector("list", nrow(wwtp_points))
          for (i in seq_len(nrow(wwtp_points))) {
            p <- wwtp_points[i, ]
            target_seg <- river_segments_sf[river_segments_sf$nearest_segment_id == p$nearest_segment_id, ]
            if (nrow(target_seg) == 0) {
              snapped_geoms[[i]] <- sf::st_geometry(p)[[1]]
              next
            }
            nearest_line <- sf::st_nearest_points(p, target_seg)
            pts_pair <- sf::st_cast(nearest_line, "POINT")
            if (length(pts_pair) >= 2) {
              snapped_geoms[[i]] <- pts_pair[[2]]
            } else if (length(pts_pair) == 1) {
              snapped_geoms[[i]] <- pts_pair[[1]]
            } else {
              snapped_geoms[[i]] <- sf::st_geometry(p)[[1]]
            }
          }
          wwtp_points$geometry <- sf::st_sfc(snapped_geoms, crs = sf::st_crs(wwtp_points))

          if (!is.null(agglomeration_points)) {
            common_cols <- intersect(names(agglomeration_points), names(wwtp_points))
            agglomeration_points <- rbind(
              agglomeration_points[, common_cols],
              wwtp_points[, common_cols]
            )
          } else {
            agglomeration_points <- wwtp_points
          }

          message("Integrated ", nrow(wwtp_points), " WWTP points.")
        } else {
          message("No WWTP points found within basin boundary.")
        }
      }
    }
  } else {
    message("No WWTP CSV path provided or file missing. Skipping.")
  }

  list(
    agglomeration_points = agglomeration_points,
    river_segments_sf = river_segments_sf,
    hydro_sheds_rivers_basin = hydro_sheds_rivers_basin,
    hydro_sheds_rivers = hydro_sheds_rivers_basin
  )
}
