EnsureColumn <- function(data, columnName, insertValue = NA) {
  if (!(columnName %in% colnames(data))) {
    data[[columnName]] <- insertValue
  }
  return(data)
}

EnsureColumns <- function(df, cols, default = NA) {
  missing <- setdiff(cols, names(df))
  for (col in missing) {
    df[[col]] <- default
  }
  df
}

# Determine UTM zone from center longitude of object
# Returns CRS string for projected coordinate system in meters
GetUtmCrs <- function(obj) {
  bbox <- sf::st_bbox(obj)
  center_lon <- mean(c(bbox["xmin"], bbox["xmax"]))
  utm_zone <- floor((center_lon + 180) / 6) + 1
  paste0("+proj=utm +zone=", utm_zone, " +datum=WGS84 +units=m +no_defs")
}

# Ensure two spatial objects have the same CRS for valid spatial operations
# Transforms obj to match ref_obj if CRS differs, otherwise returns unchanged
EnsureSameCrs <- function(ref_obj, obj, ref_name = "ref_obj", obj_name = "obj") {
  if (is.na(sf::st_crs(ref_obj))) stop("Missing CRS on ", ref_name)
  if (is.na(sf::st_crs(obj))) stop("Missing CRS on ", obj_name)
  if (sf::st_crs(ref_obj) != sf::st_crs(obj)) {
    message("Transforming ", obj_name, " to match ", ref_name)
    obj <- sf::st_transform(obj, sf::st_crs(ref_obj))
  }
  obj
}

# Break a multi-point linestring into individual 2-point segments
# Each segment gets a unique segment_id (e.g., "12345_seg_1", "12345_seg_2")
# Used to create snap targets for population/WWTP points
BreakLinestringIntoSegments <- function(linestring, original_id, crs) {
  coords <- sf::st_coordinates(linestring)
  if (nrow(coords) < 2) return(NULL)
  segments <- vector("list", nrow(coords) - 1)
  for (i in seq_len(nrow(coords) - 1)) {
    segments[[i]] <- sf::st_linestring(rbind(coords[i, ], coords[i + 1, ]))
  }
  segments_sfc <- sf::st_sfc(segments, crs = crs)
  sf::st_sf(
    geometry = segments_sfc,
    segment_id = paste0(original_id, "_seg_", seq_along(segments)),
    original_id = original_id,
    type = "river_segment"
  )
}

# Greedy nearest-neighbor ordering to arrange points along a line from upstream to downstream
# Then compute inter-point distances (d_nxt) and cumulative distance downstream (LD)
# Used when merging source points into river segments
OrderPointsOnSegment <- function(points_to_order, base_points, segment_id, segment_crs) {
  if (nrow(points_to_order) == 0) return(NULL)
  
  points_to_order <- sf::st_transform(points_to_order, segment_crs)
  
  next_idx <- 1
  ordered_points <- NULL
  
  while (nrow(points_to_order) > 0) {
    select <- points_to_order[next_idx, ]
    points_to_order <- points_to_order[-next_idx, ]
    
    if (is.null(ordered_points)) {
      ordered_points <- select
    } else {
      ordered_df <- as.data.frame(ordered_points)
      ordered_df$geometry <- NULL
      select_df <- as.data.frame(select)
      select_df$geometry <- NULL
      ordered_points <- sf::st_as_sf(
        plyr::rbind.fill(ordered_df, select_df),
        coords = c("X", "Y"),
        crs = segment_crs,
        remove = FALSE
      )
    }
    
    if (nrow(points_to_order) > 0) {
      next_idx <- which.min(CalcEuclideanDist(select, points_to_order))
    }
  }
  
  n_p <- nrow(ordered_points)
  if (n_p > 1) {
    ordered_points$ID_nxt[seq_len(n_p - 1)] <- ordered_points$ID[2:n_p]
    for (j in seq_len(n_p - 1)) {
      ordered_points$d_nxt[j] <- SafeStDistance(ordered_points[j, ], ordered_points[j + 1, ])[1]
    }
  }
  ordered_points$idx_in_line_seg <- seq_len(n_p)
  ordered_points$LD <- 0
  if (n_p > 1) {
    for (j in 2:n_p) {
      ordered_points$LD[j] <- ordered_points$LD[j - 1] + ordered_points$d_nxt[j - 1]
    }
  }
  ordered_points$LD2 <- ordered_points$LD
  
  ordered_points
}

# Prepare agglomeration/WWTP source points for integration into the network
# Assigns IDs, extracts coordinates, and resolves which river segment (L1/ARCID) each source maps to
# Returns points ready to be merged with river network nodes
PrepareAgglomerationPoints <- function(agglomeration_points, lines_sf) {
  if (is.null(agglomeration_points) || nrow(agglomeration_points) == 0) return(NULL)
  
  pts <- agglomeration_points
  pts$ID <- paste0("Source", stringr::str_pad(seq_len(nrow(pts)), 5, "left", "0"))
  
  pts_transformed <- sf::st_transform(pts, sf::st_crs(lines_sf))
  pts_coords <- sf::st_coordinates(pts_transformed)
  
  pts$X_snapped <- pts_coords[, 1]
  pts$Y_snapped <- pts_coords[, 2]
  
  snapped_index <- if ("L1" %in% names(pts) && any(!is.na(pts$L1))) {
    as.numeric(pts$L1)
  } else if ("original_id" %in% names(pts) && any(!is.na(pts$original_id))) {
    as.numeric(pts$original_id)
  } else if ("nearest_segment_index" %in% names(pts) && any(!is.na(pts$nearest_segment_index))) {
    as.numeric(pts$nearest_segment_index)
  } else {
    NA_real_
  }
  pts$Index_snapped <- snapped_index
  
  pts$ID_nxt <- pts$d_nxt <- pts$LD <- pts$loc_ID_tmp <- pts$LD2 <- NA
  pts$lineIdx <- pts$Index_snapped
  
  if (!("HL_ID_new" %in% names(pts))) pts$HL_ID_new <- 0
  if (!("lake_in" %in% names(pts))) pts$lake_in <- 0
  if (!("lake_out" %in% names(pts))) pts$lake_out <- 0
  
  if (!("pt_type" %in% names(pts))) {
    pts$pt_type <- if ("node_type" %in% names(pts)) pts$node_type else "agglomeration"
  }
  
  pts$idx_nxt_tmp <- pts$idx_in_line_seg <- NA
  pts$L1 <- pts$Index_snapped
  pts$x <- pts$X_snapped
  pts$y <- pts$Y_snapped
  pts$X <- pts$x
  pts$Y <- pts$y
  pts$ARCID <- pts$UP_CELLS <- pts$dir <- NA
  pts$is_canal <- FALSE
  pts
}

# Merge source points (WWTPs, agglomerations) into a single river line segment
# Interleaves river nodes with source points, re-orders by distance, re-computes ID_nxt chain and LD values
# Called for each river segment during the integration step
MergePointsForSegment <- function(pts_in_seg, points_in_seg, points_all, lidx, target_crs, desired_columns) {
  psub <- sf::st_transform(pts_in_seg, target_crs)
  points_sub <- sf::st_transform(points_in_seg, target_crs)
  
  psub <- EnsureColumns(psub, desired_columns, NA)
  points_sub <- EnsureColumns(points_sub, desired_columns, NA)
  psub <- psub[desired_columns]
  points_sub <- points_sub[desired_columns]
  
  psub$ARCID <- stats::median(points_sub$ARCID, na.rm = TRUE)
  psub$UP_CELLS <- stats::median(points_sub$UP_CELLS, na.rm = TRUE)
  psub$dir <- 0
  if ("is_canal" %in% names(points_sub)) {
    source_on_canal <- any(points_sub$is_canal %in% TRUE, na.rm = TRUE)
    psub$is_canal <- source_on_canal
    if (source_on_canal && "Q_model_m3s" %in% names(points_sub)) {
      model_q <- points_sub$Q_model_m3s[!is.na(points_sub$Q_model_m3s)]
      if (length(model_q) > 0) psub$Q_model_m3s <- stats::median(model_q)
    }
    if (source_on_canal && "Q_design_m3s" %in% names(points_sub)) {
      design_q <- points_sub$Q_design_m3s[!is.na(points_sub$Q_design_m3s)]
      if (length(design_q) > 0) psub$Q_design_m3s <- stats::median(design_q)
    }
  }

  psub_df <- as.data.frame(psub)
  points_sub_df <- as.data.frame(points_sub)
  psub_coords <- sf::st_coordinates(psub)
  psub_df$X <- psub_coords[, 1]
  psub_df$Y <- psub_coords[, 2]
  psub_df$geometry <- NULL
  points_coords <- sf::st_coordinates(points_sub)
  points_sub_df$X <- points_coords[, 1]
  points_sub_df$Y <- points_coords[, 2]
  points_sub_df$geometry <- NULL
  
  points_new_lsub_df <- plyr::rbind.fill(points_sub_df, psub_df)
  points_new_lsub_df <- points_new_lsub_df[!is.na(points_new_lsub_df$X) & !is.na(points_new_lsub_df$Y), ]
  points_new_lsub <- sf::st_as_sf(points_new_lsub_df, coords = c("X", "Y"), crs = target_crs, remove = FALSE)
  
  points_new_ordered <- OrderPointsOnSegment(points_new_lsub, points_all, lidx, target_crs)
  
  if (!is.null(points_new_ordered)) {
    if (nrow(points_sub) > 0) {
      last_river_id <- points_sub$ID[nrow(points_sub)]
      last_river_id_nxt <- points_sub$ID_nxt[nrow(points_sub)]
      
      last_in_ordered <- which(points_new_ordered$ID == last_river_id)
      if (length(last_in_ordered) > 0 && !is.na(last_river_id_nxt)) {
        points_new_ordered$ID_nxt[last_in_ordered] <- last_river_id_nxt
        last_idx <- which(points_all$ID == last_river_id_nxt)
        if (length(last_idx) > 0) {
          points_new_ordered$d_nxt[last_in_ordered] <- SafeStDistance(
            points_new_ordered[last_in_ordered, ],
            sf::st_transform(points_all[last_idx, ], sf::st_crs(points_new_ordered))
          )[1]
        }
      }
    }
  }
  points_new_ordered
}

# Type coercion helper - ensures character columns stay character and numeric stay numeric after rbind.fill
# Used after merging dataframes with different column sets
CoerceSchema <- function(df, char_cols = character(0), num_cols = character(0)) {
  present_char <- intersect(char_cols, names(df))
  present_num <- intersect(num_cols, names(df))
  for (col in present_char) df[[col]] <- as.character(df[[col]])
  for (col in present_num) df[[col]] <- SafeAsNumeric(df[[col]])
  df
}

# Safely convert to numeric, suppressing warnings for NA conversions
SafeAsNumeric <- function(vec) {
  if (is.numeric(vec)) return(vec)
  suppressWarnings(as.numeric(as.character(vec)))
}

# Compute distance between two spatial objects, ensuring they share a CRS first
SafeStDistance <- function(a, b) {
  if (nrow(a) == 0 || nrow(b) == 0) return(numeric(0))
  b <- EnsureSameCrs(a, b, "a", "b")
  as.numeric(sf::st_distance(a, b))
}

CalcEuclideanDist <- function(p1, p2_list) {
  sqrt((p1$X - p2_list$X)^2 + (p1$Y - p2_list$Y)^2)
}

# Quick bounding-box overlap test to avoid expensive raster operations when there's no spatial intersection
# Returns TRUE if extents overlap, FALSE otherwise
ExtentOverlap <- function(ext1, ext2) {
  ext1 <- as.vector(ext1)
  ext2 <- as.vector(ext2)
  !(ext1[2] < ext2[1] || ext1[1] > ext2[2] || ext1[4] < ext2[3] || ext1[3] > ext2[4])
}

ValidateState <- function(state, required_keys, module_name = "module") {
  missing <- setdiff(required_keys, names(state))
  if (length(missing) > 0) {
    stop("State validation failed for ", module_name, ". Missing keys: ", paste(missing, collapse = ", "))
  }
  invisible(TRUE)
}

ValidateSchema <- function(df, required_cols, label = "dataframe") {
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    stop("Schema validation failed for ", label, ". Missing columns: ", paste(missing, collapse = ", "))
  }
  invisible(TRUE)
}

PrintCheckpointSummary <- function(state) {
  message("--- Checkpoint Summary ---")
  message("State keys: ", paste(names(state), collapse = ", "))
  
  if (!is.null(state$points)) {
    points_crs <- if (inherits(state$points, "sf")) sf::st_crs(state$points)$input else "N/A"
    message("Points: ", nrow(state$points), " | CRS: ", points_crs)
  }
  
  if (!is.null(state$river_segments_sf)) {
    edges_crs <- if (inherits(state$river_segments_sf, "sf")) sf::st_crs(state$river_segments_sf)$input else "N/A"
    message("River edges: ", nrow(state$river_segments_sf), " | CRS: ", edges_crs)
  }
  
  if (!is.null(state$HL_basin)) {
    lakes_crs <- if (inherits(state$HL_basin, "sf")) sf::st_crs(state$HL_basin)$input else "N/A"
    message("Lakes: ", nrow(state$HL_basin), " | CRS: ", lakes_crs)
  }
  
  mem_size <- format(object.size(state), units = "auto")
  message("Memory usage: ", mem_size)
  message("------------------------")
}
