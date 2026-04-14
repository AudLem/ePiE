library(ePiE)
library(sf)
library(testthat)

create_mock_points <- function() {
  pts <- data.frame(
    ID = c(1, 2, 3, 4),
    ID_nxt = c(2, 3, 4, NA),
    x = c(0, 100, 200, 300),
    y = c(0, 0, 0, 0),
    LD = c(300, 200, 100, 0),
    pt_type = c("node", "node", "node", "MOUTH"),
    HL_ID_new = c(0, 0, 0, 0),
    lake_in = c(0, 0, 0, 0),
    lake_out = c(0, 0, 0, 0),
    node_type = c("Hydro_River", "Hydro_River", "Hydro_River", "Hydro_River")
  )
  sf::st_geometry(pts) <- sf::st_sfc(sf::st_point(c(0, 0)),
                                       sf::st_point(c(100, 0)),
                                       sf::st_point(c(200, 0)),
                                       sf::st_point(c(300, 0)),
                                       crs = 32631)
  pts
}

create_mock_lake <- function(center_x, center_y, radius = 50, hylak_id = 999) {
  theta <- seq(0, 2 * pi, length.out = 20)
  x_coords <- center_x + radius * cos(theta)
  y_coords <- center_y + radius * sin(theta)
  
  x_coords <- c(x_coords, x_coords[1])
  y_coords <- c(y_coords, y_coords[1])
  
  lake <- data.frame(
    Hylak_id = hylak_id,
    Lake_name = paste0("Lake_", hylak_id),
    Pour_long = 0,
    Pour_lat = 0
  )
  poly_coords <- matrix(c(x_coords, y_coords), ncol = 2)
  sf::st_geometry(lake) <- sf::st_sfc(sf::st_polygon(list(poly_coords)), crs = 32631)
  lake
}

test_that("DetectLakeSegmentCrossings returns empty list when HL_basin is NULL", {
  points <- create_mock_points()
  result <- DetectLakeSegmentCrossings(points, NULL)
  
  expect_true(is.list(result))
  expect_equal(result$segment_count, 0)
  expect_equal(result$lakes_with_crossings, 0)
  expect_equal(nrow(result$crossings), 0)
})

test_that("DetectLakeSegmentCrossings returns empty list when points is NULL", {
  lake <- create_mock_lake(150, 0, 60)
  result <- DetectLakeSegmentCrossings(NULL, lake)
  
  expect_true(is.list(result))
  expect_equal(result$segment_count, 0)
  expect_equal(result$lakes_without_crossings, 1)
  expect_equal(result$lakes_with_crossings, 0)
  expect_equal(nrow(result$crossings), 0)
})

test_that("DetectLakeSegmentCrossings detects inlet and outlet for through-lake", {
  points <- create_mock_points()
  lake <- create_mock_lake(150, 0, 60)
  result <- DetectLakeSegmentCrossings(points, lake)
  
  expect_equal(result$segment_count, 3)
  expect_equal(result$lakes_with_crossings, 1)
  
  through_crossings <- result$crossings[result$crossings$crossing_type %in% c("inlet", "outlet"), ]
  expect_equal(nrow(through_crossings), 2)
  
  inlet <- through_crossings[through_crossings$crossing_type == "inlet", ]
  outlet <- through_crossings[through_crossings$crossing_type == "outlet", ]
  
  expect_equal(nrow(inlet), 1)
  expect_equal(nrow(outlet), 1)
  expect_true(inlet$crossing_x < outlet$crossing_x)
})

test_that("DetectLakeSegmentCrossings detects through-lake with inlet and outlet", {
  points <- create_mock_points()
  lake <- create_mock_lake(150, 0, 80)
  result <- DetectLakeSegmentCrossings(points, lake)
  
  through_crossings <- result$crossings[result$crossings$crossing_type %in% c("inlet", "outlet"), ]
  expect_equal(nrow(through_crossings), 2)
  
  inlet <- through_crossings[through_crossings$crossing_type == "inlet", ]
  outlet <- through_crossings[through_crossings$crossing_type == "outlet", ]
  
  expect_true(inlet$crossing_x < outlet$crossing_x)
  expect_true(inlet$upstream_id == 1)
  expect_true(outlet$downstream_id == 4)
})

test_that("DetectLakeSegmentCrossings handles tangential crossing", {
  points <- create_mock_points()
  lake <- create_mock_lake(150, 100, 30)
  result <- DetectLakeSegmentCrossings(points, lake)
  
  expect_equal(nrow(result$crossings), 0)
  expect_equal(result$lakes_with_crossings, 0)
  expect_equal(result$lakes_without_crossings, 1)
})

test_that("DetectLakeSegmentCrossings handles multiple lakes", {
  points <- create_mock_points()
  lake1 <- create_mock_lake(50, 0, 30, 101)
  lake2 <- create_mock_lake(250, 0, 30, 102)
  lakes <- rbind(lake1, lake2)
  result <- DetectLakeSegmentCrossings(points, lakes)
  
  expect_equal(result$lakes_with_crossings, 2)
  expect_equal(nrow(result$crossings), 2)
  expect_true(101 %in% result$crossings$Hylak_id)
  expect_true(102 %in% result$crossings$Hylak_id)
})

test_that("DetectLakeSegmentCrossings validates crossing coordinates", {
  points <- create_mock_points()
  lake <- create_mock_lake(150, 0, 80)
  result <- DetectLakeSegmentCrossings(points, lake)
  
  crossing <- result$crossings[1, ]
  
  expect_true(is.numeric(crossing$crossing_x))
  expect_true(is.numeric(crossing$crossing_y))
  expect_true(!is.na(crossing$crossing_x))
  expect_true(!is.na(crossing$crossing_y))
  expect_true(crossing$distance_from_boundary >= 0)
  expect_true(crossing$distance_from_boundary <= 10)
})

test_that("DetectLakeSegmentCrossings validates CRS", {
  points <- create_mock_points()
  sf::st_crs(points) <- NA
  
  lake <- create_mock_lake(150, 0, 60)
  
  expect_error(
    DetectLakeSegmentCrossings(points, lake)
  )
})
