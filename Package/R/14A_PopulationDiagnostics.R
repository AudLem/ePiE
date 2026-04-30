# Step 5 population/agglomeration diagnostics.
#
# These helpers are intentionally internal. They render the intermediate objects
# already created by ExtractPopulationSources() so reviewers can inspect how
# population raster cells become agglomeration source points.

PopulationAgglomerationDiagnosticsEnabled <- function(diagnostics_level, diagnostics_dir) {
  !is.null(diagnostics_dir) &&
    identical(DiagLevel(diagnostics_level, default = "none"), "full")
}

SaveStep05PopulationDiagnostics <- function(diagnostics_level,
                                            diagnostics_dir,
                                            status = "ok",
                                            status_message = NULL,
                                            Basin_utm = NULL,
                                            rivers_utm = NULL,
                                            lakes_utm = NULL,
                                            ghs_pop_utm = NULL,
                                            final_pop_mask = NULL,
                                            ghs_sf_in_mask = NULL,
                                            populated_pixels = NULL,
                                            river_pixels = NULL,
                                            lake_pixels = NULL,
                                            river_segments_sf = NULL,
                                            agglomeration_trace = NULL) {
  if (!PopulationAgglomerationDiagnosticsEnabled(diagnostics_level, diagnostics_dir)) {
    return(invisible(NULL))
  }

  out_dir <- file.path(diagnostics_dir, "population_agglomerations")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  Step05WriteStatus(out_dir, status, status_message)
  Step05WriteTrace(out_dir, agglomeration_trace)

  if (is.null(Basin_utm) || is.null(ghs_pop_utm)) {
    return(invisible(out_dir))
  }

  pop_raster <- Step05PrepareRaster(ghs_pop_utm)
  all_pixels <- Step05SampleSf(ghs_sf_in_mask)
  selected_pixels <- Step05SampleSf(populated_pixels)
  sampled_river_pixels <- Step05SampleSf(river_pixels)
  sampled_lake_pixels <- Step05SampleSf(lake_pixels)

  Step05SafePlot(file.path(out_dir, "01_population_raster_crop.png"), {
    Step05PlotRaster(pop_raster, "Step 5.1 Population Raster Cropped/Masked To Basin")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
  })

  Step05SafePlot(file.path(out_dir, "02_population_inclusion_mask.png"), {
    Step05PlotFrame(Basin_utm, "Step 5.2 Population Inclusion Mask")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
    Step05PlotSf(final_pop_mask, col = "#c7e9c0", border = "#31a354", lwd = 1.2)
    Step05PlotSf(lakes_utm, col = "#9ecae1", border = "#3182bd", lwd = 1)
    Step05PlotSf(rivers_utm, col = "#2171b5", lwd = 1.4)
  })

  Step05SafePlot(file.path(out_dir, "03_selected_population_pixels.png"), {
    Step05PlotFrame(Basin_utm, "Step 5.3 Selected Population Pixels")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
    Step05PlotSf(lakes_utm, col = "#deebf7", border = "#3182bd", lwd = 1)
    Step05PlotSf(rivers_utm, col = "#2171b5", lwd = 1.2)
    Step05PlotPoints(sampled_river_pixels, col = "#e6550d", pch = 16, cex = 0.45)
    Step05PlotPoints(sampled_lake_pixels, col = "#756bb1", pch = 17, cex = 0.55)
    Step05Legend("topleft", c("River-buffer pixels", "Lake pixels"), c("#e6550d", "#756bb1"), pch = c(16, 17))
  })

  Step05SafePlot(file.path(out_dir, "04_pixel_to_target_groups.png"), {
    Step05PlotFrame(Basin_utm, "Step 5.4 Pixels Grouped By Target Segment/Lake")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
    Step05PlotSf(river_segments_sf, col = "#bdbdbd", lwd = 0.8)
    Step05PlotGroupedPixels(selected_pixels)
  })

  Step05SafePlot(file.path(out_dir, "05_weighted_centroids_before_snap.png"), {
    Step05PlotFrame(Basin_utm, "Step 5.5 Weighted Centroids Before Snap")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
    Step05PlotSf(rivers_utm, col = "#2171b5", lwd = 1.1)
    Step05PlotPoints(all_pixels, col = grDevices::adjustcolor("#969696", alpha.f = 0.35), pch = 16, cex = 0.25)
    Step05PlotTracePoints(agglomeration_trace, x_col = "centroid_x", y_col = "centroid_y", col = "#d7301f", pch = 4, cex = 1.1)
  })

  Step05SafePlot(file.path(out_dir, "06_centroids_snapped_to_network.png"), {
    Step05PlotFrame(Basin_utm, "Step 5.6 Centroids Snapped To Network")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
    Step05PlotSf(lakes_utm, col = "#deebf7", border = "#3182bd", lwd = 1)
    Step05PlotSf(rivers_utm, col = "#2171b5", lwd = 1.2)
    Step05PlotSnapLines(agglomeration_trace)
    Step05PlotTracePoints(agglomeration_trace, x_col = "centroid_x", y_col = "centroid_y", col = "#d7301f", pch = 4, cex = 0.9)
    Step05PlotTracePoints(agglomeration_trace, x_col = "snapped_x", y_col = "snapped_y", col = "#238b45", pch = 16, cex = 0.75)
    Step05Legend("topleft", c("Weighted centroid", "Snapped source"), c("#d7301f", "#238b45"), pch = c(4, 16))
  })

  Step05SafePlot(file.path(out_dir, "07_final_step05_agglomerations.png"), {
    Step05PlotFrame(Basin_utm, "Step 5.7 Final Step 5 Agglomerations")
    Step05PlotSf(Basin_utm, border = "#252525", lwd = 2)
    Step05PlotSf(final_pop_mask, col = grDevices::adjustcolor("#c7e9c0", alpha.f = 0.35), border = NA, lwd = 1)
    Step05PlotSf(lakes_utm, col = "#deebf7", border = "#3182bd", lwd = 1)
    Step05PlotSf(rivers_utm, col = "#2171b5", lwd = 1.2)
    Step05PlotFinalAgglomerations(agglomeration_trace)
  })

  invisible(out_dir)
}

Step05WriteStatus <- function(out_dir, status, status_message) {
  status_df <- data.frame(
    step = "05_extract_population",
    status = status,
    message = ifelse(is.null(status_message), "", status_message),
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  utils::write.csv(status_df, file.path(out_dir, "step_05_agglomeration_status.csv"), row.names = FALSE)
}

Step05WriteTrace <- function(out_dir, agglomeration_trace) {
  fields <- c(
    "node_type", "segment_id", "nearest_segment_id", "Hylak_id",
    "pixel_count", "total_population", "centroid_x", "centroid_y",
    "snapped_x", "snapped_y", "snap_distance_m"
  )

  if (is.null(agglomeration_trace) || nrow(agglomeration_trace) == 0) {
    trace_df <- as.data.frame(stats::setNames(rep(list(logical()), length(fields)), fields))
  } else {
    trace_df <- sf::st_drop_geometry(agglomeration_trace)
    if (!"Hylak_id" %in% names(trace_df)) {
      trace_df$Hylak_id <- if ("HL_ID_new" %in% names(trace_df)) trace_df$HL_ID_new else NA
    }
    if (!"nearest_segment_id" %in% names(trace_df) && "segment_id" %in% names(trace_df)) {
      trace_df$nearest_segment_id <- trace_df$segment_id
    }
    for (field in fields) {
      if (!field %in% names(trace_df)) trace_df[[field]] <- NA
    }
    trace_df <- trace_df[, fields, drop = FALSE]
  }

  utils::write.csv(trace_df, file.path(out_dir, "step_05_agglomeration_trace.csv"), row.names = FALSE)
}

Step05PrepareRaster <- function(r, max_cells = 250000) {
  if (is.null(r) || !inherits(r, "Raster")) return(NULL)
  if (raster::ncell(r) <= max_cells) return(r)
  fact <- ceiling(sqrt(raster::ncell(r) / max_cells))
  raster::aggregate(r, fact = fact, fun = sum, na.rm = TRUE)
}

Step05SafePlot <- function(path, expr) {
  expr <- substitute(expr)
  device_open <- FALSE
  tryCatch(
    {
      grDevices::png(path, width = 1600, height = 1100, res = 150)
      device_open <- TRUE
      on.exit({
        if (device_open && grDevices::dev.cur() > 1) grDevices::dev.off()
      }, add = TRUE)
      old_par <- graphics::par(no.readonly = TRUE)
      on.exit(graphics::par(old_par), add = TRUE)
      graphics::par(mar = c(3.5, 3.5, 3.5, 1))
      eval(expr, parent.frame())
    },
    error = function(e) {
      writeLines(conditionMessage(e), paste0(path, ".error.txt"))
    }
  )
  invisible(path)
}

Step05PlotRaster <- function(r, title) {
  if (is.null(r)) {
    graphics::plot.new()
    graphics::title(title)
    return(invisible(NULL))
  }
  pal <- grDevices::colorRampPalette(c("#f7fbff", "#c6dbef", "#6baed6", "#2171b5"))
  raster::plot(r, main = title, col = pal(40), axes = TRUE)
}

Step05PlotFrame <- function(Basin_utm, title) {
  if (Step05HasSfRows(Basin_utm)) {
    graphics::plot(sf::st_geometry(Basin_utm), col = NA, border = NA, main = title, axes = TRUE)
  } else {
    graphics::plot.new()
    graphics::title(title)
  }
}

Step05PlotSf <- function(x, col = NA, border = "#525252", lwd = 1, add = TRUE) {
  if (!Step05HasSfRows(x)) return(invisible(NULL))
  graphics::plot(sf::st_geometry(x), col = col, border = border, lwd = lwd, add = add)
}

Step05PlotPoints <- function(x, col, pch = 16, cex = 0.5) {
  if (!Step05HasSfRows(x)) return(invisible(NULL))
  xy <- sf::st_coordinates(x)
  graphics::points(xy[, 1], xy[, 2], col = col, pch = pch, cex = cex)
}

Step05PlotTracePoints <- function(trace, x_col, y_col, col, pch, cex) {
  if (is.null(trace) || nrow(trace) == 0 || !all(c(x_col, y_col) %in% names(trace))) {
    return(invisible(NULL))
  }
  trace_df <- Step05DropGeometry(trace)
  ok <- stats::complete.cases(trace_df[, c(x_col, y_col), drop = FALSE])
  if (!any(ok)) return(invisible(NULL))
  graphics::points(trace_df[[x_col]][ok], trace_df[[y_col]][ok], col = col, pch = pch, cex = cex)
}

Step05PlotSnapLines <- function(trace) {
  needed <- c("centroid_x", "centroid_y", "snapped_x", "snapped_y")
  if (is.null(trace) || nrow(trace) == 0 || !all(needed %in% names(trace))) return(invisible(NULL))
  trace_df <- Step05DropGeometry(trace)
  ok <- stats::complete.cases(trace_df[, needed, drop = FALSE])
  if (!any(ok)) return(invisible(NULL))
  graphics::segments(
    trace_df$centroid_x[ok], trace_df$centroid_y[ok],
    trace_df$snapped_x[ok], trace_df$snapped_y[ok],
    col = grDevices::adjustcolor("#636363", alpha.f = 0.55),
    lwd = 0.8
  )
}

Step05PlotGroupedPixels <- function(points) {
  if (!Step05HasSfRows(points)) return(invisible(NULL))
  df <- sf::st_drop_geometry(points)
  target_group <- if ("Hylak_id_pop" %in% names(df)) {
    ifelse(is.na(df$Hylak_id_pop), paste0("segment_", df$nearest_segment_id), paste0("lake_", df$Hylak_id_pop))
  } else {
    paste0("segment_", df$nearest_segment_id)
  }
  groups <- as.integer(factor(target_group))
  pal <- grDevices::rainbow(max(3, min(64, length(unique(groups)))), alpha = 0.75)
  xy <- sf::st_coordinates(points)
  graphics::points(xy[, 1], xy[, 2], col = pal[((groups - 1) %% length(pal)) + 1], pch = 16, cex = 0.45)
}

Step05PlotFinalAgglomerations <- function(trace) {
  if (is.null(trace) || nrow(trace) == 0 || !all(c("snapped_x", "snapped_y") %in% names(trace))) {
    return(invisible(NULL))
  }
  trace_df <- Step05DropGeometry(trace)
  ok <- stats::complete.cases(trace_df[, c("snapped_x", "snapped_y"), drop = FALSE])
  if (!any(ok)) return(invisible(NULL))
  pop <- if ("total_population" %in% names(trace_df)) trace_df$total_population else rep(1, nrow(trace_df))
  size <- ifelse(is.na(pop) | pop <= 0, 0.5, pmin(2.5, 0.5 + log10(pop + 1) / 2))
  node_type <- if ("node_type" %in% names(trace_df)) trace_df$node_type else rep("agglomeration", nrow(trace_df))
  cols <- ifelse(node_type == "agglomeration_lake", "#756bb1", "#e6550d")
  graphics::points(trace_df$snapped_x[ok], trace_df$snapped_y[ok], col = cols[ok], pch = 16, cex = size[ok])
  Step05Legend("topleft", c("Agglomeration", "Lake agglomeration"), c("#e6550d", "#756bb1"), pch = c(16, 16))
}

Step05Legend <- function(position, labels, col, pch) {
  graphics::legend(position, legend = labels, col = col, pch = pch, bty = "n", cex = 0.8)
}

Step05SampleSf <- function(x, max_points = 50000) {
  if (!Step05HasSfRows(x) || nrow(x) <= max_points) return(x)
  x[seq_len(max_points), , drop = FALSE]
}

Step05HasSfRows <- function(x) {
  inherits(x, "sf") && nrow(x) > 0
}

Step05DropGeometry <- function(x) {
  if (inherits(x, "sf")) sf::st_drop_geometry(x) else x
}
