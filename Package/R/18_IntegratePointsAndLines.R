IntegratePointsAndLines <- function(agglomeration_points, lines, points) {
  message("--- Step 8: Integrating Sources ---")

  suppress_coercion <- function(expr) {
    withCallingHandlers(expr, warning = function(w) {
      if (grepl("NAs introduced by coercion", w$message)) invokeRestart("muffleWarning")
    })
  }

  suppress_coercion({
    pts_tmp <- PrepareAgglomerationPoints(agglomeration_points, lines)

    if (!is.null(pts_tmp)) {
      message("Points to integrate: ", nrow(pts_tmp))
      print(table(pts_tmp$pt_type))
    } else {
      message("No points to integrate (pts_tmp is NULL)")
    }

    lines_indices <- unique(c(points$L1, if (!is.null(pts_tmp)) pts_tmp$L1))
    lines_indices <- lines_indices[!is.na(lines_indices)]
    points_tmpList <- vector("list", length(lines_indices))
    desired_columns <- c(
      "L1", "ARCID", "dir", "ID", "x", "y", "idx_in_line_seg", "ID_nxt",
      "pt_type", "loc_ID_tmp", "d_nxt", "LD2", "LD", "geometry", "idx_nxt_tmp",
      "total_population", "rptMStateK", "uwwLoadEnt", "uwwCapacit",
      "uwwPrimary", "uwwSeconda", "f_STP", "is_canal", "manual_Q",
      "HL_ID_new", "lake_in", "lake_out", "node_type"
    )

    for (i in seq_along(lines_indices)) {
      lidx <- lines_indices[i]
      pts_in_seg <- if (!is.null(pts_tmp)) pts_tmp[pts_tmp$L1 == lidx, ] else NULL
      points_in_seg <- points[points$L1 == lidx, ]

      if (!is.null(pts_in_seg) && nrow(pts_in_seg) > 0) {
        if (nrow(points_in_seg) == 0) {
          message("Skipping segment ", lidx, " because it has no river nodes but has sources.")
          next
        }
        points_tmpList[[i]] <- MergePointsForSegment(
          pts_in_seg,
          points_in_seg,
          points,
          lidx,
          sf::st_crs(lines),
          desired_columns
        )
      } else {
        points_tmpList[[i]] <- points[points$L1 == lidx, ]
        points_tmpList[[i]] <- sf::st_transform(points_tmpList[[i]], sf::st_crs(lines))
        points_tmpList[[i]] <- EnsureColumns(points_tmpList[[i]], desired_columns, NA)
      }
    }

    points_tmpList <- points_tmpList[!sapply(points_tmpList, is.null)]
    message("Combined segments: ", length(points_tmpList))

    points_dfs <- lapply(seq_along(points_tmpList), function(i) {
      x <- points_tmpList[[i]]
      df <- as.data.frame(x)
      if ("geometry" %in% names(df)) {
        coords <- sf::st_coordinates(x)
        df$X_coord <- coords[, 1]
        df$Y_coord <- coords[, 2]
        df$geometry <- NULL
      }
      CoerceSchema(
        df,
        char_cols = c("ID", "ID_nxt", "pt_type", "node_type"),
        num_cols = c("L1", "ARCID", "dir", "idx_in_line_seg", "d_nxt", "LD", "LD2", "manual_Q", "HL_ID_new", "lake_in", "lake_out")
      )
    })

    points_union_df <- do.call(plyr::rbind.fill, points_dfs)

    points <- suppressWarnings(sf::st_as_sf(
      points_union_df,
      coords = c("X_coord", "Y_coord"),
      crs = sf::st_crs(lines),
      remove = TRUE
    ))
  })

  message("Running final data integrity checks...")
  mandatory_cols <- c("ID", "ID_nxt", "pt_type", "d_nxt", "LD")
  missing_mandatory <- setdiff(mandatory_cols, names(points))
  if (length(missing_mandatory) > 0) {
    stop("Critical Error: Mandatory columns missing after integration: ", paste(missing_mandatory, collapse = ", "))
  }
  if (nrow(points) == 0) {
    stop("Critical Error: Integrated point network is empty.")
  }
  if (any(is.na(points$pt_type))) {
    warning("Integration Warning: Some points still have NA pt_type.")
  }

  message("Integration complete.")
  list(
    points = points,
    integration_points = points
  )
}
