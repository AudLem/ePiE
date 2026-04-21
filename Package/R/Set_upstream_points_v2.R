Set_upstream_points_v2 <- function(pts){
  # --- Geometry Guard ---------------------------------------------------------
  # merge() behaves unpredictably on sf objects in tight loops. Strip
  # geometry to ensure a stable data.frame merge.
  # ----------------------------------------------------------------------------
  if (inherits(pts, "sf")) pts <- sf::st_drop_geometry(pts)

  pts2 = split(pts,f=pts$basin_id)
  pts = c()
  for (i in 1:length(pts2)) {
    upst = table(ID=c(pts2[[i]]$ID_nxt))
    upst = data.frame(upst)
    pts2[[i]]$Freq = NULL
    pts2[[i]] = merge(pts2[[i]],upst,by="ID",all.x=TRUE,all.y=FALSE)
    pts2[[i]]$Freq[is.na(pts2[[i]]$Freq)] = 0
    pts = rbind(pts,pts2[[i]])
  }
  return(pts)
}
