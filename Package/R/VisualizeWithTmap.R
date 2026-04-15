#' Visualize Results with Tmap
#' @param res_pts sf object with concentration data.
#' @param res_hl sf object with lake concentration data.
#' @param filename Character. Output filename (HTML for view mode, PNG for plot mode).
#' @param mode Character. "view" for interactive, "plot" for static.
#' @param title Character. Map title.
#' @export
VisualizeWithTmap <- function(res_pts, res_hl, filename = "map.html", mode = "view", title = "Concentration Map") {
  if (!requireNamespace("tmap", quietly = TRUE)) {
    stop("tmap package is required. Install with: install.packages('tmap')")
  }
  
  tmap::tmap_mode(mode)
  
  col_var <- if ("C_w" %in% names(res_pts)) "C_w" else NULL
  lake_col_var <- if ("C_w" %in% names(res_hl)) "C_w" else NULL
  
  m <- tmap::tm_shape(res_pts) +
       tmap::tm_dots(fill = col_var, palette = "viridis", size = 0.5)
  
  if (!is.null(res_hl) && nrow(res_hl) > 0) {
    m <- m + tmap::tm_shape(res_hl) +
             tmap::tm_polygons(fill = lake_col_var, palette = "Blues", alpha = 0.7)
  }
  
  m <- m + tmap::tm_scalebar() + tmap::tm_compass() +
       tmap::tm_title(title) +
       tmap::tm_layout(bg.color = "white", frame = FALSE,
                       legend.position = c("right", "bottom"),
                       legend.bg.color = "white", legend.bg.alpha = 0.9)
  
  tmap::tmap_save(m, filename)
  
  if (mode == "view") {
    message("Interactive map saved to: ", filename)
    message("Open in RStudio Viewer or browser to view.")
  } else {
    message("Static map saved to: ", filename)
  }
  
  invisible(m)
}
