#' Process River Geometry
#'
#' Clips the HydroSHEDS river network to the basin boundary using strict spatial
#' intersection, producing the in-basin river segments used for network topology.
#'
#' @param hydro_sheds_rivers sf object. Full HydroSHEDS river network.
#' @param reference_hydro_sheds_rivers sf object or \code{NULL}. Optional reference river network for mouth detection.
#' @param Basin sf object. Basin boundary polygon.
#' @param Basin_buff sf object. Buffered basin polygon for spatial joins.
#' @return A named list with \code{hydro_sheds_rivers_basin} (clipped rivers) and \code{Basin_buff_r} (rasterised buffer).
#' @export
ProcessRiverGeometry <- function(hydro_sheds_rivers,
                                    reference_hydro_sheds_rivers = NULL,
                                    Basin,
                                    Basin_buff) {
  message("--- Step 3: Processing River Network (Strict Border Clipping) ---")

  if (!is.null(hydro_sheds_rivers)) hydro_sheds_rivers <- sf::st_zm(hydro_sheds_rivers)
  if (!is.null(reference_hydro_sheds_rivers)) reference_hydro_sheds_rivers <- sf::st_zm(reference_hydro_sheds_rivers)
  if (!is.null(Basin)) Basin <- sf::st_zm(Basin)
  if (!is.null(Basin_buff)) Basin_buff <- sf::st_zm(Basin_buff)

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
    # GeoGLOWS data may extend beyond the basin boundary.  Clip first,
    # then simplify in UTM to reduce vertex count.
    message("GeoGLOWS mode: clipping to basin boundary, then simplifying.")

    # Save pre-clip attributes for re-attachment after clipping
    pre_clip <- hydro_sheds_rivers
    hydro_sheds_rivers_basin <- select_basin_rivers(hydro_sheds_rivers, Basin)

    if (nrow(hydro_sheds_rivers_basin) > 0) {
      # st_intersection can split a segment into multiple pieces, dropping
      # non-spatial columns.  Rebuild LINKNO and derived columns by
      # matching clipped geometries back to their nearest pre-clip segment.
      attr_cols <- intersect(c("LINKNO", "DSLINKNO", "USContArea", "UPLAND_SKM", "ARCID"),
                             names(pre_clip))
      missing_cols <- setdiff(attr_cols, names(hydro_sheds_rivers_basin))
      if (length(missing_cols) > 0) {
        nearest <- sf::st_nearest_feature(hydro_sheds_rivers_basin, pre_clip)
        for (col in missing_cols) {
          hydro_sheds_rivers_basin[[col]] <- pre_clip[[col]][nearest]
        }
      }
    }

    utm_crs <- GetUtmCrs(Basin)
    projected <- sf::st_transform(hydro_sheds_rivers_basin, utm_crs)
    simplified <- sf::st_simplify(projected, dTolerance = 100)
    hydro_sheds_rivers_basin <- sf::st_transform(simplified, sf::st_crs(Basin))
    hydro_sheds_rivers_basin <- hydro_sheds_rivers_basin[!sf::st_is_empty(hydro_sheds_rivers_basin), ]
    nv <- sum(sapply(sf::st_geometry(hydro_sheds_rivers_basin), function(g) nrow(sf::st_coordinates(g))))
    message("GeoGLOWS mode: simplified geometries to ", nv, " vertices (from ",
            sum(sapply(sf::st_geometry(hydro_sheds_rivers), function(g) nrow(sf::st_coordinates(g)))),
            "). Features: ", nrow(hydro_sheds_rivers_basin))
  } else {
    hydro_sheds_rivers_basin <- select_basin_rivers(hydro_sheds_rivers, Basin)
  }

  if (nrow(hydro_sheds_rivers_basin) == 0) {
    stop("Critical Error: No river segments remaining inside the strict basin boundary.")
  }
  message("Number of river features in final basin network: ", nrow(hydro_sheds_rivers_basin))

  if (!("UP_CELLS" %in% names(hydro_sheds_rivers_basin)) && "USContArea" %in% names(hydro_sheds_rivers_basin)) {
    hydro_sheds_rivers_basin$UP_CELLS <- hydro_sheds_rivers_basin$USContArea / 1e6
  }

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
