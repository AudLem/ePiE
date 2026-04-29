#' Map WWTP Locations to Network
#'
#' Reads WWTP data from a CSV file, filters by basin polygon (500m buffer),
#' snaps each plant to the nearest river segment, and keeps only those whose
#' nearest segment belongs to the basin river network (determined by ARCID match).
#'
#' @param Basin sf object. Basin boundary polygon.
#' @param hydro_sheds_rivers_basin sf object. Clipped river network.
#' @param agglomeration_points sf object or \code{NULL}. Agglomeration source points.
#' @param river_segments_sf sf object or \code{NULL}. River segment geometries for snapping.
#' @param wwtp_csv_path Character or \code{NULL}. Path to the WWTP CSV data file.
#' @param hydrowaste_raw data.frame or \code{NULL}. Optional HydroWASTE data.
#' @return A named list with \code{points} (sf points including WWTP nodes).
#' @export
MapWWTPLocations <- function(Basin,
                                hydro_sheds_rivers_basin,
                                agglomeration_points = NULL,
                                river_segments_sf = NULL,
                                wwtp_csv_path = NULL,
                                hydrowaste_raw = NULL,
                                study_country = NULL,
                                diagnostics_level = NULL,
                                diagnostics_dir = NULL) {
  message("--- Step 6: Processing WWTP Sources ---")

  # `river_segments_sf` must be a segmented snap network with segment metadata.
  # If a raw river layer (or NULL) is provided, rebuild segments here.
  has_valid_segments <- !is.null(river_segments_sf) &&
    nrow(river_segments_sf) > 0 &&
    all(c("segment_id", "original_id") %in% names(river_segments_sf))
  if (!has_valid_segments) {
      current_utm_crs <- GetUtmCrs(Basin)
      rivers_utm <- sf::st_transform(hydro_sheds_rivers_basin, current_utm_crs)
      river_segments_list <- lapply(seq_len(nrow(rivers_utm)), function(i) {
        BreakLinestringIntoSegments(rivers_utm[i, ]$geometry, rivers_utm[i, ]$ARCID, current_utm_crs)
      })
      river_segments_list <- river_segments_list[!vapply(river_segments_list, is.null, logical(1))]
      river_segments_sf <- if (length(river_segments_list) > 0) do.call(rbind, river_segments_list) else NULL
      if (!is.null(river_segments_sf)) {
        message("Using rebuilt river segment snap network: ", nrow(river_segments_sf), " segments")
      }
  }

  if (is.null(river_segments_sf) || nrow(river_segments_sf) == 0) {
      warning("No river segments available for WWTP snapping.")
      return(list(agglomeration_points = agglomeration_points, river_segments_sf = river_segments_sf))
  }

  # Crucial: Capture river_segments_sf for the helper closure
  river_segments_internal <- river_segments_sf

  # Process and snap one source dataset onto the segmented river network.
  # Returns sf points with `L1` (line index used by network integration).
  ProcessWWTPs <- function(df, lon_col, lat_col, id_col, source_name) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    # Identify actual column names in df (case-insensitive or partial match)
    pat_lon <- paste0("^", lon_col, ".*$")
    actual_lon <- names(df)[tolower(names(df)) == tolower(lon_col)][1]
    if (is.na(actual_lon)) actual_lon <- names(df)[grep(pat_lon, names(df), ignore.case = TRUE)][1]
    
    pat_lat <- paste0("^", lat_col, ".*$")
    actual_lat <- names(df)[tolower(names(df)) == tolower(lat_col)][1]
    if (is.na(actual_lat)) actual_lat <- names(df)[grep(pat_lat, names(df), ignore.case = TRUE)][1]
    
    if (is.na(actual_lon) || is.na(actual_lat)) {
      warning("Could not find coordinate columns ", lon_col, "/", lat_col, " in ", source_name)
      return(NULL)
    }

    df <- df[!is.na(df[[actual_lon]]) & !is.na(df[[actual_lat]]), ]
    if (nrow(df) == 0) return(NULL)
    
    sf_pts <- sf::st_as_sf(df, coords = c(actual_lon, actual_lat), crs = 4326)
    sf_pts <- EnsureSameCrs(Basin, sf_pts, "Basin", source_name)
    
    # Filter WWTPs by basin polygon with 500m buffer.
    # This buffer matches the population source buffer and includes WWTPs
    # near basin boundaries (including edge cases like WWTPs just outside the
    # polygon whose nearest river segment is inside the basin).
    # Final membership is still validated by river segment ARCID matching (L1).
    basin_utm <- sf::st_transform(Basin, GetUtmCrs(Basin))
    Basin_buffered <- sf::st_buffer(basin_utm, 500)
    Basin_buffered <- sf::st_transform(Basin_buffered, sf::st_crs(Basin))
    pts_in_basin <- sf_pts[sf::st_intersects(sf_pts, Basin_buffered, sparse = FALSE)[, 1], ]
    
    if (nrow(pts_in_basin) == 0) {
        # Fallback to unbuffered polygon if no points found
        pts_in_basin <- sf_pts[sf::st_intersects(sf_pts, Basin, sparse = FALSE)[, 1], ]
    }
    
    if (nrow(pts_in_basin) == 0) return(NULL)
    
    message("Found ", nrow(pts_in_basin), " ", source_name, " points in basin (500m buffer).")
    current_utm_crs <- GetUtmCrs(Basin)
    pts_utm <- sf::st_transform(pts_in_basin, current_utm_crs)
    
    # Candidate snap network in matching CRS.
    snapping_rivers <- EnsureSameCrs(pts_utm, river_segments_internal, "pts_utm", "river_segments")
    
    # Restrict candidates near WWTP points to reduce false/slow nearest matches.
    bbox <- sf::st_bbox(pts_utm) |> sf::st_as_sfc() |> sf::st_buffer(5000) # 5km buffer
    snapping_rivers_local <- snapping_rivers[sf::st_intersects(snapping_rivers, bbox, sparse = FALSE)[,1], ]
    
    if (nrow(snapping_rivers_local) == 0) {
        warning("No river segments within 5km of ", source_name, " points. Using full network.")
        snapping_rivers_local <- snapping_rivers
    }

    # Index of nearest candidate segment per WWTP point.
    nearest_idx <- sf::st_nearest_feature(pts_utm, snapping_rivers_local)
    
    # Validation: Ensure nearest_idx is valid
    if (length(nearest_idx) == 0 || all(is.na(nearest_idx))) {
        warning("Failed to find nearest river segments for ", source_name, " points.")
        return(NULL)
    }

    expected_n <- nrow(pts_utm)
    got_n <- length(nearest_idx)
    if (got_n != expected_n) {
        warning(
          "Nearest-segment mapping count mismatch for ", source_name,
          " (expected ", expected_n, ", got ", got_n, ")."
        )
        return(NULL)
    }

    pts_utm$nearest_segment_id <- snapping_rivers_local$segment_id[nearest_idx]
    pts_utm$ARCID_val <- snapping_rivers_local$original_id[nearest_idx]
    
    basin_arcids <- hydro_sheds_rivers_basin$ARCID
    match_l1 <- match(pts_utm$ARCID_val, basin_arcids)

    # `L1` is the network line index consumed by downstream integration.
    if (length(match_l1) != nrow(pts_utm)) {
        warning(
          "L1 mapping length mismatch for ", source_name,
          " (expected ", nrow(pts_utm), ", got ", length(match_l1), ")."
        )
        return(NULL)
    }
    missing_l1 <- sum(is.na(match_l1))
    if (missing_l1 > 0) {
        warning(
          source_name, " dropped ", missing_l1, " point(s) with no ARCID->L1 match."
        )
    }
    pts_utm$L1 <- match_l1
    pts_utm$node_type <- "WWTP"
    pts_utm$source_db <- source_name
    if (!is.null(study_country)) pts_utm$rptMStateK <- study_country
    message(
      source_name, " mapped to network lines: ",
      sum(!is.na(pts_utm$L1)), "/", nrow(pts_utm),
      " (dropped ", sum(is.na(pts_utm$L1)), ")."
    )

    # Snap coordinates
    snapped_geoms <- vector("list", nrow(pts_utm))
    for (i in seq_len(nrow(pts_utm))) {
      p <- pts_utm[i, ]
      target_seg <- snapping_rivers_local[snapping_rivers_local$segment_id == p$nearest_segment_id, ]
      if (nrow(target_seg) == 0) {
          snapped_geoms[[i]] <- sf::st_geometry(p)[[1]]
          next
      }
      nearest_line <- sf::st_nearest_points(p, target_seg)
      pts_pair <- sf::st_cast(nearest_line, "POINT")
      snapped_geoms[[i]] <- if (length(pts_pair) >= 2) pts_pair[[2]] else pts_pair[[1]]
    }
    pts_utm$geometry <- sf::st_sfc(snapped_geoms, crs = sf::st_crs(pts_utm))
    pts_utm[!is.na(pts_utm$L1), ]
  }

  # --- Source 1: Standard WWTP CSV (EEF) ---
  if (!is.null(wwtp_csv_path) && file.exists(wwtp_csv_path)) {
    ww_df <- read.csv(wwtp_csv_path, stringsAsFactors = FALSE)
    pts_eef <- tryCatch({
        ProcessWWTPs(ww_df, "uwwLongi", "uwwLatit", "uwwCode", "EEF")
    }, error = function(e) {
        message("Warning: EEF processing failed: ", e$message)
        NULL
    })
    
    if (!is.null(pts_eef) && nrow(pts_eef) > 0) {
        if (!is.null(agglomeration_points) && nrow(agglomeration_points) > 0) {
            common_cols <- intersect(names(pts_eef), names(agglomeration_points))
            agglomeration_points <- rbind(agglomeration_points[, common_cols], pts_eef[, common_cols])
        } else {
            agglomeration_points <- pts_eef
        }
    }
  }

  # --- Source 2: HydroWASTE ---
  if (!is.null(hydrowaste_raw)) {
    pts_hw <- tryCatch({
        ProcessWWTPs(hydrowaste_raw, "LON_WWTP", "LAT_WWTP", "WWTP_ID", "HydroWASTE")
    }, error = function(e) {
        message("Warning: HydroWASTE processing failed: ", e$message)
        NULL
    })
    
    if (!is.null(pts_hw) && nrow(pts_hw) > 0) {
        # Map population served if available
        if ("POP_SERVED" %in% names(pts_hw)) pts_hw$total_population <- pts_hw$POP_SERVED
        
        if (!is.null(agglomeration_points) && nrow(agglomeration_points) > 0) {
            common_cols <- intersect(names(pts_hw), names(agglomeration_points))
            agglomeration_points <- rbind(agglomeration_points[, common_cols], pts_hw[, common_cols])
        } else {
            agglomeration_points <- pts_hw
        }
    }
  }

  if (is.null(agglomeration_points) || nrow(agglomeration_points) == 0) {
      message("NOTE: No contaminant sources (WWTP/Agglom) mapped for this basin.")
  }

  list(
    agglomeration_points = agglomeration_points,
    river_segments_sf = river_segments_sf,
    hydro_sheds_rivers_basin = hydro_sheds_rivers_basin,
    hydro_sheds_rivers = hydro_sheds_rivers_basin
  )
}
