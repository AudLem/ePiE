#' Prepare Canal Network Layers
#'
#' Processes raw canal geometries from the network state, snaps them to the basin,
#' and prepares them for integration into the river network topology.
#'
#' @param state Named list. Current pipeline state containing \code{canals_raw} geometry.
#' @param cfg Named list. Pipeline configuration (optional).
#' @return Updated \code{state} list with processed canal layers added.
#' @export
PrepareCanalLayers <- function(state, cfg = list(), diagnostics_level = NULL, diagnostics_dir = NULL) {
  if (is.null(state$canals_raw) || nrow(state$canals_raw) == 0) {
    return(state)
  }

  message("--- Step 2: Tagging Canals and Assigning Manual Q ---")

  canals <- state$canals_raw
  rivers <- state$hydro_sheds_rivers

  canals$is_canal <- TRUE
  canals <- SnapCanalStartsToCanalVertices(canals, cfg)

  canals <- AssignCanalDischarge(canals, cfg)
  canals <- AttachCanalQAnchors(canals, cfg)

  all_cols <- union(names(rivers), names(canals))
  for (col in setdiff(all_cols, names(rivers))) {
    rivers[[col]] <- if (col == "is_canal") FALSE else NA
  }
  for (col in setdiff(all_cols, names(canals))) {
    if (col == "UP_CELLS") {
      canals[[col]] <- 1
    } else if (col == "ARCID") {
      canals[[col]] <- max(rivers$ARCID, na.rm = TRUE) + seq_len(nrow(canals))
    } else if (col == "is_canal") {
      canals[[col]] <- TRUE
    } else {
      canals[[col]] <- NA
    }
  }

  rivers <- rivers[, all_cols]
  canals <- canals[, all_cols]

  q_summary <- paste(unique(round(canals$manual_Q, 2)), collapse = ", ")
  message(">>> Attached ", nrow(canals), " canal segment(s) with manual Q = ", q_summary)

  state$natural_rivers <- rivers
  state$artificial_canals <- canals
  state$hydro_sheds_rivers <- rbind(rivers, canals)

  state
}

# Snap branch starts to nearby canal vertices without changing canal mouths.
# KIS canal lines are hand digitised upstream-to-downstream and may miss their
# junction by a few metres; using vertices keeps branches disconnected from
# rivers while still expressing canal-to-canal junctions in the node topology.
SnapCanalStartsToCanalVertices <- function(canals, cfg) {
  if (is.null(canals) || nrow(canals) < 2) return(canals)

  tol_m <- if (!is.null(cfg$canal_junction_snap_tolerance_m)) {
    cfg$canal_junction_snap_tolerance_m
  } else {
    0
  }
  if (is.na(tol_m) || tol_m <= 0) return(canals)

  id_col <- if ("id" %in% names(canals)) "id" else NULL
  name_col <- if ("canal_name" %in% names(canals)) "canal_name" else NULL
  root_ids <- if (!is.null(cfg$canal_root_ids)) as.character(cfg$canal_root_ids) else "1"
  root_names <- if (!is.null(cfg$canal_root_names)) tolower(cfg$canal_root_names) else "main canal"

  projected <- sf::st_transform(canals, GetUtmCrs(canals))
  n_snapped <- 0
  for (pass in seq_len(3L)) {
    line_coords <- lapply(seq_len(nrow(projected)), function(i) {
      sf::st_coordinates(projected[i, ])[, 1:2, drop = FALSE]
    })
    changed_this_pass <- 0L

    for (i in seq_len(nrow(projected))) {
      canal_id <- if (!is.null(id_col)) as.character(projected[[id_col]][i]) else as.character(i)
      canal_name <- if (!is.null(name_col)) tolower(as.character(projected[[name_col]][i])) else ""
      if (canal_id %in% root_ids || canal_name %in% root_names) next

      coords <- line_coords[[i]]
      if (nrow(coords) < 2) next
      start_xy <- coords[1, ]

      candidates <- do.call(rbind, lapply(setdiff(seq_len(nrow(projected)), i), function(j) {
        data.frame(line_index = j, line_coords[[j]])
      }))
      if (is.null(candidates) || nrow(candidates) == 0) next

      d <- sqrt((candidates$X - start_xy[1])^2 + (candidates$Y - start_xy[2])^2)
      nearest <- which.min(d)
      if (length(nearest) == 0 || is.na(d[nearest]) || d[nearest] > tol_m) next

      new_xy <- as.numeric(candidates[nearest, c("X", "Y")])
      if (sqrt(sum((coords[1, ] - new_xy)^2)) < 0.001) next

      coords[1, ] <- new_xy
      projected$geometry[i] <- sf::st_sfc(sf::st_linestring(coords), crs = sf::st_crs(projected))
      changed_this_pass <- changed_this_pass + 1L
    }
    n_snapped <- n_snapped + changed_this_pass
    if (changed_this_pass == 0L) break
  }

  if (n_snapped > 0) {
    message("  Snapped ", n_snapped, " canal branch start(s) to nearby canal vertices")
  }
  sf::st_transform(projected, sf::st_crs(canals))
}

# Resolve canal discharge (Q) from config: either from CSV table (head+tail midpoint) or uniform value
# CSV table allows variable Q along canals (different at head vs tail)
# Returns canals sf object with q_head, q_tail, and manual_Q (midpoint) columns
# Fallback to 7.2 m3s if nothing configured
AssignCanalDischarge <- function(canals, cfg) {
  if (!is.null(cfg$canal_discharge_table) && file.exists(cfg$canal_discharge_table)) {
    result <- AssignSectionDischarge(canals, cfg$canal_discharge_table)
    canals$q_head <- result$q_head
    canals$q_tail <- result$q_tail
    canals$manual_Q <- result$q_mid
    return(canals)
  }
  tail_fraction <- if (!is.null(cfg$canal_tail_flow_fraction)) cfg$canal_tail_flow_fraction else 0.5
  if (!is.null(cfg$canal_discharge_m3s)) {
    message("  Using uniform canal Q = ", cfg$canal_discharge_m3s, " m3/s (from config)")
    canals$q_head <- rep(cfg$canal_discharge_m3s, nrow(canals))
    canals$q_tail <- rep(cfg$canal_discharge_m3s * tail_fraction, nrow(canals))
    canals$manual_Q <- rep(cfg$canal_discharge_m3s, nrow(canals))
    return(canals)
  }
  message("  Warning: No canal discharge configured. Using default 7.2 m3/s.")
  canals$q_head <- rep(7.2, nrow(canals))
  canals$q_tail <- rep(7.2 * tail_fraction, nrow(canals))
  canals$manual_Q <- rep(7.2, nrow(canals))
  canals
}

# Read canal discharge table and assign Q to each canal segment
# Returns list with q_head, q_tail, and q_mid (midpoint) for each segment
# Fallback to 7.2 m3s for segments not in the table
AssignSectionDischarge <- function(canals, csv_path) {
  q_table <- read.csv(csv_path, stringsAsFactors = FALSE)
  required_cols <- c("id", "discharge_head_m3s", "discharge_tail_m3s")
  missing_cols <- setdiff(required_cols, names(q_table))
  if (length(missing_cols) > 0) {
    stop("Canal discharge table missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  q_head <- rep(NA_real_, nrow(canals))
  q_tail <- rep(NA_real_, nrow(canals))
  q_mid <- rep(NA_real_, nrow(canals))
  for (i in seq_len(nrow(canals))) {
    seg_id <- canals$id[i]
    row_match <- which(q_table$id == seg_id)
    if (length(row_match) == 0 && "canal_name" %in% names(canals) && "section_name" %in% names(q_table)) {
      row_match <- which(tolower(q_table$section_name) == tolower(canals$canal_name[i]))
    }
    if (length(row_match) == 0) {
      warning("No discharge entry for canal segment id=", seg_id, ". Using 7.2 m3/s fallback.")
      q_head[i] <- 7.2
      q_tail[i] <- 7.2
      q_mid[i] <- 7.2
      next
    }
    q_head[i] <- q_table$discharge_head_m3s[row_match[1]]
    q_tail[i] <- q_table$discharge_tail_m3s[row_match[1]]
    q_mid[i] <- (q_head[i] + q_tail[i]) / 2
  }
  list(q_mid = q_mid, q_head = q_head, q_tail = q_tail)
}

AttachCanalQAnchors <- function(canals, cfg) {
  canals$q_anchor_chainage_m <- NA_character_
  canals$q_anchor_model_m3s <- NA_character_
  if (is.null(cfg$canal_q_anchor_table) || !file.exists(cfg$canal_q_anchor_table)) {
    return(canals)
  }

  anchors <- read.csv(cfg$canal_q_anchor_table, stringsAsFactors = FALSE)
  required_cols <- c("chainage_m", "Q_model_m3s")
  missing_cols <- setdiff(required_cols, names(anchors))
  if (length(missing_cols) > 0) {
    stop("Canal Q anchor table missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  for (i in seq_len(nrow(canals))) {
    matches <- integer(0)
    if ("id" %in% names(canals) && "id" %in% names(anchors)) {
      matches <- which(anchors$id == canals$id[i])
    }
    if (length(matches) == 0 && "canal_name" %in% names(canals) && "section_name" %in% names(anchors)) {
      matches <- which(tolower(anchors$section_name) == tolower(canals$canal_name[i]))
    }
    if (length(matches) == 0) next

    a <- anchors[matches, ]
    a <- a[order(a$chainage_m), ]
    canals$q_anchor_chainage_m[i] <- paste(a$chainage_m, collapse = "|")
    canals$q_anchor_model_m3s[i] <- paste(a$Q_model_m3s, collapse = "|")
  }
  canals
}
