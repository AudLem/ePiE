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
# Purpose: Top-level orchestrator that (1) extracts flow data at each network
#   point (from either a gridded FLO1K raster or GeoGLOWS v2 per-segment GPKG)
#   and (2) computes derived hydraulic properties (velocity, depth, mixing
#   lengths) using Manning-Strickler.
#
# Parameters:
#   basin_data             - list containing the network points data frame
#                            ($pts) and other basin-level structures
#   flow_rast              - a terra/SpatRaster of gridded discharge values
#                            [m^3/s] (used when network_source = "hydrosheds")
#   discharge_gpkg_path    - path to a GeoGLOWS v2 discharge GeoPackage
#                            (used when network_source = "geoglows")
#   simulation_year        - integer year for GeoGLOWS column selection
#                            (e.g. 2020 selects columns y2020_mMM)
#   simulation_months      - integer vector of month(s) for GeoGLOWS column
#                            selection (e.g. c(9,10) for Sep-Oct). A single
#                            month selects that column directly; multiple
#                            months are aggregated via discharge_aggregation.
#   discharge_aggregation  - method to aggregate across multiple months:
#                            "mean" (default), "min", "max", or "specific"
#                            (uses first month only)
#   network_source         - "hydrosheds" (default) for FLO1K raster extraction,
#                            or "geoglows" for per-segment GPKG discharge
#
# Returns:
#   basin_data  - the input list with $pts updated to include Q, V, H,
#                 D_MIX_vert, D_MIX_trans, V_NXT, etc.
# --------------------------------------------------------------------------------
AddFlowToBasinData = function(basin_data,
                               flow_rast = NULL,
                               discharge_gpkg_path = NULL,
                               simulation_year = NULL,
                               simulation_months = NULL,
                               discharge_aggregation = "mean",
                               network_source = "hydrosheds"){

  pts = basin_data$pts

  # --- Select discharge source ------------------------------------------------
  if (network_source == "geoglows" && !is.null(discharge_gpkg_path)) {
    # GeoGLOWS v2 per-segment discharge: load GPKG, pick/aggregate monthly
    # columns, then map LINKNO -> Q for each network node
    pts = AddFlowFromGeoGLOWS(
      pts                    = pts,
      discharge_gpkg_path    = discharge_gpkg_path,
      simulation_year        = simulation_year,
      simulation_months      = simulation_months,
      discharge_aggregation  = discharge_aggregation
    )
  } else {
    # Existing HydroSHEDS / FLO1K raster extraction path (unchanged)
    pts = Add_new_flow_fast(pts = pts, flow_raster = flow_rast)
  }

  # --- Manning-Strickler hydraulic properties (same for both discharge sources) ---
  pts = Select_hydrology_fast2(pts)

  basin_data$pts = pts
  return(basin_data)
}

# --- AddFlowFromGeoGLOWS --------------------------------------------------------
# Purpose: Loads per-segment discharge from a GeoGLOWS v2 GeoPackage, selects
#   and optionally aggregates monthly Q columns, then assigns Q to each
#   network node via LINKNO (or ARCID -> LINKNO mapping).
#
# GeoGLOWS GPKG expected columns:
#   LINKNO  - integer segment identifier
#   ARCID   - (optional) HydroSHEDS ARCID for cross-mapping
#   yYYYY_mMM - monthly mean discharge columns, e.g. y2020_m09
#
# Column selection logic:
#   - Single simulation_months value: use column y{year}_m{MM} directly
#   - Multiple simulation_months: aggregate selected columns using
#     discharge_aggregation ("mean", "min", "max", or "specific")
#
# Node mapping logic (tried in order):
#   1. pts has LINKNO -> direct lookup
#   2. pts has ARCID AND GPKG has ARCID -> map ARCID -> LINKNO -> Q
#
# Parameters:
#   pts                   - data frame of network points (must have Pt_type,
#                           Down_type, line_node, basin_id, ID columns)
#   discharge_gpkg_path   - character path to the GeoGLOWS discharge GPKG
#   simulation_year       - integer year (e.g. 2020)
#   simulation_months     - integer vector of months (e.g. c(9,10) or 1)
#   discharge_aggregation - "mean", "min", "max", or "specific"
#
# Returns:
#   pts with a new column Q__NEW containing discharge values [m^3/s]
# --------------------------------------------------------------------------------
AddFlowFromGeoGLOWS = function(pts,
                                discharge_gpkg_path,
                                simulation_year,
                                simulation_months,
                                discharge_aggregation) {

  # --- Load GeoGLOWS discharge GeoPackage --------------------------------------
  discharge_sf <- sf::st_read(discharge_gpkg_path, quiet = TRUE)
  discharge_df <- sf::st_drop_geometry(discharge_sf)

  # --- Validate / default simulation_year --------------------------------------
  if (is.null(simulation_year)) {
    # Attempt to detect year from column names (pick the most recent year)
    year_cols <- regmatches(names(discharge_df), regexpr("y[0-9]{4}", names(discharge_df)))
    if (length(year_cols) == 0) {
      stop("GeoGLOWS GPKG contains no 'yYYYY_mMM' discharge columns and simulation_year is not provided.")
    }
    simulation_year <- max(as.integer(gsub("y", "", unique(year_cols))))
    message("GeoGLOWS: simulation_year not specified; using detected year ", simulation_year)
  }

  # --- Default simulation_months to all 12 months if not provided --------------
  if (is.null(simulation_months)) {
    simulation_months <- 1:12
    message("GeoGLOWS: simulation_months not specified; using annual aggregate (months 1-12)")
  }

  # --- Build column names for selected months ----------------------------------
  q_cols <- sprintf("y%04d_m%02d", simulation_year, simulation_months)
  missing <- q_cols[!q_cols %in% names(discharge_df)]
  if (length(missing) > 0) {
    stop(
      "GeoGLOWS discharge column(s) not found in GPKG: ",
      paste(missing, collapse = ", "),
      ". Available columns: ",
      paste(grep("^y[0-9]{4}_m[0-9]{2}$", names(discharge_df), value = TRUE),
            collapse = ", ")
    )
  }

  # --- Aggregate monthly columns into a single Q_segment value -----------------
  if (length(q_cols) == 1) {
    discharge_df$Q_segment <- discharge_df[[q_cols]]
  } else {
    q_matrix <- as.matrix(discharge_df[, q_cols, drop = FALSE])
    discharge_df$Q_segment <- switch(discharge_aggregation,
      mean     = rowMeans(q_matrix, na.rm = TRUE),
      min      = apply(q_matrix, 1, min,  na.rm = TRUE),
      max      = apply(q_matrix, 1, max,  na.rm = TRUE),
      specific = discharge_df[[q_cols[1]]],
      rowMeans(q_matrix, na.rm = TRUE)
    )
  }

  # --- Build lookup table: LINKNO -> Q_segment ---------------------------------
  if (!("LINKNO" %in% names(discharge_df))) {
    stop("GeoGLOWS GPKG must contain a 'LINKNO' column for segment identification.")
  }
  linkno_lookup <- stats::setNames(discharge_df$Q_segment, discharge_df$LINKNO)

  # --- Map Q to each network node ----------------------------------------------
  if ("LINKNO" %in% names(pts)) {
    # Direct lookup via LINKNO on network points
    pts$Q__NEW <- as.numeric(linkno_lookup[as.character(pts$LINKNO)])
  } else if ("ARCID" %in% names(pts) && "ARCID" %in% names(discharge_df)) {
    # Cross-map: ARCID (network points) -> LINKNO (GPKG) -> Q_segment
    arcid_to_linkno <- stats::setNames(discharge_df$LINKNO, discharge_df$ARCID)
    pts_linkno <- as.numeric(arcid_to_linkno[as.character(pts$ARCID)])
    pts$Q__NEW <- as.numeric(linkno_lookup[as.character(pts_linkno)])
  } else {
    stop(
      "Cannot map network points to GeoGLOWS segments. ",
      "Network points need a 'LINKNO' column, or both pts and GPKG need 'ARCID'."
    )
  }

  # --- Assign Q of line rather than point to monitoring / WWTP points ----------
  # that are upstream of junctions (same correction as Add_new_flow_fast)
  if ("Pt_type" %in% names(pts)) {
    loop_indices <- which(grepl("MONIT|WWTP|Agglomerations", pts$Pt_type))
    for (i in loop_indices) {
      if (!is.na(pts$Down_type[i]) && pts$Down_type[i] == "JNCT") {
        idx <- which(pts$ID == pts$line_node[i] & pts$basin_id == pts$basin_id[i])
        if (length(idx) > 0) pts$Q__NEW[i] <- pts$Q__NEW[idx]
      }
    }
  }

  return(pts)
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

  # --- Raster Presence Guard --------------------------------------------------
  if (is.null(flow_raster)) {
    pts$Q__NEW = NA_real_
    message("  Warning: No flow raster provided. Setting Q__NEW to NA.")
    return(pts)
  }

  # set projection
  crs = Get_LatLong_crs()

  # project pts
  p = sf::st_as_sf(pts,coords=c("x","y"),crs=crs)

  # add flow
  imported_raster = flow_raster
  terra::crs(imported_raster) = crs
  Q__NEW = terra::extract(imported_raster, p)

  # --- Extraction Guard -------------------------------------------------------
  # terra::extract() may return a different row count if points are outside
  # the raster extent. Guard against assignment mismatch.
  # ----------------------------------------------------------------------------
  if (nrow(Q__NEW) == nrow(pts)) {
    pts$Q__NEW = Q__NEW[,2]
  } else {
    pts$Q__NEW = NA_real_
    message("  Warning: terra::extract returned ", nrow(Q__NEW), " rows for ", nrow(pts), " points. Setting Q__NEW to NA.")
  }

  # assign Q of line rather than point to monitoring points that are upstream of junctions
  loop_indices = which(grepl("MONIT|WWTP|Agglomerations",pts$Pt_type))
  for (i in loop_indices) {
    if(!is.na(pts$Down_type[i]) && pts$Down_type[i]=="JNCT"){
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

    # Propagate Dist_down from the downstream neighbour where available
    distd_safety <- 0
    while (any(is.na(pts$Dist_down[nodistd]))) {
      prev_na <- sum(is.na(pts$Dist_down[nodistd]))
      for (i in nodistd) {
        if (!is.na(pts$ID_nxt[i])) {
          ds_idx <- match(pts$ID_nxt[i], pts$ID)
          if (!is.na(ds_idx) && !is.na(pts$Dist_down[ds_idx])) {
            pts$Dist_down[i] <- pts$Dist_down[ds_idx]
          }
        }
      }
      curr_na <- sum(is.na(pts$Dist_down[nodistd]))
      if (curr_na == prev_na) break
      distd_safety <- distd_safety + 1
      if (distd_safety > 50) {
        message("  Warning: Dist_down propagation did not converge for ", curr_na, " nodes. Setting to 0.")
        pts$Dist_down[nodistd][is.na(pts$Dist_down[nodistd])] <- 0
        break
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

    canal_override_idx <- integer(0)
    if ("Q_model_m3s" %in% names(pts)) {
      canal_override_idx <- which(!is.na(pts$Q_model_m3s))
      if (length(canal_override_idx) > 0) {
        pts$Q__NEW[canal_override_idx] <- pts$Q_model_m3s[canal_override_idx]
      }
    }

    # --- Phase 2: Propagate Q to zero-flow nodes -------------------------------
    # Rename extracted flow and remove temporary column
    pts$Q <- pts$Q__NEW
    pts$Q__NEW <- NULL

    # Replace NA flows with 0 so the propagation loops can handle them
    pts$Q[is.na(pts$Q)] <- 0
    if (length(canal_override_idx) > 0) {
      pts$Q[canal_override_idx] <- pts$Q_model_m3s[canal_override_idx]
    }
    # Identify all nodes with zero flow
    nf <- which(pts$Q==0)
    f <- length(nf)

    # Loop 2a: Fill from upstream — if all upstream nodes have flow, assign
    # the sum of upstream flows to this node.
    while (length(nf) > 0) {
      for (i in nf) {
        up_idx <- which(pts$ID_nxt == pts$ID[i])
        if (length(up_idx) > 0 && pts$Q[i] == 0 && !any(pts$Q[up_idx] == 0) && pts$Pt_type[i]!="START") {
          pts$Q[i] <- sum(pts$Q[up_idx])
          if (pts$Q[i] > 0) f <- f - 1
        }
      }
      if (f == length(nf)) {break}
      nf <- which(pts$Q==0)

    }

    # Loop 2b: Fill from downstream — for nodes that could not be filled
    # upstream (e.g. START points with no flow), use the downstream Q.
    while (length(nf) > 0) {
      for (i in nf) {
        ds_idx <- which(pts$ID == pts$ID_nxt[i])
        if (length(ds_idx) > 0 && pts$Q[i]==0 && any(pts$Q[ds_idx] != 0) && pts$Pt_type[i]!="MOUTH") {
          pts$Q[i] <- pts$Q[ds_idx[1]]
          if (pts$Q[i] > 0) f <- f - 1
        }
      }
      if (f == length(nf)) {break}
      nf <- which(pts$Q==0)
    }

    # Loop 2c: Last resort — try both upstream and downstream for any
    # remaining zero-flow nodes (complete isolated branches).
    while (length(nf) > 0) {
      for (i in nf) {
        up_idx <- which(pts$ID_nxt == pts$ID[i])
        ds_idx <- which(pts$ID == pts$ID_nxt[i])
        if (length(up_idx) > 0 && pts$Q[i]==0 && any(pts$Q[up_idx] != 0) && pts$Pt_type[i]!="START") {
          pts$Q[i] <- sum(pts$Q[up_idx])
          if (pts$Q[i] > 0) f <- f - 1
        } else if (length(ds_idx) > 0 && pts$Q[i]==0 && any(pts$Q[ds_idx] != 0) && pts$Pt_type[i]!="MOUTH") {
          pts$Q[i] <- pts$Q[ds_idx[1]]
          if (pts$Q[i] > 0) f <- f - 1
        }
      }
      if (f == length(nf)) {break} #if no updates were possible anymore, break
      nf <- which(pts$Q==0) #update vector with zero flow nodes
    }

    # If any node still has zero flow after all propagation attempts, use a
    # small fallback value rather than aborting.  This can happen when nodes
    # (e.g. agglomerations on canals) have no upstream/downstream neighbours
    # with Q data.
    zero_q <- which(pts$Q == 0)
    if (length(canal_override_idx) > 0) {
      zero_q <- setdiff(zero_q, canal_override_idx)
    }
    if (length(zero_q) > 0) {
      positive_q <- pts$Q[pts$Q > 0]
      if (length(positive_q) > 0) {
        message("  Warning: ", length(zero_q), " nodes still have Q=0 after propagation. Using median Q fallback.")
        pts$Q[zero_q] <- stats::median(positive_q, na.rm = TRUE)
      } else {
        message("  Warning: No positive Q values found in basin. Using small fallback Q = 0.001 m^3/s")
        pts$Q[zero_q] <- 0.001
      }
    }

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

    # If any node still has zero slope, use a small fallback
    zero_slope <- which(pts$slope == 0)
    if (length(zero_slope) > 0) {
      positive_slope <- pts$slope[pts$slope > 0]
      if (length(positive_slope) > 0) {
        message("  Warning: ", length(zero_slope), " nodes still have slope=0 after propagation. Using median slope fallback.")
        pts$slope[zero_slope] <- stats::median(positive_slope, na.rm = TRUE)
      } else {
        message("  Warning: No positive slope values found in basin. Using small fallback slope = 0.001")
        pts$slope[zero_slope] <- 0.001
      }
    }
    if (all(pts$slope == 0)) pts$slope <- 0.001

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
