# ==============================================================================
# Flow Extraction and Hydraulic Property Computation
# ==============================================================================
# This file extracts river flow data from a gridded raster and augments the
# basin network point data with hydraulic properties needed for concentration
# modelling. It is the first step in the concentration pipeline.
#
# Key operations:
#   1. Extract discharge Q from a flow raster at each network node
#   2. Propagate Q to nodes where the raster has no data (NA/zero fill)
#   3. Propagate slope to nodes where slope is missing (NA/zero fill)
#   4. Compute local hydraulic properties via the Manning-Strickler formulation
#      (Formula H1 from the PhD proposal):
#        v = (1/n) * R^(2/3) * S^(1/2)
#      adapted according to Pistocchi and Pennington (2006).
#
# Reference: Pistocchi, A. and Pennington, D. (2006), European Journal of
#   Operational Research, 170(2), 407-419.
# ==============================================================================

# --- AddFlowToBasinData ---------------------------------------------------------
# Purpose: Top-level orchestrator that (1) extracts gridded flow data at each
#   network point and (2) computes derived hydraulic properties (velocity,
#   depth, mixing lengths) using Manning-Strickler.
#
# Parameters:
#   basin_data  - list containing the network points data frame ($pts) and
#                 other basin-level structures
#   flow_rast   - a terra/SpatRaster of gridded discharge values [m^3/s]
#
# Returns:
#   basin_data  - the input list with $pts updated to include Q, V, H,
#                 D_MIX_vert, D_MIX_trans, V_NXT, etc.
# TODO(SEASONAL): Currently uses a single static flow raster. Seasonal flow
#   rasters (e.g. monthly climatologies) should be selectable here.
# --------------------------------------------------------------------------------
AddFlowToBasinData = function(basin_data,flow_rast){

  # extract pts
  pts = basin_data$pts

  # add flow to pts
  pts = Add_new_flow_fast(pts=pts,flow_raster=flow_rast)

  # Set hydrology
  pts = Select_hydrology_fast2(pts)

  # return pts list
  basin_data$pts = pts
  return(basin_data)
}

# --- Get_LatLong_crs ------------------------------------------------------------
# Purpose: Returns the WGS84 lat/long CRS string used consistently across the
#   package for spatial operations (raster extraction, point projection).
#
# Returns:
#   A proj4string for EPSG:4326 (WGS84 geographic coordinates).
# --------------------------------------------------------------------------------
Get_LatLong_crs = function(){
  return("+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
}

# --- Add_new_flow_fast ----------------------------------------------------------
# Purpose: Extracts discharge values from a gridded flow raster at each network
#   point location. Points are projected to WGS84 to match the raster CRS,
#   then values are extracted via terra::extract(). A correction loop reassigns
#   flow to monitoring/WWTP points that sit upstream of junctions, using the
#   flow value from their associated line node instead.
#
# Parameters:
#   pts          - data frame of network points (must have columns x, y,
#                  Pt_type, Down_type, line_node, basin_id, ID)
#   flow_raster  - a terra SpatRaster of discharge [m^3/s]
#
# Returns:
#   pts - the input data frame with a new column Q__NEW containing extracted
#         discharge values [m^3/s].
# TODO(SEASONAL): flow_raster should be replaced with a seasonal stack so that
#   the correct month's flow is extracted per simulation time step.
# --------------------------------------------------------------------------------
Add_new_flow_fast = function(pts, flow_raster){

  # set projection
  crs = Get_LatLong_crs()

  # project pts
  p = sf::st_as_sf(pts,coords=c("x","y"),crs=crs)

  # add flow
  imported_raster = flow_raster
  terra::crs(imported_raster) = crs
  Q__NEW = terra::extract(imported_raster, p)
  pts$Q__NEW = Q__NEW[,2]

  # assign Q of line rather than point to monitoring points that are upstream of junctions
  loop_indices = which(grepl("MONIT|WWTP|Agglomerations",pts$Pt_type))
  for (i in loop_indices) {
    if(pts$Down_type[i]=="JNCT"){
      idx = which(pts$ID == pts$line_node[i] & pts$basin_id == pts$basin_id[i])
      pts$Q__NEW[i] = pts$Q__NEW[idx]
    }
  }

  # return data
  return(pts)
}

# --- Select_hydrology_fast2 -----------------------------------------------------
# Purpose: Processes each basin independently to (1) fill missing distance,
#   flow, and slope values through network propagation; (2) compute local
#   hydraulic properties from Q and slope using the Manning-Strickler
#   formulation (Formula H1); (3) compute mixing zone lengths.
#
# Parameters:
#   pts - data frame of all network points (multiple basins), must include
#         columns: basin_id, dist_nxt, Dist_down, Q__NEW, slope, ID, ID_nxt,
#         Pt_type, Down_type, x, y
#
# Returns:
#   A data frame (rbind across basins) with new columns: Q, V, H, V_NXT,
#   D_MIX_vert, D_MIX_trans, and all original columns preserved.
#
# Processing phases per basin:
#   Phase 1 - Fill missing dist_nxt / Dist_down
#   Phase 2 - Propagate Q from upstream (zero-fill, 3 fallback loops)
#   Phase 3 - Propagate slope from neighbours (zero-fill, 3 fallback loops)
#   Phase 4 - Compute Manning-Strickler hydraulic properties (Formula H1)
#   Phase 5 - Compute average velocity over reach length (V_NXT)
# TODO(SEASONAL): Q values are static. Replace with time-varying Q when
#   seasonal flow rasters are available (GAP 1 in proposal).
# --------------------------------------------------------------------------------
Select_hydrology_fast2 = function(pts) {

  # Split points by basin for independent processing
  if(length(unique(pts$basin_id))==1){
    pts2 = list()
    pts2[[1]] = pts
  }else{
    pts2 <- split(pts,f=pts$basin_id)
  }
  pts3 <- c()



  for (b in 1:length(pts2)) {
    pts <- pts2[[b]]

    # --- Phase 1: Fill missing dist_nxt / Dist_down ----------------------------
    # Some points lack dist_nxt (distance to next downstream node). If Dist_down
    # is available but dist_nxt is NA, set dist_nxt to 0 (co-located nodes).
    pts$dist_nxt <- ifelse(is.na(pts$dist_nxt) & !is.na(pts$Dist_down),0,pts$dist_nxt)
    # Identify nodes missing both Dist_down and dist_nxt (excluding MOUTH)
    nodistd <- which(is.na(pts$Dist_down) & is.na(pts$dist_nxt) & pts$Pt_type!="MOUTH")

    # Propagate Dist_down from downstream neighbours where available
    while (any(is.na(pts$Dist_down[nodistd]))) {
      for (i in nodistd) {
        if (!is.na(pts$Dist_down[pts$ID_nxt %in% pts$ID[i] & pts$basin_id %in% pts$basin_id[i]])) {
          pts$Dist_down[i] <- pts$Dist_down[pts$ID_nxt %in% pts$ID[i] & pts$basin_id %in% pts$basin_id[i]]
        }
      }
    }

    # Compute dist_nxt as the difference in Dist_down between the downstream
    # node of this point and this point itself
    # xlim = c(pts$x[i]-0.2,pts$x[i]+0.2)
    # ylim = c(pts$y[i]-0.2,pts$y[i]+0.2)
    # plot(pts$x,pts$y,xlim=xlim,ylim=ylim)
    # points(pts$x[i],pts$y[i],col="red")
    for (i in nodistd) {
      # if(length(which(pts$ID %in% pts$ID_nxt[i]))==0){
      #   pts$dist_nxt[i] = 0
      #   pts$Pt_type[i] = "MOUTH"
      # }else{
      pts$dist_nxt[i] <- pts$Dist_down[pts$ID_nxt %in% pts$ID[i] & pts$basin_id %in% pts$basin_id[i]]  - pts$Dist_down[pts$ID %in% pts$ID_nxt[i] & pts$basin_id %in% pts$basin_id[i]]
      # }
    }

    # For points whose next node is MOUTH, dist_nxt equals their own Dist_down
    pts$dist_nxt[which(pts$ID_nxt %in% pts$ID[pts$Pt_type=="MOUTH"])] <- pts$Dist_down[which(pts$ID_nxt %in% pts$ID[pts$Pt_type=="MOUTH"])]

    # --- Phase 2: Propagate Q to zero-flow nodes -------------------------------
    # Rename extracted flow and remove temporary column
    pts$Q <- pts$Q__NEW
    pts$Q__NEW <- NULL

    # Replace NA flows with 0 so the propagation loops can handle them
    pts$Q[is.na(pts$Q)] <- 0
    # Identify all nodes with zero flow
    nf <- which(pts$Q==0)
    f <- length(nf)

    # Loop 2a: Fill from upstream — if all upstream nodes have flow, assign
    # the sum of upstream flows to this node.
    while (length(nf) > 0) {
      for (i in nf) {
        if (pts$Q[i] == 0 & !any(pts$Q[which(pts$ID_nxt == pts$ID[i])] == 0) & pts$Pt_type[i]!="START") {
          pts$Q[i] <- sum(pts$Q[which(pts$ID_nxt == pts$ID[i])])
          f <- f - 1
        }
      }
      if (f == length(nf)) {break} #if no updates were possible anymore, break
      nf <- which(pts$Q==0) #update vector with zero flow nodes

    }

    # Loop 2b: Fill from downstream — for nodes that could not be filled
    # upstream (e.g. START points with no flow), use the downstream Q.
    #check whether any nodes in network are still without flow because there is a start point with zero flow;
    #fill those with downstream flow
    while (length(nf) > 0) {
      for (i in nf) {
        if (pts$Q[i]==0 & any(pts$Q[which(pts$ID==pts$ID_nxt[i])] != 0) & pts$Pt_type[i]!="MOUTH") {
          pts$Q[i] <- pts$Q[which(pts$ID==pts$ID_nxt[i])]
          f <- f - 1
        }
      }
      if (f == length(nf)) {break} #if no updates were possible anymore, break
      nf <- which(pts$Q==0) #update vector with zero flow nodes
    }

    # Loop 2c: Last resort — try both upstream and downstream for any
    # remaining zero-flow nodes (complete isolated branches).
    #if there are any nodes with zero flow left, these are complete branches (START to MOUTH)
    #final option is to check whether any junctions are present in that branch of which the upstream flow of other branch can be used to fill up
    while (length(nf) > 0) {
      for (i in nf) {
        if (pts$Q[i]==0 & any(pts$Q[which(pts$ID_nxt == pts$ID[i])] != 0) & pts$Pt_type[i]!="START") {
          pts$Q[i] <- sum(pts$Q[which(pts$ID_nxt==pts$ID[i])])
          f <- f - 1
        } else if (pts$Q[i]==0 & any(pts$Q[which(pts$ID==pts$ID_nxt[i])] != 0) & pts$Pt_type[i]!="MOUTH") {
          pts$Q[i] <- pts$Q[which(pts$ID==pts$ID_nxt[i])]
          f <- f - 1
        }
      }
      if (f == length(nf)) {break} #if no updates were possible anymore, break
      nf <- which(pts$Q==0) #update vector with zero flow nodes
    }

    # If any node still has zero flow after all propagation attempts, abort
    #still nodes without flow? error message that calculation is not possible
    try(if(any(pts$Q==0)) stop(paste0("Prediction not possible due to insufficient flow data for ",pts$basin_id[1])))

    # --- Phase 3: Propagate slope to zero-slope nodes --------------------------
    # Same propagation strategy as Q: fill from upstream, then downstream,
    # then both. The !is.na() guards are critical — slope propagation loops
    # crash when slope values are NA (bug fix: NA values must be excluded
    # before comparing against zero).
    #same as above, now for slope
    pts$slope[is.na(pts$slope)] <- 0
    if (!("slope" %in% names(pts))) pts$slope <- 0
    ns <- which(pts$slope==0)
    s <- length(ns)
    index_next_point = list()
    for (i in ns) index_next_point[[i]] = which(pts$ID[i]==pts$ID_nxt)

    # Loop 3a: Fill slope from upstream — average upstream slopes
    while (length(ns) > 0) {

      for (i in ns) {

        #// SLOW CODE
        index_next_point2 = index_next_point[[i]]
        # NA guard: !is.na(pts$slope[i]) prevents crash when slope is NA;
        # without this check the loop crashes during slope propagation
        if (!is.na(pts$slope[i]) && pts$slope[i] == 0 && length(index_next_point2) > 0 && !any(pts$slope[index_next_point2] == 0) && pts$Pt_type[i]!="START") {
          pts$slope[i] <- mean(pts$slope[index_next_point2])
          s <- s - 1
        }


      }
      if (s == length(ns)) {break} #if no updates were possible anymore, break
      ns <- which(pts$slope==0) #update vector with zero slope nodes
    }

    index_prev_point = list()
    for (i in ns) index_prev_point[[i]] = which(pts$ID_nxt[i]==pts$ID)

    # Loop 3b: Fill slope from downstream neighbour
    while (length(ns) > 0) {
      for (i in ns) {

        #// SLOW CODE
        index_prev_point2 = index_prev_point[[i]]
        # NA guard: !is.na(pts$slope[i]) prevents crash when slope is NA
        if (length(index_prev_point2) > 0 && !is.na(pts$slope[i]) && pts$slope[i]==0 && any(pts$slope[index_prev_point2] != 0) && pts$Pt_type[i]!="MOUTH") {
          pts$slope[i] <- pts$slope[index_prev_point2]
          s <- s - 1
        }

      }
      if (s == length(ns)) {break} #if no updates were possible anymore, break
      ns <- which(pts$slope==0) #update vector with zero slope nodes

    }

    # Loop 3c: Last resort — try both upstream and downstream for remaining
    # zero-slope nodes
    while (length(ns) > 0) {
      for (i in ns) {
        # NA guards: !is.na(pts$slope[i]) in both branches prevents crash
        # when slope values are NA during propagation
        if (!is.na(pts$slope[i]) && pts$slope[i]==0 && any(pts$slope[which(pts$ID_nxt == pts$ID[i])] != 0) && pts$Pt_type[i]!="START") {
          pts$slope[i] <- mean(pts$slope[which(pts$ID_nxt==pts$ID[i])])
          s <- s - 1
        } else if (!is.na(pts$slope[i]) && pts$slope[i]==0 && any(pts$slope[which(pts$ID==pts$ID_nxt[i])] != 0) && pts$Pt_type[i]!="MOUTH") {
          pts$slope[i] <- pts$slope[which(pts$ID==pts$ID_nxt[i])]
          s <- s - 1
        }
      }
      if (s == length(ns)) {break}
      ns <- which(pts$slope==0)
    }

    # If any node still has zero slope, abort
    try(if(any(pts$slope==0)) stop(paste0("Prediction not possible due to insufficient slope data for ",pts$basin_id[1])))

    # --- Phase 4: Manning-Strickler hydraulic properties (Formula H1) ----------
    # Governing equation:  v = (1/n) * R^(2/3) * S^(1/2)
    #   v = flow velocity [m/s]
    #   n = Manning's roughness coefficient [s * m^(-1/3)]
    #   R = hydraulic radius [m] (approx. as cross-section / wetted perimeter)
    #   S = channel slope [m/m]
    #
    # The implementation below follows the algebraic rearrangement from
    # Pistocchi and Pennington (2006), which expresses velocity as a direct
    # function of Q, width W, slope, and roughness n, eliminating R:
    #   V = n^(-3/5) * Q^(2/5) * W^(-2/5) * slope^(3/10)
    #
    # TODO(SEASONAL): n, W, and slope are static. Seasonal variation in
    #   roughness (vegetation growth) and width should be modelled.
    # --------------------------------------------------------------------------

    #Calculation local hydrology
    #Manning's roughness coefficient (s*m-1/3), 0.045 as proposed by Pistocchi and Pennington (2006)
    n <- 0.045
    #Slope of river (m/m) — convert from degrees to dimensionless slope via tan()
    # tan(slope_degrees * pi/180) gives the rise-over-run ratio
    slope_m <- tan(pts$slope * pi / 180)
    #River river width (m), from Pistocchi and Pennington (2006)
    # Power-law relationship: W = 7.3607 * Q^0.52425
    W <- 7.3607 * pts$Q ^ 0.52425
    #Flow velocity (m/s), Manning-Strickler equation adapted according to Pistocchi and Pennington (2006)
    # This is Formula H1 rearranged: V = n^(-3/5) * Q^(2/5) * W^(-2/5) * S^(3/10)
    # Derived by substituting R = Q/(V*W) into v = (1/n)*R^(2/3)*S^(1/2) and
    # solving for V analytically.
    pts$V <- n ^ (-3/5) * pts$Q ^ (2/5) * W ^ (-2/5) * slope_m ^ (3/10)
    #River depth (m), power equation as derived by Pistocchi and Pennington (2006)
    # H = Q / (V * W) from the continuity equation (Q = V * A, where A = H * W
    # assuming a rectangular cross-section)
    pts$H <- pts$Q / (pts$V * W)
    #Shear velocity over distance D (m/s)
    # u* = sqrt(g * H * S), used to compute turbulent mixing coefficients below
    V_s <- sqrt(9.80665 * pts$H * slope_m)
    #Lateral dispersion coefficient (m2/s)
    # Dy = 0.6 * H * u* (Deng et al. empirical formula)
    Dy <- 0.6 * pts$H * V_s
    #Vertical dispersion coefficient (m2/s)
    # Ez = 0.07 * H * u* (Rutherford empirical formula)
    Ez <- 0.07 * pts$H * V_s
    #Length of vertical mixing zone for discharges into a stream from its side (m) (Sajer 2013)
    D_MIX_vert  <- (0.4 * pts$V * pts$H ^ 2) / Ez
    #Length of transverse mixing zone for discharges into a stream from its side (m) (Sajer 2013)
    D_MIX_trans <- (0.4 * W ^ 2 * pts$V) / Dy

    # --- Phase 5: Average velocity over reach (V_NXT) --------------------------
    #Average flow velocity over distance to next point
    #set Q_down: if next point is not sea, lake or junction, then Q_down==Q__NEW, else Q_down == Q__NEW of next point
    pts$V_NXT <- pts$V

    #// SLOW CODE
    # For non-lake, non-junction nodes, V_NXT is the average of this node's
    # velocity and the next node's velocity (linear interpolation along reach)
    loop_idx = which(!is.na(pts$ID_nxt) & pts$Down_type != "Hydro_Lake" & pts$Down_type != "JNCT")
    idx_next = match(pts$ID_nxt,pts$ID)
    V_nxt_tmp = pts$V[idx_next]
    pts$V_NXT[loop_idx] = ( pts$V[loop_idx] + V_nxt_tmp[loop_idx] ) / 2


    pts3 <- rbind(pts3,pts)
  }

  return(pts3)


}
