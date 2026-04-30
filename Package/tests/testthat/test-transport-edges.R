library(ePiE)
library(testthat)

make_canal_transport_points <- function(kind = c("offtake", "full_split")) {
  kind <- match.arg(kind)

  if (identical(kind, "offtake")) {
    data.frame(
      ID = c("P1", "P2", "B1"),
      ID_nxt = c("P2", NA, NA),
      basin_id = "test",
      x = c(0, 0.01, 0),
      y = c(0, 0, 0.01),
      is_canal = TRUE,
      pt_type = "node",
      canal_pt_type = c("CANAL_BRANCH", "CANAL_END", "CANAL_END"),
      canal_name = c("Main canal", "Main canal", "AK C1"),
      canal_idx = c(1L, 2L, 1L),
      canal_downstream_ids = c("P2|B1", NA, NA),
      canal_downstream_count = c(2L, 0L, 0L),
      chainage_m = c(1000, 1400, 0),
      canal_d_nxt_m = c(400, NA, NA),
      Q_model_m3s = c(6.0, 5.5, 0.4),
      Q_parent_m3s = c(6.0, NA, NA),
      Q_out_sum_m3s = c(0.4, NA, NA),
      Q_residual_m3s = c(5.6, NA, NA),
      Q_role = c("parent_branch_available", "through_flow", "child_branch_outflow"),
      Q_source = "test",
      V = 1,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      ID = c("P1", "N1", "S1"),
      ID_nxt = c("N1", NA, NA),
      basin_id = "test",
      x = c(0, 0.01, -0.01),
      y = c(0, 0.01, 0.01),
      is_canal = TRUE,
      pt_type = "node",
      canal_pt_type = c("CANAL_BRANCH", "CANAL_END", "CANAL_END"),
      canal_name = c("Main canal", "NLLC", "SLLC"),
      canal_idx = c(10L, 1L, 1L),
      canal_downstream_ids = c("N1|S1", NA, NA),
      canal_downstream_count = c(2L, 0L, 0L),
      chainage_m = c(16000, 0, 0),
      canal_d_nxt_m = c(NA, NA, NA),
      Q_model_m3s = c(4.11, 2.07, 2.04),
      Q_parent_m3s = c(4.11, NA, NA),
      Q_out_sum_m3s = c(4.11, NA, NA),
      Q_residual_m3s = c(0, NA, NA),
      Q_role = c("parent_branch_available", "child_branch_outflow", "child_branch_outflow"),
      Q_source = "test",
      V = 1,
      stringsAsFactors = FALSE
    )
  }
}

test_that("BuildTransportEdges preserves parent-canal continuation after an offtake", {
  edges <- ePiE:::BuildTransportEdges(make_canal_transport_points("offtake"), warn = FALSE)

  expect_true(any(edges$from_id == "P1" & edges$to_id == "P2" & edges$edge_type == "canal_reach"))
  expect_true(any(edges$from_id == "P1" & edges$to_id == "B1" & edges$edge_type == "canal_branch"))

  parent_edges <- edges[edges$from_id == "P1", , drop = FALSE]
  expect_equal(nrow(parent_edges), 2)
  expect_lte(sum(parent_edges$flow_fraction), 1)
})

test_that("BuildTransportEdges avoids duplicate ID_nxt edges for true canal splits", {
  edges <- ePiE:::BuildTransportEdges(make_canal_transport_points("full_split"), warn = FALSE)

  parent_edges <- edges[edges$from_id == "P1", , drop = FALSE]
  expect_equal(nrow(parent_edges), 2)
  expect_true(all(parent_edges$edge_type == "canal_branch"))
  expect_true(any(parent_edges$to_id == "N1"))
  expect_true(any(parent_edges$to_id == "S1"))
  expect_equal(sum(parent_edges$flow_fraction), 1, tolerance = 1e-8)
})
