library(testthat)

test_that("display junction annotation marks coincident confluence nodes only for display", {
  pts <- data.frame(
    ID = c("A_end", "B_end", "C_jnct", "D_next", "Src"),
    ID_nxt = c("C_jnct", "C_jnct", "D_next", NA, "C_jnct"),
    pt_type = c("node", "node", "JNCT", "node", "agglomeration"),
    x = c(1, 1, 1, 2, 1),
    y = c(1, 1, 1, 1, 1),
    stringsAsFactors = FALSE
  )

  out <- AnnotateDisplayJunctions(pts)

  expect_equal(out$pt_type[out$ID == "A_end"], "node")
  expect_equal(out$display_pt_type[out$ID == "A_end"], "JNCT")
  expect_equal(out$junction_role[out$ID == "A_end"], "coincident_confluence_node")
  expect_equal(out$display_pt_type[out$ID == "C_jnct"], "JNCT")
  expect_equal(out$junction_role[out$ID == "C_jnct"], "fan_in_receiver")
  expect_equal(out$display_pt_type[out$ID == "Src"], "agglomeration")
  expect_true(is.na(out$junction_role[out$ID == "Src"]))
})
