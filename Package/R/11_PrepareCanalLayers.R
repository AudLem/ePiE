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

  # Ensure DSLINKNO column exists for canal downstream linking (HydroSHEDS mode)
  if (!("DSLINKNO" %in% all_cols)) {
    rivers$DSLINKNO <- NA
    canals$DSLINKNO <- NA
    all_cols <- c(all_cols, "DSLINKNO")
    rivers <- rivers[, all_cols]
    canals <- canals[, all_cols]
  }

  # Assign downstream link for canals via spatial matching.
  # Find the nearest river segment to each canal's tail (downstream) endpoint
  # and store its ID as DSLINKNO. This enables topology wiring in
  # BuildNetworkTopology for both HydroSHEDS and GeoGLOWS modes.
  # This is critical for canal connectivity - without DSLINKNO, canals would be dead ends.
  if (all(sf::st_is_valid(canals)) && nrow(rivers) > 0) {
    n_assigned <- 0
    for (i in seq_len(nrow(canals))) {
      coords <- sf::st_coordinates(canals[i, ])
      if (nrow(coords) < 2) next
      tail_pt <- sf::st_sfc(sf::st_point(coords[nrow(coords), 1:2]), crs = sf::st_crs(rivers))
      nearest_idx <- sf::st_nearest_feature(tail_pt, rivers)
      # Use LINKNO if available (GeoGLOWS), otherwise ARCID (HydroSHEDS)
      ds_id <- if ("LINKNO" %in% names(rivers) && !is.na(rivers$LINKNO[nearest_idx])) {
        rivers$LINKNO[nearest_idx]
      } else {
        rivers$ARCID[nearest_idx]
      }
      canals$DSLINKNO[i] <- ds_id
      n_assigned <- n_assigned + 1
    }
    if (n_assigned > 0) message("  Assigned DSLINKNO to ", n_assigned, " canal segment(s)")
  }

  q_summary <- paste(unique(round(canals$manual_Q, 2)), collapse = ", ")
  message(">>> Attached ", nrow(canals), " canal segment(s) with manual Q = ", q_summary)

  state$natural_rivers <- rivers
  state$artificial_canals <- canals
  state$hydro_sheds_rivers <- rbind(rivers, canals)

  state
}

# Resolve canal discharge (Q) from config: either from CSV table (head+tail midpoint) or uniform value
# CSV table allows variable Q along canals (different at head vs tail)
# Fallback to 7.2 m3s if nothing configured
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

# Read canal discharge table and assign Q to each canal segment
# For each segment, use midpoint of head and tail discharge values
# Fallback to 7.2 m3s for segments not in the table
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
