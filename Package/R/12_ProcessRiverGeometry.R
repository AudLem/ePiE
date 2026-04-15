#' Process River Geometry
#'
#' Clips the HydroSHEDS river network to the basin boundary using strict spatial
#' intersection, producing the in-basin river segments used for network topology.
#'
#' @param hydro_sheds_rivers sf object. Full HydroSHEDS river network.
#' @param reference_hydro_sheds_rivers sf object or \code{NULL}. Optional reference river network for mouth detection.
#' @param Basin sf object. Basin boundary polygon.
#' @param Basin_buff sf object. Buffered basin polygon for spatial joins.
#' @param cfg Named list. Configuration.
#' @param river_simplification_tolerance numeric. Optional tolerance.
#' @return A named list with \code{hydro_sheds_rivers_basin} (clipped rivers) and \code{Basin_buff_r} (rasterised buffer).
#' @export
ProcessRiverGeometry <- function(hydro_sheds_rivers,
                                    reference_hydro_sheds_rivers = NULL,
                                    Basin,
                                    Basin_buff,
                                    cfg = list(),
                                    river_simplification_tolerance = NULL) {
  message("--- Step 3: Processing River Network (Strict Border Clipping) ---")

  if (!is.null(hydro_sheds_rivers)) hydro_sheds_rivers <- sf::st_zm(hydro_sheds_rivers)
  if (!is.null(reference_hydro_sheds_rivers)) reference_hydro_sheds_rivers <- sf::st_zm(reference_hydro_sheds_rivers)
  if (!is.null(Basin)) Basin <- sf::st_zm(Basin)
  if (!is.null(Basin_buff)) Basin_buff <- sf::st_zm(Basin_buff)

  # Two-pass clipping: first bbox filter, then strict st_intersection
  # bas_val==1 means fully inside basin, bas_val>0 means partially overlapping
  # After intersection, cast MULTILINESTRING to LINESTRING and remove empty geometries
  select_basin_rivers <- function(rivers, target_polygon) {
    rivers <- EnsureSameCrs(target_polygon, rivers, "target_polygon", "Rivers")
    touches_idx <- sf::st_intersects(rivers, target_polygon, sparse = FALSE)[, 1]
    rivers_in_area <- rivers[touches_idx, ]
    if (nrow(rivers_in_area) == 0) return(rivers_in_area)
    message(">>> Strictly clipping ", nrow(rivers_in_area), " features to the official basin border.")
    result <- suppressWarnings(sf::st_intersection(rivers_in_area, sf::st_geometry(target_polygon)))
    result <- result[sf::st_geometry_type(result) %in% c("LINESTRING", "MULTILINESTRING"), ]
    if (nrow(result) == 0) return(result)
    result <- suppressWarnings(sf::st_cast(suppressWarnings(sf::st_cast(result, "MULTILINESTRING")), "LINESTRING"))
    result[!sf::st_is_empty(result), ]
  }

  if ("LINKNO" %in% names(hydro_sheds_rivers)) {
    # GeoGLOWS mode
    message("GeoGLOWS mode: clipping to basin boundary, then simplifying.")
    pre_clip <- hydro_sheds_rivers
    hydro_sheds_rivers_basin <- select_basin_rivers(hydro_sheds_rivers, Basin)

    if (nrow(hydro_sheds_rivers_basin) > 0) {
      attr_cols <- intersect(c("LINKNO", "DSLINKNO", "USContArea", "UPLAND_SKM", "ARCID"), names(pre_clip))
      missing_cols <- setdiff(attr_cols, names(hydro_sheds_rivers_basin))
      if (length(missing_cols) > 0) {
        nearest <- sf::st_nearest_feature(hydro_sheds_rivers_basin, pre_clip)
        for (col in missing_cols) hydro_sheds_rivers_basin[[col]] <- pre_clip[[col]][nearest]
        if ("DSLINKNO" %in% names(hydro_sheds_rivers_basin) && "LINKNO" %in% names(hydro_sheds_rivers_basin)) {
          basin_linknos <- as.character(hydro_sheds_rivers_basin$LINKNO)
          for (si in seq_len(nrow(hydro_sheds_rivers_basin))) {
            ds_id <- hydro_sheds_rivers_basin$DSLINKNO[si]
            if (is.na(ds_id) || as.character(ds_id) %in% basin_linknos) next
            coords_si <- sf::st_coordinates(hydro_sheds_rivers_basin[si, ])
            tail_si <- coords_si[nrow(coords_si), 1:2]
            for (sj in seq_len(nrow(hydro_sheds_rivers_basin))) {
              if (si == sj) next
              coords_sj <- sf::st_coordinates(hydro_sheds_rivers_basin[sj, ])
              head_sj <- coords_sj[1, 1:2]
              if (all(abs(tail_si - head_sj) < 1e-6)) {
                hydro_sheds_rivers_basin$DSLINKNO[si] <- hydro_sheds_rivers_basin$LINKNO[sj]
                break
              }
            }
          }
        }
      }
      
      utm_crs <- GetUtmCrs(Basin)
      projected <- sf::st_transform(hydro_sheds_rivers_basin, utm_crs)
      canal_simplify <- if (!is.null(cfg$simplification$canal_simplify)) cfg$simplification$canal_simplify else TRUE
      simplified <- SimplifyRiverGeometry(projected, river_simplification_tolerance, canal_simplify)
      hydro_sheds_rivers_basin <- sf::st_transform(simplified, sf::st_crs(Basin))
      hydro_sheds_rivers_basin <- hydro_sheds_rivers_basin[!sf::st_is_empty(hydro_sheds_rivers_basin), ]
    }
  } else {
    hydro_sheds_rivers_basin <- select_basin_rivers(hydro_sheds_rivers, Basin)
    if (nrow(hydro_sheds_rivers_basin) > 0 && !is.null(river_simplification_tolerance) && river_simplification_tolerance > 0) {
      utm_crs <- GetUtmCrs(Basin)
      projected <- sf::st_transform(hydro_sheds_rivers_basin, utm_crs)
      canal_simplify <- if (!is.null(cfg$simplification$canal_simplify)) cfg$simplification$canal_simplify else TRUE
      simplified <- SimplifyRiverGeometry(projected, river_simplification_tolerance, canal_simplify)
      hydro_sheds_rivers_basin <- sf::st_transform(simplified, sf::st_crs(Basin))
      hydro_sheds_rivers_basin <- hydro_sheds_rivers_basin[!sf::st_is_empty(hydro_sheds_rivers_basin), ]
    } else {
      message(">>> River simplification skipped (tolerance is NULL or 0)")
    }
  }

  if (nrow(hydro_sheds_rivers_basin) == 0) {
    stop("Critical Error: No river segments remaining inside the strict basin boundary.")
  }

  # Snap canal endpoints to the nearest river segment
  if ("is_canal" %in% names(hydro_sheds_rivers_basin)) {
    canal_mask <- !is.na(hydro_sheds_rivers_basin$is_canal) & hydro_sheds_rivers_basin$is_canal
    if (any(canal_mask)) {
      river_only <- hydro_sheds_rivers_basin[!canal_mask, ]
      river_union <- sf::st_union(river_only)
      n_snapped <- 0
      for (ci in which(canal_mask)) {
        coords <- sf::st_coordinates(hydro_sheds_rivers_basin[ci, ])
        if (nrow(coords) < 2) next
        start_pt <- sf::st_sfc(sf::st_point(coords[1, 1:2]), crs = sf::st_crs(river_only))
        end_pt <- sf::st_sfc(sf::st_point(coords[nrow(coords), 1:2]), crs = sf::st_crs(river_only))
        snap_line_s <- sf::st_nearest_points(start_pt, river_union)
        snap_line_e <- sf::st_nearest_points(end_pt, river_union)
        new_start <- sf::st_point(sf::st_coordinates(snap_line_s)[2, 1:2])
        new_end <- sf::st_point(sf::st_coordinates(snap_line_e)[2, 1:2])
        coords[1, 1:2] <- c(new_start[1], new_start[2])
        coords[nrow(coords), 1:2] <- c(new_end[1], new_end[2])
        hydro_sheds_rivers_basin$geometry[ci] <- sf::st_sfc(sf::st_linestring(coords[, 1:2]), crs = sf::st_crs(river_only))
        n_snapped <- n_snapped + 1
      }
      if (n_snapped > 0) message("  Snapped ", n_snapped, " canal endpoint(s) to river network")
    }
  }

  message("Number of river features in final basin network: ", nrow(hydro_sheds_rivers_basin))
  
  if (!("UP_CELLS" %in% names(hydro_sheds_rivers_basin)) && "USContArea" %in% names(hydro_sheds_rivers_basin)) {
    hydro_sheds_rivers_basin$UP_CELLS <- hydro_sheds_rivers_basin$USContArea / 1e6
  }

  # The river mouth is the segment with the most upstream cells (largest catchment)
  # This is where the river exits the basin - identified by max UP_CELLS
  river_candidates <- hydro_sheds_rivers_basin
  if ("is_canal" %in% names(river_candidates)) {
    river_candidates <- river_candidates[is.na(river_candidates$is_canal) | !river_candidates$is_canal, ]
  }
  if (nrow(river_candidates) == 0) {
    stop("Error: No non-canal river segments found for mouth selection.")
  }
  mouth_idx <- which.max(river_candidates$UP_CELLS)
  mouth <- river_candidates[mouth_idx[1], ]
  mouth_points <- suppressWarnings(sf::st_cast(mouth, "POINT"))
  mouth_pt <- mouth_points[nrow(mouth_points), ]

  mouth_pt_utm <- sf::st_transform(mouth_pt, GetUtmCrs(Basin))
  mouth_buff_utm <- sf::st_buffer(mouth_pt_utm, 100)
  mouth_buff <- sf::st_transform(mouth_buff_utm, sf::st_crs(mouth_pt))

  basin_border_new <- Basin_buff

  mouth_point_newFrom <- mouth_points[nrow(mouth_points), ]
  s1 <- 0.005; s2 <- 0.005; s3 <- 0.01; s4 <- 0.01

  mouth_point_newTo1 <- mouth_point_newFrom
  mouth_point_newTo2 <- mouth_point_newFrom

  # Create a dummy 2-segment line to extend the mouth point outside the basin
  # This ensures the mouth has a valid downstream connection that exits the basin cleanly
  # Otherwise the mouth would be a dead end (no ID_nxt, breaks topology)
  # Small random offsets (s1-s4) create a realistic-looking extension
  mouth_point_newTo1$geometry <- sf::st_sfc(sf::st_point(c(
    mouth_point_newFrom$geometry[[1]][1] + s1,
    mouth_point_newFrom$geometry[[1]][2] + s2
  )))
  mouth_point_newTo2$geometry <- sf::st_sfc(sf::st_point(c(
    mouth_point_newFrom$geometry[[1]][1] + s3,
    mouth_point_newFrom$geometry[[1]][2] + s4
  )))

  mouth_point_newTo1 <- sf::st_set_crs(mouth_point_newTo1, sf::st_crs(mouth_point_newFrom))
  mouth_point_newTo2 <- sf::st_set_crs(mouth_point_newTo2, sf::st_crs(mouth_point_newFrom))

  mouth_point_new <- rbind(mouth_point_newFrom, mouth_point_newTo1, mouth_point_newTo2)
  mouth_point_new <- sf::st_cast(sf::st_combine(mouth_point_new), "LINESTRING")

  mouth2 <- mouth
  mouth2$UP_CELLS <- mouth$UP_CELLS + 10
  mouth2$ARCID <- max(hydro_sheds_rivers_basin$ARCID, na.rm = TRUE) + 1
  mouth2$geometry[[1]] <- mouth_point_new[[1]]

  hydro_sheds_rivers_basin <- rbind(hydro_sheds_rivers_basin, mouth2)
  hydro_sheds_rivers_basin <- suppressWarnings(sf::st_cast(hydro_sheds_rivers_basin, "LINESTRING"))

  list(
    natural_rivers_processed = hydro_sheds_rivers_basin,
    hydro_sheds_rivers_basin = hydro_sheds_rivers_basin,
    hydro_sheds_rivers = hydro_sheds_rivers_basin,
    basin_border_new = basin_border_new,
    mouth = mouth,
    Basin_mouth = mouth,
    mouth_points = mouth_points,
    mouth_pt = mouth_pt,
    mouth_buff = mouth_buff
  )
}
