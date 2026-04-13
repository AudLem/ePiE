#' Normalize Scenario State
#'
#' Standardises raw network nodes into a consistent schema: renames topology
#' fields, propagates downstream distances, harmonises Pt_type labels, fills
#' default environmental values, and validates downstream link integrity.
#'
#' @param raw_network_nodes data.frame. Raw network point data from the build pipeline.
#' @param lake_nodes data.frame or \code{NULL}. Lake node data.
#' @param study_country Character. ISO country code for the basin (e.g. \code{"GH"}).
#' @param basin_id Character. Basin identifier.
#' @param default_temp Numeric. Default air temperature when raster data is missing (Celsius).
#' @param default_wind Numeric. Default wind speed when raster data is missing (m/s).
#' @return A named list with \code{normalized_network_nodes} and \code{lake_nodes}.
#' @export
# ==============================================================================
# Topology Normalization
# ==============================================================================
# This file transforms raw network node data from the build pipeline into a
# consistent internal schema. It is called before simulation to ensure:
#   1. All coordinates are in WGS84 (EPSG:4326)
#   2. Node IDs and downstream links are validated and consistent
#   3. Cumulative downstream distances are computed for every node
#   4. Source types (WWTP, agglomeration, etc.) are harmonised
#   5. Environmental fields (temperature, wind, slope) have valid defaults
#
# The output is a normalised data.frame ready for the transport engine.
# ==============================================================================

NormalizeScenarioState <- function(raw_network_nodes,
                                       lake_nodes = NULL,
                                       study_country,
                                       basin_id,
                                       default_temp = 12,
                                       default_wind = 3) {
  message("--- Step 2: Normalizing Topology ---")

  # --- Coordinate reprojection to WGS84 ----------------------------------------
  # Detects UTM coordinates (x > 180 or y > 90) and converts them to WGS84
  # using EPSG:32631 (UTM zone 31N) as the source CRS. Nodes already in WGS84
  # pass through unchanged.
  # --------------------------------------------------------------------------------
  standardize_coordinates_to_wgs84 <- function(network_nodes) {
    # Identify rows with coordinate values exceeding WGS84 bounds
    utm_indices <- which(network_nodes$x > 180 | network_nodes$y > 90)
    if (length(utm_indices) == 0) return(network_nodes)
    message("Converting ", length(utm_indices), " UTM points to WGS84...")

    pts_utm <- network_nodes[utm_indices, ]
    pts_wgs84 <- network_nodes[-utm_indices, ]

    # Transform UTM points -> sf object -> reproject to EPSG:4326
    # Auto-detect UTM zone from mean coordinate range
    mean_x <- mean(pts_utm$x, na.rm = TRUE)
    zone <- floor((mean_x + 180) / 6) + 1
    epsg <- if (mean(pts_utm$y, na.rm = TRUE) > 0) 32600 + zone else 32700 + zone
    pts_utm_sf <- sf::st_as_sf(pts_utm, coords = c("x", "y"), crs = epsg)
    pts_utm_wgs84 <- sf::st_transform(pts_utm_sf, crs = 4326)
    coords_wgs84 <- sf::st_coordinates(pts_utm_wgs84)

    # Overwrite original coordinates with reprojected lon/lat
    pts_utm$x <- coords_wgs84[, 1]
    pts_utm$y <- coords_wgs84[, 2]

    # Merge back: WGS84-native rows + reprojected rows
    rbind(pts_wgs84, pts_utm)
  }

  # --- Topology field normalisation ---------------------------------------------
  # Renames raw ID columns to internal names (node_id, next_node_id,
  # distance_to_next), back-fills legacy column names, resolves the line_node
  # field used for polyline drawing, and invalidates downstream links that
  # point to non-existent nodes.
  # --------------------------------------------------------------------------------
  normalize_river_topology_fields <- function(network_nodes) {
    # Map raw ID columns to canonical internal names
    network_nodes$node_id <- as.character(network_nodes$ID)
    network_nodes$next_node_id <- as.character(network_nodes$ID_nxt)

    # Resolve distance_to_next from possible legacy column names
    if (!("distance_to_next" %in% names(network_nodes))) {
      if ("dist_nxt" %in% names(network_nodes)) {
        network_nodes$distance_to_next <- as.numeric(network_nodes$dist_nxt)
      } else if ("d_nxt" %in% names(network_nodes)) {
        network_nodes$distance_to_next <- as.numeric(network_nodes$d_nxt)
      }
    }

    # Synchronise legacy aliases so downstream code can use either name
    network_nodes$ID <- network_nodes$node_id
    network_nodes$ID_nxt <- network_nodes$next_node_id
    network_nodes$dist_nxt <- network_nodes$distance_to_next

    # Resolve line_node: determines which node defines the reach polyline.
    # Defaults to next_node_id if missing or points to a non-existent node.
    if (!("line_node" %in% names(network_nodes))) {
      network_nodes$line_node <- network_nodes$next_node_id
    } else {
      network_nodes$line_node <- as.character(network_nodes$line_node)
      bad_line_node <- is.na(network_nodes$line_node) | !(network_nodes$line_node %in% network_nodes$node_id)
      network_nodes$line_node[bad_line_node] <- network_nodes$next_node_id[bad_line_node]
    }

    # Invalidate downstream links that reference nodes not present in the network
    invalid_links <- !is.na(network_nodes$next_node_id) & !(network_nodes$next_node_id %in% network_nodes$node_id)
    if (any(invalid_links)) {
      message("Fixing ", sum(invalid_links), " invalid downstream links.")
      network_nodes$next_node_id[invalid_links] <- NA
      network_nodes$ID_nxt[invalid_links] <- NA
    }

    network_nodes
  }

  # --- Downstream distance propagation ------------------------------------------
  # Computes cumulative Dist_down (distance to the river mouth / outlet) for
  # every node by iteratively walking downstream. Terminal nodes (no downstream
  # neighbour) get Dist_down = 0. Each iteration resolves nodes whose
  # downstream neighbour already has a known distance.
  # --------------------------------------------------------------------------------
  propagate_downstream_distance <- function(network_nodes) {
    network_nodes$Dist_down <- NA_real_

    # Terminal nodes (outlets) have zero cumulative distance
    terminal_idx <- which(is.na(network_nodes$next_node_id))
    network_nodes$Dist_down[terminal_idx] <- 0

    message("Propagating downstream distances...")

    # Iterative propagation: each pass resolves nodes whose downstream
    # neighbour was resolved in a previous pass. Converges in at most N passes.
    max_iter <- nrow(network_nodes) + 5
    for (k in seq_len(max_iter)) {
      changed <- FALSE
      for (i in seq_len(nrow(network_nodes))) {
        if (is.na(network_nodes$Dist_down[i])) {
          # Find the downstream neighbour of node i
          j <- match(network_nodes$next_node_id[i], network_nodes$node_id)
          if (!is.na(j) && !is.na(network_nodes$Dist_down[j])) {
            dnext <- ifelse(is.na(network_nodes$distance_to_next[i]), 0, network_nodes$distance_to_next[i])
            network_nodes$Dist_down[i] <- network_nodes$Dist_down[j] + dnext
            changed <- TRUE
          }
        }
      }
      if (!changed) break
    }

    # Any remaining unresolved nodes default to 0 (isolated / disconnected)
    network_nodes$Dist_down[is.na(network_nodes$Dist_down)] <- 0
    network_nodes$distance_to_next[is.na(network_nodes$distance_to_next)] <- 0
    network_nodes$dist_nxt <- network_nodes$distance_to_next
    network_nodes
  }

  # --- Source type harmonisation -------------------------------------------------
  # Normalises Pt_type labels (WWTP, agglomeration, node) into a consistent
  # set of categories, fills missing rptMStateK (country code) values, and
  # maps the downstream node type into Down_type for every node.
  # TODO(MULTI-PATHOGEN): Source type may need pathogen-specific sub-categories
  #   (e.g. "WWTP_Cryptosporidium" vs "WWTP_Rotavirus") if treatment removal
  #   differs by pathogen. Currently Pt_type is pathogen-agnostic.
  # --------------------------------------------------------------------------------
  standardize_source_types <- function(network_nodes, study_country_code) {
    # Determine Pt_type from whichever column name is present
    if ("pt_type" %in% names(network_nodes)) {
      network_nodes$Pt_type <- as.character(network_nodes$pt_type)
    } else if ("Pt_type" %in% names(network_nodes)) {
      network_nodes$Pt_type <- as.character(network_nodes$Pt_type)
    } else {
      # Default: generic river node with no specific source type
      network_nodes$Pt_type <- "node"
    }

    # Harmonise variant spellings into canonical labels
    network_nodes$Pt_type[tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations")] <- "agglomeration"
    network_nodes$Pt_type[tolower(network_nodes$Pt_type) == "wwtp"] <- "WWTP"

    # Fill missing country codes with the study area default
    if (!("rptMStateK" %in% names(network_nodes))) {
      network_nodes$rptMStateK <- study_country_code
    }
    network_nodes$rptMStateK <- as.character(network_nodes$rptMStateK)
    network_nodes$rptMStateK[is.na(network_nodes$rptMStateK) | network_nodes$rptMStateK == ""] <- study_country_code

    # Map downstream node type for each node (used in transport logic)
    network_nodes$Down_type <- NA_character_
    nxt_idx <- match(network_nodes$next_node_id, network_nodes$node_id)
    valid_nxt <- !is.na(nxt_idx)
    network_nodes$Down_type[valid_nxt] <- network_nodes$Pt_type[nxt_idx[valid_nxt]]
    network_nodes
  }

  # --- Environmental field defaults ----------------------------------------------
  # Ensures all required environmental columns exist with sensible defaults.
  # If the data already contains these columns (e.g. from raster extraction),
  # the existing values are preserved; only missing/NA values are back-filled.
  # TODO(MULTI-PATHOGEN): Pathogen-specific environmental defaults (e.g.
  #   different f_STP removal fractions per organism) should be loaded from
  #   inst/pathogen_input/<name>.R when the multi-pathogen extension is built.
  # --------------------------------------------------------------------------------
  normalize_environmental_inputs <- function(node_data, default_temp, default_wind) {
    if (is.null(node_data) || nrow(node_data) == 0) return(node_data)

    # Map lower-case column names to the internal camelCase schema
    if ("temperature" %in% names(node_data)) node_data$T_AIR <- node_data$temperature
    if ("wind" %in% names(node_data)) node_data$Wind <- node_data$wind
    if ("slope" %in% names(node_data)) node_data$SLOPE__deg <- node_data$slope

    # Create columns with defaults if they do not exist
    if (!("T_AIR" %in% names(node_data))) node_data$T_AIR <- default_temp
    if (!("Wind" %in% names(node_data))) node_data$Wind <- default_wind
    if (!("SLOPE__deg" %in% names(node_data))) node_data$SLOPE__deg <- 0

    # Population and direct-discharge fractions
    if (!("Inh" %in% names(node_data))) node_data$Inh <- 0
    if (!("f_direct" %in% names(node_data))) node_data$f_direct <- 0
    # Default WWTP removal fraction: 90% of load reaches the outlet
    if (!("f_STP" %in% names(node_data))) node_data$f_STP <- 0.9

    # Wastewater treatment plant fields
    # TODO(MULTI-PATHOGEN): uwwLoadEnt is currently the only pathogen load
    #   column. Multi-pathogen support requires additional load columns
    #   (e.g. uwwLoadRotavirus, uwwLoadEcoli).
    if (!("uwwLoadEnt" %in% names(node_data))) node_data$uwwLoadEnt <- NA_real_
    if (!("uwwCapacit" %in% names(node_data))) node_data$uwwCapacit <- NA_real_
    if (!("uwwPrimary" %in% names(node_data))) node_data$uwwPrimary <- 0
    if (!("uwwSeconda" %in% names(node_data))) node_data$uwwSeconda <- 0

    # Replace NA values in existing columns with defaults
    node_data$T_AIR[is.na(node_data$T_AIR)] <- default_temp
    node_data$Wind[is.na(node_data$Wind)] <- default_wind
    node_data$SLOPE__deg[is.na(node_data$SLOPE__deg)] <- 0
    node_data$Inh[is.na(node_data$Inh)] <- 0
    node_data$f_direct[is.na(node_data$f_direct)] <- 0
    node_data$f_STP[is.na(node_data$f_STP)] <- 0.9

    node_data
  }

  # === Main normalisation pipeline ==============================================
  # Each helper is applied in sequence; order matters because later steps
  # depend on fields created by earlier ones.
  # ==============================================================================

  normalized_network_nodes <- raw_network_nodes

  # Step 1: Ensure all coordinates are in WGS84
  normalized_network_nodes <- standardize_coordinates_to_wgs84(normalized_network_nodes)

  # Step 2: Rename and validate topology fields (IDs, distances, links)
  normalized_network_nodes <- normalize_river_topology_fields(normalized_network_nodes)

  # Step 3: Compute cumulative downstream distance from each node to outlet
  normalized_network_nodes <- propagate_downstream_distance(normalized_network_nodes)

  # Step 4: Harmonise source types and populate Down_type
  message("Mapping downstream node types...")
  normalized_network_nodes <- standardize_source_types(normalized_network_nodes, study_country)

  # Step 5: Initialise lake-related columns (required by lake CSTR model)
  if (!("Hylak_id" %in% names(normalized_network_nodes))) normalized_network_nodes$Hylak_id <- 0
  if (!("HL_ID_new" %in% names(normalized_network_nodes))) normalized_network_nodes$HL_ID_new <- normalized_network_nodes$Hylak_id
  if (!("lake_out" %in% names(normalized_network_nodes))) normalized_network_nodes$lake_out <- 0

  # Tag lake nodes with basin_id if not already present
  if (!is.null(lake_nodes) && nrow(lake_nodes) > 0) {
    if (!("basin_id" %in% names(lake_nodes))) lake_nodes$basin_id <- basin_id
  }

  # Step 6: Fill missing environmental fields with defaults
  message("Normalizing environmental fields...")
  normalized_network_nodes <- normalize_environmental_inputs(normalized_network_nodes, default_temp, default_wind)
  lake_nodes <- normalize_environmental_inputs(lake_nodes, default_temp, default_wind)

  message("Topology normalization complete.")
  list(
    normalized_network_nodes = normalized_network_nodes,
    lake_nodes = lake_nodes
  )
}
