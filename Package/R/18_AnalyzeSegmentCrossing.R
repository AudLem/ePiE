#' Analyze Segment Crossing
#'
#' Helper for DetectLakeSegmentCrossings to classify and compute intersection points.
#'
#' @param segment sf LINESTRING.
#' @param lake_polygon sf POLYGON/MULTIPOLYGON.
#' @param points sf object.
#' @param upstream_idx index of upstream node.
#' @param downstream_idx index of downstream node.
#' @return A list with crossing classification, entry point, and exit point.
AnalyzeSegmentCrossing <- function(segment, lake_polygon, points, upstream_idx, downstream_idx) {
  
  upstream_inside <- tryCatch({
    if (!is.na(upstream_idx)) {
      contains <- sf::st_contains(lake_polygon, sf::st_geometry(points[upstream_idx, ]))
      length(contains[[1]]) > 0
    } else {
      FALSE
    }
  }, error = function(e) FALSE)
  
  downstream_inside <- tryCatch({
    if (!is.na(downstream_idx)) {
      contains <- sf::st_contains(lake_polygon, sf::st_geometry(points[downstream_idx, ]))
      length(contains[[1]]) > 0
    } else {
      FALSE
    }
  }, error = function(e) FALSE)
  
  mid_point <- sf::st_sfc(sf::st_point(c((points$x[upstream_idx] + points$x[downstream_idx]) / 2,
                                         (points$y[upstream_idx] + points$y[downstream_idx]) / 2)),
                          crs = sf::st_crs(points))
  segment_passes_through <- tryCatch({
    contains <- sf::st_contains(lake_polygon, mid_point)
    length(contains[[1]]) > 0
  }, error = function(e) FALSE)
  
  crossing_type <- if (!upstream_inside && downstream_inside) {
    "inlet"
  } else if (upstream_inside && !downstream_inside) {
    "outlet"
  } else if (!upstream_inside && !downstream_inside && segment_passes_through) {
    "tangential"
  } else {
    "tangential"
  }
  
  # Compute intersection geometry
  intersection <- tryCatch({
    sf::st_intersection(segment, lake_polygon)
  }, error = function(e) NULL)
  
  if (is.null(intersection) || sf::st_is_empty(intersection[1])) {
    return(NULL)
  }
  
  geom <- sf::st_geometry(intersection)[[1]]
  coords <- sf::st_coordinates(geom)
  
  entry_point <- coords[1, 1:2]
  exit_point <- if (nrow(coords) >= 2) coords[nrow(coords), 1:2] else entry_point
  
  list(
    type = crossing_type,
    entry = entry_point,
    exit = exit_point
  )
}
