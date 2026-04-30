#' Build Transport Edges
#'
#' Builds the canonical directed edge table used by branch-aware transport.
#' The node table remains the primary artifact; this helper derives one row per
#' routed connection, including multi-downstream canal branches.
BuildTransportEdges <- function(points, tolerance = 1e-6, warn = TRUE) {
  if (is.null(points) || nrow(points) == 0) {
    return(data.frame())
  }

  df <- if (inherits(points, "sf")) sf::st_drop_geometry(points) else points
  required_cols <- c("ID", "ID_nxt")
  if (!all(required_cols %in% names(df))) {
    return(data.frame())
  }

  if (!("basin_id" %in% names(df))) {
    df$basin_id <- NA_character_
  }
  if (!("is_canal" %in% names(df))) {
    df$is_canal <- FALSE
  }

  q_from_value <- function(idx) {
    if (isTRUE(df$is_canal[idx]) && "Q_model_m3s" %in% names(df) && !is.na(df$Q_model_m3s[idx])) {
      return(as.numeric(df$Q_model_m3s[idx]))
    }
    if ("Q" %in% names(df) && !is.na(df$Q[idx])) {
      return(as.numeric(df$Q[idx]))
    }
    NA_real_
  }

  q_to_value <- function(idx) {
    if (isTRUE(df$is_canal[idx]) && "Q_model_m3s" %in% names(df) && !is.na(df$Q_model_m3s[idx])) {
      return(as.numeric(df$Q_model_m3s[idx]))
    }
    if ("Q" %in% names(df) && !is.na(df$Q[idx])) {
      return(as.numeric(df$Q[idx]))
    }
    NA_real_
  }

  velocity_value <- function(from_idx, to_idx) {
    if ("V" %in% names(df) && !is.na(df$V[to_idx]) && df$V[to_idx] > 0) {
      return(as.numeric(df$V[to_idx]))
    }
    if ("V_NXT" %in% names(df) && !is.na(df$V_NXT[from_idx]) && df$V_NXT[from_idx] > 0) {
      return(as.numeric(df$V_NXT[from_idx]))
    }
    if ("V" %in% names(df) && !is.na(df$V[from_idx]) && df$V[from_idx] > 0) {
      return(as.numeric(df$V[from_idx]))
    }
    NA_real_
  }

  distance_value <- function(from_idx, to_idx) {
    if ("d_nxt" %in% names(df) && !is.na(df$d_nxt[from_idx]) && identical(as.character(df$ID_nxt[from_idx]), as.character(df$ID[to_idx]))) {
      return(as.numeric(df$d_nxt[from_idx]))
    }
    if ("canal_d_nxt_m" %in% names(df) && !is.na(df$canal_d_nxt_m[from_idx]) && identical(as.character(df$ID_nxt[from_idx]), as.character(df$ID[to_idx]))) {
      return(as.numeric(df$canal_d_nxt_m[from_idx]))
    }
    if (all(c("x", "y") %in% names(df))) {
      p1 <- sf::st_sfc(sf::st_point(c(as.numeric(df$x[from_idx]), as.numeric(df$y[from_idx]))), crs = 4326)
      p2 <- sf::st_sfc(sf::st_point(c(as.numeric(df$x[to_idx]), as.numeric(df$y[to_idx]))), crs = 4326)
      return(as.numeric(sf::st_distance(p1, p2)))
    }
    NA_real_
  }

  explicit_canal_branch_keys <- character(0)
  canal_branch_edges <- BuildCanalEdges(points)
  if (!is.null(canal_branch_edges) && nrow(canal_branch_edges) > 0) {
    canal_branch_edges <- canal_branch_edges[canal_branch_edges$edge_type == "canal_branch", , drop = FALSE]
    if (nrow(canal_branch_edges) > 0) {
      explicit_canal_branch_keys <- paste(canal_branch_edges$from_id, canal_branch_edges$to_id, sep = "\r")
    }
  }

  rows <- list()

  is_terminal_canal <- rep(FALSE, nrow(df))
  if ("canal_pt_type" %in% names(df)) {
    is_terminal_canal <- !is.na(df$canal_pt_type) & df$canal_pt_type == "CANAL_END"
  }
  if ("canal_downstream_count" %in% names(df)) {
    is_terminal_canal <- is_terminal_canal | (!is.na(df$canal_downstream_count) & df$canal_downstream_count == 0)
  }

  linear_idx <- which(
    !is.na(df$ID_nxt) &
      df$ID_nxt != "" &
      !is_terminal_canal
  )
  for (i in linear_idx) {
    j <- match(df$ID_nxt[i], df$ID)
    if (is.na(j)) next
    edge_key <- paste(df$ID[i], df$ID[j], sep = "\r")
    if (edge_key %in% explicit_canal_branch_keys) next

    q_from <- q_from_value(i)
    q_to <- q_to_value(j)
    flow_fraction <- 1
    if (isTRUE(df$is_canal[i]) && isTRUE(df$is_canal[j]) &&
        is.finite(q_from) && q_from > tolerance && is.finite(q_to)) {
      ratio <- q_to / q_from
      if (ratio < 1 - tolerance) {
        flow_fraction <- ratio
      } else if (ratio <= 1 + tolerance) {
        flow_fraction <- 1
      } else {
        flow_fraction <- 1
      }
    }

    rows[[length(rows) + 1L]] <- data.frame(
      from_id = as.character(df$ID[i]),
      to_id = as.character(df$ID[j]),
      basin_id = as.character(df$basin_id[i]),
      edge_type = if (isTRUE(df$is_canal[i]) || isTRUE(df$is_canal[j])) "canal_reach" else "reach",
      is_canal = isTRUE(df$is_canal[i]) || isTRUE(df$is_canal[j]),
      from_canal = if ("canal_name" %in% names(df)) as.character(df$canal_name[i]) else NA_character_,
      to_canal = if ("canal_name" %in% names(df)) as.character(df$canal_name[j]) else NA_character_,
      dist_m = distance_value(i, j),
      Q_from_m3s = q_from,
      Q_to_m3s = q_to,
      flow_fraction = as.numeric(flow_fraction),
      V_edge_mps = velocity_value(i, j),
      q_source = if ("Q_source" %in% names(df)) as.character(df$Q_source[i]) else NA_character_,
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(canal_branch_edges) && nrow(canal_branch_edges) > 0) {
    for (row_idx in seq_len(nrow(canal_branch_edges))) {
      edge <- canal_branch_edges[row_idx, , drop = FALSE]
      from_idx <- match(edge$from_id, df$ID)
      to_idx <- match(edge$to_id, df$ID)
      if (is.na(from_idx) || is.na(to_idx)) next

      child_q <- if (!is.na(edge$Q_model_m3s)) as.numeric(edge$Q_model_m3s) else q_to_value(to_idx)
      parent_q <- if (!is.na(edge$Q_parent_m3s)) as.numeric(edge$Q_parent_m3s) else q_from_value(from_idx)
      if (!is.finite(child_q) || !is.finite(parent_q) || parent_q <= tolerance) {
        stop("Missing canal branch discharge for transport edge ", edge$from_id, " -> ", edge$to_id)
      }

      rows[[length(rows) + 1L]] <- data.frame(
        from_id = as.character(edge$from_id),
        to_id = as.character(edge$to_id),
        basin_id = as.character(df$basin_id[from_idx]),
        edge_type = "canal_branch",
        is_canal = TRUE,
        from_canal = as.character(edge$from_canal),
        to_canal = as.character(edge$to_canal),
        dist_m = as.numeric(edge$dist_m),
        Q_from_m3s = parent_q,
        Q_to_m3s = child_q,
        flow_fraction = as.numeric(child_q / parent_q),
        V_edge_mps = velocity_value(from_idx, to_idx),
        q_source = as.character(edge$q_source),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(data.frame())
  }

  edges <- do.call(rbind, rows)
  edges <- edges[!duplicated(edges[, c("from_id", "to_id", "edge_type")]), , drop = FALSE]

  valid_targets <- !is.na(edges$to_id) & edges$to_id %in% df$ID
  if (warn && any(!valid_targets)) {
    warning("BuildTransportEdges: dropped ", sum(!valid_targets), " edges with missing downstream nodes.")
  }
  edges <- edges[valid_targets, , drop = FALSE]

  if (nrow(edges) == 0) {
    return(edges)
  }

  branch_rows <- edges$edge_type == "canal_branch"
  if (any(branch_rows)) {
    by_parent <- split(edges[branch_rows, , drop = FALSE], edges$from_id[branch_rows])
    for (parent_id in names(by_parent)) {
      frac_sum <- sum(by_parent[[parent_id]]$flow_fraction, na.rm = TRUE)
      if (!is.finite(frac_sum)) {
        stop("Transport edge fractions are missing for canal branch parent ", parent_id)
      }
      if (frac_sum > 1 + tolerance) {
        stop("Transport edge fractions exceed 1 for canal branch parent ", parent_id, " (sum=", signif(frac_sum, 6), ")")
      }
    }
  }

  canal_split_rows <- edges$is_canal %in% TRUE
  canal_outgoing <- table(edges$from_id[canal_split_rows])
  split_parent_ids <- names(canal_outgoing)[canal_outgoing > 1]
  for (parent_id in split_parent_ids) {
    parent_edges <- edges[canal_split_rows & edges$from_id == parent_id, , drop = FALSE]
    frac_sum <- sum(parent_edges$flow_fraction, na.rm = TRUE)
    if (!is.finite(frac_sum)) {
      stop("Transport edge fractions are missing for canal split parent ", parent_id)
    }
    if (frac_sum > 1 + tolerance) {
      stop("Transport edge fractions exceed 1 for canal split parent ", parent_id, " (sum=", signif(frac_sum, 6), ")")
    }
  }

  edges
}

#' Apply Lake Through-Flow To Boundary Nodes
#'
#' Artificial LakeIn/LakeOut nodes sit on lake boundaries, so raster-extracted
#' Q at those exact points can be unrelated to the river flow entering the lake.
#' This helper derives lake through-flow from the routed inlet edges and writes
#' it back to lake nodes before transport edges are rebuilt.
ApplyLakeThroughflow <- function(points,
                                 transport_edges = NULL,
                                 lake_transport_mode = "cstr",
                                 tolerance = 1e-9) {
  if (is.null(points) || nrow(points) == 0) return(points)

  mode_value <- if (is.null(lake_transport_mode) || length(lake_transport_mode) == 0) {
    NA_character_
  } else {
    as.character(lake_transport_mode[[1]])
  }
  mode <- if (is.na(mode_value) || !nzchar(mode_value)) {
    "cstr"
  } else {
    mode_value
  }
  mode <- match.arg(mode, c("cstr", "legacy_pass_through"))

  if (!all(c("ID", "Hylak_id", "lake_in", "lake_out") %in% names(points))) {
    return(points)
  }

  if (!("Q_lake_m3s" %in% names(points))) points$Q_lake_m3s <- NA_real_
  if (!("lake_throughflow_m3s" %in% names(points))) points$lake_throughflow_m3s <- NA_real_
  if (!("lake_transport_mode" %in% names(points))) points$lake_transport_mode <- NA_character_

  # Recalculate local hydraulic estimates for lake boundary nodes whose Q is
  # overwritten. The formulas mirror Select_hydrology_fast2() and keep exported
  # Q/V/H internally consistent after the through-flow correction.
  recompute_hydraulics <- function(df, idx) {
    idx <- idx[!is.na(idx)]
    if (length(idx) == 0 || !("Q" %in% names(df))) return(df)

    if (!("slope" %in% names(df))) df$slope <- 0.001
    slope <- as.numeric(df$slope[idx])
    slope[!is.finite(slope) | slope <= 0] <- stats::median(as.numeric(df$slope[df$slope > 0]), na.rm = TRUE)
    slope[!is.finite(slope) | slope <= 0] <- 0.001

    q <- as.numeric(df$Q[idx])
    q[!is.finite(q) | q <= 0] <- NA_real_
    valid <- !is.na(q)
    if (!any(valid)) return(df)

    n <- 0.045
    slope_m <- tan(slope[valid] * pi / 180)
    slope_m[!is.finite(slope_m) | slope_m <= 0] <- tan(0.001 * pi / 180)
    W <- 7.3607 * q[valid] ^ 0.52425
    V <- n ^ (-3 / 5) * q[valid] ^ (2 / 5) * W ^ (-2 / 5) * slope_m ^ (3 / 10)
    H <- q[valid] / (V * W)

    valid_idx <- idx[valid]
    df$V[valid_idx] <- V
    df$H[valid_idx] <- H
    if ("V_NXT" %in% names(df)) df$V_NXT[valid_idx] <- V
    df
  }

  if (is.null(transport_edges) || nrow(transport_edges) == 0) {
    transport_edges <- BuildTransportEdges(points, warn = FALSE)
  }
  if (is.null(transport_edges) || nrow(transport_edges) == 0) {
    return(points)
  }

  # Network artifacts can carry the lake identifier in either Hylak_id or the
  # older HL_ID_new column. Prefer HL_ID_new when Hylak_id is still the neutral
  # river value (0), so existing saved Bega networks do not need rebuilding.
  lake_id_vec <- suppressWarnings(as.numeric(points$Hylak_id))
  if ("HL_ID_new" %in% names(points)) {
    hl_id_new <- suppressWarnings(as.numeric(points$HL_ID_new))
    use_hl_id_new <- (is.na(lake_id_vec) | lake_id_vec <= 0) &
      is.finite(hl_id_new) & hl_id_new > 0
    lake_id_vec[use_hl_id_new] <- hl_id_new[use_hl_id_new]
    if ("Hylak_id" %in% names(points)) {
      points$Hylak_id[use_hl_id_new] <- hl_id_new[use_hl_id_new]
    }
  }

  lake_out_idx <- which(!is.na(points$lake_out) & points$lake_out == 1 &
                          !is.na(lake_id_vec) & lake_id_vec > 0)
  lake_ids <- unique(lake_id_vec[lake_out_idx])
  if (length(lake_ids) == 0) return(points)

  updated_idx <- integer(0)
  for (lake_id in lake_ids) {
    inlet_idx <- which(lake_id_vec == lake_id & points$lake_in == 1)
    outlet_idx <- which(lake_id_vec == lake_id & points$lake_out == 1)
    if (length(inlet_idx) == 0 || length(outlet_idx) == 0) next

    inlet_ids <- as.character(points$ID[inlet_idx])
    incoming <- transport_edges[transport_edges$to_id %in% inlet_ids, , drop = FALSE]

    inlet_q <- stats::setNames(rep(NA_real_, length(inlet_ids)), inlet_ids)
    for (inlet_id in inlet_ids) {
      rows <- incoming[incoming$to_id == inlet_id, , drop = FALSE]
      q <- suppressWarnings(as.numeric(rows$Q_from_m3s))
      q <- q[is.finite(q) & q > tolerance]
      if (length(q) == 0) {
        q <- suppressWarnings(as.numeric(rows$Q_to_m3s))
        q <- q[is.finite(q) & q > tolerance]
      }
      if (length(q) == 0 && "Q" %in% names(points)) {
        q <- as.numeric(points$Q[match(inlet_id, points$ID)])
        q <- q[is.finite(q) & q > tolerance]
      }
      if (length(q) > 0) inlet_q[inlet_id] <- sum(q, na.rm = TRUE)
    }

    q_lake <- sum(inlet_q[is.finite(inlet_q) & inlet_q > tolerance], na.rm = TRUE)
    if (!is.finite(q_lake) || q_lake <= tolerance) {
      q_lake <- suppressWarnings(max(as.numeric(points$Q[outlet_idx]), na.rm = TRUE))
    }
    if (!is.finite(q_lake) || q_lake <= tolerance) next

    # LakeIn nodes keep their own incoming branch Q; LakeOut carries total lake
    # through-flow. This prevents a low raster value at the outlet boundary from
    # acting as an artificial dilution/removal control.
    for (inlet_id in names(inlet_q)) {
      ii <- match(inlet_id, points$ID)
      if (!is.na(ii) && is.finite(inlet_q[inlet_id]) && inlet_q[inlet_id] > tolerance) {
        points$Q[ii] <- inlet_q[inlet_id]
        if ("river_discharge" %in% names(points)) points$river_discharge[ii] <- inlet_q[inlet_id]
        points$Q_lake_m3s[ii] <- q_lake
        points$lake_throughflow_m3s[ii] <- q_lake
        points$lake_transport_mode[ii] <- mode
        updated_idx <- c(updated_idx, ii)
      }
    }

    points$Q[outlet_idx] <- q_lake
    if ("river_discharge" %in% names(points)) points$river_discharge[outlet_idx] <- q_lake
    points$Q_lake_m3s[outlet_idx] <- q_lake
    points$lake_throughflow_m3s[outlet_idx] <- q_lake
    points$lake_transport_mode[outlet_idx] <- mode
    updated_idx <- c(updated_idx, outlet_idx)
  }

  recompute_hydraulics(points, unique(updated_idx))
}

#' Detect Branch-Aware Transport
#'
#' Returns TRUE when the transport graph contains any split or merge that
#' requires edge-based routing instead of the legacy single-ID_nxt solver.
HasTransportBranching <- function(transport_edges) {
  if (is.null(transport_edges) || nrow(transport_edges) == 0) {
    return(FALSE)
  }
  outgoing <- table(transport_edges$from_id)
  incoming <- table(transport_edges$to_id)
  any(outgoing > 1) || any(incoming > 1)
}

#' Set Upstream Counts From Transport Edges
#'
#' Replaces the legacy Freq counting when the graph contains real branches.
Set_upstream_points_from_edges <- function(points, transport_edges) {
  pts <- if (inherits(points, "sf")) sf::st_drop_geometry(points) else points
  pts$Freq <- 0L
  pts$transport_incoming_count <- 0L
  if (is.null(transport_edges) || nrow(transport_edges) == 0) {
    return(pts)
  }

  incoming <- table(transport_edges$to_id)
  match_idx <- match(names(incoming), pts$ID)
  keep <- !is.na(match_idx)
  pts$transport_incoming_count[match_idx[keep]] <- as.integer(incoming[keep])
  pts$Freq <- pts$transport_incoming_count
  pts
}

#' Export Transport Edges
#'
#' Writes the branch-aware transport graph to disk for inspection and map use.
ExportTransportEdges <- function(transport_edges, run_output_dir) {
  if (is.null(transport_edges) || nrow(transport_edges) == 0 || is.null(run_output_dir)) {
    return(invisible(NULL))
  }
  if (!dir.exists(run_output_dir)) {
    dir.create(run_output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  path <- file.path(run_output_dir, "transport_edges.csv")
  write.csv(transport_edges, path, row.names = FALSE)
  invisible(path)
}

#' Convert Transport Edges To Simple Features
#'
#' Creates line geometries from the edge table for visualization.
TransportEdgesToSf <- function(transport_edges, points) {
  if (is.null(transport_edges) || nrow(transport_edges) == 0 || is.null(points) || nrow(points) == 0) {
    return(NULL)
  }

  pts <- if (inherits(points, "sf")) sf::st_drop_geometry(points) else points
  if (!all(c("ID", "x", "y") %in% names(pts))) {
    return(NULL)
  }

  from_idx <- match(transport_edges$from_id, pts$ID)
  to_idx <- match(transport_edges$to_id, pts$ID)
  keep <- !is.na(from_idx) & !is.na(to_idx)
  if (!any(keep)) {
    return(NULL)
  }

  edge_df <- transport_edges[keep, , drop = FALSE]
  from_idx <- from_idx[keep]
  to_idx <- to_idx[keep]

  geoms <- lapply(seq_len(nrow(edge_df)), function(i) {
    sf::st_linestring(matrix(
      c(
        as.numeric(pts$x[from_idx[i]]), as.numeric(pts$y[from_idx[i]]),
        as.numeric(pts$x[to_idx[i]]), as.numeric(pts$y[to_idx[i]])
      ),
      ncol = 2,
      byrow = TRUE
    ))
  })

  sf::st_as_sf(edge_df, geometry = sf::st_sfc(geoms, crs = 4326))
}
