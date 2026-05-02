library(ePiE)
library(testthat)

make_visualization_nodes <- function() {
  data.frame(
    ID = c("P1", "S1", "P2", "P3"),
    ID_nxt = c("S1", "P2", "P3", NA),
    x = c(0, 1, 2, 3),
    y = c(6, 6, 6, 6),
    Pt_type = c("node", "WWTP", "node", "agglomeration"),
    C_w = c(0.01, 0.02, NA, 0.04),
    Q = c(1, 2, 3, 4),
    total_population = c(0, 1000, 0, 500),
    is_canal = c(FALSE, TRUE, FALSE, FALSE),
    stringsAsFactors = FALSE
  )
}

test_that("concentration maps use poster-friendly multicolor palettes", {
  style <- ePiE:::ePieVisualizationStyle()
  binned_scale <- ePiE:::BuildConcentrationBinnedScale(c(0, 5e-7, 5e-5, 2))

  expect_equal(style$concentration_palette, c("#2C7BB6", "#00A6A6", "#1A9850", "#FFD92F", "#F46D43", "#B2182B", "#762A83"))
  expect_equal(ePiE:::getTmapConcentrationPalette(style), style$concentration_palette)
  expect_equal(ePiE:::formatTmapConcentrationLabels(c(-8, -3, 0, 3)), c("1.000e-08", "0.001", "1", "1000"))
  expect_equal(binned_scale$labels[1], "0")
  expect_equal(length(binned_scale$labels), 9)
  expect_equal(
    ePiE:::getTmapBinnedClassLabels(c(0, 5e-7, 5e-5, 2), binned_scale$breaks, binned_scale$labels),
    c("0", binned_scale$labels[2], binned_scale$labels[4], binned_scale$labels[9])
  )
  expect_equal(length(ePiE:::getTmapBinnedPalette(style, binned_scale$labels)), length(binned_scale$labels))
  expect_equal(ePiE:::getTmapBinnedPalette()[1], style$concentration_palette[1])
  expect_equal(ePiE:::getTmapBinnedPalette()[length(ePiE:::getTmapBinnedLabels())], style$concentration_palette[length(style$concentration_palette)])
})

test_that("NormalizeVisualizationVariants accepts the static binned variant", {
  expect_equal(
    ePiE:::NormalizeVisualizationVariants(c("linear_binned", "linear", "bad")),
    c("linear_binned", "linear")
  )
  expect_true(ePiE:::IsStaticOnlyVisualizationVariant("linear_binned"))
})

test_that("BuildConcentrationMapSpec prefers topology edges and splits canals", {
  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = make_visualization_nodes(),
    target_substance = "Ibuprofen",
    basin_id = "test"
  )

  expect_equal(spec$layer_source, "topology")
  expect_s3_class(spec$topology_edges, "sf")
  expect_equal(nrow(spec$topology_edges), 3)
  expect_equal(nrow(spec$rivers), 2)
  expect_equal(nrow(spec$canals), 1)
})

test_that("BuildConcentrationMapSpec prepares shared legend metadata and source nodes", {
  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = make_visualization_nodes(),
    substance_type = "pathogen",
    pathogen_name = "Cryptosporidium",
    pathogen_units = "CFU/100mL",
    basin_id = "volta_dry"
  )

  expect_equal(spec$legend_title, "Cryptosporidium (CFU/100mL, log scale)")
  expect_equal(spec$map_scale, "log10")
  expect_equal(spec$map_title_text, "Cryptosporidium - volta_dry - log10")
  expect_equal(ePiE:::getTmapLegendTitle(spec), "Cryptosporidium\nCFU/100mL, log scale")
  expect_equal(nrow(spec$source_nodes), 2)
  expect_equal(nrow(spec$concentration_nodes_plot), 3)
  tmap_segments <- ePiE:::prepareTmapConcentrationSegments(spec)
  expect_equal(nrow(tmap_segments), nrow(spec$concentration_segments_plot))
  expect_equal(tmap_segments$tmap_segment_weight, spec$concentration_segments_plot$segment_weight * 1.6)
  expect_true(all(c("popup_html", "x", "y") %in% names(spec$concentration_nodes)))
})

test_that("BuildConcentrationMapSpec infers pathogen-specific units", {
  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = make_visualization_nodes(),
    substance_type = "pathogen",
    pathogen_name = "campylobacter",
    basin_id = "volta"
  )

  expect_equal(spec$units, "CFU/L")
  expect_equal(spec$legend_title, "campylobacter (CFU/L, log scale)")
  expect_equal(spec$concentration_nodes$C_w_map[1], log10(0.01))
})

test_that("BuildConcentrationMapSpec handles missing optional layers", {
  nodes <- make_visualization_nodes()
  nodes$is_canal <- NULL

  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = nodes,
    input_paths = list(
      rivers = tempfile(fileext = ".shp"),
      lakes = tempfile(fileext = ".shp"),
      basin = tempfile(fileext = ".shp")
    ),
    target_substance = "Ibuprofen"
  )

  expect_null(spec$basin)
  expect_null(spec$lakes)
  expect_equal(spec$layer_source, "topology")
  expect_equal(nrow(spec$canals), 0)
  expect_equal(spec$legend_title, "Ibuprofen (µg/L)")
  expect_equal(ePiE:::getTmapLegendTitle(spec), "Ibuprofen\nµg/L")
})

test_that("BuildConcentrationMapSpec supports explicit linear and log variants", {
  linear_spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = make_visualization_nodes(),
    substance_type = "pathogen",
    pathogen_name = "campylobacter",
    basin_id = "volta",
    map_scale = "linear",
    map_variant = "linear"
  )
  expect_equal(linear_spec$map_scale, "linear")
  expect_equal(linear_spec$map_filename, "concentration_map_linear.html")
  expect_equal(linear_spec$concentration_nodes$C_w_map[1], 0.01)

  log_spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = make_visualization_nodes(),
    substance_type = "pathogen",
    pathogen_name = "campylobacter",
    basin_id = "volta",
    map_scale = "log10",
    map_variant = "log10"
  )
  expect_equal(log_spec$map_scale, "log10")
  expect_equal(log_spec$map_filename, "concentration_map_log10.html")
  expect_equal(log_spec$concentration_nodes$C_w_map[1], log10(0.01))
})

test_that("BuildConcentrationMapSpec supports the static linear_binned variant", {
  nodes <- make_visualization_nodes()
  nodes$C_w[1] <- 0
  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = nodes,
    substance_type = "pathogen",
    pathogen_name = "cryptosporidium",
    pathogen_units = "oocysts/L",
    basin_id = "volta",
    map_scale = "linear",
    map_variant = "linear_binned"
  )
  scale <- ePiE:::getTmapConcentrationScale(spec, spec$style)
  tmap_segments <- ePiE:::prepareTmapConcentrationSegments(spec)

  expect_equal(spec$map_scale, "linear")
  expect_equal(spec$map_variant, "linear_binned")
  expect_equal(spec$map_title_text, "cryptosporidium - volta - linear_binned")
  expect_equal(spec$static_map_filename, "static_concentration_map_linear_binned.png")
  expect_equal(spec$concentration_nodes$C_w_map, spec$concentration_nodes$C_w)
  expect_equal(ePiE:::getTmapLegendTitle(spec), "cryptosporidium\noocysts/L\nuneven concentration classes")
  expect_equal(ePiE:::getTmapBinnedMaxValue(spec), 0.02)
  expect_match(
    ePiE:::getTmapBinnedLegendTitle(spec),
    "Colors are classes, not equal intervals.",
    fixed = TRUE
  )
  expect_match(
    ePiE:::getTmapBinnedLegendTitle(spec),
    "Max calculated: 0.02 oocysts/L",
    fixed = TRUE
  )
  expect_equal(scale$labels, spec$binned_scale$labels)
  expect_equal(spec$binned_scale$labels[1], "0")
  expect_equal(tail(spec$binned_scale$labels, 1), "0 - 0.02")
  expect_true(any(tmap_segments$C_w_map == 0 & tmap_segments$tmap_C_w_map < 0))
})

test_that("BuildConcentrationMapSpec can reuse shared binned classes", {
  shared_scale <- ePiE:::BuildConcentrationBinnedScale(c(0, 1e-6, 1e-4, 1))
  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = make_visualization_nodes(),
    substance_type = "pathogen",
    pathogen_name = "cryptosporidium",
    pathogen_units = "oocysts/L",
    basin_id = "volta",
    map_scale = "linear",
    map_variant = "linear_binned",
    binned_breaks = shared_scale$breaks,
    binned_labels = shared_scale$labels
  )

  expect_equal(spec$binned_scale, shared_scale)
  expect_equal(ePiE:::getTmapConcentrationScale(spec, spec$style)$labels, shared_scale$labels)
})

test_that("BuildConcentrationMapSpec keeps zero concentration segments on log maps", {
  nodes <- make_visualization_nodes()
  nodes$C_w[1] <- 0

  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = nodes,
    substance_type = "pathogen",
    pathogen_name = "campylobacter",
    basin_id = "volta",
    map_scale = "log10",
    map_variant = "log10"
  )

  zero_node <- spec$concentration_nodes[spec$concentration_nodes$ID == "P1", ]
  positive_values <- spec$concentration_nodes$C_w[spec$concentration_nodes$C_w > 0]

  expect_true(is.finite(zero_node$C_w_map))
  expect_lt(zero_node$C_w_map, min(log10(positive_values), na.rm = TRUE))
  expect_true("P1" %in% spec$concentration_segments_plot$from_id)
})

test_that("BuildConcentrationMapSpec enriches popup fields from network nodes", {
  network_nodes <- make_visualization_nodes()
  network_path <- tempfile(fileext = ".csv")
  write.csv(network_nodes, network_path, row.names = FALSE)

  simulation_nodes <- network_nodes[, setdiff(names(network_nodes), c("total_population", "Inh")), drop = FALSE]
  spec <- ePiE:::BuildConcentrationMapSpec(
    simulation_results = simulation_nodes,
    input_paths = list(pts = network_path),
    target_substance = "Ibuprofen",
    basin_id = "test"
  )

  source_node <- spec$concentration_nodes[spec$concentration_nodes$ID == "S1", ]
  expect_equal(source_node$total_population, 1000)
  expect_match(source_node$popup_html, "Total population:</b> 1000", fixed = TRUE)
})
