PrepareCanalLayers <- function(state, cfg = list()) {
  if (is.null(state$canals_raw) || nrow(state$canals_raw) == 0) {
    return(state)
  }

  message("--- Step 2: Tagging Canals and Assigning Manual Q ---")

  canals <- state$canals_raw
  rivers <- state$hydro_sheds_rivers

  canals$is_canal <- TRUE

  canals$manual_Q <- AssignCanalDischarge(canals, cfg)

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

AssignCanalDischarge <- function(canals, cfg) {
  if (!is.null(cfg$canal_discharge_table) && file.exists(cfg$canal_discharge_table)) {
    return(AssignSectionDischarge(canals, cfg$canal_discharge_table))
  }
  if (!is.null(cfg$canal_discharge_m3s)) {
    message("  Using uniform canal Q = ", cfg$canal_discharge_m3s, " m3/s (from config)")
    return(rep(cfg$canal_discharge_m3s, nrow(canals)))
  }
  message("  Warning: No canal discharge configured. Using default 7.2 m3/s.")
  rep(7.2, nrow(canals))
}

AssignSectionDischarge <- function(canals, csv_path) {
  q_table <- read.csv(csv_path, stringsAsFactors = FALSE)
  required_cols <- c("id", "discharge_head_m3s", "discharge_tail_m3s")
  missing_cols <- setdiff(required_cols, names(q_table))
  if (length(missing_cols) > 0) {
    stop("Canal discharge table missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  result <- rep(NA_real_, nrow(canals))
  for (i in seq_len(nrow(canals))) {
    seg_id <- canals$id[i]
    row_match <- which(q_table$id == seg_id)
    if (length(row_match) == 0) {
      warning("No discharge entry for canal segment id=", seg_id, ". Using 7.2 m3/s fallback.")
      result[i] <- 7.2
      next
    }
    q_head <- q_table$discharge_head_m3s[row_match[1]]
    q_tail <- q_table$discharge_tail_m3s[row_match[1]]
    q_mid <- (q_head + q_tail) / 2
    result[i] <- q_mid
  }
  result
}
