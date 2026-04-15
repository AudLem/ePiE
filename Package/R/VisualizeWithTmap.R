#' Visualize Results with Tmap
#' @param res_pts sf object with concentration data.
#' @param res_hl sf object with lake concentration data.
#' @param basin sf object with basin boundary (optional).
#' @param rivers sf object with river lines (optional).
#' @param canals sf object with canal lines (optional).
#' @param network_pts sf object with network nodes (optional).
#' @param filename Character. Output filename (HTML for view mode, PNG for plot mode).
#' @param mode Character. "view" for interactive, "plot" for static.
#' @param title Character. Map title.
#' @export
VisualizeWithTmap <- function(res_pts,
                                res_hl = NULL,
                                basin = NULL,
                                rivers = NULL,
                                canals = NULL,
                                network_pts = NULL,
                                filename = "map.html",
                                mode = "view",
                                title = "Concentration Map") {
  if (!requireNamespace("tmap", quietly = TRUE)) {
    stop("tmap package is required. Install with: install.packages('tmap')")
  }
  
  tmap::tmap_mode(mode)
  
  m <- tmap::tm_layout(bg.color = "white", frame = FALSE,
                       legend.position = c("right", "bottom"),
                       legend.bg.color = "white", legend.bg.alpha = 0.9)
  
  if (!is.null(basin) && nrow(basin) > 0) {
    m <- m + tmap::tm_shape(basin) + tmap::tm_polygons(fill = "lightgrey", border = "darkgrey", lwd = 1.5)
  }
  
  if (!is.null(rivers) && nrow(rivers) > 0) {
    m <- m + tmap::tm_shape(rivers) + tmap::tm_lines(col = "#2171b5", lwd = 1.5)
  }
  
  if (!is.null(canals) && nrow(canals) > 0) {
    m <- m + tmap::tm_shape(canals) + tmap::tm_lines(col = "#00bcd4", lwd = 2.5)
  }
  
  if (!is.null(res_hl) && nrow(res_hl) > 0) {
    m <- m + tmap::tm_shape(res_hl) + tmap::tm_polygons(fill = "lightblue", col = "#2171b5", alpha = 0.7)
  }
  
  if (!is.null(network_pts) && nrow(network_pts) > 0) {
    pt_type_col <- if ("pt_type" %in% names(network_pts)) "pt_type" else NULL
    m <- m + tmap::tm_shape(network_pts) + tmap::tm_dots(col = pt_type_col, palette = "viridis", size = 0.5)
  }
  
  col_var <- if ("C_w" %in% names(res_pts)) "C_w" else NULL
  m <- m + tmap::tm_shape(res_pts) + tmap::tm_dots(fill = col_var, palette = "viridis", size = 0.5)
  
  m <- m + tmap::tm_scalebar() + tmap::tm_compass() + tmap::tm_title(title)
  
  tmap::tmap_save(m, filename)
  
  if (mode == "view") {
    message("Interactive map saved to: ", filename)
    message("Open in RStudio Viewer or browser to view.")
  } else {
    message("Static map saved to: ", filename)
  }
  
  invisible(m)
}
