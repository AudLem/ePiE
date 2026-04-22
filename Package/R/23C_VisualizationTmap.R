RenderTmapConcentrationMap <- function(spec, plots_dir) {
  if (is.null(spec) || !requireNamespace("tmap", quietly = TRUE)) {
    return(invisible(NULL))
  }

  style <- spec$style
  static_map_png <- file.path(plots_dir, "static_concentration_map.png")

  tryCatch(
    {
      tmap::tmap_mode("plot")

      map_plot <- tmap::tm_layout(
        bg.color = "white",
        frame = FALSE,
        legend.outside = TRUE,
        legend.outside.position = "right",
        legend.position = c("right", "top"),
        legend.bg.color = "white",
        legend.bg.alpha = 0.9
      )

      if (!is.null(spec$basin) && nrow(spec$basin) > 0) {
        map_plot <- map_plot + tmap::tm_shape(spec$basin) +
          tmap::tm_polygons(
            fill = style$colors$basin_fill,
            col = style$colors$basin_border,
            lwd = style$line_widths$basin,
            fill_alpha = style$fill_opacity$basin
          )
      }

      if (!is.null(spec$rivers) && nrow(spec$rivers) > 0) {
        river_width <- if (identical(spec$layer_source, "topology")) style$line_widths$river else style$line_widths$fallback_river
        map_plot <- map_plot + tmap::tm_shape(spec$rivers) +
          tmap::tm_lines(col = style$colors$river, lwd = river_width)
      }

      if (!is.null(spec$canals) && nrow(spec$canals) > 0) {
        canal_width <- if (identical(spec$layer_source, "topology")) style$line_widths$canal else style$line_widths$fallback_canal
        map_plot <- map_plot + tmap::tm_shape(spec$canals) +
          tmap::tm_lines(col = style$colors$canal, lwd = canal_width)
      }

      if (!is.null(spec$lakes) && nrow(spec$lakes) > 0) {
        map_plot <- map_plot + tmap::tm_shape(spec$lakes) +
          tmap::tm_polygons(
            fill = style$colors$lake_fill,
            col = style$colors$lake_border,
            lwd = style$line_widths$lake,
            fill_alpha = style$fill_opacity$lake
          )
      }

      if (!is.null(spec$concentration_nodes_plot) && nrow(spec$concentration_nodes_plot) > 0) {
        map_plot <- map_plot + tmap::tm_shape(spec$concentration_nodes_plot) +
          tmap::tm_dots(
            fill = "C_w",
            size = style$point_sizes$concentration_tmap,
            fill.scale = tmap::tm_scale_continuous(values = style$concentration_palette),
            fill.legend = tmap::tm_legend(title = spec$legend_title, text.size = 0.9, title.size = 0.7)
          )
      }

      if (!is.null(spec$source_nodes) && nrow(spec$source_nodes) > 0) {
        map_plot <- map_plot + tmap::tm_shape(spec$source_nodes) +
          tmap::tm_symbols(
            fill = style$colors$source_fill,
            col = style$colors$source_outline,
            shape = 21,
            size = style$point_sizes$source_tmap,
            fill.legend = tmap::tm_legend_hide()
          )
      }

      map_plot <- map_plot +
        tmap::tm_scalebar() +
        tmap::tm_compass() +
        tmap::tm_title(spec$map_title_text)

      tmap::tmap_save(map_plot, static_map_png, width = 6000, height = 4000, dpi = 300)
      message("Static concentration map (PNG) saved to: ", static_map_png)
    },
    error = function(e) {
      message("Note: tmap static map skipped: ", e$message)
    }
  )

  invisible(static_map_png)
}
