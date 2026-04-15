#' Simplify River Geometry
#' 
#' Helper for ProcessRiverGeometry to handle river simplification safely for both
#' HydroSHEDS and GeoGLOWS network sources.
#'
#' @param rivers sf LINESTRING.
#' @param tolerance numeric. Simplification tolerance in meters.
#' @param canal_simplify logical. Whether to simplify canals.
#' @return Simplified sf LINESTRING.
SimplifyRiverGeometry <- function(rivers, tolerance, canal_simplify = TRUE) {
  if (is.null(tolerance) || tolerance <= 0) {
    message(">>> River simplification skipped (tolerance is NULL or 0)")
    return(rivers)
  }

  has_canals <- "is_canal" %in% names(rivers)
  
  if (has_canals && !canal_simplify) {
    canal_mask <- !is.na(rivers$is_canal) & rivers$is_canal
    canals <- rivers[canal_mask, ]
    rivers_to_simplify <- rivers[!canal_mask, ]
    
    simplified_rivers <- sf::st_simplify(rivers_to_simplify, preserveTopology = TRUE, dTolerance = tolerance)
    return(rbind(simplified_rivers, canals))
  } else {
    return(sf::st_simplify(rivers, preserveTopology = TRUE, dTolerance = tolerance))
  }
}
