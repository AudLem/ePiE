NormalizeScenarioState <- function(raw_network_nodes,
                                       lake_nodes = NULL,
                                       study_country,
                                       basin_id,
                                       default_temp = 12,
                                       default_wind = 3) {
  message("--- Step 2: Normalizing Topology ---")

  standardize_coordinates_to_wgs84 <- function(network_nodes) {
    utm_indices <- which(network_nodes$x > 180 | network_nodes$y > 90)
    if (length(utm_indices) == 0) return(network_nodes)
    message("Converting ", length(utm_indices), " UTM points to WGS84...")
    pts_utm <- network_nodes[utm_indices, ]
    pts_wgs84 <- network_nodes[-utm_indices, ]
    pts_utm_sf <- sf::st_as_sf(pts_utm, coords = c("x", "y"), crs = 32631)
    pts_utm_wgs84 <- sf::st_transform(pts_utm_sf, crs = 4326)
    coords_wgs84 <- sf::st_coordinates(pts_utm_wgs84)
    pts_utm$x <- coords_wgs84[, 1]
    pts_utm$y <- coords_wgs84[, 2]
    rbind(pts_wgs84, pts_utm)
  }

  normalize_river_topology_fields <- function(network_nodes) {
    network_nodes$node_id <- as.character(network_nodes$ID)
    network_nodes$next_node_id <- as.character(network_nodes$ID_nxt)

    if (!("distance_to_next" %in% names(network_nodes))) {
      if ("dist_nxt" %in% names(network_nodes)) {
        network_nodes$distance_to_next <- as.numeric(network_nodes$dist_nxt)
      } else if ("d_nxt" %in% names(network_nodes)) {
        network_nodes$distance_to_next <- as.numeric(network_nodes$d_nxt)
      }
    }

    network_nodes$ID <- network_nodes$node_id
    network_nodes$ID_nxt <- network_nodes$next_node_id
    network_nodes$dist_nxt <- network_nodes$distance_to_next

    if (!("line_node" %in% names(network_nodes))) {
      network_nodes$line_node <- network_nodes$next_node_id
    } else {
      network_nodes$line_node <- as.character(network_nodes$line_node)
      bad_line_node <- is.na(network_nodes$line_node) | !(network_nodes$line_node %in% network_nodes$node_id)
      network_nodes$line_node[bad_line_node] <- network_nodes$next_node_id[bad_line_node]
    }

    invalid_links <- !is.na(network_nodes$next_node_id) & !(network_nodes$next_node_id %in% network_nodes$node_id)
    if (any(invalid_links)) {
      message("Fixing ", sum(invalid_links), " invalid downstream links.")
      network_nodes$next_node_id[invalid_links] <- NA
      network_nodes$ID_nxt[invalid_links] <- NA
    }

    network_nodes
  }

  propagate_downstream_distance <- function(network_nodes) {
    network_nodes$Dist_down <- NA_real_
    terminal_idx <- which(is.na(network_nodes$next_node_id))
    network_nodes$Dist_down[terminal_idx] <- 0
    message("Propagating downstream distances...")
    max_iter <- nrow(network_nodes) + 5
    for (k in seq_len(max_iter)) {
      changed <- FALSE
      for (i in seq_len(nrow(network_nodes))) {
        if (is.na(network_nodes$Dist_down[i])) {
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
    network_nodes$Dist_down[is.na(network_nodes$Dist_down)] <- 0
    network_nodes$distance_to_next[is.na(network_nodes$distance_to_next)] <- 0
    network_nodes$dist_nxt <- network_nodes$distance_to_next
    network_nodes
  }

  standardize_source_types <- function(network_nodes, study_country_code) {
    if ("pt_type" %in% names(network_nodes)) {
      network_nodes$Pt_type <- as.character(network_nodes$pt_type)
    } else if ("Pt_type" %in% names(network_nodes)) {
      network_nodes$Pt_type <- as.character(network_nodes$Pt_type)
    } else {
      network_nodes$Pt_type <- "node"
    }

    network_nodes$Pt_type[tolower(network_nodes$Pt_type) %in% c("agglomeration", "agglomerations")] <- "agglomeration"
    network_nodes$Pt_type[tolower(network_nodes$Pt_type) == "wwtp"] <- "WWTP"

    if (!("rptMStateK" %in% names(network_nodes))) {
      network_nodes$rptMStateK <- study_country_code
    }
    network_nodes$rptMStateK <- as.character(network_nodes$rptMStateK)
    network_nodes$rptMStateK[is.na(network_nodes$rptMStateK) | network_nodes$rptMStateK == ""] <- study_country_code

    network_nodes$Down_type <- NA_character_
    nxt_idx <- match(network_nodes$next_node_id, network_nodes$node_id)
    valid_nxt <- !is.na(nxt_idx)
    network_nodes$Down_type[valid_nxt] <- network_nodes$Pt_type[nxt_idx[valid_nxt]]
    network_nodes
  }

  normalize_environmental_inputs <- function(node_data, default_temp, default_wind) {
    if (is.null(node_data) || nrow(node_data) == 0) return(node_data)

    if ("temperature" %in% names(node_data)) node_data$T_AIR <- node_data$temperature
    if ("wind" %in% names(node_data)) node_data$Wind <- node_data$wind
    if ("slope" %in% names(node_data)) node_data$SLOPE__deg <- node_data$slope

    if (!("T_AIR" %in% names(node_data))) node_data$T_AIR <- default_temp
    if (!("Wind" %in% names(node_data))) node_data$Wind <- default_wind
    if (!("SLOPE__deg" %in% names(node_data))) node_data$SLOPE__deg <- 0

    if (!("Inh" %in% names(node_data))) node_data$Inh <- 0
    if (!("f_direct" %in% names(node_data))) node_data$f_direct <- 0
    if (!("f_STP" %in% names(node_data))) node_data$f_STP <- 0.9

    if (!("uwwLoadEnt" %in% names(node_data))) node_data$uwwLoadEnt <- NA_real_
    if (!("uwwCapacit" %in% names(node_data))) node_data$uwwCapacit <- NA_real_
    if (!("uwwPrimary" %in% names(node_data))) node_data$uwwPrimary <- 0
    if (!("uwwSeconda" %in% names(node_data))) node_data$uwwSeconda <- 0

    node_data$T_AIR[is.na(node_data$T_AIR)] <- default_temp
    node_data$Wind[is.na(node_data$Wind)] <- default_wind
    node_data$SLOPE__deg[is.na(node_data$SLOPE__deg)] <- 0
    node_data$Inh[is.na(node_data$Inh)] <- 0
    node_data$f_direct[is.na(node_data$f_direct)] <- 0
    node_data$f_STP[is.na(node_data$f_STP)] <- 0.9

    node_data
  }

  normalized_network_nodes <- raw_network_nodes
  normalized_network_nodes <- standardize_coordinates_to_wgs84(normalized_network_nodes)
  normalized_network_nodes <- normalize_river_topology_fields(normalized_network_nodes)
  normalized_network_nodes <- propagate_downstream_distance(normalized_network_nodes)
  message("Mapping downstream node types...")
  normalized_network_nodes <- standardize_source_types(normalized_network_nodes, study_country)

  if (!("Hylak_id" %in% names(normalized_network_nodes))) normalized_network_nodes$Hylak_id <- 0
  if (!("HL_ID_new" %in% names(normalized_network_nodes))) normalized_network_nodes$HL_ID_new <- normalized_network_nodes$Hylak_id
  if (!("lake_out" %in% names(normalized_network_nodes))) normalized_network_nodes$lake_out <- 0
  if (!is.null(lake_nodes) && nrow(lake_nodes) > 0) {
    if (!("basin_id" %in% names(lake_nodes))) lake_nodes$basin_id <- basin_id
  }

  message("Normalizing environmental fields...")
  normalized_network_nodes <- normalize_environmental_inputs(normalized_network_nodes, default_temp, default_wind)
  lake_nodes <- normalize_environmental_inputs(lake_nodes, default_temp, default_wind)

  message("Topology normalization complete.")
  list(
    normalized_network_nodes = normalized_network_nodes,
    lake_nodes = lake_nodes
  )
}
