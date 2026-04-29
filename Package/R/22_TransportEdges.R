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

  branch_parent_ids <- character(0)
  canal_branch_edges <- BuildCanalEdges(points)
  if (!is.null(canal_branch_edges) && nrow(canal_branch_edges) > 0) {
    canal_branch_edges <- canal_branch_edges[canal_branch_edges$edge_type == "canal_branch", , drop = FALSE]
    if (nrow(canal_branch_edges) > 0) {
      branch_parent_ids <- unique(as.character(canal_branch_edges$from_id))
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
      !(df$ID %in% branch_parent_ids) &
      !is_terminal_canal
  )
  for (i in linear_idx) {
    j <- match(df$ID_nxt[i], df$ID)
    if (is.na(j)) next

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

  edges
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
