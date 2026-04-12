#' Process Lake Geometries
#'
#' Intersects HydroLAKES polygons with the basin boundary, enriches them with
#' volume and depth data, and prepares lake nodes for routing.
#'
#' @param dir Raster. Flow-direction raster used for lake outlet detection.
#' @param HL sf object. HydroLAKES polygons.
#' @param Basin sf object. Basin boundary polygon.
#' @param Basin_buff_r Raster. Rasterised buffered basin.
#' @param enable_lakes Logical. Whether to include lake routing in the network.
#' @return A named list with \code{HL_basin} (in-basin lakes) and \code{lake_mask} raster.
#' @export
ProcessLakeGeometries <- function(dir,
                                     HL,
                                     Basin,
                                     Basin_buff_r,
                                     enable_lakes = TRUE) {
  message("--- Step 4: Processing Lakes ---")

  if (!isTRUE(enable_lakes)) {
    message(">>> Lakes disabled by configuration. Skipping processing.")
    return(list(
      HL_basin = NULL,
      Basin_lakes = NULL,
      HL = NULL
    ))
  }

  bas_bbox <- sf::st_bbox(Basin)
  ext <- as.vector(raster::extent(dir))
  ext[c(1, 3)] <- ext[c(1, 3)] - 2
  ext[c(2, 4)] <- ext[c(2, 4)] + 2

  HL_crop <- HL
  rm_longs <- HL_crop$Pour_long < ext[1] | HL_crop$Pour_long > ext[2]
  HL_crop <- HL_crop[!rm_longs, ]
  rm_lats <- HL_crop$Pour_lat < ext[3] | HL_crop$Pour_lat > ext[4]
  HL_crop <- HL_crop[!rm_lats, ]

  HL_crop <- EnsureSameCrs(dir, HL_crop, "flow_dir", "Lakes")
  HL_crop <- sf::st_make_valid(HL_crop)
  lak_bbox <- lapply(HL_crop[["geometry"]], sf::st_bbox)
  lak_bbox <- do.call(rbind, lak_bbox) |> as.data.frame()
  HL_crop2 <- HL_crop[
    lak_bbox$ymax > bas_bbox$ymin &
      lak_bbox$ymin < bas_bbox$ymax &
      lak_bbox$xmax > bas_bbox$xmin &
      lak_bbox$xmin < bas_bbox$xmax,
  ]

  if (!requireNamespace("exactextractr", quietly = TRUE)) {
    stop("Package 'exactextractr' is required for lake processing. Install it with install.packages('exactextractr')")
  }

  HL_crop2$bas_val <- exactextractr::exact_extract(
    Basin_buff_r,
    HL_crop2,
    function(values, coverage_fractions) mean(values, na.rm = TRUE)
  )
  HL_crop2_p1 <- HL_crop2[HL_crop2$bas_val == 1, ]
  HL_crop2_p2 <- HL_crop2[HL_crop2$bas_val > 0 & HL_crop2$bas_val < 1, ]
  if (nrow(HL_crop2_p2) > 0) {
    HL_crop2_p2 <- EnsureSameCrs(Basin, HL_crop2_p2, "Basin", "Lakes")
    tmp <- sf::st_within(HL_crop2_p2, Basin, sparse = FALSE)
    HL_crop2_p2 <- HL_crop2_p2[which(apply(tmp, 1, any)), ]
  }
  if (nrow(HL_crop2_p2) > 0) {
    HL_crop2 <- rbind(HL_crop2_p1, HL_crop2_p2)
  } else {
    HL_crop2 <- HL_crop2_p1
  }
  HL_basin <- HL_crop2

  if (nrow(HL_basin) > 0) {
    HL_basin <- EnsureSameCrs(Basin, HL_basin, "Basin", "HL_basin")
    intersects_mask <- sf::st_intersects(HL_basin, Basin, sparse = FALSE)[, 1]
    HL_basin <- HL_basin[intersects_mask, ]
    if (nrow(HL_basin) > 0) {
      HL_basin <- sf::st_intersection(HL_basin, Basin)
      HL_basin <- HL_basin[sf::st_dimension(HL_basin) == 2, ]
    }
  }

  if (nrow(HL_basin) > 0) {
    total_vertices_before <- sum(sapply(sf::st_geometry(HL_basin), function(x) nrow(sf::st_coordinates(x))))
    HL_basin <- sf::st_simplify(HL_basin, preserveTopology = TRUE, dTolerance = 0.001)
    HL_basin <- sf::st_make_valid(HL_basin)
    HL_basin <- HL_basin[!sf::st_is_empty(HL_basin), ]
    total_vertices_after <- sum(sapply(sf::st_geometry(HL_basin), function(x) nrow(sf::st_coordinates(x))))
    message("Lake features in basin: ", nrow(HL_basin))
    message(">>> Simplification reduced vertices from ", total_vertices_before, " to ", total_vertices_after)
  }

  list(
    HL_basin = HL_basin,
    Basin_lakes = HL_basin,
    HL = HL
  )
}
