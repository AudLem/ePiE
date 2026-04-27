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

  q_summary <- paste(unique(round(canals$manual_Q, 2)), collapse = ", ")
  message(">>> Attached ", nrow(canals), " canal segment(s) with manual Q = ", q_summary)

  state$natural_rivers <- rivers
  state$artificial_canals <- canals
  state$hydro_sheds_rivers <- rbind(rivers, canals)

  state
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
