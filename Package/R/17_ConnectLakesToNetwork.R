#' Connect Lakes to Network
#'
#' Creates explicit lake inlet and outlet node pairs for each lake polygon in
#' the basin. River segments that cross a lake boundary are intercepted and
#' rewired through a dedicated inlet -> outlet pair, enabling through-lake
#' routing with a Completely Stirred Tank Reactor (CSTR) model.
#'
#' @param points sf object. Network point nodes.
#' @param HL_basin sf object. In-basin lake polygons.
#' @return A named list with `points` (updated sf object).
#' @export
ConnectLakesToNetwork <- function(points, HL_basin) {
  message("--- Step 8b: Establishing Lake Connectivity ---")

  if (is.null(HL_basin) || nrow(HL_basin) == 0) {
    message(">>> No lakes found. Skipping.")
    points$lake_in <- 0; points$lake_out <- 0; points$HL_ID_new <- 0
    return(list(points = points))
  }

  HL_basin <- EnsureSameCrs(points, HL_basin, "points", "HL_basin")
  points$lake_in <- 0; points$lake_out <- 0; points$HL_ID_new <- 0

  # Detect interior nodes
  within_indices <- sf::st_intersects(points, HL_basin)
  for (i in seq_along(within_indices)) {
    if (length(within_indices[[i]]) > 0) points$HL_ID_new[i] <- HL_basin$Hylak_id[within_indices[[i]][1]]
  }

  # Detect boundary crossings
  crossing_data <- DetectLakeSegmentCrossings(points, HL_basin)
  
  # Accumulate ops
  new_nodes <- list()
  rewire_ops <- list()
  remove_ids <- c()

  for (lake_id in unique(HL_basin$Hylak_id)) {
    lake_idx <- match(lake_id, HL_basin$Hylak_id)
    in_this_lake <- which(points$HL_ID_new == lake_id)
    if (length(in_this_lake) == 0 && !(lake_id %in% crossing_data$crossings$Hylak_id)) next

    # Get crossings
    crossings <- crossing_data$crossings[crossing_data$crossings$Hylak_id == lake_id, ]
    inlet_crossings <- crossings[crossings$crossing_type == "inlet", ]
    outlet_crossings <- crossings[crossings$crossing_type == "outlet", ]
    
    # Select best inlet: sort by upstream LD descending (higher LD = further upstream)
    best_inlet <- if (nrow(inlet_crossings) > 0) {
      inlet_lds <- points$LD[match(inlet_crossings$upstream_id, points$ID)]
      inlet_crossings[which.max(inlet_lds), ]
    } else NULL

    # Select best outlet: sort by upstream LD ascending (lower LD = further downstream)
    # Note: For outlets, we use the upstream_id (the inside node) LD
    best_outlet <- if (nrow(outlet_crossings) > 0) {
      outlet_lds <- points$LD[match(outlet_crossings$upstream_id, points$ID)]
      outlet_crossings[which.min(outlet_lds), ]
    } else NULL

    # Get coordinates for inlet and outlet nodes
    lake_centroid <- sf::st_coordinates(sf::st_centroid(HL_basin[lake_idx, ]))
    if (is.matrix(lake_centroid) && nrow(lake_centroid) >= 1) {
      centroid_coord <- lake_centroid[1, 1:2]
    } else {
      centroid_coord <- c(NA, NA)
    }

    in_coord <- if (!is.null(best_inlet)) c(best_inlet$crossing_x, best_inlet$crossing_y) else centroid_coord
    out_coord <- if (!is.null(best_outlet)) c(best_outlet$crossing_x, best_outlet$crossing_y) else centroid_coord

    # Validate that inlet and outlet coordinates differ
    # This catches the coincident-node bug where LakeIn and LakeOut are at the same location
    coord_diff <- sqrt(sum((in_coord - out_coord)^2))
    if (coord_diff < 1e-6) {
      warning(paste0("LakeIn and LakeOut coordinates are coincident for lake ", lake_id,
                     ". Adjusting LakeOut slightly downstream to ensure valid topology."))
      # Move outlet slightly downstream in the direction of the centroid
      # This is a fallback when both fall back to centroid or crossing detection failed
      if (!is.null(best_outlet)) {
        # If we have an outlet crossing, use its direction
        out_coord <- out_coord + c(1e-5, 0)
      } else {
        # Otherwise, move in a default direction (east)
        out_coord <- out_coord + c(1e-5, 0)
      }
    }

    # Create new nodes
    inlet_row <- points[1, ]; inlet_row$ID <- paste0("LakeIn_", lake_id); inlet_row$geometry <- sf::st_sfc(sf::st_point(in_coord), crs=sf::st_crs(points))
    inlet_row$lake_in <- 1; inlet_row$lake_out <- 0; inlet_row$HL_ID_new <- lake_id; inlet_row$pt_type <- "LakeInlet"; inlet_row$ID_nxt <- paste0("LakeOut_", lake_id)
    
    outlet_row <- points[1, ]; outlet_row$ID <- paste0("LakeOut_", lake_id); outlet_row$geometry <- sf::st_sfc(sf::st_point(out_coord), crs=sf::st_crs(points))
    outlet_row$lake_in <- 0; outlet_row$lake_out <- 1; outlet_row$HL_ID_new <- lake_id; outlet_row$pt_type <- "LakeOutlet"
    
    # Set outlet's ID_nxt: use best_outlet's downstream_id if it exists, otherwise NA (terminal)
    if (!is.null(best_outlet)) {
      downstream_id <- best_outlet$downstream_id
      # Check if the downstream_id exists in the current points
      if (downstream_id %in% points$ID) {
        outlet_row$ID_nxt <- downstream_id
      } else {
        outlet_row$ID_nxt <- NA
      }
    } else {
      outlet_row$ID_nxt <- NA
    }

    new_nodes[[length(new_nodes) + 1]] <- inlet_row
    new_nodes[[length(new_nodes) + 1]] <- outlet_row
    
    # Handle source nodes inside the lake - they should be rewired to point to the inlet
    # but NOT removed (unlike interior nodes)
    source_inside <- in_this_lake[points$pt_type[in_this_lake] %in%
                                    c("agglomeration", "agglomeration_lake", "WWTP")]
    interior_nodes <- in_this_lake[!points$pt_type[in_this_lake] %in%
                                     c("agglomeration", "agglomeration_lake", "WWTP")]
    
    # Rewire source nodes to point to the inlet
    for (si in source_inside) {
      rewire_ops[[points$ID[si]]] <- inlet_row$ID
    }
    
    # Track rewiring for ALL inlets (not just best_inlet)
    if (nrow(inlet_crossings) > 0) {
      for (i in seq_len(nrow(inlet_crossings))) {
        rewire_ops[[inlet_crossings$upstream_id[i]]] <- inlet_row$ID
      }
    }
    
    # Only remove interior nodes (not source nodes)
    remove_ids <- c(remove_ids, points$ID[interior_nodes])
  }

  # Apply rewiring
  for (fid in names(rewire_ops)) points$ID_nxt[points$ID == fid] <- rewire_ops[[fid]]
  
  # Cleanup
  points <- points[!points$ID %in% remove_ids, ]
  if (length(new_nodes) > 0) points <- rbind(points, do.call(rbind, new_nodes))

  # Recalculate LD/topology (placeholder for the mandatory rebuild)
  message(">>> Lake connectivity updated. Run topology rebuild.")
  list(points = points)
}
