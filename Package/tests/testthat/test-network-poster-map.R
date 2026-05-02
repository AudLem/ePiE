library(ePiE)

test_that("RenderPosterNetworkMap writes poster PNG and PDF", {
  testthat::skip_if_not_installed("sf")
  testthat::skip_if_not_installed("tmap")

  basin <- sf::st_sf(
    id = 1,
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)
      ))),
      crs = 4326
    )
  )
  rivers <- sf::st_sf(
    id = 1,
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(0.1, 0.2), c(0.9, 0.8))), crs = 4326)
  )
  canals <- sf::st_sf(
    id = 1,
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(0.2, 0.8), c(0.8, 0.2))), crs = 4326)
  )
  points <- sf::st_as_sf(
    data.frame(
      ID = c("P_00001", "P_00002", "Source00001", "C_00001"),
      display_pt_type = c("START", "MOUTH", "agglomeration", "CANAL_BRANCH"),
      pt_type = c("START", "MOUTH", "agglomeration", "CANAL_BRANCH"),
      node_type = c(NA, NA, "agglomeration", NA),
      x = c(0.1, 0.9, 0.5, 0.6),
      y = c(0.2, 0.8, 0.5, 0.4),
      stringsAsFactors = FALSE
    ),
    coords = c("x", "y"),
    crs = 4326
  )
  selected_agglomeration_areas <- sf::st_sf(
    layer = "selected_agglomeration_area",
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(
        c(0.35, 0.35), c(0.65, 0.35), c(0.65, 0.65), c(0.35, 0.65), c(0.35, 0.35)
      ))),
      crs = 4326
    )
  )

  plots_dir <- tempfile("network-poster-")
  dir.create(plots_dir)
  out <- ePiE:::RenderPosterNetworkMap(
    Basin = basin,
    rivers = rivers,
    canals = canals,
    points = points,
    selected_agglomeration_areas = selected_agglomeration_areas,
    plots_dir = plots_dir,
    basin_id = "test",
    png_width = 1000,
    png_height = 700,
    png_dpi = 100
  )

  expect_true(file.exists(out$png))
  expect_true(file.exists(out$pdf))
})

test_that("BuildSelectedAgglomerationAreas returns selected raster cell areas", {
  testthat::skip_if_not_installed("raster")
  testthat::skip_if_not_installed("sf")

  r <- raster::raster(
    nrows = 2,
    ncols = 2,
    xmn = 0,
    xmx = 2,
    ymn = 0,
    ymx = 2,
    crs = "+proj=longlat +datum=WGS84"
  )
  raster::values(r) <- c(0, 5, NA, 3)

  selected_areas <- ePiE:::BuildSelectedAgglomerationAreas(r)
  geometry_types <- as.character(sf::st_geometry_type(selected_areas, by_geometry = TRUE))

  expect_s3_class(selected_areas, "sf")
  expect_true(all(geometry_types %in% c("POLYGON", "MULTIPOLYGON")))
  expect_false(any(geometry_types == "POINT"))
  expect_equal(unique(selected_areas$selected_pixel_count), 2)
})
