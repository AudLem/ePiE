RenderLeafletConcentrationMap <- function(spec, plots_dir) {
  if (is.null(spec)) {
    return(invisible(NULL))
  }

  style <- spec$style
  color_palette <- leaflet::colorNumeric(
    palette = style$concentration_palette,
    domain = spec$concentration_nodes$C_w_map,
    na.color = "transparent"
  )
  legend_format <- if (identical(spec$map_scale, "log10")) {
    leaflet::labelFormat(transform = function(x) 10^x, digits = 3)
  } else {
    leaflet::labelFormat(digits = 3)
  }

  map_widget <- leaflet::leaflet(
    options = leaflet::leafletOptions(preferCanvas = TRUE, attributionControl = FALSE)
  ) |>
    leaflet::addProviderTiles(
      leaflet::providers$CartoDB.Positron,
      group = "Light",
      options = leaflet::tileOptions(attribution = "&copy; CARTO &copy; OpenStreetMap contributors")
    ) |>
    leaflet::addProviderTiles(
      leaflet::providers$Esri.WorldStreetMap,
      group = "Streets & Buildings",
      options = leaflet::tileOptions(attribution = "&copy; Esri, HERE, Garmin, OpenStreetMap")
    ) |>
    leaflet::addProviderTiles(
      leaflet::providers$Esri.WorldImagery,
      group = "Satellite",
      options = leaflet::tileOptions(attribution = "&copy; Esri, Maxar, Earthstar Geographics")
    ) |>
    leaflet::addProviderTiles(
      leaflet::providers$OpenTopoMap,
      group = "Topographic",
      options = leaflet::tileOptions(attribution = "&copy; OpenTopoMap (CC-BY-SA)")
    ) |>
    leaflet::addControl(
      html = htmltools::tags$div(
        htmltools::HTML("<small>&copy; Esri (WorldImagery/WorldStreetMap) | CARTO | OpenStreetMap | OpenTopoMap</small>"),
        style = "background: rgba(255,255,255,0.7); padding: 2px 6px; font-size: 10px;"
      ),
      position = "bottomright"
    )

  if (!is.null(spec$basin) && nrow(spec$basin) > 0) {
    map_widget <- map_widget |>
      leaflet::addPolygons(
        data = spec$basin,
        color = style$colors$basin_border,
        weight = style$line_widths$basin,
        fillColor = style$colors$basin_fill,
        fillOpacity = style$fill_opacity$basin,
        group = "Basin"
      )
  }

  if (!is.null(spec$rivers) && nrow(spec$rivers) > 0) {
    river_weight <- if (identical(spec$layer_source, "topology")) style$line_widths$river else style$line_widths$fallback_river
    river_opacity <- if (identical(spec$layer_source, "topology")) 0.9 else 0.7
    map_widget <- map_widget |>
      leaflet::addPolylines(
        data = spec$rivers,
        color = style$colors$river,
        weight = river_weight,
        opacity = river_opacity,
        group = "Rivers"
      )
  }

  if (!is.null(spec$canals) && nrow(spec$canals) > 0) {
    canal_weight <- if (identical(spec$layer_source, "topology")) style$line_widths$canal else style$line_widths$fallback_canal
    canal_opacity <- if (identical(spec$layer_source, "topology")) 0.9 else 0.8
    map_widget <- map_widget |>
      leaflet::addPolylines(
        data = spec$canals,
        color = style$colors$canal,
        weight = canal_weight,
        opacity = canal_opacity,
        group = "Canals"
      )
  }

  if (!is.null(spec$lakes) && nrow(spec$lakes) > 0) {
    map_widget <- map_widget |>
      leaflet::addPolygons(
        data = spec$lakes,
        color = style$colors$lake_border,
        weight = style$line_widths$lake,
        fillColor = style$colors$lake_fill,
        fillOpacity = style$fill_opacity$lake,
        group = "Lakes"
      )
  }

  map_widget <- map_widget |>
    leaflet::addCircleMarkers(
      data = spec$concentration_nodes,
      lng = ~x,
      lat = ~y,
      radius = style$point_sizes$concentration,
      weight = 1,
      fillOpacity = style$fill_opacity$concentration,
      color = ~color_palette(C_w_map),
      fillColor = ~color_palette(C_w_map),
      popup = ~popup_html,
      group = "Concentrations"
    )

  if (!is.null(spec$source_nodes) && nrow(spec$source_nodes) > 0) {
    map_widget <- map_widget |>
      leaflet::addCircleMarkers(
        data = spec$source_nodes,
        lng = ~x,
        lat = ~y,
        radius = style$point_sizes$source,
        weight = 2,
        fillOpacity = style$fill_opacity$source,
        color = style$colors$source_outline,
        fillColor = ~color_palette(C_w_map),
        popup = ~popup_html,
        group = "Sources"
      )
  }

  tag_title <- htmltools::tags$div(
    htmltools::HTML(spec$map_title_html),
    style = "background: white; padding: 8px 12px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.2); font-size: 14px;"
  )

  map_widget <- map_widget |>
    leaflet::addControl(html = tag_title, position = "bottomleft") |>
    leaflet::addLegend(
      "topright",
      pal = color_palette,
      values = spec$concentration_nodes$C_w_map,
      title = spec$legend_title,
      labFormat = legend_format,
      opacity = 1
    ) |>
    leaflet::addLayersControl(
      baseGroups = style$base_groups,
      overlayGroups = style$overlay_groups,
      options = leaflet::layersControlOptions(collapsed = TRUE)
    )

  map_html <- file.path(plots_dir, "concentration_map.html")
  message("Saving interactive map HTML: ", map_html)
  map_libdir <- paste0(tools::file_path_sans_ext(basename(map_html)), "_files")
  unlink(file.path(plots_dir, map_libdir), recursive = TRUE, force = TRUE)
  tryCatch(
    htmlwidgets::saveWidget(map_widget, file = map_html, selfcontained = FALSE, libdir = map_libdir),
    error = function(e) message("Note: interactive map save failed: ", e$message)
  )

  map_html
}
