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
    non_physical <- tolower(as.character(points$pt_type)) %in% c(
      "agglomeration", "agglomeration_lake", "wwtp", "lakeinlet", "lakeoutlet"
    )
    canal_class_idx <- canal_class_idx[!non_physical[canal_class_idx]]
    points$pt_type[canal_class_idx] <- points$canal_pt_type[canal_class_idx]
  }

  list(
    lines = lines,
    hydro_sheds_rivers = lines,
    points = points
  )
}

AnnotateDisplayJunctions <- function(points, coord_digits = 7) {
  if (is.null(points) || nrow(points) == 0 || !all(c("ID", "ID_nxt", "pt_type") %in% names(points))) {
    return(points)
  }

  if (!all(c("x", "y") %in% names(points))) {
    coords <- sf::st_coordinates(points)
    points$x <- coords[, 1]
    points$y <- coords[, 2]
  }

  pt_type <- as.character(points$pt_type)
  points$display_pt_type <- pt_type
  points$junction_role <- NA_character_

  valid_next <- !is.na(points$ID_nxt) & points$ID_nxt != ""
  incoming_count <- table(points$ID_nxt[valid_next])
  fanin_ids <- names(incoming_count)[incoming_count >= 2]

  coord_key <- paste(round(points$x, coord_digits), round(points$y, coord_digits), sep = "_")
  true_junction_idx <- which(points$ID %in% fanin_ids | pt_type == "JNCT")
  if (length(true_junction_idx) == 0) {
    return(points)
  }

  junction_keys <- unique(coord_key[true_junction_idx])
  at_junction_coord <- coord_key %in% junction_keys
  source_or_special <- pt_type %in% c(
    "agglomeration", "agglomeration_lake", "WWTP",
    "LakeInlet", "LakeOutlet", "Hydro_Lake",
    "START", "MOUTH"
  )
  canal_node <- if ("is_canal" %in% names(points)) {
    !is.na(points$is_canal) & as.logical(points$is_canal)
  } else {
    rep(FALSE, nrow(points))
  }

  display_idx <- which(at_junction_coord & !source_or_special & !canal_node)
  points$junction_role[true_junction_idx] <- "fan_in_receiver"
  points$junction_role[setdiff(display_idx, true_junction_idx)] <- "coincident_confluence_node"
  points$display_pt_type[display_idx] <- "JNCT"

  points
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
  non_physical <- tolower(as.character(point_df$pt_type)) %in% c(
    "agglomeration", "agglomeration_lake", "wwtp", "lakeinlet", "lakeoutlet"
  )
  canal_class_idx <- canal_idx[!non_physical[canal_idx]]
  point_df$pt_type[canal_class_idx] <- point_df$canal_pt_type[canal_class_idx]

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
          up_pt <- if ("pt_type" %in% names(point_df)) as.character(point_df$pt_type[up_idx]) else NA_character_
          up_is_physical <- !is.na(up_pt) && up_pt %in% c("CANAL_START", "CANAL_NODE", "CANAL_BRANCH", "CANAL_JUNCTION", "CANAL_END")
          if (!up_is_physical) next

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
  df$Q_role <- NA_character_
  df$Q_parent_m3s <- NA_real_
  df$Q_out_sum_m3s <- NA_real_
  df$Q_residual_m3s <- NA_real_

  for (i in canal_idx[is.na(df$Q_model_m3s[canal_idx])]) {
    df$Q_model_m3s[i] <- df$Q_design_m3s[i]
  }

  df <- ApplyCanalPiecewiseResiduals(df, canal_idx)

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

  df <- AnnotateCanalQRoles(df, canal_idx)

  df$Q_model_m3s[canal_idx] <- pmax(0, df$Q_model_m3s[canal_idx])
  points$Q_model_m3s <- df$Q_model_m3s
  points$Q_source <- df$Q_source
  points$Q_role <- df$Q_role
  points$Q_parent_m3s <- df$Q_parent_m3s
  points$Q_out_sum_m3s <- df$Q_out_sum_m3s
  points$Q_residual_m3s <- df$Q_residual_m3s
  points
}

ApplyCanalPiecewiseResiduals <- function(df, canal_idx) {
  if (!all(c("L1", "canal_idx", "canal_reach_chainage_m", "canal_downstream_ids") %in% names(df))) {
    return(df)
  }

  loc_key <- paste(round(df$x, 7), round(df$y, 7), sep = "_")
  line_ids <- unique(df$L1[canal_idx])
  line_ids <- line_ids[!is.na(line_ids)]

  for (line_id in line_ids) {
    idx <- canal_idx[df$L1[canal_idx] == line_id]
    idx <- idx[order(df$canal_reach_chainage_m[idx], df$canal_idx[idx])]
    if (length(idx) < 2) next

    q_head <- df$Q_design_m3s[idx[which.min(df$canal_reach_chainage_m[idx])]]
    q_tail <- df$Q_design_m3s[idx[which.max(df$canal_reach_chainage_m[idx])]]
    if (is.na(q_head) || is.na(q_tail)) next

    max_reach <- max(df$canal_reach_chainage_m[idx], na.rm = TRUE)
    if (!is.finite(max_reach) || max_reach <= 0) next

    internal_events <- list()
    for (key in unique(loc_key[idx])) {
      members <- canal_idx[loc_key[canal_idx] == key]
      parent_members <- intersect(members, idx)
      child_starts <- members[
        df$L1[members] != line_id &
          !is.na(df$canal_idx[members]) &
          df$canal_idx[members] == 1
      ]
      if (length(parent_members) == 0 || length(child_starts) == 0) next

      event_reach <- max(df$canal_reach_chainage_m[parent_members], na.rm = TRUE)
      if (!is.finite(event_reach) || event_reach <= 0 || event_reach >= max_reach) next

      child_q <- sum(df$Q_design_m3s[child_starts], na.rm = TRUE)
      if (child_q > 0) {
        internal_events[[length(internal_events) + 1L]] <- list(
          reach = event_reach,
          child_q = child_q,
          key = key
        )
      }
    }
    if (length(internal_events) == 0) next

    events_df <- do.call(rbind, lapply(internal_events, as.data.frame))
    total_internal_child_q <- sum(events_df$child_q, na.rm = TRUE)
    head_to_tail_drop <- q_head - q_tail
    if (!is.finite(total_internal_child_q) || total_internal_child_q <= 0) next

    # If the section head-to-tail drop is explained by internal offtakes, keep
    # upstream flow constant until the offtake, then route the residual onward.
    if (abs(total_internal_child_q - head_to_tail_drop) <= 0.05) {
      events_df <- events_df[order(events_df$reach), , drop = FALSE]
      for (row in seq_len(nrow(events_df))) {
        event_reach <- events_df$reach[row]
        event_idx <- idx[abs(df$canal_reach_chainage_m[idx] - event_reach) <= 1e-6]
        parent_available <- q_head - if (row > 1) sum(events_df$child_q[seq_len(row - 1L)], na.rm = TRUE) else 0
        df$Q_model_m3s[event_idx] <- parent_available
        df$Q_source[event_idx] <- "piecewise_parent_available_at_offtake"
        downstream_idx <- idx[df$canal_reach_chainage_m[idx] > event_reach]
        df$Q_model_m3s[downstream_idx] <- pmax(q_tail, q_head - sum(events_df$child_q[seq_len(row)], na.rm = TRUE))
        df$Q_source[downstream_idx] <- "piecewise_internal_offtake_residual"
      }
      upstream_idx <- idx[df$canal_reach_chainage_m[idx] < min(events_df$reach, na.rm = TRUE)]
      df$Q_model_m3s[upstream_idx] <- q_head
      df$Q_source[upstream_idx] <- "piecewise_upstream_of_offtake"
    }
  }

  df
}

AnnotateCanalQRoles <- function(df, canal_idx) {
  loc_key <- paste(round(df$x, 7), round(df$y, 7), sep = "_")
  df$Q_role[canal_idx] <- "through_flow"

  for (key in unique(loc_key[canal_idx])) {
    members <- canal_idx[loc_key[canal_idx] == key]
    if (length(members) < 2) next

    child_starts <- members[
      !is.na(df$canal_idx[members]) &
        df$canal_idx[members] == 1 &
        !is.na(df$Q_model_m3s[members])
    ]
    if (length(child_starts) == 0) next

    parent_candidates <- setdiff(members, child_starts)
    if (length(parent_candidates) == 0) next

    parent_idx <- parent_candidates[which.max(df$Q_model_m3s[parent_candidates])]
    parent_q <- df$Q_model_m3s[parent_idx]
    child_sum <- sum(df$Q_model_m3s[child_starts], na.rm = TRUE)
    residual <- parent_q - child_sum

    df$Q_role[parent_idx] <- "parent_branch_available"
    df$Q_parent_m3s[parent_idx] <- parent_q
    df$Q_out_sum_m3s[parent_idx] <- child_sum
    df$Q_residual_m3s[parent_idx] <- residual

    df$Q_role[child_starts] <- "child_branch_outflow"
    df$Q_parent_m3s[child_starts] <- parent_q
    df$Q_out_sum_m3s[child_starts] <- child_sum
    df$Q_residual_m3s[child_starts] <- residual

    sibling_parents <- setdiff(parent_candidates, parent_idx)
    if (length(sibling_parents) > 0) {
      df$Q_parent_m3s[sibling_parents] <- parent_q
      df$Q_out_sum_m3s[sibling_parents] <- child_sum
      df$Q_residual_m3s[sibling_parents] <- residual
    }
  }

  terminal_idx <- canal_idx[is.na(df$ID_nxt[canal_idx]) | df$ID_nxt[canal_idx] == ""]
  df$Q_role[terminal_idx] <- ifelse(
    is.na(df$Q_role[terminal_idx]) | df$Q_role[terminal_idx] == "through_flow",
    "terminal_residual",
    df$Q_role[terminal_idx]
  )

  df
}

BuildCanalEdges <- function(points) {
  if (is.null(points) || nrow(points) == 0 || !("is_canal" %in% names(points))) {
    return(data.frame())
  }
  df <- if (inherits(points, "sf")) sf::st_drop_geometry(points) else points
  canal_idx <- which(df$is_canal %in% TRUE)
  if (length(canal_idx) == 0 || !("canal_downstream_ids" %in% names(df))) {
    return(data.frame())
  }
  loc_key <- paste(round(df$x, 7), round(df$y, 7), sep = "_")

  is_physical_canal <- rep(FALSE, nrow(df))
  if ("canal_pt_type" %in% names(df)) {
    physical_types <- c("CANAL_START", "CANAL_NODE", "CANAL_BRANCH", "CANAL_JUNCTION", "CANAL_END")
    non_physical_pt <- if ("pt_type" %in% names(df)) {
      as.character(df$pt_type) %in% c("agglomeration", "agglomeration_lake", "WWTP", "LakeInlet", "LakeOutlet")
    } else {
      rep(FALSE, nrow(df))
    }
    is_physical_canal <- !is.na(df$canal_pt_type) & df$canal_pt_type %in% physical_types & !non_physical_pt
  }

  resolve_physical_target <- function(start_idx, expected_canal, max_hops = 100L) {
    if (is.na(start_idx) || start_idx <= 0) return(NA_integer_)
    cur <- start_idx
    hops <- 0L
    while (hops < max_hops) {
      if (isTRUE(is_physical_canal[cur]) && identical(as.character(df$canal_name[cur]), as.character(expected_canal))) {
        return(cur)
      }
      nxt_id <- df$ID_nxt[cur]
      if (is.na(nxt_id) || nxt_id == "") return(NA_integer_)
      nxt_idx <- match(nxt_id, df$ID)
      if (is.na(nxt_idx)) return(NA_integer_)
      if (nxt_idx == cur) return(NA_integer_)
      cur <- nxt_idx
      hops <- hops + 1L
    }
    NA_integer_
  }

  edge_dist_m <- function(i, j) {
    same_canal <- identical(as.character(df$canal_name[i]), as.character(df$canal_name[j]))
    if (same_canal && all(c("chainage_m") %in% names(df)) && is.finite(df$chainage_m[i]) && is.finite(df$chainage_m[j])) {
      d <- abs(df$chainage_m[j] - df$chainage_m[i])
      if (is.finite(d)) return(as.numeric(d))
    }
    if (all(c("x", "y") %in% names(df))) {
      p1 <- sf::st_sfc(sf::st_point(c(as.numeric(df$x[i]), as.numeric(df$y[i]))), crs = 4326)
      p2 <- sf::st_sfc(sf::st_point(c(as.numeric(df$x[j]), as.numeric(df$y[j]))), crs = 4326)
      return(as.numeric(sf::st_distance(p1, p2)))
    }
    NA_real_
  }

  rows <- list()
  for (i in canal_idx[is_physical_canal[canal_idx]]) {
    downstream_ids <- SplitIdList(df$canal_downstream_ids[i])
    if (length(downstream_ids) == 0) next
    for (to_id in downstream_ids) {
      raw_j <- match(to_id, df$ID)
      if (is.na(raw_j)) next
      to_canal <- as.character(df$canal_name[raw_j])
      j <- resolve_physical_target(raw_j, expected_canal = to_canal)
      if (is.na(j)) next

      edge_type <- if (df$canal_name[i] != df$canal_name[j]) "canal_branch" else "canal_reach"
      if (edge_type == "canal_branch" && !isTRUE(df$Q_role[i] == "parent_branch_available")) {
        next
      }
      branch_target_idx <- j
      if (edge_type == "canal_branch") {
        same_coord_child_start <- canal_idx[
          loc_key[canal_idx] == loc_key[i] &
            df$canal_name[canal_idx] == df$canal_name[j] &
            !is.na(df$canal_idx[canal_idx]) &
            df$canal_idx[canal_idx] == 1
        ]
        if (length(same_coord_child_start) > 0) {
          branch_target_idx <- same_coord_child_start[1]
        }
      }
      edge_q <- if (edge_type == "canal_branch" && !is.na(df$Q_model_m3s[branch_target_idx])) {
        df$Q_model_m3s[branch_target_idx]
      } else {
        df$Q_model_m3s[i]
      }
      rows[[length(rows) + 1L]] <- data.frame(
        from_id = df$ID[i],
        to_id = df$ID[j],
        from_canal = df$canal_name[i],
        to_canal = df$canal_name[j],
        edge_type = edge_type,
        dist_m = edge_dist_m(i, j),
        chainage_from_m = df$chainage_m[i],
        chainage_to_m = df$chainage_m[j],
        Q_model_m3s = edge_q,
        Q_parent_m3s = df$Q_parent_m3s[i],
        Q_out_sum_m3s = df$Q_out_sum_m3s[i],
        Q_residual_m3s = df$Q_residual_m3s[i],
        flow_fraction = if (!is.na(df$Q_parent_m3s[i]) && df$Q_parent_m3s[i] > 0) edge_q / df$Q_parent_m3s[i] else NA_real_,
        q_source = df$Q_source[i],
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) return(data.frame())
  out <- do.call(rbind, rows)
  out <- out[!duplicated(out[, c("from_id", "to_id", "edge_type")]), , drop = FALSE]
  out
}

BuildCanalQDiagnostics <- function(points, tolerance = 1e-6) {
  edges <- BuildCanalEdges(points)
  if (nrow(edges) == 0) return(data.frame())
  branch_edges <- edges[edges$edge_type == "canal_branch", , drop = FALSE]
  if (nrow(branch_edges) == 0) return(data.frame())
  diagnostics <- lapply(split(branch_edges, branch_edges$from_id), function(x) {
      parent_candidates <- x$Q_parent_m3s[!is.na(x$Q_parent_m3s)]
      parent_q <- if (length(parent_candidates) > 0) parent_candidates[1] else NA_real_
      out_sum <- sum(x$Q_model_m3s, na.rm = TRUE)
      data.frame(
        from_id = x$from_id[1],
        from_canal = x$from_canal[1],
        n_branch_edges = nrow(x),
        Q_parent_m3s = parent_q,
        Q_branch_sum_m3s = out_sum,
        Q_residual_m3s = parent_q - out_sum,
        mass_balance_ok = is.na(parent_q) || out_sum <= parent_q + tolerance,
        downstream_ids = paste(x$to_id, collapse = "|"),
        downstream_canals = paste(x$to_canal, collapse = "|"),
        stringsAsFactors = FALSE
      )
    })
  do.call(rbind, diagnostics)
}

SplitIdList <- function(x) {
  if (length(x) == 0 || is.na(x) || x == "") return(character(0))
  strsplit(as.character(x), "\\|", fixed = FALSE)[[1]]
}
