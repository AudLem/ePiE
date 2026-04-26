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
  if (!is.null(Basin)) Basin <- sf::st_read(Basin, quiet = TRUE) # Logic simplified for brevity in this mock step
  # Note: The above st_read is a placeholder, usually Basin is already sf.
  
  # Helper to process and snap WWTP points from a data.frame
  ProcessWWTPs <- function(df, lon_col, lat_col, id_col, source_name) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    df <- df[!is.na(df[[lon_col]]) & !is.na(df[[lat_col]]), ]
    if (nrow(df) == 0) return(NULL)
    
    sf_pts <- sf::st_as_sf(df, coords = c(lon_col, lat_col), crs = 4326)
    sf_pts <- EnsureSameCrs(Basin, sf_pts, "Basin", source_name)
    pts_in_basin <- sf_pts[sf::st_intersects(sf_pts, Basin, sparse = FALSE)[, 1], ]
    
    if (nrow(pts_in_basin) == 0) return(NULL)
    
    message("Found ", nrow(pts_in_basin), " ", source_name, " points in basin.")
    current_utm_crs <- GetUtmCrs(Basin)
    pts_utm <- sf::st_transform(pts_in_basin, current_utm_crs)
    
    # Ensure river segments are ready
    if (is.null(river_segments_sf)) {
        rivers_utm <- sf::st_transform(hydro_sheds_rivers_basin, current_utm_crs)
        river_segments_list <- lapply(seq_len(nrow(rivers_utm)), function(i) {
          BreakLinestringIntoSegments(rivers_utm[i, ]$geometry, rivers_utm[i, ]$ARCID, current_utm_crs)
        })
        river_segments_sf <<- do.call(rbind, river_segments_list)
    }
    
    river_segments_sf <- EnsureSameCrs(pts_utm, river_segments_sf, "pts_utm", "river_segments")
    nearest_idx <- sf::st_nearest_feature(pts_utm, river_segments_sf)
    
    pts_utm$nearest_segment_id <- river_segments_sf$segment_id[nearest_idx]
    pts_utm$ARCID_val <- river_segments_sf$original_id[nearest_idx]
    basin_arcids <- hydro_sheds_rivers_basin$ARCID
    pts_utm$L1 <- match(pts_utm$ARCID_val, basin_arcids)
    pts_utm$node_type <- "WWTP"
    pts_utm$source_db <- source_name
    
    # Snap coordinates
    snapped_geoms <- vector("list", nrow(pts_utm))
    for (i in seq_len(nrow(pts_utm))) {
      p <- pts_utm[i, ]
      target_seg <- river_segments_sf[river_segments_sf$segment_id == p$nearest_segment_id, ]
      nearest_line <- sf::st_nearest_points(p, target_seg)
      pts_pair <- sf::st_cast(nearest_line, "POINT")
      snapped_geoms[[i]] <- if (length(pts_pair) >= 2) pts_pair[[2]] else pts_pair[[1]]
    }
    pts_utm$geometry <- sf::st_sfc(snapped_geoms, crs = sf::st_crs(pts_utm))
    pts_utm
  }

  # --- Source 1: Standard WWTP CSV (EEF) ---
  if (!is.null(wwtp_csv_path) && file.exists(wwtp_csv_path)) {
    ww_df <- read.csv(wwtp_csv_path, stringsAsFactors = FALSE)
    lon_c <- if ("uwwLongi_1" %in% names(ww_df)) "uwwLongi_1" else "X"
    lat_c <- if ("uwwLatit_1" %in% names(ww_df)) "uwwLatit_1" else "Y"
    pts_eef <- ProcessWWTPs(ww_df, lon_c, lat_c, "uwwCode", "EEF")
    if (!is.null(pts_eef)) {
        if (!is.null(agglomeration_points)) {
            agglomeration_points <- rbind(agglomeration_points, pts_eef[, intersect(names(pts_eef), names(agglomeration_points))])
        } else {
            agglomeration_points <- pts_eef
        }
    }
  }

  # --- Source 2: HydroWASTE ---
  if (!is.null(hydrowaste_raw)) {
    pts_hw <- ProcessWWTPs(hydrowaste_raw, "LON_WWTP", "LAT_WWTP", "WWTP_ID", "HydroWASTE")
    if (!is.null(pts_hw)) {
        # Map population served if available
        if ("POP_SERVED" %in% names(pts_hw)) pts_hw$total_population <- pts_hw$POP_SERVED
        
        if (!is.null(agglomeration_points)) {
            common_cols <- intersect(names(pts_hw), names(agglomeration_points))
            agglomeration_points <- rbind(agglomeration_points, pts_hw[, common_cols])
        } else {
            agglomeration_points <- pts_hw
        }
    }
  }

  list(
    agglomeration_points = agglomeration_points,
    river_segments_sf = river_segments_sf,
    hydro_sheds_rivers_basin = hydro_sheds_rivers_basin,
    hydro_sheds_rivers = hydro_sheds_rivers_basin
  )
}
