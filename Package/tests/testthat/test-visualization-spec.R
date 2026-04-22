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

  expect_equal(spec$legend_title, "Cryptosporidium (CFU/100mL)")
  expect_equal(spec$map_title_text, "Cryptosporidium - volta_dry")
  expect_equal(nrow(spec$source_nodes), 2)
  expect_equal(nrow(spec$concentration_nodes_plot), 3)
  expect_true(all(c("popup_html", "x", "y") %in% names(spec$concentration_nodes)))
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
})
