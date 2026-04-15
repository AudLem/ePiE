#' Load and adapt the pre-built Bega network from AudLem Outputs to the format
#' expected by ComputeEnvConcentrations (v1.26 conventions).
#'
#' The AudLem pre-built network uses column names that differ from what the
#' SHoeks/v1.25 engine expects. This helper performs the translation using
#' v1.26 conventions (f_direct lowercase, cons$cnt, etc.).
#'
#' @param pts_path Path to Outputs/bega/pts.csv
#' @param hl_path  Path to Outputs/bega/HL.csv
#' @param default_temp Default air temperature (C). Default 11.0.
#' @param default_wind Default wind speed (m/s). Default 4.5.
#' @return list(pts, hl) ready for ComputeEnvConcentrations
adapt_bega_network <- function(pts_path, hl_path,
                               default_temp = 11.0, default_wind = 4.5) {
  pts <- read.csv(pts_path, stringsAsFactors = FALSE)
  hl  <- read.csv(hl_path, stringsAsFactors = FALSE)

  pts$Pt_type <- pts$pt_type
  pts$pt_type <- NULL
  pts$Dist_down <- pts$LD
  pts$LD <- NULL
  pts$LD_new <- NULL
  pts$dist_nxt <- pts$d_nxt
  pts$d_nxt <- NULL

  pts$basin_id <- "bega"
  pts$country <- ifelse(!is.na(pts$rptMStateK), as.character(pts$rptMStateK), "RO")

  pts$Freq <- 0
  pts2 <- split(pts, f = pts$basin_id)
  pts_list <- list()
  for (i in seq_along(pts2)) {
    upst <- table(ID = pts2[[i]]$ID_nxt)
    upst <- data.frame(upst)
    pts2[[i]]$Freq <- NULL
    pts2[[i]] <- merge(pts2[[i]], upst, by = "ID", all.x = TRUE, all.y = FALSE)
    pts2[[i]]$Freq[is.na(pts2[[i]]$Freq)] <- 0
    pts_list[[i]] <- pts2[[i]]
  }
  pts <- do.call(rbind, pts_list)
  row.names(pts) <- NULL

  nxt_idx <- match(pts$ID_nxt, pts$ID)
  valid_nxt <- !is.na(nxt_idx)
  pts$Down_type <- NA_character_
  pts$Down_type[valid_nxt] <- pts$Pt_type[nxt_idx[valid_nxt]]

  pts$line_node <- pts$ID_nxt
  bad_line <- is.na(pts$line_node) | !(pts$line_node %in% pts$ID)
  pts$line_node[bad_line] <- NA

  pts$T_AIR <- default_temp
  pts$Wind <- default_wind
  pts$pH <- 7.4

  pts$f_direct <- 0
  pts$F_direct <- NULL

  for (cc in c("uwwNRemova","uwwPRemova","uwwUV","uwwChlorin",
               "uwwOzonati","uwwSandFil","uwwMicroFi")) {
    if (!(cc %in% names(pts))) pts[[cc]] <- NA
  }
  for (cc in c("uwwOtherTr","uwwOther","uwwSpecifi","aggID","aggCode",
               "aggName","aggGenerat","stop","flow_acc")) {
    if (!(cc %in% names(pts))) pts[[cc]] <- NA
  }

  pts$L1 <- NULL
  pts$ARCID <- NULL
  pts$is_canal <- NULL
  pts$manual_Q <- NULL
  pts$dir <- NULL
  pts$loc_ID_tmp <- NULL
  pts$LD2 <- NULL
  pts$idx_nxt_tmp <- NULL
  pts$node_type <- NULL
  pts$X <- pts$x
  pts$Y <- pts$y

  hl$basin_id <- "bega"
  hl$T_AIR <- default_temp
  hl$Wind <- default_wind
  hl$pH <- 7.4
  hl$HRT <- hl$Res_time
  hl$HRT_sec <- hl$HRT * 86400
  hl$H_av <- hl$Depth_avg

  list(pts = pts, hl = hl)
}
