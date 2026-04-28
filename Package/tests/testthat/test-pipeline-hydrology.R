library(ePiE)
library(testthat)

test_that("ApplyCanalDischargeOverrides returns unchanged when no Q_model_m3s column", {
  nodes <- data.frame(
    node_id = c("1", "2", "3"),
    river_discharge = c(10.5, 20.0, 0.001),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::ApplyCanalDischargeOverrides(nodes)
  expect_identical(result$river_discharge, c(10.5, 20.0, 0.001))
})

test_that("ApplyCanalDischargeOverrides overrides where Q_model_m3s is not NA", {
  nodes <- data.frame(
    node_id = c("1", "2", "3"),
    river_discharge = c(10.5, 20.0, 0.001),
    Q_model_m3s = c(50.0, NA, NA),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::ApplyCanalDischargeOverrides(nodes)
  expect_equal(result$river_discharge[1], 50.0)
  expect_equal(result$river_discharge[2], 20.0)
  expect_equal(result$river_discharge[3], 0.001)
})

test_that("ApplyCanalDischargeOverrides handles all-NA Q_model_m3s", {
  nodes <- data.frame(
    node_id = c("1", "2"),
    river_discharge = c(5.0, 15.0),
    Q_model_m3s = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::ApplyCanalDischargeOverrides(nodes)
  expect_identical(result$river_discharge, c(5.0, 15.0))
})
