getTmapConcentrationPalette <- function(style) {
  style$concentration_palette
}

getTmapContinuousPalette <- function(style, n = 256) {
  grDevices::colorRampPalette(getTmapConcentrationPalette(style))(n)
}

isLinearBinnedTmapSpec <- function(spec) {
  identical(spec$map_variant, "linear_binned")
}

formatTmapConcentrationValue <- function(values, digits = 4) {
  values <- suppressWarnings(as.numeric(values))
  labels <- ifelse(
    is.finite(values) & values != 0 & (abs(values) < 0.001 | abs(values) >= 10000),
    formatC(values, format = "e", digits = max(1, digits - 1)),
    formatC(values, format = "fg", digits = digits)
  )
  labels[is.finite(values) & values == 0] <- "0"
  labels[!is.finite(values)] <- NA_character_
  trimws(labels)
}

formatTmapBinnedIntervalLabels <- function(breaks, max_value = NULL) {
  if (length(breaks) < 3) {
    return("0")
  }

  upper <- breaks[-c(1, 2)]
  lower <- c(0, upper[-length(upper)])
  if (!is.null(max_value) && length(max_value) > 0 && is.finite(max_value[[1]]) && length(upper) > 0) {
    upper[length(upper)] <- max_value[[1]]
  }

  c(
    "0",
    paste(formatTmapConcentrationValue(lower), formatTmapConcentrationValue(upper), sep = " - ")
  )
}

BuildConcentrationBinnedScale <- function(values,
                                          breaks = NULL,
                                          labels = NULL,
                                          n_positive_classes = 8) {
  if (!is.null(breaks)) {
    breaks <- sort(unique(suppressWarnings(as.numeric(breaks))))
    breaks <- breaks[is.finite(breaks)]
    if (length(breaks) < 3) {
      stop("Binned concentration scale needs at least three finite breaks.", call. = FALSE)
    }
    if (is.null(labels)) {
      labels <- formatTmapBinnedIntervalLabels(breaks)
    }
    return(list(breaks = breaks, labels = as.character(labels)))
  }

  values <- suppressWarnings(as.numeric(values))
  values <- values[is.finite(values) & values >= 0]
  positive_values <- values[values > 0]
  if (length(positive_values) == 0) {
    return(list(
      breaks = c(-1e-12, 0, 1),
      labels = c("0", "no positive values")
    ))
  }

  min_positive <- min(positive_values, na.rm = TRUE)
  max_positive <- max(positive_values, na.rm = TRUE)
  n_positive_classes <- max(1L, as.integer(n_positive_classes[[1]]))

  if (isTRUE(all.equal(min_positive, max_positive))) {
    upper_breaks <- max_positive * (1 + 1e-9)
  } else {
    upper_breaks <- 10^seq(
      log10(min_positive),
      log10(max_positive),
      length.out = n_positive_classes + 1L
    )[-1]
    upper_breaks[length(upper_breaks)] <- max_positive * (1 + 1e-9)
  }

  breaks <- c(-1e-12, 0, upper_breaks)
  list(
    breaks = breaks,
    labels = formatTmapBinnedIntervalLabels(breaks, max_value = max_positive)
  )
}

getTmapBinnedScaleSpec <- function(spec = NULL, values = NULL) {
  if (!is.null(spec) && !is.null(spec$binned_scale)) {
    return(spec$binned_scale)
  }

  if (is.null(values) && !is.null(spec)) {
    values <- getTmapOriginalConcentrationValues(spec)
  }

  BuildConcentrationBinnedScale(values)
}

getTmapBinnedBreaks <- function(spec = NULL, values = NULL) {
  getTmapBinnedScaleSpec(spec = spec, values = values)$breaks
}

getTmapBinnedLabels <- function(spec = NULL, values = NULL) {
  getTmapBinnedScaleSpec(spec = spec, values = values)$labels
}

getTmapBinnedPalette <- function(style = ePieVisualizationStyle(), labels = NULL) {
  if (is.null(labels)) {
    labels <- getTmapBinnedLabels()
  }
  grDevices::colorRampPalette(getTmapConcentrationPalette(style))(length(labels))
}

getTmapBinnedClassLabels <- function(values, breaks = NULL, labels = NULL) {
  values <- suppressWarnings(as.numeric(values))
  if (is.null(breaks) || is.null(labels)) {
    scale <- BuildConcentrationBinnedScale(values)
    breaks <- scale$breaks
    labels <- scale$labels
  }

  adjusted_values <- values
  adjusted_values[is.finite(adjusted_values) & adjusted_values == 0] <- -1e-12
  as.character(cut(
    adjusted_values,
    breaks = breaks,
    labels = labels,
    include.lowest = TRUE,
    right = FALSE
  ))
}

getTmapConcentrationPlotValues <- function(spec) {
  if (!is.null(spec$concentration_segments_plot) && nrow(spec$concentration_segments_plot) > 0) {
    return(spec$concentration_segments_plot$C_w_map)
  }

  if (!is.null(spec$concentration_nodes_plot) && nrow(spec$concentration_nodes_plot) > 0) {
    return(spec$concentration_nodes_plot$C_w_map)
  }

  numeric(0)
}

getTmapOriginalConcentrationValues <- function(spec) {
  if (!is.null(spec$concentration_segments_plot) && nrow(spec$concentration_segments_plot) > 0 &&
      "C_w" %in% names(spec$concentration_segments_plot)) {
    return(spec$concentration_segments_plot$C_w)
  }

  if (!is.null(spec$concentration_nodes_plot) && nrow(spec$concentration_nodes_plot) > 0 &&
      "C_w" %in% names(spec$concentration_nodes_plot)) {
    return(spec$concentration_nodes_plot$C_w)
  }

  numeric(0)
}

formatTmapConcentrationLabels <- function(values) {
  formatTmapConcentrationValue(10^values)
}

formatTmapLinearConcentrationLabels <- function(values) {
  formatTmapConcentrationValue(values)
}

getTmapConcentrationScale <- function(spec, style) {
  if (isLinearBinnedTmapSpec(spec)) {
    scale_spec <- getTmapBinnedScaleSpec(spec)
    return(tmap::tm_scale_intervals(
      style = "fixed",
      breaks = scale_spec$breaks,
      interval.closure = "left",
      midpoint = NA,
      values = getTmapBinnedPalette(style, scale_spec$labels),
      labels = scale_spec$labels
    ))
  }

  plot_values <- getTmapConcentrationPlotValues(spec)
  value_range <- range(plot_values, na.rm = TRUE)
  scale_args <- list(
    n = 256,
    values = getTmapContinuousPalette(style),
    midpoint = NA
  )

  if (all(is.finite(value_range))) {
    scale_args$limits <- value_range
    ticks <- pretty(value_range, n = 5)
    ticks <- ticks[ticks >= value_range[1] & ticks <= value_range[2]]
    if (length(ticks) > 0) {
      scale_args$ticks <- ticks
      if (identical(spec$map_scale, "log10")) {
        scale_args$labels <- formatTmapConcentrationLabels(ticks)
      } else {
        scale_args$labels <- formatTmapLinearConcentrationLabels(ticks)
      }
    }
  }

  do.call(tmap::tm_scale_continuous, scale_args)
}

getTmapLegendTitle <- function(spec) {
  legend_units <- if (isLinearBinnedTmapSpec(spec)) {
    paste(spec$units, "uneven concentration classes", sep = "\n")
  } else if (identical(spec$map_scale, "log10")) {
    paste0(spec$units, ", log scale")
  } else {
    spec$units
  }

  paste(spec$display_substance, legend_units, sep = "\n")
}

formatTmapMaxValue <- function(value) {
  value <- suppressWarnings(as.numeric(value))
  if (!is.finite(value)) {
    return("not available")
  }
  trimws(formatC(value, format = "fg", digits = 4))
}

getTmapBinnedMaxValue <- function(spec) {
  segments <- spec$concentration_segments_plot
  if (is.null(segments) || nrow(segments) == 0 || !("C_w" %in% names(segments))) {
    return(NA_real_)
  }

  values <- suppressWarnings(as.numeric(segments$C_w))
  if (!any(is.finite(values))) {
    return(NA_real_)
  }
  max(values, na.rm = TRUE)
}

getTmapBinnedLegendTitle <- function(spec) {
  paste(
    spec$display_substance,
    spec$units,
    "uneven concentration classes",
    "Colors are classes, not equal intervals.",
    paste0("Max calculated: ", formatTmapMaxValue(getTmapBinnedMaxValue(spec)), " ", spec$units),
    sep = "\n"
  )
}

getTmapConcentrationLegend <- function(spec, legend_title) {
  if (isLinearBinnedTmapSpec(spec)) {
    return(tmap::tm_legend_hide())
  }

  tmap::tm_legend(
    title = legend_title,
    orientation = "portrait",
    text.size = 1.6,
    title.size = 2.0,
    item.width = 3.2,
    item.height = 1.0,
    item.space = 0,
    ticks.lwd = 2
  )
}

getTmapBinnedManualLegend <- function(spec, legend_title) {
  if (!isLinearBinnedTmapSpec(spec)) {
    return(NULL)
  }
  scale_spec <- getTmapBinnedScaleSpec(spec)

  tmap::tm_add_legend(
    type = "polygons",
    labels = scale_spec$labels,
    fill = getTmapBinnedPalette(spec$style, scale_spec$labels),
    col = rep("#2b2b2b", length(scale_spec$labels)),
    title = getTmapBinnedLegendTitle(spec),
    text.size = 1.35,
    title.size = 1.45,
    item.width = 1.4,
    item.height = 0.85,
    item.space = 0.25
  )
}

prepareTmapConcentrationSegments <- function(spec) {
  segments <- spec$concentration_segments_plot
  if (is.null(segments) || nrow(segments) == 0) {
    return(NULL)
  }

  segment_weight <- suppressWarnings(as.numeric(segments$segment_weight))
  segment_weight[!is.finite(segment_weight)] <- 4
  segments$tmap_segment_weight <- segment_weight * 1.6
  segments$tmap_C_w_map <- segments$C_w_map
  if (isLinearBinnedTmapSpec(spec)) {
    zero_values <- is.finite(segments$tmap_C_w_map) & segments$tmap_C_w_map == 0
    segments$tmap_C_w_map[zero_values] <- -1e-12
  }
  segments
}

addTmapLightBasemap <- function(map_plot) {
  if (!requireNamespace("maptiles", quietly = TRUE)) {
    return(map_plot)
  }

  tmap::tm_basemap("CartoDB.Positron") + map_plot
}

getTmapScaleBarLayer <- function(spec) {
  layers <- list(
    spec$basin,
    spec$rivers,
    spec$canals,
    spec$lakes,
    spec$concentration_segments_plot
  )
  layers <- layers[vapply(layers, function(layer) !is.null(layer) && nrow(layer) > 0, logical(1))]
  if (length(layers) == 0) {
    return(NULL)
  }
  layers[[1]]
}

getTmapScaleBarBreaks <- function(spec) {
  layer <- getTmapScaleBarLayer(spec)
  if (is.null(layer) || !requireNamespace("sf", quietly = TRUE)) {
    return(c(0, 10))
  }

  bbox <- sf::st_bbox(sf::st_transform(layer, 4326))
  mid_y <- mean(c(bbox[["ymin"]], bbox[["ymax"]]), na.rm = TRUE)
  width_m <- suppressWarnings(as.numeric(sf::st_distance(
    sf::st_sfc(sf::st_point(c(bbox[["xmin"]], mid_y)), crs = 4326),
    sf::st_sfc(sf::st_point(c(bbox[["xmax"]], mid_y)), crs = 4326),
    by_element = TRUE
  )))

  if (!is.finite(width_m) || width_m <= 0) {
    return(c(0, 10))
  }

  target_km <- (width_m / 1000) / 5
  nice_steps <- c(1, 2, 5) * 10^floor(log10(target_km))
  max_break <- nice_steps[which.min(abs(nice_steps - target_km))]
  max_break <- max(1, max_break)
  c(0, max_break)
}

RenderTmapConcentrationMap <- function(spec, plots_dir) {
  if (is.null(spec) || !requireNamespace("tmap", quietly = TRUE)) {
    return(invisible(NULL))
  }

  style <- spec$style
  tmap_concentration_scale <- getTmapConcentrationScale(spec, style)
  tmap_legend_title <- getTmapLegendTitle(spec)
  tmap_concentration_legend <- getTmapConcentrationLegend(spec, tmap_legend_title)
  tmap_binned_manual_legend <- getTmapBinnedManualLegend(spec, tmap_legend_title)
  tmap_concentration_segments <- prepareTmapConcentrationSegments(spec)
  static_filename <- if (!is.null(spec$static_map_filename) && nzchar(spec$static_map_filename)) {
    spec$static_map_filename
  } else {
    "static_concentration_map.png"
  }
  static_map_png <- file.path(plots_dir, static_filename)

  tryCatch(
    {
      tmap::tmap_mode("plot")

      map_plot <- tmap::tm_layout(
        bg.color = "#f7f7f7",
        frame = FALSE,
        legend.outside = TRUE,
        legend.outside.position = "right",
        legend.position = c("right", "top"),
        legend.bg.color = "white",
        legend.bg.alpha = 0.9,
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

      if (!is.null(tmap_concentration_segments) && nrow(tmap_concentration_segments) > 0) {
        concentration_color_column <- if (isLinearBinnedTmapSpec(spec)) "tmap_C_w_map" else "C_w_map"
        map_plot <- map_plot + tmap::tm_shape(tmap_concentration_segments) +
          tmap::tm_lines(
            col = concentration_color_column,
            col.scale = tmap_concentration_scale,
            col.legend = tmap_concentration_legend,
            lwd = "tmap_segment_weight",
            lwd.scale = tmap::tm_scale_asis(),
            lwd.legend = tmap::tm_legend_hide()
        )
      }

      if (!is.null(tmap_binned_manual_legend)) {
        map_plot <- map_plot + tmap_binned_manual_legend
      }

      map_plot <- addTmapLightBasemap(map_plot)

      map_plot <- map_plot +
        tmap::tm_scalebar(
          breaks = getTmapScaleBarBreaks(spec),
          text.size = 2.2,
          lwd = 2.5,
          position = c("left", "bottom")
        ) +
        tmap::tm_compass(
          type = "arrow",
          size = 3.5,
          text.size = 1.6,
          lwd = 2,
          position = c("right", "bottom")
        ) +
        tmap::tm_title(spec$map_title_text, size = 1.6)

      tmap::tmap_save(map_plot, static_map_png, width = 6000, height = 4000, dpi = 300)
      if (isTRUE(spec$write_legacy_map)) {
        legacy_png <- file.path(plots_dir, "static_concentration_map.png")
        if (!identical(normalizePath(static_map_png, mustWork = FALSE), normalizePath(legacy_png, mustWork = FALSE))) {
          file.copy(static_map_png, legacy_png, overwrite = TRUE)
        }
      }
      message("Static concentration map (PNG) saved to: ", static_map_png)
    },
    error = function(e) {
      message("Note: tmap static map skipped: ", e$message)
    }
  )

  invisible(static_map_png)
}
