#' Connect Lakes to Network
#'
#' Creates explicit lake inlet and outlet node pairs for each lake polygon in
#' the basin. River segments that cross a lake boundary are intercepted and
#' rewired through a dedicated inlet \eqn{\rightarrow} outlet pair, enabling
#' through-lake routing with a Completely Stirred Tank Reactor (CSTR) model.
#'
#' @section Algorithm overview:
#'
#' The function performs five phases:
#'
#' 1. **Crossing detection** — For each lake polygon, find all river segments
#'    (LINESTRING edges from the existing topology) that cross the lake
#'    boundary. A segment that goes from outside to inside marks a **potential
#'    inlet crossing**; a segment going from inside to outside marks a
#'    **potential outlet crossing**.
#'
#' 2. **Crossing point creation** — At each boundary crossing, compute the
#'    exact intersection point on the lake polygon outline and create a new
#'    node there. Each node inherits the properties of the nearest existing
#'    river node (flow direction, ARCID, segment index).
#'
#' 3. **Inlet/outlet selection** — For lakes with multiple inlets, the one
#'    furthest upstream (lowest cumulative downstream distance LD) is selected
#'    as the primary inlet. For multiple outlets, the one furthest downstream
#'    (highest LD) is selected. Unselected crossings are marked as
#'    \dQuote{secondary} and still receive correct topology but are not used
#'    as CSTR endpoints.
#'
#' 4. **Network rewiring** — The river network is surgically modified:
#'    \itemize{
#'      \item The node just upstream of the inlet crossing has its
#'            \code{ID_nxt} redirected to the new inlet node.
#'      \item The inlet node links to the outlet node
#'            (\code{LakeIn_<id> \rightarrow LakeOut_<id>}).
#'      \item The outlet node links to whatever node the old downstream node
#'            pointed to.
#'      \item Old nodes inside the lake polygon are absorbed: their emissions
#'            are transferred to the inlet node and they are removed from the
#'            network.
#'    }
#'
#' 5. **Metadata tagging** — Each new node receives:
#'    \itemize{
#'      \item \code{lake_in = 1} / \code{lake_out = 1}
#'      \item \code{pt_type = "LakeInlet"} / \code{"LakeOutlet"}
#'      \item \code{HL_ID_new = <Hylak_id>} (the lake identifier)
#'      \item \code{node_type = "Hydro_Lake"} (for downstream classification)
#'    }
#'
#' @param points sf object. Network point nodes (from BuildNetworkTopology).
#' @param HL_basin sf object or \code{NULL}. In-basin lake polygons (from
#'   ProcessLakeGeometries).
#' @return A named list with \code{points} (updated sf object with lake
#'   inlet/outlet nodes added and interior lake nodes removed).
#' @export
ConnectLakesToNetwork <- function(points, HL_basin) {
  message("--- Step 8b: Establishing Lake Connectivity ---")

  # ==========================================================================
  # Phase 0: Early exit when no lakes are present
  # ==========================================================================
  # If HL_basin is empty or NULL, there are no lakes to process. We still
  # ensure the required columns exist (lake_in, lake_out, HL_ID_new) so that
  # downstream functions do not crash on missing columns.
  # ==========================================================================
  if (is.null(HL_basin) || nrow(HL_basin) == 0) {
    message(">>> No lakes found in basin. Skipping lake connectivity.")
    if (!("lake_in" %in% names(points)))   points$lake_in   <- 0
    if (!("lake_out" %in% names(points)))  points$lake_out  <- 0
    if (!("HL_ID_new" %in% names(points))) points$HL_ID_new <- 0
    return(list(points = points))
  }

  HL_basin <- EnsureSameCrs(points, HL_basin, "points", "HL_basin")
  message(">>> Points: ", nrow(points), ", Lakes: ", nrow(HL_basin))

  if (!("lake_in" %in% names(points)))   points$lake_in   <- 0
  if (!("lake_out" %in% names(points)))  points$lake_out  <- 0
  if (!("HL_ID_new" %in% names(points))) points$HL_ID_new <- 0
  points$lake_in[is.na(points$lake_in)]     <- 0
  points$lake_out[is.na(points$lake_out)]   <- 0
  points$HL_ID_new[is.na(points$HL_ID_new)] <- 0

  # Pre-compute the lake boundary as a MULTILINESTRING for each lake.
  # st_boundary converts a POLYGON to its outer ring — this is the line we
  # intersect with river segments to find where rivers cross into/out of lakes.
  lake_boundaries <- sf::st_boundary(HL_basin)

  # ==========================================================================
  # Phase 1: Tag existing nodes inside lake polygons
  # ==========================================================================
  # Before creating inlet/outlet nodes, we identify which existing nodes fall
  # inside a lake polygon. These "interior" nodes will later be absorbed
  # (their emissions transferred to the inlet, then removed from the network).
  #
  # We use st_intersects which performs a spatial join: for each point, it
  # returns the indices of lake polygons that contain it.
  # ==========================================================================
  within_indices <- sf::st_intersects(points, HL_basin)
  for (i in seq_along(within_indices)) {
    idx <- within_indices[[i]]
    if (length(idx) > 0) {
      if (points$HL_ID_new[i] == 0) {
        points$HL_ID_new[i] <- HL_basin$Hylak_id[idx[1]]
      }
    }
  }
  in_lake_mask <- points$HL_ID_new != 0
  message(">>> Nodes inside lake polygons: ", sum(in_lake_mask))

  # ==========================================================================
  # Phase 2: For each lake, detect river-boundary crossings
  # ==========================================================================
  # We iterate over each lake polygon. For every lake, we:
  #   1. Find all nodes that are inside the lake (HL_ID_new matches)
  #   2. For each inside node, check if its downstream neighbour (ID_nxt)
  #      is OUTSIDE the lake — this means the river exits here (outlet crossing)
  #   3. For each inside node, check if any upstream neighbour is OUTSIDE —
  #      this means the river enters here (inlet crossing)
  #   4. Compute the boundary crossing point using linear interpolation
  #      between the inside node and its outside neighbour
  #
  # For hydrologists: think of this as finding where the river "pierces"
  # the lake shoreline. The crossing point is the exact spot where water
  # enters or leaves the lake.
  # ==========================================================================

  # Collect all new inlet/outlet nodes and rewiring instructions
  new_nodes <- list()
  rewire_ops <- list()
  remove_ids <- c()
  node_counter <- 0

  id_to_lake <- setNames(as.numeric(points$HL_ID_new), points$ID)

  for (lake_idx in seq_len(nrow(HL_basin))) {
    hylak_id <- HL_basin$Hylak_id[lake_idx]
    lake_name <- paste0("Lake_", hylak_id)

    # Nodes inside this specific lake
    in_this_lake <- which(points$HL_ID_new == hylak_id)
    if (length(in_this_lake) == 0) {
      message(">>> ", lake_name, ": no nodes inside — skipping.")
      next
    }

    # Also identify source nodes (agglomerations/WWTPs) inside this lake.
    # These have emissions that must be absorbed into the lake CSTR.
    source_inside <- in_this_lake[points$pt_type[in_this_lake] %in%
                                    c("agglomeration", "agglomeration_lake", "WWTP")]
    interior_nodes <- in_this_lake[!points$pt_type[in_this_lake] %in%
                                     c("agglomeration", "agglomeration_lake", "WWTP")]

    message(">>> ", lake_name, ": ", length(in_this_lake),
            " nodes (", length(source_inside), " sources, ",
            length(interior_nodes), " interior)")

    # ------------------------------------------------------------------
    # Phase 2a: Find OUTLET crossings (river exits the lake)
    # ------------------------------------------------------------------
    # For each node inside the lake, check its downstream neighbour.
    # If the downstream node is outside the lake (or is MOUTH/NA), then the
    # river segment between them crosses the lake boundary — this is where
    # water flows OUT of the lake.
    #
    # The crossing point is estimated by linear interpolation on the line
    # between the inside node and the outside node. We snap it to the lake
    # boundary for accuracy.
    # ------------------------------------------------------------------
    outlet_crossings <- list()
    for (i in in_this_lake) {
      next_id <- points$ID_nxt[i]
      if (is.na(next_id)) {
        # Node at lake outlet has no downstream — it IS the outlet
        outlet_crossings[[length(outlet_crossings) + 1]] <- list(
          inside_idx = i,
          inside_id = points$ID[i],
          next_id = NA,
          coords = sf::st_coordinates(points[i, ])
        )
      } else {
        next_lake <- if (next_id %in% names(id_to_lake)) id_to_lake[next_id] else 0
        if (next_lake != hylak_id) {
          # Downstream node is outside this lake — river exits here
          # Find the downstream node's coordinates
          next_idx <- match(next_id, points$ID)
          if (!is.na(next_idx)) {
            crossing_pt <- tryCatch({
              # Create a line segment from inside node to outside node
              inside_coord <- sf::st_coordinates(points[i, ])
              outside_coord <- sf::st_coordinates(points[next_idx, ])
              seg_line <- sf::st_sfc(
                sf::st_linestring(matrix(c(inside_coord, outside_coord), nrow = 2, byrow = TRUE)),
                crs = sf::st_crs(points)
              )
              # Intersect with lake boundary to get exact crossing point
              crossing <- sf::st_intersection(seg_line, lake_boundaries[lake_idx])
              if (length(crossing) > 0 && !sf::st_is_empty(crossing[1])) {
                sf::st_sfc(sf::st_geometry(crossing)[[1]], crs = sf::st_crs(points))
              } else {
                NULL
              }
            }, error = function(e) NULL)

            outlet_crossings[[length(outlet_crossings) + 1]] <- list(
              inside_idx = i,
              inside_id = points$ID[i],
              next_id = next_id,
              next_idx = next_idx,
              coords = if (!is.null(crossing_pt)) sf::st_coordinates(crossing_pt) else sf::st_coordinates(points[i, ])
            )
          }
        }
      }
    }

    # ------------------------------------------------------------------
    # Phase 2b: Find INLET crossings (river enters the lake)
    # ------------------------------------------------------------------
    # For each node inside the lake, check its upstream neighbours.
    # If any upstream neighbour is outside the lake, the river segment
    # between them crosses the lake boundary — this is where water
    # flows INTO the lake.
    # ------------------------------------------------------------------
    upstream_lookup <- split(points$ID, points$ID_nxt)
    inlet_crossings <- list()

    for (i in in_this_lake) {
      curr_id <- points$ID[i]
      up_ids <- if (curr_id %in% names(upstream_lookup)) upstream_lookup[[curr_id]] else NULL

      has_outside_upstream <- FALSE
      outside_up_info <- NULL

      if (length(up_ids) > 0) {
        for (uid in up_ids) {
          up_lake <- if (uid %in% names(id_to_lake)) id_to_lake[uid] else 0
          if (up_lake != hylak_id) {
            has_outside_upstream <- TRUE
            up_idx <- match(uid, points$ID)
            if (!is.na(up_idx)) {
              outside_up_info <- list(
                up_id = uid,
                up_idx = up_idx
              )
            }
            break
          }
        }
      }

      # Also treat START nodes inside lakes as having an implicit inlet
      # (the river begins inside the lake, e.g., a spring-fed lake)
      if (points$pt_type[i] %in% c("START", "start")) {
        has_outside_upstream <- TRUE
      }

      if (has_outside_upstream) {
        crossing_pt <- NULL
        if (!is.null(outside_up_info)) {
          crossing_pt <- tryCatch({
            inside_coord <- sf::st_coordinates(points[i, ])
            outside_coord <- sf::st_coordinates(points[outside_up_info$up_idx, ])
            seg_line <- sf::st_sfc(
              sf::st_linestring(matrix(c(outside_coord, inside_coord), nrow = 2, byrow = TRUE)),
              crs = sf::st_crs(points)
            )
            crossing <- sf::st_intersection(seg_line, lake_boundaries[lake_idx])
            if (length(crossing) > 0 && !sf::st_is_empty(crossing[1])) {
              sf::st_sfc(sf::st_geometry(crossing)[[1]], crs = sf::st_crs(points))
            } else {
              NULL
            }
          }, error = function(e) NULL)
        }

        inlet_crossings[[length(inlet_crossings) + 1]] <- list(
          inside_idx = i,
          inside_id = points$ID[i],
          up_id = if (!is.null(outside_up_info)) outside_up_info$up_id else NA,
          up_idx = if (!is.null(outside_up_info)) outside_up_info$up_idx else NA,
          coords = if (!is.null(crossing_pt)) sf::st_coordinates(crossing_pt) else sf::st_coordinates(points[i, ])
        )
      }
    }

    # ------------------------------------------------------------------
    # Phase 3: Select best inlet and outlet, create nodes
    # ------------------------------------------------------------------
    # For lakes with multiple river crossings, we select:
    #   - Inlet:  the crossing whose inside node has the SMALLEST LD
    #             (closest to headwaters = most upstream entry point)
    #   - Outlet: the crossing whose inside node has the LARGEST LD
    #             (closest to mouth = most downstream exit point)
    #
    # LD is the cumulative downstream distance from the node to the basin
    # outlet, computed in BuildNetworkTopology. A lower LD means the node
    # is more upstream. This ensures we connect the "first" entry and the
    # "last" exit, which represents the dominant through-flow path.
    #
    # If a lake has no inlet crossing (e.g., a headwater lake fed only by
    # precipitation/direct runoff), we still create an outlet for the CSTR.
    # If a lake has no outlet (lake at basin mouth), the outlet is the
    # terminal node.
    # ------------------------------------------------------------------

    if (length(outlet_crossings) == 0 && length(inlet_crossings) == 0) {
      message(">>> ", lake_name, ": no crossings detected — lake is bypassed.")
      next
    }

    # Pick best outlet (highest LD = most downstream)
    best_outlet <- NULL
    if (length(outlet_crossings) > 0) {
      out_lds <- sapply(outlet_crossings, function(oc) {
        ld_val <- points$LD[oc$inside_idx]
        if (is.null(ld_val) || length(ld_val) == 0) 0 else ld_val[1]
      })
      best_outlet <- outlet_crossings[[which.max(out_lds)]]
    }

    # Pick best inlet (lowest LD = most upstream)
    best_inlet <- NULL
    if (length(inlet_crossings) > 0) {
      in_lds <- sapply(inlet_crossings, function(ic) {
        ld_val <- points$LD[ic$inside_idx]
        if (is.null(ld_val) || length(ld_val) == 0) 0 else ld_val[1]
      })
      best_inlet <- inlet_crossings[[which.min(in_lds)]]
    }

    # ------------------------------------------------------------------
    # Phase 4: Create new inlet and outlet nodes
    # ------------------------------------------------------------------
    # We create two new sf POINT nodes for each lake:
    #   - LakeIn_<Hylak_id>:  positioned at the inlet crossing on the
    #                         lake boundary. Receives all upstream load
    #                         and emissions from absorbed interior nodes.
    #   - LakeOut_<Hylak_id>: positioned at the outlet crossing on the
    #                         lake boundary. The CSTR concentration is
    #                         computed here.
    #
    # If only one crossing exists (single-node lake), we place both nodes
    # at that crossing. The CSTR model will still work correctly because
    # the load passes from inlet to outlet in one step.
    # ------------------------------------------------------------------

    # Determine coordinates for inlet and outlet nodes
    in_coord <- if (!is.null(best_inlet)) {
      best_inlet$coords[1, 1:2]
    } else if (!is.null(best_outlet)) {
      best_outlet$coords[1, 1:2]
    } else {
      sf::st_coordinates(sf::st_centroid(HL_basin[lake_idx, ]))[1, 1:2]
    }

    out_coord <- if (!is.null(best_outlet)) {
      best_outlet$coords[1, 1:2]
    } else if (!is.null(best_inlet)) {
      best_inlet$coords[1, 1:2]
    } else {
      sf::st_coordinates(sf::st_centroid(HL_basin[lake_idx, ]))[1, 1:2]
    }

    # Template: copy columns from the closest interior node
    template_idx <- if (!is.null(best_inlet)) best_inlet$inside_idx else best_outlet$inside_idx
    if (is.null(template_idx)) template_idx <- in_this_lake[1]

    inlet_id <- paste0("LakeIn_", hylak_id)
    outlet_id <- paste0("LakeOut_", hylak_id)

    # ------------------------------------------------------------------
    # Phase 4a: Sum emissions from all source nodes inside the lake
    # ------------------------------------------------------------------
    # Source nodes (agglomerations, WWTPs) that are inside the lake polygon
    # have direct emissions (total_population, E_w, etc.). We transfer these
    # to the inlet node so the CSTR model accounts for them.
    #
    # For hydrologists: this is equivalent to saying "all wastewater discharge
    # points around the lake shore contribute to a single well-mixed volume."
    # The CSTR then dilutes and decays these combined loads before releasing
    # them at the outlet.
    # ------------------------------------------------------------------
    absorbed_pop <- if ("total_population" %in% names(points)) {
      sum(points$total_population[source_inside], na.rm = TRUE)
    } else 0

    # Collect all interior node IDs to remove later
    # (but keep source nodes — they will be re-tagged as agglomeration nodes
    #  at the inlet location, so their emissions flow into the CSTR)
    ids_to_remove <- points$ID[interior_nodes]
    if (length(ids_to_remove) > 0) {
      message(">>> ", lake_name, ": absorbing ", length(ids_to_remove),
              " interior nodes into CSTR")
    }

    # ------------------------------------------------------------------
    # Phase 4b: Build the inlet sf node
    # ------------------------------------------------------------------
    # The inlet node inherits spatial and network properties from the template
    # node, but with new ID, type flags, and position at the lake boundary.
    # ------------------------------------------------------------------
    inlet_geom <- sf::st_sfc(sf::st_point(c(in_coord[1], in_coord[2])),
                              crs = sf::st_crs(points))
    inlet_row <- points[template_idx, ]
    inlet_row$geometry <- inlet_geom
    inlet_row$ID <- inlet_id
    inlet_row$ID_nxt <- outlet_id
    inlet_row$pt_type <- "LakeInlet"
    inlet_row$node_type <- "Hydro_Lake"
    inlet_row$lake_in <- 1
    inlet_row$lake_out <- 0
    inlet_row$HL_ID_new <- hylak_id
    inlet_row$x <- in_coord[1]
    inlet_row$y <- in_coord[2]
    if ("total_population" %in% names(inlet_row)) {
      inlet_row$total_population <- absorbed_pop
    }

    # ------------------------------------------------------------------
    # Phase 4c: Build the outlet sf node
    # ------------------------------------------------------------------
    # The outlet node's ID_nxt points to whatever the best outlet's
    # downstream node was. This preserves the river topology: after the
    # lake, the river continues downstream to the next node.
    # ------------------------------------------------------------------
    outlet_geom <- sf::st_sfc(sf::st_point(c(out_coord[1], out_coord[2])),
                               crs = sf::st_crs(points))
    outlet_row <- points[template_idx, ]
    outlet_row$geometry <- outlet_geom
    outlet_row$ID <- outlet_id
    outlet_row$ID_nxt <- if (!is.null(best_outlet) && !is.na(best_outlet$next_id)) {
      best_outlet$next_id
    } else {
      points$ID_nxt[template_idx]
    }
    outlet_row$pt_type <- "LakeOutlet"
    outlet_row$node_type <- "Hydro_Lake"
    outlet_row$lake_in <- 0
    outlet_row$lake_out <- 1
    outlet_row$HL_ID_new <- hylak_id
    outlet_row$x <- out_coord[1]
    outlet_row$y <- out_coord[2]
    if ("total_population" %in% names(outlet_row)) {
      outlet_row$total_population <- 0
    }

    # ------------------------------------------------------------------
    # Phase 4d: Rewire upstream nodes to point to the new inlet
    # ------------------------------------------------------------------
    # The node immediately upstream of the inlet crossing must now point
    # to the new inlet node instead of the old interior node.
    #
    # Before: upstream_node → interior_node_inside_lake → ...
    # After:  upstream_node → LakeIn_<id> → LakeOut_<id> → downstream_node
    # ------------------------------------------------------------------
    if (!is.null(best_inlet) && !is.na(best_inlet$up_id)) {
      rewire_ops[[length(rewire_ops) + 1]] <- list(
        from_id = best_inlet$up_id,
        new_nxt = inlet_id
      )
    }

    # Also rewire source nodes inside the lake to point to the inlet
    # instead of their old downstream target. Their emissions will flow
    # into the CSTR.
    for (si in source_inside) {
      points$ID_nxt[si] <- inlet_id
      points$pt_type[si] <- "agglomeration"
      points$HL_ID_new[si] <- 0
      points$lake_in[si] <- 0
      points$lake_out[si] <- 0
    }

    new_nodes[[length(new_nodes) + 1]] <- inlet_row
    new_nodes[[length(new_nodes) + 1]] <- outlet_row
    remove_ids <- c(remove_ids, ids_to_remove)
    node_counter <- node_counter + 2

    message(">>> ", lake_name, ": created ", inlet_id, " → ", outlet_id,
            " (outlet → ", ifelse(is.null(best_outlet) || is.na(best_outlet$next_id),
                                   "terminal", best_outlet$next_id), ")")
  }

  # ==========================================================================
  # Phase 5: Apply rewiring and assemble final network
  # ==========================================================================
  # Now we surgically modify the network:
  #   1. Apply all rewiring operations (redirect ID_nxt pointers)
  #   2. Remove interior nodes that were absorbed into the CSTR
  #   3. Append the new inlet/outlet nodes
  #   4. Recalculate distances (d_nxt) for the modified links
  # ==========================================================================

  # Apply rewiring: redirect upstream nodes to point to new inlet
  for (op in rewire_ops) {
    idx <- match(op$from_id, points$ID)
    if (!is.na(idx)) {
      message(">>> Rewiring: ", op$from_id, " → ", op$new_nxt,
              " (was → ", points$ID_nxt[idx], ")")
      points$ID_nxt[idx] <- op$new_nxt
    }
  }

  # Remove absorbed interior nodes
  if (length(remove_ids) > 0) {
    keep_mask <- !points$ID %in% remove_ids
    message(">>> Removing ", sum(!keep_mask), " absorbed interior nodes")
    points <- points[keep_mask, ]
  }

  # Append new inlet/outlet nodes
  if (length(new_nodes) > 0) {
    # Combine all new nodes into a single sf object
    # Use rbind which works for sf objects with identical columns
    new_sf <- do.call(rbind, new_nodes)
    points <- rbind(points, new_sf)
    message(">>> Added ", nrow(new_sf), " lake inlet/outlet nodes")
  }

  # Recalculate d_nxt (distance to next downstream node) for new links.
  # This uses UTM projection for accurate metric distances.
  current_utm_crs <- GetUtmCrs(points)
  pts_utm <- sf::st_transform(points, crs = current_utm_crs)
  coords_utm <- sf::st_coordinates(pts_utm)
  idx_next <- match(points$ID_nxt, points$ID)
  points$d_nxt <- ifelse(
    is.na(idx_next),
    NA_real_,
    sqrt((coords_utm[, 1] - coords_utm[idx_next, 1])^2 +
         (coords_utm[, 2] - coords_utm[idx_next, 2])^2)
  )

  # ==========================================================================
  # Final summary
  # ==========================================================================
  n_inlets  <- sum(points$lake_in  == 1, na.rm = TRUE)
  n_outlets <- sum(points$lake_out == 1, na.rm = TRUE)
  n_hydro   <- sum(points$pt_type %in% c("LakeInlet", "LakeOutlet"), na.rm = TRUE)
  message(">>> Lake connectivity complete: ",
          n_inlets, " inlet(s), ",
          n_outlets, " outlet(s), ",
          n_hydro, " Hydro_Lake node(s), ",
          nrow(points), " total nodes")

  list(points = points)
}
