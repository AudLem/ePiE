library(ePiE)
library(testthat)

test_that("PrepareCountryConsumption returns default table for known country", {
  nodes <- data.frame(
    node_id = c("1"),
    total_population = 1000000,
    rptMStateK = "DE",
    Pt_type = "WWTP",
    stringsAsFactors = FALSE
  )
  result <- ePiE:::PrepareCountryConsumption(nodes, "DE", "Ibuprofen")
  expect_true("DE" %in% result$cnt)
  expect_true("Ibuprofen" %in% names(result))
  expect_true("population" %in% names(result))
  expect_equal(nrow(result), 51)
})

test_that("PrepareCountryConsumption adds synthetic row for unknown country", {
  nodes <- data.frame(
    node_id = c("1", "2"),
    total_population = c(500000, 500000),
    rptMStateK = c("ZZ", "ZZ"),
    Pt_type = c("agglomeration", "WWTP"),
    stringsAsFactors = FALSE
  )
  result <- ePiE:::PrepareCountryConsumption(nodes, "ZZ", "Ibuprofen")
  expect_true("ZZ" %in% result$cnt)
  zz_row <- result[result$cnt == "ZZ", ]
  expect_true(zz_row$Ibuprofen > 0)
  expect_true(zz_row$population > 0)
})

test_that("PrepareCountryConsumption uses fallback population when node pop is missing", {
  nodes <- data.frame(
    node_id = c("1"),
    total_population = NA_real_,
    rptMStateK = "ZZ",
    Pt_type = "WWTP",
    stringsAsFactors = FALSE
  )
  result <- ePiE:::PrepareCountryConsumption(nodes, "ZZ", "Ibuprofen")
  zz_row <- result[result$cnt == "ZZ", ]
  expect_equal(zz_row$population, 1e6)
})

test_that("Check_cons_v2 works with matching country and substance", {
  pts <- data.frame(
    rptMStateK = c("DE", "DE"),
    Pt_type = c("Agglomerations", "WWTP"),
    basin_id = "test",
    stringsAsFactors = FALSE
  )
  chem <- data.frame(API = "Ibuprofen", CAS = "xxx", stringsAsFactors = FALSE)
  cons_data <- data.frame(
    cnt = "DE",
    population = 83000000,
    year = 2019,
    Ibuprofen = 83000000 * 0.0045,
    stringsAsFactors = FALSE
  )
  result <- ePiE:::Check_cons_v2(pts, chem, cons_data)
  expect_true("DE" %in% result$country)
  expect_true("Ibuprofen" %in% names(result))
  expect_true(result$Ibuprofen[1] > 0)
})

test_that("Check_cons_v2 errors on missing consumption data", {
  pts <- data.frame(
    rptMStateK = "ZZ",
    Pt_type = "Agglomerations",
    basin_id = "test",
    stringsAsFactors = FALSE
  )
  chem <- data.frame(API = "Ibuprofen", CAS = "xxx", stringsAsFactors = FALSE)
  cons_data <- data.frame(
    cnt = "DE",
    population = 83000000,
    year = 2019,
    Ibuprofen = 83000000 * 0.0045,
    stringsAsFactors = FALSE
  )
  expect_error(ePiE:::Check_cons_v2(pts, chem, cons_data), "insufficient consumption data")
})
