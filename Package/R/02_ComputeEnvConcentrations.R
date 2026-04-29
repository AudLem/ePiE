ComputeEnvConcentrations = function(basin_data, chem, cons, verbose = FALSE, cpp = FALSE,
                                     substance_type = "chemical", pathogen_params = NULL){

  # ====================================================================
  # Route to the correct computation branch based on substance_type.
  #
  # Chemical branch: loops over all chemicals in the chem table,
  #   computes partition coefficients, runs SimpleTreat WWTP model,
  #   and applies 5-pathway dissipation (bio + photo + hydro + sed + vol).
  #
  # Pathogen branch: uses the pathogen-specific decay model (K_T + K_R + K_S)
  #   with emission from WWTP and agglomeration nodes. Runs once per pathogen.
  #
  # TODO(MULTI-PATHOGEN): To support running multiple pathogens in one call:
  #   1. Accept a list of pathogen_params instead of a single one
  #   2. Loop over pathogen_params similar to the chem loop (line 49)
  #   3. Accumulate results into combined data frames with a 'substance' column
  #   4. This would enable comparing Cryptosporidium vs Rotavirus vs Giardia
  #      in a single pipeline run.
  # ====================================================================

  is_pathogen <- identical(substance_type, "pathogen")
  pts = basin_data$points
  hl = basin_data$hl
  transport_edges <- if (!is.null(basin_data$transport_edges)) basin_data$transport_edges else NULL
  use_edge_transport <- !is.null(transport_edges) && HasTransportBranching(transport_edges)

  if (inherits(pts, "sf")) {
    geom <- sf::st_geometry(pts)
    pts <- sf::st_drop_geometry(pts)
    attr(pts, "sf_geometry") <- geom
  }
  if (inherits(hl, "sf")) {
    geom_hl <- sf::st_geometry(hl)
    hl <- sf::st_drop_geometry(hl)
    attr(hl, "sf_geometry") <- geom_hl
  }

  if (is_pathogen) {
    if (is.null(pathogen_params)) stop("pathogen_params required when substance_type = 'pathogen'")
    pathogen_params <- ResolvePathogenParams(pathogen_params)
    if ("HL_ID_new" %in% names(pts) && !"Hylak_id" %in% names(pts)) {
      pts$Hylak_id <- pts$HL_ID_new
    }
    # Redundant call removed: Set_upstream_points_v2 is already called
    # in RunSimulationPipeline() at line 55.
    pts$upcount <- pts$Freq
    pts <- AssignPathogenEmissions(pts, pathogen_params)
    decay_result <- AssignPathogenDecayParameters(pts, hl, pathogen_params)
    pts <- decay_result$network_nodes
    hl  <- decay_result$lake_nodes

    pts$E_up <- 0
    pts$E_w_NXT <- 0
    pts$fin <- 0
    pts$C_w <- NA_real_
    pts$C_sd <- NA_real_

    if (!is.null(hl) && nrow(hl) > 0) {
      hl$C_w <- NA_real_
      hl$C_sd <- NA_real_
      hl$fin <- rep(0, nrow(hl))
      hl$E_in <- if ("E_in" %in% names(hl)) hl$E_in else rep(0, nrow(hl))
      hl$k_NXT <- hl$k
    }

    pts$k_NXT <- pts$k

    results <- if (use_edge_transport) {
      Compute_env_concentrations_edges(
        pts = pts,
        HL = hl,
        transport_edges = transport_edges,
        print = verbose,
        substance_type = "pathogen"
      )
    } else {
      Compute_env_concentrations_v4(pts, hl, print = verbose, substance_type = "pathogen")
    }
    results$pts$substance <- pathogen_params$name
    if (!is.null(results$hl) && nrow(results$hl) > 0) {
      results$hl$substance <- pathogen_params$name
    }

    out <- list(pts = results$pts, hl = results$hl)
    if (!is.null(out$pts) && "basin_ID" %in% names(out$pts)) {
      out$pts$basin_id <- out$pts$basin_ID
      out$pts$basin_ID <- NULL
    }
    return(out)
  }

  for (chem_ii in 1:nrow(chem)) {

    pts.backup = pts
    chem.backup = chem

    pts_hl = Set_local_parameters_custom_removal_fast3(pts,hl,cons,chem,chem_ii)

    if(cpp && !use_edge_transport){

      idx = which(!pts_hl$pts$basin_id%in%pts_hl$hl$basin_id)
      basin_ids_no_lakes = unique(pts_hl$pts$basin_id[idx])
      if(nrow(pts_hl$hl)>0 & length(basin_ids_no_lakes)>0){
        tmp = pts_hl$hl[1,]
        tmp = tmp[rep(1, each = length(basin_ids_no_lakes)), ]
        tmp$Hylak_id = -99999
        tmp$basin_id = basin_ids_no_lakes
        tmp$Lake_name = "placeholder"
        tmp$E_in = 0
        pts_hl$hl = rbind(pts_hl$hl,tmp)
      }else if(nrow(pts_hl$hl)==0 & length(basin_ids_no_lakes)>0){
        tmp = data.frame(Vol_total = 0,
                        k = 0,
                        k_ws = 0,
                        Depth_avg = 0,
                        H_sed = 0,
                        poros = 0,
                        rho_sd = 0,
                        Hylak_id = -99999,
                        E_in = 0,
                        k_sw = 0,
                        basin_id = NA)
        tmp = tmp[rep(1, each = length(basin_ids_no_lakes)), ]
        tmp$basin_id = basin_ids_no_lakes
        tmp$Lake_name = "placeholder"
        tmp$E_in = 0
        pts_hl$hl = tmp
      }

      unique_basins = unique(pts_hl$pts$basin_id)
      basin_id_df = data.frame(basin_id=unique_basins,new_id=1:length(unique_basins))
      pts_hl$hl$basin_id = basin_id_df$new_id[match(pts_hl$hl$basin_id,basin_id_df$basin_id)]
      pts_hl$pts$basin_id = basin_id_df$new_id[match(pts_hl$pts$basin_id,basin_id_df$basin_id)]

      pts_hl$hl$basin_id = as.integer(pts_hl$hl$basin_id)
      pts_hl$hl$Hylak_id = as.integer(pts_hl$hl$Hylak_id)
      pts_hl$pts$basin_id = as.integer(pts_hl$pts$basin_id)
      pts_hl$pts$Hylak_id = as.integer(pts_hl$pts$Hylak_id)

      if(class(verbose)!="logical"){verbose = TRUE}

      # Pass canal metadata to the C++ engine so outputs preserve canal identity
      # and modeled discharge values.
      results = Compute_env_concentrations_v4_cpp(
        pts_ID = pts_hl[[1]]$ID,
        pts_ID_nxt = pts_hl[[1]]$ID_nxt,
        pts_basin_id = pts_hl[[1]]$basin_id,
        pts_upcount = pts_hl[[1]]$upcount,
        pts_lake_out = pts_hl[[1]]$lake_out,
        pts_Hylak_id = pts_hl[[1]]$Hylak_id,
        pts_E_w = pts_hl[[1]]$E_w,
        pts_E_up = pts_hl[[1]]$E_up,
        pts_Q = pts_hl[[1]]$Q,
        pts_E_w_NXT = pts_hl[[1]]$E_w_NXT,
        pts_k_NXT = pts_hl[[1]]$k_NXT,
        pts_k_ws = pts_hl[[1]]$k_ws,
        pts_k_sw = pts_hl[[1]]$k_sw,
        pts_H_sed = pts_hl[[1]]$H_sed,
        pts_H = pts_hl[[1]]$H,
        pts_poros = pts_hl[[1]]$poros,
        pts_rho_sd = pts_hl[[1]]$rho_sd,
        pts_dist_nxt = pts_hl[[1]]$dist_nxt,
        pts_V_NXT = pts_hl[[1]]$V_NXT,
        pts_f_rem_WWTP = pts_hl[[1]]$f_rem_WWTP,
        pts_x = pts_hl[[1]]$x,
        pts_y = pts_hl[[1]]$y,
        pts_Pt_type = pts_hl[[1]]$Pt_type,
        pts_is_canal = if ("is_canal" %in% names(pts_hl[[1]])) as.logical(pts_hl[[1]]$is_canal) else rep(FALSE, nrow(pts_hl[[1]])),
        pts_Q_model_m3s = if ("Q_model_m3s" %in% names(pts_hl[[1]])) as.numeric(pts_hl[[1]]$Q_model_m3s) else rep(NA_real_, nrow(pts_hl[[1]])),
        hl_Vol_total = pts_hl[[2]]$Vol_total,
        hl_k = pts_hl[[2]]$k,
        hl_k_ws = pts_hl[[2]]$k_ws,
        hl_Depth_avg = pts_hl[[2]]$Depth_avg,
        hl_H_sed = pts_hl[[2]]$H_sed,
        hl_poros = pts_hl[[2]]$poros,
        hl_rho_sd = pts_hl[[2]]$rho_sd,
        hl_Hylak_id = pts_hl[[2]]$Hylak_id,
        hl_E_in = pts_hl[[2]]$E_in,
        hl_k_sw = pts_hl[[2]]$k_sw,
        hl_basin_id = pts_hl[[2]]$basin_id,
        print = verbose
      )

      results$HL = results$HL[results$HL$Hylak_id>0,]

      results$pts$basin_ID = basin_id_df$basin_id[match(results$pts$basin_ID,basin_id_df$new_id)]
      idx = which(results$HL$Hylak_id==pts_hl[[2]]$Hylak_id)
      results$HL$basin_id = pts_hl[[2]]$basin_id[idx]
      results$HL$basin_id = basin_id_df$basin_id[match(results$HL$basin_id,basin_id_df$new_id)]

    }else{
      if (cpp && use_edge_transport) {
        warning("Branch-aware transport detected; falling back from cpp=TRUE to the R edge-aware solver.")
      }
      results = if (use_edge_transport) {
        Compute_env_concentrations_edges(
          pts = pts_hl[[1]],
          HL = pts_hl[[2]],
          transport_edges = transport_edges,
          print = verbose,
          substance_type = "chemical"
        )
      } else {
        Compute_env_concentrations_v4(pts_hl[[1]],pts_hl[[2]],print=verbose)
      }

    }

    results[[1]]$API = chem$API[chem_ii]
    if (!is.null(hl) && nrow(hl)!=0) {
      if (!is.null(results[[2]])) {
        results[[2]]$API = chem$API[chem_ii]
      }
    }

    if(!is.null(hl) && nrow(hl)!=0) {
      if(chem_ii==1){
        results_com = results[[1]]
        results_lakes = results[[2]]
      }else{
        results_com = rbind(results_com,results[[1]])
        results_lakes = rbind(results_lakes,results[[2]])
      }
    }else{
      results_lakes = NULL
      if(chem_ii==1) {
        results_com = results[[1]]
      }else{
        results_com = rbind(results_com,results[[1]])
      }
    }

    pts = pts.backup
    chem = chem.backup
  }

  out = list(pts=results_com,hl=results_lakes)
  out$pts$basin_id = out$pts$basin_ID
  out$pts$basin_ID = NULL

  return(out)
}
