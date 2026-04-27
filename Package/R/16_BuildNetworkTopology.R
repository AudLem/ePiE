#' Build Network Topology
#'
#' Converts river segments into a directed node-link topology using flow-direction
#' rasters (HydroSHEDS) or explicit DSLINKNO topology (GeoGLOWS v2), assigning
#' each node an upstream/downstream relationship.
#'
#' @param hydro_sheds_rivers_basin sf object. Clipped river network.
#' @param dir Raster. Flow-direction raster (HydroSHEDS). Ignored for GeoGLOWS.
#' @param Basin sf object. Basin boundary polygon.
#' @param topology_source character. One of "hydrosheds" (default), "geoglows", or
#'   NULL for auto-detection from column names.
#' @return A named list with \code{points} (network nodes) and \code{lines} (network edges).
#' @export
BuildNetworkTopology <- function(hydro_sheds_rivers_basin,
                                    dir,
                                    Basin,
                                    topology_source = NULL,
                                    diagnostics_level = NULL,
                                    diagnostics_dir = NULL) {
  message("--- Step 7: Building Network Topology ---")

  if (is.null(topology_source)) {
    topology_source <- if ("LINKNO" %in% names(hydro_sheds_rivers_basin) && "DSLINKNO" %in% names(hydro_sheds_rivers_basin)) "geoglows" else "hydrosheds"
  }
  use_geoglows <- identical(topology_source, "geoglows")
  if (use_geoglows) message("  Using GeoGLOWS v2 explicit topology (DSLINKNO)")
  if (!use_geoglows) message("  Using HydroSHEDS topology (flow-direction raster)")

  lines <- hydro_sheds_rivers_basin
  lines <- suppressWarnings(sf::st_cast(lines, "LINESTRING"))
  points_coords <- sf::st_coordinates(lines)
  points <- as.data.frame(points_coords)
  points <- sf::st_as_sf(points, coords = c("X", "Y"), remove = FALSE)
  points <- sf::st_set_crs(points, sf::st_crs(lines))

  if (use_geoglows) {
    # Preserve existing ARCID for rows without LINKNO (e.g., canals)
    lines$ARCID <- ifelse(is.na(lines$LINKNO), lines$ARCID, lines$LINKNO)
    points$ARCID <- lines$LINKNO[points$L1]
    points$LINKNO <- lines$LINKNO[points$L1]
    points$UP_CELLS <- if ("UPLAND_SKM" %in% names(lines)) lines$UPLAND_SKM[points$L1] else if ("USContArea" %in% names(lines)) lines$USContArea[points$L1] / 1e6 else NA_real_
    points$is_canal <- if ("is_canal" %in% names(lines)) as.logical(lines$is_canal[points$L1]) else FALSE
    points$dir <- NA_real_
  } else {
    points$ARCID <- lines$ARCID[points$L1]
    points$UP_CELLS <- lines$UPLAND_SKM[points$L1]
    points$is_canal <- if ("is_canal" %in% names(lines)) as.logical(lines$is_canal[points$L1]) else FALSE
    points$dir <- raster::extract(dir, points)
  }

  points$ID <- paste0("P_", stringr::str_pad(seq_len(nrow(points)), 5, "left", "0"))
  points$x <- sf::st_coordinates(points)[, 1]
  points$y <- sf::st_coordinates(points)[, 2]

  if (!use_geoglows) {
    points$dir <- ifelse(is.na(points$dir), 1, points$dir)
  }

  LineIDs <- unique(points$ARCID)
  points$idx_in_line_seg <- NA
  points$ID_nxt <- NA
  points$pt_type <- "node"
  # Snap coordinates to ~1mm grid to handle floating-point drift at confluences
  # where two segments share endpoints but differ by ~1e-15 due to st_coordinates()
  snap_tol <- 1e-6
  points$loc_ID_tmp <- paste0(round(points$X / snap_tol) * snap_tol, "_",
                              round(points$Y / snap_tol) * snap_tol)

  points_df <- sf::st_drop_geometry(points)

  for (i in seq_along(LineIDs)) {
    idx <- which(points_df$ARCID == LineIDs[i])
    if (length(idx) > 1) {
      points_df$ID_nxt[idx[1:(length(idx) - 1)]] <- points_df$ID[idx[2:length(idx)]]
    }
    points_df$idx_in_line_seg[idx] <- seq_along(idx)
  }

  if (use_geoglows) {
    ds_map <- setNames(lines$DSLINKNO, lines$LINKNO)
    all_ids <- as.character(LineIDs)
    for (i in seq_along(LineIDs)) {
      current_id <- LineIDs[i]
      idx <- which(points_df$ARCID == current_id)
      last_pt_idx <- idx[length(idx)]
      ds_id <- ds_map[as.character(current_id)]
      if (!is.na(ds_id) && !(ds_id == -1) && as.character(ds_id) %in% all_ids) {
        ds_idx <- which(points_df$ARCID == ds_id)
        if (length(ds_idx) > 0) {
          ds_first <- ds_idx[which.min(points_df$idx_in_line_seg[ds_idx])]
          # Fan-in support: if another segment already points to this junction,
          # keep the existing link (both upstream segments feed into the same node)
          if (is.na(points_df$ID_nxt[last_pt_idx])) {
            points_df$ID_nxt[last_pt_idx] <- points_df$ID[ds_first]
          }
          points_df$pt_type[ds_first] <- "JNCT"
        }
      }
    }
  } else {
    loc_ids <- points_df$loc_ID_tmp
    for (i in seq_along(LineIDs)) {
      idx <- which(points_df$ARCID == LineIDs[i])
      last_pt_idx <- idx[length(idx)]
      last_loc <- points_df$loc_ID_tmp[last_pt_idx]
      matches <- which(loc_ids == last_loc)
      if (length(matches) > 1) {
        other_starts <- matches[points_df$idx_in_line_seg[matches] == 1 & matches != last_pt_idx]
        if (length(other_starts) > 0) {
          points_df$ID_nxt[last_pt_idx] <- points_df$ID[other_starts[1]]
          points_df$pt_type[other_starts[1]] <- "JNCT"
        }
      }
    }
  }

  points$ID_nxt <- points_df$ID_nxt
  points$pt_type <- points_df$pt_type
  points$idx_in_line_seg <- points_df$idx_in_line_seg

  # Initialize manual_Q in points_df with NA values
  points_df$manual_Q <- NA_real_

  # Interpolate Q along canal segments (irrigation flow reduction)
  # For canal segments with q_head/q_tail, linearly interpolate based on node position
  if ("q_head" %in% names(lines) && "q_tail" %in% names(lines)) {
    for (arcid in unique(lines$ARCID[!is.na(lines$q_head)])) {
      arcid_char <- as.character(arcid)
      arc_idx <- which(points_df$ARCID == arcid_char)
      if (length(arc_idx) == 0) next

      seg_q_head <- lines$q_head[lines$ARCID == arcid_char][1]
      seg_q_tail <- lines$q_tail[lines$ARCID == arcid_char][1]

      if (is.na(seg_q_head) || is.na(seg_q_tail)) next

      n_nodes <- length(arc_idx)
      if (n_nodes == 1) {
        points_df$manual_Q[arc_idx] <- seg_q_head
      } else {
        for (j in seq_along(arc_idx)) {
          idx_in_seg <- points_df$idx_in_line_seg[arc_idx[j]]
          if (!is.na(idx_in_seg)) {
            frac <- (idx_in_seg - 1) / (n_nodes - 1)
            points_df$manual_Q[arc_idx[j]] <- seg_q_head + (seg_q_tail - seg_q_head) * frac
          }
        }
      }
    }
  }

  # For non-canal or segments without head/tail Q, use segment's manual_Q
  if ("manual_Q" %in% names(lines)) {
    missing_idx <- which(is.na(points_df$manual_Q))
    if (length(missing_idx) > 0) {
      points_df$manual_Q[missing_idx] <- lines$manual_Q[points_df$L1[missing_idx]]
    }
  }

  points$manual_Q <- points_df$manual_Q

  points <- points[which(is.na(points$ID_nxt) | points$ID_nxt != "REMOVE"), ]

  current_utm_crs <- GetUtmCrs(Basin)
  points_utm <- sf::st_transform(points, crs = current_utm_crs)
  idx_next_vec <- match(points$ID_nxt, points$ID)
  coords_utm <- sf::st_coordinates(points_utm)
  
  # Distance to next node (0 for MOUTH nodes)
  points$d_nxt <- 0
  has_next <- !is.na(idx_next_vec)
  if (any(has_next)) {
    points$d_nxt[has_next] <- sqrt(
      (coords_utm[has_next, 1] - coords_utm[idx_next_vec[has_next], 1])^2 +
        (coords_utm[has_next, 2] - coords_utm[idx_next_vec[has_next], 2])^2
    )
  }

  mouth_idx <- which(is.na(idx_next_vec))
  points$pt_type[mouth_idx] <- "MOUTH"
  points$pt_type[which(!points$ID %in% points$ID_nxt)] <- "START"

  # Map NAs to -1 for C++ safety (indices are 0-based in C++)
  idx_nxt_cpp <- idx_next_vec - 1
  idx_nxt_cpp[is.na(idx_nxt_cpp)] <- -1
  
  isMouth <- as.numeric(points$pt_type == "MOUTH")
  points$LD2 <- 0
  idx_cpp <- (seq_len(nrow(points)))[which(points$pt_type != "MOUTH")] - 1
  if (length(idx_cpp) > 0) {
    points$LD2[idx_cpp + 1] <- calc_ld_cpp(
        i = idx_cpp,
        isMouth = isMouth,
        d_nxt = points$d_nxt,
        idx_nxt_tmp = idx_nxt_cpp,
        total_nodes = nrow(points)
    )
  }
  points$LD <- points$LD2

  list(
    lines = lines,
    hydro_sheds_rivers = lines,
    points = points
  )
}
