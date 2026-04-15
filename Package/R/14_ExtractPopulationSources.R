#' Extract Population and Agglomeration Sources
#'
#' Rasterises population data over the basin, identifies agglomeration points
#' above a threshold, and attaches population counts to network source nodes.
#'
#' @param Basin sf object. Basin boundary polygon.
#' @param hydro_sheds_rivers_basin sf object. Clipped river network.
#' @param HL_basin sf object or \code{NULL}. In-basin lake polygons.
#' @param pop_raster_path Character or \code{NULL}. Path to a population raster (e.g. GHS-POP).
#' @return A named list with \code{agglomeration_points} (sf points with population).
#' @export
ExtractPopulationSources <- function(Basin,
                                       hydro_sheds_rivers_basin,
                                       HL_basin = NULL,
                                       pop_raster_path = NULL) {
  message("--- Step 5: Processing Population and Agglomerations ---")
  if (!is.null(Basin)) Basin <- sf::st_zm(Basin)
  if (!is.null(hydro_sheds_rivers_basin)) hydro_sheds_rivers_basin <- sf::st_zm(hydro_sheds_rivers_basin)
  if (!is.null(HL_basin)) HL_basin <- sf::st_zm(HL_basin)

  river_segments_sf <- NULL
  if (!is.null(pop_raster_path) && file.exists(pop_raster_path)) {
    message("Processing population and agglomerations...")
    ghs_pop_global <- raster::raster(pop_raster_path)

    # GHS-POP is too large to reproject directly (memory issues). Crop in Mollweide first, then reproject to UTM
    # Basin_moll_buff with 1km buffer avoids losing data near the boundary
    Basin_moll <- sf::st_transform(Basin, raster::crs(ghs_pop_global))
    Basin_moll <- sf::st_make_valid(Basin_moll)
    Basin_moll_buff <- sf::st_buffer(Basin_moll, dist = 1000)
    Basin_moll_buff <- sf::st_make_valid(Basin_moll_buff)

    if (!ExtentOverlap(raster::extent(ghs_pop_global), raster::extent(Basin_moll_buff))) {
      message("Warning: Population raster does not overlap with basin. Skipping agglomerations.")
      agglomeration_points <- NULL
    } else {
      ghs_pop_cropped_moll <- raster::crop(ghs_pop_global, Basin_moll_buff)
      current_utm_crs <- GetUtmCrs(Basin)

      Basin_utm <- sf::st_transform(Basin, current_utm_crs)
      rivers_utm <- sf::st_zm(sf::st_transform(hydro_sheds_rivers_basin, current_utm_crs))
      lakes_utm <- if (!is.null(HL_basin)) sf::st_zm(sf::st_transform(HL_basin, current_utm_crs)) else NULL

      dir.create(raster::rasterOptions()$tmpdir, recursive = TRUE, showWarnings = FALSE)
      ghs_pop_utm <- raster::projectRaster(
        ghs_pop_cropped_moll,
        crs = current_utm_crs,
        filename = raster::rasterTmpFile(),
        overwrite = TRUE
      )
      ghs_pop_utm <- raster::mask(
        ghs_pop_utm,
        Basin_utm,
        filename = raster::raster::tmpdir, filename = raster::rasterTmpFile(),
        overwrite = TRUE
      )

      rm(ghs_pop_global, ghs_pop_cropped_moll)
      gc()

      # Create 500m buffer around rivers and lakes - assumes population discharges into surface water within this distance
      # Buffer is unioned and clipped to basin to keep only relevant areas
      river_buffers <- dplyr::select(sf::st_buffer(rivers_utm, dist = 500), geometry)
      river_buffers <- sf::st_union(river_buffers)
      river_buffers <- EnsureSameCrs(Basin_utm, river_buffers, "Basin_utm", "river_buffers")

      combined_mask <- if (!is.null(lakes_utm) && nrow(lakes_utm) > 0) {
        lake_buffers <- dplyr::select(sf::st_buffer(lakes_utm, dist = 500), geometry)
        lake_buffers <- sf::st_union(lake_buffers)
        sf::st_union(river_buffers, lake_buffers)
      } else {
        river_buffers
      }

      final_pop_mask <- sf::st_intersection(combined_mask, Basin_utm)

      # Break rivers into 2-point segments for pixel-to-segment assignment
      river_segments_list <- lapply(seq_len(nrow(rivers_utm)), function(i) {
        BreakLinestringIntoSegments(rivers_utm[i, ]$geometry, rivers_utm[i, ]$ARCID, current_utm_crs)
      })
      river_segments_sf <- do.call(rbind, river_segments_list)
      river_segments_sf <- sf::st_zm(river_segments_sf)

      ghs_pop_in_mask <- raster::mask(ghs_pop_utm, methods::as(final_pop_mask, "Spatial"))
      ghs_points_in_mask <- raster::rasterToPoints(ghs_pop_in_mask, spatial = TRUE, na.rm = TRUE)
      names(ghs_points_in_mask@data) <- "population"
      ghs_sf_in_mask <- sf::st_as_sf(ghs_points_in_mask, coords = c("x", "y"), crs = current_utm_crs)
      ghs_sf_in_mask <- sf::st_zm(ghs_sf_in_mask)

      # Mark pixels that fall inside lakes with the lake's Hylak_id for separate handling
      if (!is.null(lakes_utm) && nrow(lakes_utm) > 0) {
        lake_indices <- sf::st_within(ghs_sf_in_mask, lakes_utm)
        ghs_sf_in_mask$Hylak_id_pop <- sapply(lake_indices, function(x) if (length(x) > 0) lakes_utm$Hylak_id[x[1]] else NA)
        message(">>> Map population to lakes: ", sum(!is.na(ghs_sf_in_mask$Hylak_id_pop)), " pixels found inside lakes.")
      } else {
        ghs_sf_in_mask$Hylak_id_pop <- NA
      }

      # Assign each population pixel to the nearest river segment via st_nearest_feature (returns index)
      ghs_sf_in_mask <- EnsureSameCrs(river_segments_sf, ghs_sf_in_mask, "river_segments", "pop_points")
      ghs_sf_in_mask$nearest_segment_index <- sf::st_nearest_feature(ghs_sf_in_mask, river_segments_sf)
      ghs_sf_in_mask$nearest_segment_id <- river_segments_sf$segment_id[ghs_sf_in_mask$nearest_segment_index]

      populated_pixels <- ghs_sf_in_mask[ghs_sf_in_mask$population > 0, ]
      message(">>> Populated pixels total: ", nrow(populated_pixels))

      if (nrow(populated_pixels) > 0) {
        river_pixels <- populated_pixels[is.na(populated_pixels$Hylak_id_pop), ]
        message(">>> River pixels (non-lake): ", nrow(river_pixels))
        # For each river segment's group of populated pixels, compute a weighted centroid
        # Weighted centroid = where people actually live within that segment (not just geometric center)
        # Then snap to the nearest point on the segment (ensures it's on the river network)
        agglomeration_points_river <- if (nrow(river_pixels) > 0) {
          pixel_groups <- dplyr::group_split(dplyr::group_by(river_pixels, nearest_segment_id))
          do.call(dplyr::bind_rows, lapply(pixel_groups, function(group) {
            coords <- sf::st_coordinates(group)
            population <- group$population
            x_weighted <- stats::weighted.mean(coords[, 1], w = population)
            y_weighted <- stats::weighted.mean(coords[, 2], w = population)
            centroid <- sf::st_sfc(sf::st_point(c(x_weighted, y_weighted)), crs = st_crs(group))
            seg_id <- unique(group$nearest_segment_id)
            target_seg <- river_segments_sf[river_segments_sf$segment_id == seg_id, ]
            snapped_points <- sf::st_cast(sf::st_nearest_points(centroid, target_seg), "POINT")
            snapped_centroid <- snapped_points[2]
            sf::st_sf(
              geometry = snapped_centroid,
              segment_id = seg_id,
              total_population = sum(population, na.rm = TRUE),
              HL_ID_new = NA,
              node_type = "agglomeration"
            )
          }))
        } else { NULL }

        lake_pixels <- populated_pixels[!is.na(populated_pixels$Hylak_id_pop), ]
        agglomeration_points_lake <- if (nrow(lake_pixels) > 0) {
          pixel_groups <- dplyr::group_split(dplyr::group_by(lake_pixels, Hylak_id_pop))
          do.call(dplyr::bind_rows, lapply(pixel_groups, function(group) {
            coords <- sf::st_coordinates(group)
            population <- group$population
            hid <- unique(group$Hylak_id_pop)
            x_weighted <- stats::weighted.mean(coords[, 1], w = population)
            y_weighted <- stats::weighted.mean(coords[, 2], w = population)
            centroid <- sf::st_sfc(sf::st_point(c(x_weighted, y_weighted)), crs = sf::st_crs(group))
            target_lake <- lakes_utm[lakes_utm$Hylak_id == hid, ]
            segments_in_lake <- river_segments_sf[sf::st_intersects(river_segments_sf, target_lake, sparse = FALSE)[, 1], ]
            target_seg <- if (nrow(segments_in_lake) == 0) {
              nearest_seg_idx <- sf::st_nearest_feature(centroid, river_segments_sf)
              river_segments_sf[nearest_seg_idx, ]
            } else {
              nearest_seg_idx <- sf::st_nearest_feature(centroid, segments_in_lake)
              segments_in_lake[nearest_seg_idx, ]
            }
            snapped_points <- sf::st_cast(sf::st_nearest_points(centroid, target_seg), "POINT")
            snapped_centroid <- snapped_points[2]
            sf::st_sf(
              geometry = snapped_centroid,
              segment_id = target_seg$segment_id,
              total_population = sum(population, na.rm = TRUE),
              HL_ID_new = hid,
              node_type = "agglomeration_lake"
            )
          }))
        } else { NULL }

        agglomeration_points <- if (!is.null(agglomeration_points_river) && !is.null(agglomeration_points_lake)) {
          rbind(agglomeration_points_river, agglomeration_points_lake)
        } else if (!is.null(agglomeration_points_river)) {
          agglomeration_points_river
        } else {
          agglomeration_points_lake
        }

        if (is.null(agglomeration_points) || nrow(agglomeration_points) == 0) {
          message("No agglomerations generated after filtering.")
          return(list(agglomeration_points = NULL, river_segments_sf = river_segments_sf))
        }

        nearest_idx <- sf::st_nearest_feature(agglomeration_points, river_segments_sf)
        agglomeration_points$nearest_segment_id <- river_segments_sf$segment_id[nearest_idx]
        agglomeration_points$ARCID_val <- river_segments_sf$original_id[nearest_idx]
        basin_arcids <- hydro_sheds_rivers_basin$ARCID
        agglomeration_points$original_id <- match(agglomeration_points$ARCID_val, basin_arcids)

        if (any(sf::st_is_empty(agglomeration_points))) {
          message("Warning: Some agglomeration points have empty geometries. Removing them.")
          agglomeration_points <- agglomeration_points[!sf::st_is_empty(agglomeration_points), ]
        }

        message("Generated ", nrow(agglomeration_points), " agglomeration centroids (",
                sum(agglomeration_points$node_type == "agglomeration_lake"), " from lakes).")
      } else {
        message("No populated pixels found in buffers. Skipping agglomerations.")
        agglomeration_points <- NULL
      }
    }
  } else {
    message("No population raster provided. Skipping agglomerations.")
    agglomeration_points <- NULL
  }

  list(
    agglomeration_points = agglomeration_points,
    river_segments_sf = river_segments_sf
  )
}
