Compute_env_concentrations_v4 = function(pts, HL, print = TRUE, substance_type = "chemical"){

  is_pathogen <- identical(substance_type, "pathogen")

  #store all columns as vectors (faster)
  for(i in 1:ncol(pts)) assign(paste('pts.',colnames(pts)[i],sep=''),pts[,i])
  for(i in 1:ncol(HL)) assign(paste('HL.',colnames(HL)[i],sep=''),HL[,i])
  if(!exists("pts.Hylak_id")) pts.Hylak_id = rep(1,length(pts.ID))
  if(!exists("pts.lake_out")) pts.lake_out = rep(0,length(pts.ID))

  # init break vector
  break.vec1 = c();

  # get pts and HL indexing
  HL_indices_match = match(pts.Hylak_id,HL.Hylak_id)
  pts_indices_down = match(paste0(pts.basin_id,'_',pts.ID_nxt),paste0(pts.basin_id,'_',pts.ID))

  #continue looping until all points and lakes are assessed
  while (any(pts.fin==0)){

    if(print){
      print(paste('# points in pts:',sum(pts.fin == 0),sep=' '))
      print(paste('# points in HL:',ifelse(nrow(HL)!=0,sum(HL.fin==0),0),sep=' '))
    }

    break.vec1 = c(break.vec1,sum(pts.fin == 0));
    if(length(break.vec1)-length(unique(break.vec1))>10) break

    pts_to_process = which(pts.fin==0 & pts.upcount==0)

    for (j in pts_to_process) {

      if(pts.fin[j]==0){
        HL_index_match = HL_indices_match[j]
        pts_index_down = pts_indices_down[j]
      }

        if (!is.na(match(pts.basin_id[j], HL.basin_id)) & (pts.lake_out[j] == 1)) {

          E_total = HL.E_in[HL_index_match] + pts.E_w[j] + pts.E_up[j]

          V = HL.Vol_total[HL_index_match] * 1e6
          k = HL.k[HL_index_match]

          if (is_pathogen) {
            pts.C_w[j] = (E_total / (pts.Q[j] + k * V)) / (365 * 24 * 3600) * 1000
          } else {
            pts.C_w[j] = E_total / (pts.Q[j] + k * V) * 1e6 / (365*24*3600)
            chem_exchange = HL.k_ws[HL_index_match] / HL.k_sw[HL_index_match]
            H_ratio = HL.Depth_avg[HL_index_match] / HL.H_sed[HL_index_match]
            dens_transform = HL.poros[HL_index_match] + (1 - HL.poros[HL_index_match]) * HL.rho_sd[HL_index_match]
            pts.C_sd[j] = pts.C_w[j] * chem_exchange * H_ratio * dens_transform
          }

          HL.C_w[HL_index_match] = pts.C_w[j]
          HL.C_sd[HL_index_match] = pts.C_sd[j]
          HL.fin[HL_index_match] = 1

          if (is_pathogen) {
            pts.E_w_NXT[j] = pts.C_w[j] * pts.Q[j] * 365 * 24 * 3600 / 1000 * exp(-pts.k_NXT[j] * pts.dist_nxt[j] / pts.V_NXT[j])
          } else {
            pts.E_w_NXT[j] = pts.C_w[j] * pts.Q[j] * 365 * 24 * 3600 / 1e6 * exp(-pts.k_NXT[j] * pts.dist_nxt[j] / pts.V_NXT[j])
          }
          if (!is.na(pts_index_down)) {
            pts.E_up[pts_index_down] = pts.E_up[pts_index_down] + pts.E_w_NXT[j]
            pts.upcount[pts_index_down] = pts.upcount[pts_index_down] - 1
          }


        } else if ((pts.Hylak_id[j] == 0) | (pts.lake_out[j] == 1)) {

          E_total = pts.E_w[j] + pts.E_up[j]

          if (is_pathogen) {
            pts.C_w[j] = as.numeric((E_total / (365 * 24 * 3600)) / (pts.Q[j] * 1000))
          } else {
            pts.C_w[j] = as.numeric(E_total / pts.Q[j] * 1e6 / (365*24*3600))
            chem_exchange = pts.k_ws[j] / pts.k_sw[j]
            H_ratio = pts.H[j] / pts.H_sed[j]
            dens_transform = pts.poros[j] + (1 - pts.poros[j]) * pts.rho_sd[j]
            pts.C_sd[j] = as.numeric(pts.C_w[j] * chem_exchange * H_ratio * dens_transform)
          }

          pts.E_w_NXT[j] = E_total * exp(-pts.k_NXT[j] * pts.dist_nxt[j] / pts.V_NXT[j])
          if (!is.na(pts_index_down)) {
            pts.E_up[pts_index_down] = pts.E_up[pts_index_down] + pts.E_w_NXT[j]
            pts.upcount[pts_index_down] = pts.upcount[pts_index_down] - 1
          }

        } else {

          E_total = pts.E_w[j] + pts.E_up[j]
          pts.C_w[j] = NA
          pts.C_sd[j] = NA

          pts.E_w_NXT[j] = E_total
          if (!is.na(pts_index_down)) {
            pts.E_up[pts_index_down] = pts.E_up[pts_index_down] + pts.E_w_NXT[j]
            pts.upcount[pts_index_down] = pts.upcount[pts_index_down] - 1
          }
        }

        pts.fin[j] = 1

    }

  }

  if (nrow(HL) != 0) {
    return(list(
      pts = data.frame(
        ID = pts.ID,
        Pt_type = pts.Pt_type,
        ID_nxt = pts.ID_nxt,
        basin_ID = pts.basin_id,
        Hylak_id = pts.Hylak_id,
        x = pts.x,
        y = pts.y,
        Q = pts.Q,
        C_w = pts.C_w,
        C_sd = pts.C_sd,
        WWTPremoval = pts.f_rem_WWTP
      ),
      HL = data.frame(
        Hylak_id = HL.Hylak_id,
        C_w = HL.C_w,
        C_sd = HL.C_sd
      )
    ))
  } else {
    return(list(
      pts = data.frame(
        ID = pts.ID,
        Pt_type = pts.Pt_type,
        ID_nxt = pts.ID_nxt,
        basin_ID = pts.basin_id,
        x = pts.x,
        y = pts.y,
        Q = pts.Q,
        C_w = pts.C_w,
        C_sd = pts.C_sd,
        WWTPremoval = pts.f_rem_WWTP
      )
    ))
  }
}
