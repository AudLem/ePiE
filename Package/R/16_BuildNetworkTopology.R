#' Build Network Topology
#'
#' Converts river segments into a directed node-link topology using flow-direction
#' rasters, assigning each node an upstream/downstream relationship.
#'
#' @param hydro_sheds_rivers_basin sf object. Clipped river network.
#' @param dir Raster. Flow-direction raster (HydroSHEDS).
#' @param Basin sf object. Basin boundary polygon.
#' @return A named list with \code{points} (network nodes) and \code{lines} (network edges).
#' @export
BuildNetworkTopology <- function(hydro_sheds_rivers_basin,
                                    dir,
                                    Basin) {
  message("--- Step 7: Building Network Topology ---")

  lines <- hydro_sheds_rivers_basin
  lines <- suppressWarnings(sf::st_cast(lines, "LINESTRING"))
  points_coords <- sf::st_coordinates(lines)
  points <- as.data.frame(points_coords)
  points <- sf::st_as_sf(points, coords = c("X", "Y"), remove = FALSE)
  points <- sf::st_set_crs(points, sf::st_crs(lines))
  points$ARCID <- lines$ARCID[points$L1]
  points$UP_CELLS <- lines$UPLAND_SKM[points$L1]
  points$is_canal <- if ("is_canal" %in% names(lines)) as.logical(lines$is_canal[points$L1]) else FALSE
  points$manual_Q <- if ("manual_Q" %in% names(lines)) as.numeric(lines$manual_Q[points$L1]) else NA_real_
  points$dir <- raster::extract(dir, points)
  points$ID <- paste0("P_", stringr::str_pad(seq_len(nrow(points)), 5, "left", "0"))
  points$x <- sf::st_coordinates(points)[, 1]
  points$y <- sf::st_coordinates(points)[, 2]
  points$dir <- ifelse(is.na(points$dir), 1, points$dir)

  LineIDs <- unique(lines$ARCID)
  points$idx_in_line_seg <- NA
  points$ID_nxt <- NA
  points$pt_type <- "node"
  points$loc_ID_tmp <- paste0(points$X, "_", points$Y)

  points_df <- sf::st_drop_geometry(points)

  for (i in seq_along(LineIDs)) {
    idx <- which(points_df$ARCID == LineIDs[i])
    if (length(idx) > 1) {
      points_df$ID_nxt[idx[1:(length(idx) - 1)]] <- points_df$ID[idx[2:length(idx)]]
    }
    points_df$idx_in_line_seg[idx] <- seq_along(idx)
  }

  loc_ids <- points_df$loc_ID_tmp
  for (i in seq_along(LineIDs)) {
    idx <- which(points_df$ARCID == LineIDs[i])
    last_pt_idx <- idx[length(idx)]
    last_loc <- points_df$loc_ID_tmp[last_pt_idx]
    matches <- which(loc_ids == last_loc)
    if (length(matches) > 1) {
      other_starts <- matches[points_df$idx_in_line_seg[matches] == 1 & matches != last_pt_idx]
      if (length(other_starts) > 0) {
        points_df$ID_nxt[last_pt_idx] <- points_df$ID[other_starts[1]]
        points_df$pt_type[other_starts[1]] <- "JNCT"
      }
    }
  }

  points$ID_nxt <- points_df$ID_nxt
  points$pt_type <- points_df$pt_type
  points$idx_in_line_seg <- points_df$idx_in_line_seg

  points <- points[which(is.na(points$ID_nxt) | points$ID_nxt != "REMOVE"), ]

  current_utm_crs <- GetUtmCrs(Basin)
  points_utm <- sf::st_transform(points, crs = current_utm_crs)
  idx_next_vec <- match(points$ID_nxt, points$ID)
  coords_utm <- sf::st_coordinates(points_utm)
  points$d_nxt <- sqrt(
    (coords_utm[, 1] - coords_utm[idx_next_vec, 1])^2 +
      (coords_utm[, 2] - coords_utm[idx_next_vec, 2])^2
  )

  mouth_idx <- which(is.na(points$d_nxt))
  points$pt_type[mouth_idx] <- "MOUTH"
  points$pt_type[which(!points$ID %in% points$ID_nxt)] <- "START"

  idx_nxt_tmp <- match(points$ID_nxt, points$ID)
  isMouth <- as.numeric(points$pt_type == "MOUTH")
  points$LD2 <- 0
  idx_cpp <- (seq_len(nrow(points)))[which(points$pt_type != "MOUTH")] - 1
  if (length(idx_cpp) > 0) {
    points$LD2[idx_cpp + 1] <- calc_ld_cpp(i = idx_cpp, isMouth, points$d_nxt, idx_nxt_tmp - 1)
  }
  points$LD <- points$LD2

  list(
    lines = lines,
    hydro_sheds_rivers = lines,
    points = points
  )
}
