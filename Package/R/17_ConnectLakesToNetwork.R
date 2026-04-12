#' Connect Lakes to Network
#'
#' Enriches network points with lake IDs and creates inlet/outlet node pairs
#' for each lake, enabling through-lake routing and decay calculations.
#'
#' @param points sf object. Network point nodes.
#' @param HL_basin sf object or \code{NULL}. In-basin lake polygons.
#' @return Updated \code{points} sf object with lake connectivity columns.
#' @export
ConnectLakesToNetwork <- function(points, HL_basin) {
  message("--- Step 8b: Establishing Lake Connectivity ---")

  if (is.null(HL_basin) || nrow(HL_basin) == 0) {
    message(">>> No lakes found in basin. Skipping lake connectivity enrichment.")
    if (!("lake_in" %in% names(points))) points$lake_in <- 0
    if (!("lake_out" %in% names(points))) points$lake_out <- 0
    if (!("HL_ID_new" %in% names(points))) points$HL_ID_new <- 0
    return(list(points = points))
  }

  HL_basin <- EnsureSameCrs(points, HL_basin, "points", "HL_basin")

  message(">>> Points count: ", nrow(points), ", Lakes count: ", nrow(HL_basin))

  if (!("lake_in" %in% names(points))) points$lake_in <- 0
  if (!("lake_out" %in% names(points))) points$lake_out <- 0
  if (!("HL_ID_new" %in% names(points))) points$HL_ID_new <- 0

  points$lake_in[is.na(points$lake_in)] <- 0
  points$lake_out[is.na(points$lake_out)] <- 0
  points$HL_ID_new[is.na(points$HL_ID_new)] <- 0

  within_indices <- sf::st_intersects(points, HL_basin)

  assigned_count <- 0
  for (i in seq_along(within_indices)) {
    idx <- within_indices[[i]]
    if (length(idx) > 0) {
      if (is.na(points$HL_ID_new[i]) || points$HL_ID_new[i] == 0) {
        points$HL_ID_new[i] <- HL_basin$Hylak_id[idx[1]]
        assigned_count <- assigned_count + 1
      }
    }
  }

  in_lake_mask <- points$HL_ID_new != 0
  message(">>> Assigned HL_ID_new to ", assigned_count, " NEW nodes. Total nodes in lakes: ", sum(in_lake_mask, na.rm = TRUE))

  if (sum(in_lake_mask, na.rm = TRUE) > 0) {
    id_to_lake <- setNames(as.numeric(points$HL_ID_new), points$ID)

    for (i in which(in_lake_mask)) {
      current_lake <- as.numeric(points$HL_ID_new[i])
      next_id <- points$ID_nxt[i]

      if (is.na(next_id) || (points$pt_type[i] %in% c("MOUTH", "mouth"))) {
        points$lake_out[i] <- 1
        points$pt_type[i] <- "Hydro_Lake"
      } else {
        next_lake <- if (next_id %in% names(id_to_lake)) id_to_lake[next_id] else NA
        if (is.na(next_lake) || next_lake != current_lake) {
          points$lake_out[i] <- 1
          points$pt_type[i] <- "Hydro_Lake"
        }
      }
    }

    upstream_lookup <- split(points$ID, points$ID_nxt)

    for (i in which(in_lake_mask)) {
      current_lake <- as.numeric(points$HL_ID_new[i])
      curr_id <- points$ID[i]

      up_ids <- if (curr_id %in% names(upstream_lookup)) upstream_lookup[[curr_id]] else NULL

      if (is.null(up_ids) || length(up_ids) == 0 || (points$pt_type[i] %in% c("START", "start"))) {
        points$lake_in[i] <- 1
      } else {
        up_lakes <- id_to_lake[up_ids]
        if (any(is.na(up_lakes) | up_lakes != current_lake)) {
          points$lake_in[i] <- 1
        }
      }
    }
  }

  message(">>> Identified ", sum(points$lake_in, na.rm = TRUE), " inlet nodes and ",
          sum(points$lake_out, na.rm = TRUE), " outlet nodes.")

  list(points = points)
}
