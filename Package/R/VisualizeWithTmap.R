#' Visualize Results with Tmap
#' @param res_pts sf object.
#' @param res_hl sf object.
#' @param filename Character.
#' @export
VisualizeWithTmap <- function(res_pts, res_hl, filename = "map.html") {
  library(tmap)
  tmap_mode("view")
  
  m <- tm_shape(res_pts) + 
         tm_dots(col = "C_w", palette = "viridis", title = "Conc (ug/L)") +
         tm_shape(res_hl) + 
         tm_polygons(col = "C_w", palette = "Blues", title = "Lake Conc (ug/L)") +
         tm_scale_bar()
  
  tmap_save(m, filename)
}
