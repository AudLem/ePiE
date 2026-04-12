library(ePiE)
library(testthat)

test_that("ApplyManualDischargeOverrides returns unchanged when no manual_Q column", {
  nodes <- data.frame(
    node_id = c("1", "2", "3"),
    river_discharge = c(10.5, 20.0, 0.001),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::ApplyManualDischargeOverrides(nodes)
  expect_identical(result$river_discharge, c(10.5, 20.0, 0.001))
})

test_that("ApplyManualDischargeOverrides overrides where manual_Q is not NA", {
  nodes <- data.frame(
    node_id = c("1", "2", "3"),
    river_discharge = c(10.5, 20.0, 0.001),
    manual_Q = c(50.0, NA, NA),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::ApplyManualDischargeOverrides(nodes)
  expect_equal(result$river_discharge[1], 50.0)
  expect_equal(result$river_discharge[2], 20.0)
  expect_equal(result$river_discharge[3], 0.001)
})

test_that("ApplyManualDischargeOverrides handles all-NA manual_Q", {
  nodes <- data.frame(
    node_id = c("1", "2"),
    river_discharge = c(5.0, 15.0),
    manual_Q = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::ApplyManualDischargeOverrides(nodes)
  expect_identical(result$river_discharge, c(5.0, 15.0))
})
