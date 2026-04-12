library(ePiE)
library(testthat)

make_test_nodes <- function(n = 10) {
  data.frame(
    ID = as.character(seq_len(n)),
    ID_nxt = as.character(c(seq_len(n - 1) + 1L, NA)),
    x = seq(-0.5, 0.4, length.out = n),
    y = rep(5.2, n),
    d_nxt = rep(1000, n),
    pt_type = c(rep("agglomeration", 2), rep("node", n - 4), "WWTP", "node"),
    total_population = c(rep(1000, 2), rep(0, n - 3), 500),
    rptMStateK = rep("GH", n),
    uwwLoadEnt = c(rep(NA, 2), rep(NA, n - 3), 500),
    uwwCapacit = c(rep(NA, 2), rep(NA, n - 3), 600),
    uwwPrimary = c(rep(0, 2), rep(0, n - 3), -1),
    uwwSeconda = c(rep(0, 2), rep(0, n - 3), -1),
    f_STP = c(rep(0.9, 2), rep(0, n - 3), 0.9),
    slope = rep(0.01, n),
    stringsAsFactors = FALSE
  )
}

make_test_lakes <- function() {
  data.frame(
    Hylak_id = integer(0),
    basin_id = character(0),
    Vol_total = numeric(0),
    Depth_avg = numeric(0),
    T_AIR = numeric(0),
    Wind = numeric(0),
    stringsAsFactors = FALSE
  )
}

test_that("NormalizeScenarioState adds all required columns", {
  pts <- make_test_nodes()
  hl <- make_test_lakes()
  result <- NormalizeScenarioState(pts, hl, "GH", "test", 27.5, 4.5)
  nodes <- result$normalized_network_nodes

  required <- c("node_id", "next_node_id", "distance_to_next", "Dist_down",
                "Pt_type", "Down_type", "T_AIR", "Wind", "SLOPE__deg",
                "Inh", "f_direct", "f_STP", "Hylak_id", "HL_ID_new", "lake_out")
  for (col in required) {
    expect_true(col %in% names(nodes), info = paste("Missing column:", col))
  }
})

test_that("NormalizeScenarioState normalizes Pt_type values", {
  pts <- make_test_nodes()
  hl <- make_test_lakes()
  result <- NormalizeScenarioState(pts, hl, "GH", "test")
  nodes <- result$normalized_network_nodes

  expect_true("WWTP" %in% nodes$Pt_type)
  expect_true("agglomeration" %in% nodes$Pt_type)
  expect_true("node" %in% nodes$Pt_type)
})

test_that("NormalizeScenarioState fills defaults for missing environmental columns", {
  pts <- make_test_nodes()
  pts$T_AIR <- NULL
  pts$Wind <- NULL
  pts$slope <- NULL
  hl <- make_test_lakes()

  result <- NormalizeScenarioState(pts, hl, "GH", "test", 25, 3)
  nodes <- result$normalized_network_nodes

  expect_true(all(nodes$T_AIR == 25))
  expect_true(all(nodes$Wind == 3))
  expect_true(all(nodes$SLOPE__deg == 0))
})

test_that("NormalizeScenarioState handles empty lake nodes", {
  pts <- make_test_nodes()
  hl <- make_test_lakes()
  result <- NormalizeScenarioState(pts, hl, "GH", "test")
  expect_true(nrow(result$lake_nodes) == 0)
})

test_that("NormalizeScenarioState propagates Dist_down correctly", {
  pts <- make_test_nodes(5)
  hl <- make_test_lakes()
  result <- NormalizeScenarioState(pts, hl, "GH", "test")
  nodes <- result$normalized_network_nodes

  terminal <- is.na(nodes$next_node_id)
  expect_true(all(nodes$Dist_down[terminal] == 0))
  expect_true(all(nodes$Dist_down[!terminal] > 0))
})

test_that("NormalizeScenarioState sets rptMStateK from study_country", {
  pts <- make_test_nodes()
  pts$rptMStateK <- NULL
  hl <- make_test_lakes()
  result <- NormalizeScenarioState(pts, hl, "XX", "test")
  expect_true(all(result$normalized_network_nodes$rptMStateK == "XX"))
})

test_that("NormalizeScenarioState fixes invalid downstream links", {
  pts <- make_test_nodes(5)
  pts$ID_nxt[3] <- "nonexistent"
  hl <- make_test_lakes()
  result <- NormalizeScenarioState(pts, hl, "GH", "test")
  expect_true(is.na(result$normalized_network_nodes$next_node_id[3]))
})
