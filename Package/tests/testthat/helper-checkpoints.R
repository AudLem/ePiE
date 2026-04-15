#' Assert that a checkpoint file exists and is valid
#' @param checkpoint_path Path to the checkpoint file
#' @export
AssertCheckpointExists <- function(checkpoint_path) {
  if (!file.exists(checkpoint_path)) {
    stop("Checkpoint file does not exist: ", checkpoint_path)
  }
  
  state <- tryCatch(
    readRDS(checkpoint_path),
    error = function(e) {
      stop("Failed to read checkpoint file: ", checkpoint_path, " - ", e$message)
    }
  )
  
  if (!is.list(state)) {
    stop("Checkpoint must be a list, got ", class(state)[1])
  }
  
  invisible(state)
}

#' Load a checkpoint from file
#' @param checkpoint_path Path to the checkpoint file
#' @return The loaded checkpoint state
#' @export
LoadCheckpoint <- function(checkpoint_path) {
  state <- AssertCheckpointExists(checkpoint_path)
  message("Loaded checkpoint from: ", checkpoint_path)
  message("Checkpoint keys: ", paste(names(state), collapse = ", "))
  state
}

#' Helper for network integrity tests
#' @param state Pipeline state list.
#' @export
expect_valid_network <- function(state) {
  testthat::expect_s3_class(state$points, "data.frame")
  testthat::expect_true("ID" %in% names(state$points))
  testthat::expect_true("ID_nxt" %in% names(state$points))

  # Check for dangling edges
  invalid_nxt <- state$points$ID_nxt[!is.na(state$points$ID_nxt) & state$points$ID_nxt != "" & !(state$points$ID_nxt %in% state$points$ID)]
  testthat::expect_equal(length(invalid_nxt), 0, info = paste("Dangling edges found:", paste(head(invalid_nxt), collapse=",")))
}

#' Helper for schema consistency
#' @param state Pipeline state list.
#' @export
expect_consistent_schema <- function(state) {
  required_cols <- c("ID", "x", "y", "ID_nxt", "LD")
  for (col in required_cols) {
    testthat::expect_true(col %in% names(state$points), info = paste("Missing column:", col))
  }
}
