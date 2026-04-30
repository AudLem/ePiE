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

  message("--- Step 2: Tagging Canals and Assigning Canal Q ---")

  canals <- state$canals_raw
  rivers <- state$hydro_sheds_rivers

  canals$is_canal <- TRUE
  canals <- SnapCanalStartsToCanalVertices(canals, cfg)

  canals <- AssignCanalDischarge(canals, cfg)

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

  q_summary <- paste(unique(round(canals$q_head, 2)), collapse = ", ")
  message(">>> Attached ", nrow(canals), " canal segment(s) with canal head Q = ", q_summary)

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

# Resolve canal discharge (Q) from a named, citation-backed source registry.
# The selected source supplies section head/tail values plus provenance; node-
# level Q is interpolated later when canal vertices and chainage are known.
AssignCanalDischarge <- function(canals, cfg) {
  if (!is.null(cfg$canal_q_source_table) && nzchar(as.character(cfg$canal_q_source_table))) {
    result <- AssignCanalDischargeFromSource(canals, cfg)
    if (!is.null(result)) return(result)
  }

  if (!is.null(cfg$canal_discharge_table) && file.exists(cfg$canal_discharge_table)) {
    result <- AssignSectionDischarge(canals, cfg$canal_discharge_table)
    canals$q_head <- result$q_head
    canals$q_tail <- result$q_tail
    canals$canal_q_source_id <- "legacy_section_table"
    canals$canal_q_reference_short <- "legacy section table"
    canals$canal_q_reference_url <- NA_character_
    canals$canal_q_regime <- NA_character_
    canals$canal_q_data_period <- NA_character_
    canals$canal_q_season <- NA_character_
    canals$canal_q_value_origin <- NA_character_
    canals$canal_q_derivation_rule <- NA_character_
    canals$canal_q_notes <- NA_character_
    return(canals)
  }
  tail_fraction <- if (!is.null(cfg$canal_tail_flow_fraction)) cfg$canal_tail_flow_fraction else 0.5
  if (!is.null(cfg$canal_discharge_m3s)) {
    message("  Using uniform canal Q = ", cfg$canal_discharge_m3s, " m3/s (from config)")
    canals$q_head <- rep(cfg$canal_discharge_m3s, nrow(canals))
    canals$q_tail <- rep(cfg$canal_discharge_m3s * tail_fraction, nrow(canals))
    return(canals)
  }
  message("  Warning: No canal discharge configured. Using default 7.2 m3/s.")
  canals$q_head <- rep(7.2, nrow(canals))
  canals$q_tail <- rep(7.2 * tail_fraction, nrow(canals))
  canals
}

# Select one canal-Q source from the registry and attach both Q values and
# source metadata to each canal line. The registry is the scientific contract:
# changing source_id changes the hydraulic interpretation without code edits.
AssignCanalDischargeFromSource <- function(canals, cfg) {
  source_path <- as.character(cfg$canal_q_source_table)
  if (!file.exists(source_path)) {
    stop("Configured canal_q_source_table does not exist: ", source_path)
  }

  source_id <- if (!is.null(cfg$canal_q_source_id) && nzchar(as.character(cfg$canal_q_source_id))) {
    as.character(cfg$canal_q_source_id)
  } else {
    "jica_2012_peak"
  }

  q_table <- read.csv(source_path, stringsAsFactors = FALSE)
  selected <- q_table[q_table$source_id == source_id, , drop = FALSE]
  if (nrow(selected) == 0) {
    stop(
      "Unknown canal_q_source_id '", source_id, "'. Available sources: ",
      paste(sort(unique(q_table$source_id)), collapse = ", ")
    )
  }

  required_cols <- c(
    "source_id", "reference_short", "reference_full", "reference_url",
    "publication_year", "data_year_start", "data_year_end", "season_label",
    "regime_type", "canal_id", "section_name", "discharge_head_m3s",
    "discharge_tail_m3s", "value_origin", "derivation_rule"
  )
  missing_cols <- setdiff(required_cols, names(selected))
  if (length(missing_cols) > 0) {
    stop("Canal Q source registry missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  bad_required <- !stats::complete.cases(selected[, c(
    "source_id", "reference_short", "publication_year", "regime_type",
    "canal_id", "section_name", "discharge_head_m3s", "discharge_tail_m3s",
    "value_origin", "derivation_rule"
  )])
  if (any(bad_required)) {
    stop("Canal Q source '", source_id, "' has incomplete required metadata/Q rows.")
  }

  result <- AssignSectionDischarge(canals, selected)
  canals$q_head <- result$q_head
  canals$q_tail <- result$q_tail
  canals$canal_q_source_id <- result$metadata$source_id
  canals$canal_q_reference_short <- result$metadata$reference_short
  canals$canal_q_reference_url <- result$metadata$reference_url
  canals$canal_q_regime <- result$metadata$regime_type
  canals$canal_q_data_period <- result$metadata$data_period
  canals$canal_q_season <- result$metadata$season_label
  canals$canal_q_value_origin <- result$metadata$value_origin
  canals$canal_q_derivation_rule <- result$metadata$derivation_rule
  canals$canal_q_notes <- result$metadata$notes

  message("  Using canal Q source: ", source_id, " (", unique(selected$reference_short)[1], ")")
  canals
}

# Read canal discharge table and assign head/tail Q to each canal segment.
AssignSectionDischarge <- function(canals, csv_path) {
  q_table <- if (is.data.frame(csv_path)) csv_path else read.csv(csv_path, stringsAsFactors = FALSE)
  if (!("id" %in% names(q_table)) && "canal_id" %in% names(q_table)) {
    q_table$id <- q_table$canal_id
  }
  required_cols <- c("id", "discharge_head_m3s", "discharge_tail_m3s")
  missing_cols <- setdiff(required_cols, names(q_table))
  if (length(missing_cols) > 0) {
    stop("Canal discharge table missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  q_head <- rep(NA_real_, nrow(canals))
  q_tail <- rep(NA_real_, nrow(canals))
  metadata_cols <- c(
    "source_id", "reference_short", "reference_url", "regime_type",
    "season_label", "value_origin", "derivation_rule", "notes"
  )
  metadata <- lapply(metadata_cols, function(col) rep(NA_character_, nrow(canals)))
  names(metadata) <- metadata_cols
  metadata$data_period <- rep(NA_character_, nrow(canals))

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
      next
    }
    q_head[i] <- q_table$discharge_head_m3s[row_match[1]]
    q_tail[i] <- q_table$discharge_tail_m3s[row_match[1]]
    for (col in metadata_cols) {
      if (col %in% names(q_table)) {
        metadata[[col]][i] <- as.character(q_table[[col]][row_match[1]])
      }
    }
    if (all(c("data_year_start", "data_year_end") %in% names(q_table))) {
      metadata$data_period[i] <- paste0(q_table$data_year_start[row_match[1]], "-", q_table$data_year_end[row_match[1]])
    }
  }
  list(q_head = q_head, q_tail = q_tail, metadata = metadata)
}
