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

  points <- AnnotateCanalTopology(points, lines, Basin)

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

  if ("canal_pt_type" %in% names(points)) {
    canal_class_idx <- which(!is.na(points$canal_pt_type) & points$canal_pt_type != "")
    points$pt_type[canal_class_idx] <- points$canal_pt_type[canal_class_idx]
  }

  list(
    lines = lines,
    hydro_sheds_rivers = lines,
    points = points
  )
}

AnnotateCanalTopology <- function(points, lines, Basin) {
  if (!("is_canal" %in% names(points)) || !any(points$is_canal %in% TRUE, na.rm = TRUE)) {
    return(points)
  }

  points$canal_id <- NA_character_
  points$canal_name <- NA_character_
  points$canal_idx <- NA_integer_
  points$canal_upstream_ids <- NA_character_
  points$canal_downstream_ids <- NA_character_
  points$canal_upstream_count <- NA_integer_
  points$canal_downstream_count <- NA_integer_
  points$canal_pt_type <- NA_character_
  points$chainage_m <- NA_real_
  points$canal_reach_chainage_m <- NA_real_
  points$canal_d_nxt_m <- NA_real_
  points$Q_design_m3s <- NA_real_
  points$Q_model_m3s <- NA_real_
  points$Q_source <- NA_character_

  canal_idx <- which(points$is_canal %in% TRUE)
  if (length(canal_idx) == 0) return(points)

  point_df <- sf::st_drop_geometry(points)
  line_df <- sf::st_drop_geometry(lines)
  projected <- sf::st_transform(points, GetUtmCrs(Basin))
  coords_utm <- sf::st_coordinates(projected)
  snap_tol_m <- 0.1

  loc_key <- paste0(
    round(coords_utm[, 1] / snap_tol_m) * snap_tol_m,
    "_",
    round(coords_utm[, 2] / snap_tol_m) * snap_tol_m
  )
  point_df$canal_loc_key <- loc_key

  line_ids <- unique(point_df$L1[canal_idx])
  line_ids <- line_ids[!is.na(line_ids)]
  line_start_chainage <- setNames(rep(NA_real_, length(line_ids)), as.character(line_ids))

  # chainage_m is the cumulative downstream distance, in meters, from the
  # upstream intake of this canal system. It is used to audit branch locations
  # and display each canal node position. Discharge is interpolated within each
  # canal section from KIS_canal_discharge.csv head/tail values.
  for (pass in seq_len(length(line_ids) + 1L)) {
    changed <- FALSE
    for (line_id in line_ids) {
      line_key <- as.character(line_id)
      idx <- canal_idx[point_df$L1[canal_idx] == line_id]
      idx <- idx[order(point_df$idx_in_line_seg[idx])]
      if (length(idx) == 0 || !is.na(line_start_chainage[[line_key]])) next

      start_key <- point_df$canal_loc_key[idx[1]]
      upstream_at_start <- canal_idx[
        point_df$canal_loc_key[canal_idx] == start_key &
          point_df$L1[canal_idx] != line_id &
          !is.na(point_df$canal_d_nxt_m[canal_idx])
      ]
      if (length(upstream_at_start) == 0) {
        line_start_chainage[[line_key]] <- 0
      } else if (all(!is.na(point_df$chainage_m[upstream_at_start]))) {
        line_start_chainage[[line_key]] <- max(point_df$chainage_m[upstream_at_start], na.rm = TRUE)
      } else {
        next
      }

      line_coords <- coords_utm[idx, , drop = FALSE]
      seg_d <- rep(0, length(idx))
      if (length(idx) > 1) {
        seg_d[-length(idx)] <- sqrt(rowSums((line_coords[-length(idx), , drop = FALSE] -
                                               line_coords[-1, , drop = FALSE])^2))
      }
      reach_chainage <- c(0, cumsum(seg_d[-length(seg_d)]))
      point_df$canal_reach_chainage_m[idx] <- reach_chainage
      point_df$chainage_m[idx] <- line_start_chainage[[line_key]] + reach_chainage
      point_df$canal_d_nxt_m[idx] <- seg_d
      changed <- TRUE
    }
    if (!changed) break
  }

  for (line_id in line_ids) {
    idx <- canal_idx[point_df$L1[canal_idx] == line_id]
    if (length(idx) == 0) next
    first <- idx[which.min(point_df$idx_in_line_seg[idx])]
    src <- line_df[point_df$L1[first], , drop = FALSE]
    point_df$canal_id[idx] <- if ("id" %in% names(src)) as.character(src$id[1]) else as.character(point_df$ARCID[first])
    point_df$canal_name[idx] <- if ("canal_name" %in% names(src)) as.character(src$canal_name[1]) else point_df$canal_id[idx]
    point_df$canal_idx[idx] <- point_df$idx_in_line_seg[idx]

    seg_q_head <- if ("q_head" %in% names(src)) src$q_head[1] else NA_real_
    seg_q_tail <- if ("q_tail" %in% names(src)) src$q_tail[1] else NA_real_
    if (!is.na(seg_q_head) && !is.na(seg_q_tail)) {
      reach <- point_df$canal_reach_chainage_m[idx]
      max_reach <- suppressWarnings(max(reach, na.rm = TRUE))
      frac <- if (is.finite(max_reach) && max_reach > 0) reach / max_reach else rep(0, length(idx))
      frac[is.na(frac)] <- 0
      section_q <- seg_q_head + (seg_q_tail - seg_q_head) * frac
      point_df$Q_design_m3s[idx] <- section_q
      point_df$Q_model_m3s[idx] <- section_q
      point_df$Q_source[idx] <- "section_head_tail_interpolation"
    } else {
      point_df$Q_source[idx] <- "missing_section_discharge"
    }
  }

  node_ids <- as.character(point_df$ID)
  upstream <- vector("list", nrow(point_df))
  downstream <- vector("list", nrow(point_df))
  for (i in seq_len(nrow(point_df))) {
    upstream[[i]] <- character(0)
    downstream[[i]] <- character(0)
  }

  for (line_id in line_ids) {
    idx <- canal_idx[point_df$L1[canal_idx] == line_id]
    idx <- idx[order(point_df$idx_in_line_seg[idx])]
    if (length(idx) < 2) next
    for (k in seq_len(length(idx) - 1L)) {
      downstream[[idx[k]]] <- unique(c(downstream[[idx[k]]], node_ids[idx[k + 1L]]))
      upstream[[idx[k + 1L]]] <- unique(c(upstream[[idx[k + 1L]]], node_ids[idx[k]]))
    }
  }
  intrinsic_downstream <- downstream
  intrinsic_upstream <- upstream

  loc_groups <- split(canal_idx, point_df$canal_loc_key[canal_idx])
  for (members in loc_groups) {
    if (length(members) < 2) next
    incoming <- unique(unlist(upstream[members], use.names = FALSE))
    outgoing <- unique(unlist(downstream[members], use.names = FALSE))
    for (m in members) {
      upstream[[m]] <- unique(c(upstream[[m]], setdiff(incoming, node_ids[members])))
      # Branch starts at the same coordinate should not inherit sibling
      # downstream paths. Only terminal parent rows at that shared coordinate
      # fan out to all outgoing canal branches.
      if (length(intrinsic_upstream[[m]]) > 0 || length(intrinsic_downstream[[m]]) == 0) {
        downstream[[m]] <- unique(c(downstream[[m]], setdiff(outgoing, node_ids[members])))
      }
    }
  }

  up_count <- lengths(upstream)
  down_count <- lengths(downstream)
  point_df$canal_upstream_ids[canal_idx] <- vapply(upstream[canal_idx], paste, collapse = "|", FUN.VALUE = character(1))
  point_df$canal_downstream_ids[canal_idx] <- vapply(downstream[canal_idx], paste, collapse = "|", FUN.VALUE = character(1))
  point_df$canal_upstream_ids[point_df$canal_upstream_ids == ""] <- NA_character_
  point_df$canal_downstream_ids[point_df$canal_downstream_ids == ""] <- NA_character_
  point_df$canal_upstream_count[canal_idx] <- up_count[canal_idx]
  point_df$canal_downstream_count[canal_idx] <- down_count[canal_idx]

  canal_type <- rep(NA_character_, nrow(point_df))
  canal_type[canal_idx] <- "CANAL_NODE"
  canal_type[canal_idx[up_count[canal_idx] == 0 & down_count[canal_idx] >= 1]] <- "CANAL_START"
  canal_type[canal_idx[up_count[canal_idx] >= 1 & down_count[canal_idx] == 0]] <- "CANAL_END"
  canal_type[canal_idx[up_count[canal_idx] >= 1 & down_count[canal_idx] >= 2]] <- "CANAL_BRANCH"
  canal_type[canal_idx[up_count[canal_idx] >= 2 & down_count[canal_idx] == 1]] <- "CANAL_JUNCTION"
  point_df$canal_pt_type <- canal_type
  point_df$pt_type[canal_idx] <- point_df$canal_pt_type[canal_idx]

  # Apply canal upstream connections to the actual topology (ID_nxt field)
  # For canal nodes with upstream_count > 0, ensure at least one upstream node points to them.
  # This fixes cases where canal topology analysis identifies upstream connections but
  # the geometric topology (based on actual node connections) does not have them.
  # IMPORTANT: Only create connections when nodes are at the same coordinates (junctions).
  # Long-distance connections (>1m) are likely errors in the canal topology analysis.
  for (i in canal_idx[up_count[canal_idx] > 0]) {
    upstream_ids <- SplitIdList(point_df$canal_upstream_ids[i])
    if (length(upstream_ids) > 0) {
      # Find which upstream node should point to this one
      # Only consider upstream nodes at the same coordinates (geometric junction)
      # This prevents creating incorrect long-distance connections
      current_coord <- coords_utm[i, , drop = FALSE]
      
      best_upstream_idx <- NA
      
      for (upstream_id in upstream_ids) {
        up_idx <- match(upstream_id, point_df$ID)
        if (!is.na(up_idx)) {
          up_coord <- coords_utm[up_idx, , drop = FALSE]
          distance <- sqrt(sum((current_coord - up_coord)^2))
          
          # Only consider nodes at exactly the same coordinates (junction)
          # Use 1m tolerance for floating point precision
          if (distance < 1.0) {
            best_upstream_idx <- up_idx
            message("  Connecting ", point_df$ID[best_upstream_idx], " -> ", point_df$ID[i],
                    " (junction connection, distance: ", round(distance, 6), "m)")
            break
          }
        }
      }
      
      # Update the upstream node to point to this one (only if at same coordinates)
      if (!is.na(best_upstream_idx)) {
        current_nxt <- point_df$ID_nxt[best_upstream_idx]
        # Only update if the upstream node doesn't already point to this specific node
        if (is.na(current_nxt) || current_nxt != point_df$ID[i]) {
          point_df$ID_nxt[best_upstream_idx] <- point_df$ID[i]
        }
      }
    }
  }

  for (col in c("canal_id", "canal_name", "canal_idx", "canal_upstream_ids",
                "canal_downstream_ids", "canal_upstream_count",
                "canal_downstream_count", "canal_pt_type", "chainage_m",
                "canal_reach_chainage_m", "canal_d_nxt_m",
                "Q_design_m3s", "Q_model_m3s", "Q_source")) {
    points[[col]] <- point_df[[col]]
  }

  points <- ApplyCanalMassBalance(points)

  points
}

ApplyCanalMassBalance <- function(points) {
  if (!("canal_pt_type" %in% names(points)) || !any(!is.na(points$canal_pt_type))) {
    return(points)
  }

  df <- sf::st_drop_geometry(points)
  canal_idx <- which(!is.na(df$canal_pt_type))
  if (length(canal_idx) == 0) return(points)

  if (!("Q_model_m3s" %in% names(df))) df$Q_model_m3s <- df$Q_design_m3s
  if (!("Q_source" %in% names(df))) df$Q_source <- NA_character_

  for (i in canal_idx[is.na(df$Q_model_m3s[canal_idx])]) {
    df$Q_model_m3s[i] <- df$Q_design_m3s[i]
  }

  branch_allocator_idx <- canal_idx[!grepl("^Source", df$ID[canal_idx])]
  order_idx <- branch_allocator_idx[order(df$chainage_m[branch_allocator_idx],
                                          df$canal_id[branch_allocator_idx],
                                          df$canal_idx[branch_allocator_idx])]
  for (i in order_idx) {
    downstream_ids <- SplitIdList(df$canal_downstream_ids[i])
    if (length(downstream_ids) == 0) next

    down_idx <- match(downstream_ids, df$ID)
    down_idx <- down_idx[!is.na(down_idx)]
    down_idx <- down_idx[!grepl("^Source", df$ID[down_idx])]
    if (length(down_idx) == 0) next

    available_q <- df$Q_model_m3s[i]
    if (is.na(available_q)) next

    design_q <- df$Q_design_m3s[down_idx]
    design_q[is.na(design_q) | design_q < 0] <- 0
    design_sum <- sum(design_q)
    if (design_sum <= 0) next

    if (length(down_idx) < 2) next

    scaled_q <- available_q * design_q / design_sum
    df$Q_model_m3s[down_idx] <- pmin(df$Q_model_m3s[down_idx], scaled_q, na.rm = TRUE)
    df$Q_source[down_idx] <- "mass_balance_scaled_branch"
  }

  df$Q_model_m3s[canal_idx] <- pmax(0, df$Q_model_m3s[canal_idx])
  points$Q_model_m3s <- df$Q_model_m3s
  points$Q_source <- df$Q_source
  points
}

SplitIdList <- function(x) {
  if (length(x) == 0 || is.na(x) || x == "") return(character(0))
  strsplit(as.character(x), "\\|", fixed = FALSE)[[1]]
}
