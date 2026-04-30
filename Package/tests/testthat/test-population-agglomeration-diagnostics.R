library(ePiE)
library(testthat)

make_step05_diagnostic_fixture <- function() {
  crs <- sf::st_crs(32631)
  raster <- raster::raster(nrows = 3, ncols = 3, xmn = 0, xmx = 3, ymn = 0, ymx = 3, crs = crs$wkt)
  raster <- raster::setValues(raster, c(0, 1, 2, NA, 4, 5, 0, 2, 1))

  basin <- sf::st_sf(
    geometry = sf::st_sfc(
      sf::st_polygon(list(matrix(c(0, 0, 3, 0, 3, 3, 0, 3, 0, 0), ncol = 2, byrow = TRUE))),
      crs = crs
    )
  )

  rivers <- sf::st_sf(
    ARCID = 1,
    geometry = sf::st_sfc(sf::st_linestring(matrix(c(0, 0.5, 3, 2.5), ncol = 2, byrow = TRUE)), crs = crs)
  )

  segments <- sf::st_sf(
    segment_id = "seg1",
    original_id = 1,
    geometry = sf::st_sfc(sf::st_linestring(matrix(c(0, 0.5, 3, 2.5), ncol = 2, byrow = TRUE)), crs = crs)
  )

  pixels <- sf::st_as_sf(
    data.frame(
      population = c(10, 20),
      Hylak_id_pop = c(NA, NA),
      nearest_segment_id = c("seg1", "seg1"),
      x = c(0.5, 1.5),
      y = c(0.7, 1.4)
    ),
    coords = c("x", "y"),
    crs = crs
  )

  agglomeration <- sf::st_sf(
    node_type = "agglomeration",
    segment_id = "seg1",
    nearest_segment_id = "seg1",
    HL_ID_new = NA_real_,
    pixel_count = 2,
    total_population = 30,
    centroid_x = 1.1,
    centroid_y = 1.15,
    snapped_x = 1.1,
    snapped_y = 1.23,
    snap_distance_m = 0.08,
    geometry = sf::st_sfc(sf::st_point(c(1.1, 1.23)), crs = crs)
  )

  list(
    raster = raster,
    basin = basin,
    rivers = rivers,
    segments = segments,
    pixels = pixels,
    agglomeration = agglomeration
  )
}

test_that("Step 5 diagnostics stay disabled unless full diagnostics are requested", {
  fixture <- make_step05_diagnostic_fixture()
  out_dir <- tempfile("step05_disabled_")

  ePiE:::SaveStep05PopulationDiagnostics(
    diagnostics_level = "none",
    diagnostics_dir = out_dir,
    Basin_utm = fixture$basin,
    rivers_utm = fixture$rivers,
    ghs_pop_utm = fixture$raster
  )

  expect_false(dir.exists(file.path(out_dir, "population_agglomerations")))
})

test_that("Step 5 diagnostics write trace CSV and map series", {
  fixture <- make_step05_diagnostic_fixture()
  out_dir <- tempfile("step05_enabled_")

  ePiE:::SaveStep05PopulationDiagnostics(
    diagnostics_level = "full",
    diagnostics_dir = out_dir,
    status = "ok",
    Basin_utm = fixture$basin,
    rivers_utm = fixture$rivers,
    ghs_pop_utm = fixture$raster,
    final_pop_mask = fixture$basin,
    ghs_sf_in_mask = fixture$pixels,
    populated_pixels = fixture$pixels,
    river_pixels = fixture$pixels,
    river_segments_sf = fixture$segments,
    agglomeration_trace = fixture$agglomeration
  )

  diag_dir <- file.path(out_dir, "population_agglomerations")
  expected_files <- c(
    "01_population_raster_crop.png",
    "02_population_inclusion_mask.png",
    "03_selected_population_pixels.png",
    "04_pixel_to_target_groups.png",
    "05_weighted_centroids_before_snap.png",
    "06_centroids_snapped_to_network.png",
    "07_final_step05_agglomerations.png",
    "step_05_agglomeration_status.csv",
    "step_05_agglomeration_trace.csv"
  )

  expect_true(all(file.exists(file.path(diag_dir, expected_files))))
  expect_length(list.files(diag_dir, pattern = "\\.error\\.txt$"), 0)

  trace <- read.csv(file.path(diag_dir, "step_05_agglomeration_trace.csv"))
  expect_equal(nrow(trace), 1)
  expect_true(all(c("centroid_x", "centroid_y", "snapped_x", "snapped_y", "snap_distance_m") %in% names(trace)))
  expect_equal(trace$pixel_count, 2)
  expect_equal(trace$total_population, 30)
})

test_that("Step 5 diagnostics handle empty agglomeration results", {
  fixture <- make_step05_diagnostic_fixture()
  out_dir <- tempfile("step05_empty_")

  ePiE:::SaveStep05PopulationDiagnostics(
    diagnostics_level = "full",
    diagnostics_dir = out_dir,
    status = "no_populated_pixels_in_mask",
    status_message = "synthetic empty case",
    Basin_utm = fixture$basin,
    rivers_utm = fixture$rivers,
    ghs_pop_utm = fixture$raster,
    final_pop_mask = fixture$basin,
    ghs_sf_in_mask = fixture$pixels,
    populated_pixels = fixture$pixels[FALSE, ],
    river_segments_sf = fixture$segments
  )

  diag_dir <- file.path(out_dir, "population_agglomerations")
  expect_true(file.exists(file.path(diag_dir, "step_05_agglomeration_status.csv")))
  expect_true(file.exists(file.path(diag_dir, "step_05_agglomeration_trace.csv")))
  expect_length(list.files(diag_dir, pattern = "\\.error\\.txt$"), 0)

  status <- read.csv(file.path(diag_dir, "step_05_agglomeration_status.csv"))
  expect_equal(status$status, "no_populated_pixels_in_mask")
})
