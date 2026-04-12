# ==============================================================================
# Set_local_parameters_custom_removal_fast3
# ==============================================================================
# Purpose:
#   Set up all chemical-specific local parameters for a single substance
#   (indexed by chem_ii) across the river network. This includes:
#     1. Environmental default parameters (temperature, pH, sediment, etc.)
#     2. WWTP emission and removal calculations (SimpleTreat or custom)
#     3. Tertiary treatment removal (N, P, UV, chlorination, O3, sand/micro filtration)
#     4. Chemical- and environment-dependent fate parameters:
#        ionisation fraction, partition coefficients, biodegradation, hydrolysis,
#        photolysis, sediment-water exchange, volatilization
#     5. Total dissipation rate (k) for each network node
#
# Parameters:
#   pts     - data.frame of point sources (WWTPs, agglomerations, junctions)
#             Must contain columns: Pt_type, T_AIR, pH, Wind, H, f_STP,
#             rptMStateK, uwwLoadEnt, uwwCapacit, uwwPrimary, uwwSeconda,
#             f_direct, ID, ID_nxt, basin_id, Down_type, Freq, HL_ID_new
#             NOTE: column 'f_direct' (lowercase) is expected here. Historical
#             versions used 'F_direct' (uppercase) — verify column names in pts.
#   HL      - data.frame of hydro-lake nodes (may have 0 rows if no lakes)
#   cons    - data.frame of per-country consumption values. Column naming is
#             inconsistent across data sources: some use 'cnt', others 'country'.
#             NOTE: The code normalises 'country' -> 'cnt' to handle this.
#             Columns include one column per API name with consumption in kg/yr.
#   chem    - data.frame of substance properties (one row per API). Contains
#             physicochemical parameters (MW, Pv, S, pKa, KOC, KOW, etc.),
#             degradation rates, and custom WWTP removal fractions.
#   chem_ii - integer index into chem identifying which substance to process
#
# Return:
#   list(pts, hl) — the updated pts and HL data.frames with all local
#   chemical parameters attached as new columns
#
# Reference framework: Keller et al. (2014), version 3 of the ePiE model.
# The "custom_removal" variant allows overriding SimpleTreat with user-specified
# primary/secondary/tertiary removal fractions.
# ==============================================================================

Set_local_parameters_custom_removal_fast3 = function(pts,HL,cons,chem,chem_ii){

  # --- Normalise Pt_type labels ------------------------------------------------
  # Standardise agglomeration variants to a single label "Agglomerations"
  pts$Pt_type[tolower(pts$Pt_type) == "agglomeration" | pts$Pt_type == "Agglomerations"] <- "Agglomerations"

  # --- Fix column name inconsistency in consumption data ------------------------
  # BUG NOTE: Some consumption datasets use 'country' while the code expects
  # 'cnt'. We normalise here. See also: cons$cnt vs cons$country references
  # below that also guard against this inconsistency.
  if ("country" %in% names(cons) && !("cnt" %in% names(cons))) {
    names(cons)[names(cons) == "country"] <- "cnt"
  }

  # --- Extract consumption data for the current substance -----------------------
  chem_name = chem$API[chem_ii]

  # Select the country/region column plus the column matching the current API
  # BUG NOTE: This fallback to 'country' is a safety net in case the rename
  # above did not apply (e.g., cons was passed by reference elsewhere).
  if(any(grepl("cnt",names(cons)))){
    cons_chem = cons[,c("cnt",chem_name)]
  }else if(any(grepl("country",names(cons)))){
    cons_chem = cons[,c("country",chem_name)]
  }

  # add consumption data prodrugs, if relevant
  # If the current substance has a metabolite (prodrug), add its consumption column
  if(!is.na(chem$API_metab)){
    cons_chem$metab = cons[,which(names(cons)==chem$API_metab)]
  }

  # chem_ii chem idx data
  # Resolve the row index in chem for the current substance (should equal chem_ii)
  chem_idx = which(chem$API==chem_name)

  # --- Setting local parameters with (default) values relevant for concentration estimations ----

  #Geographically explicit parameters
  pts$T_AIR       <- pts$T_AIR+273.15            #air temperature in K
  default_pH      <- 7.4                        #pH of local surface water, proposed default pH of 7.4 (Meybeck et al 1995)
  if(is.null(pts$pH)) pts$pH = default_pH #pH of local surface water, proposed default pH of 7.4 (Meybeck et al 1995)
  pts$pH[is.na(pts$pH)] = default_pH
  if(nrow(HL)!=0) {
    HL$T_AIR <- HL$T_AIR+273.15   #air temperature in K
    if(is.null(HL$pH)) HL$pH = default_pH
    HL$pH[is.na(HL$pH)] = default_pH
  }

  #Default values (should be assigned as new fields to pts and HL when available)
  pts$BACT_sw     <- 1E6         #bacterial density in surface water (cells/L), range 1E6-1E9 (REF)
  pts$BACT_sed    <- 1E5         #bacterial density in sediments (cells/L), assumed factor 10 lower than surface waters
  pts$T_sw        <- 285         #local water temperature (K), for now: 285 K (ECHA 2016)
  pts$f_light     <- 0.5         #local fraction of light per day, proposed 0.5 default
  pts$C_susp      <- 0.015E-3    #concentration suspended solids in water (kg*L-1), proposed default value based on Humbert et al. (2011)
  pts$C_DOC       <- 0.005E-3    #concentration DOC in water (kg*L-1), proposed default value based on Asselman (1997)
  pts$H_sed       <- 0.03        #mixed depth of sediment column relevant for exchange (m), proposed default value based on Fantke et al (2016)
  pts$v_mw_wsd    <- 2.778E-6    #partial mass transfer coefficient at water side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
  pts$v_msd_wsd   <- 2.778E-8    #partial mass transfer coefficient at sediment side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
  pts$poros       <- 0.8         #porosity of the sediment (Lwater/Lsed), proposed default value based on Paterson & Mackay (1995) & Honti et al (2016)
  pts$rho_sd      <- 2.33165     #mineral density of sediment (kg*L-1), proposed default value based on Fantke et al (2016) and Honti et al (2016)
  pts$v_set       <- 2.89E-5     #settling velocity of suspended particles (m*s-1), proposed default value based on den Hollander et al (2004)
  pts$v_sd_acc    <- 0           #net sediment accumulation rate in water (m*s-1), no proposed default value yet
  pts$fOC_susp    <- 0.1         #mass fraction organic carbon in suspended solids (-), proposed default value based on Fantke et al (2016)
  pts$fOC_sd      <- 0.05        #mass fraction organic carbon in sediments (-), proposed default value based on Fantke et al (2016)

  # --- Assign same environmental defaults to lake nodes -------------------------
  if (nrow(HL)!=0) {
    HL$BACT_sw     <- 1E6                              #bacterial density in surface water (cells/L), range 1E6-1E9 (REF)
    HL$BACT_sed    <- 1E5                              #bacterial density in sediments (cells/L), same assumed as surface waters
    HL$T_sw        <- 285                              #local water temperature (K), for now: 285 K (ECHA 2016)
    HL$f_light     <- 0.5                              #local fraction of light per day, proposed 0.5 default
    HL$C_OH_w      <- 1e-18                            #concentration OH-radicals in water (M), summer day, mid-latitude range 10e-18 - 10e-16 M (Latch et al 2003)
    HL$C_O2_w      <- 1e-14                            #concentration of singlet oxygen in water (M), summer day, mid-latitude range 7e-11 - 11e-11 M (Latch et al 2003)
    HL$C_susp      <- 0.015E-3                         #concentration suspended solids in water (kg*L-1), proposed default value based on Humbert et al. (2011)
    HL$C_DOC       <- 0.005E-3                         #concentration DOC in water (kg*L-1), proposed default value based on Asselman (1997)
    HL$H_sed       <- 0.03                             #mixed depth of sediment column relevant for exchange (m), proposed default value based on Fantke et al (2016)
    HL$v_mw_wsd    <- 2.778E-6                         #partial mass transfer coefficient at water side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
    HL$v_msd_wsd   <- 2.778E-8                         #partial mass transfer coefficient at sediment side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
    HL$poros       <- 0.8                              #porosity of the sediment (Lwater/Lsed), proposed default value based on Paterson & Mackay (1995) & Honti et al (2016)
    HL$rho_sd      <- 2.1663                           #mineral density of sediment (kg*L-1), proposed default value based on Fantke et al (2016)
    HL$v_set       <- 2.89E-5                          #settling velocity of suspended particles (m*s-1), proposed default value based on den Hollander et al (2004)
    HL$v_sd_acc    <- 0                                #net sediment accumulation rate in water (m*s-1), no proposed default value yet
    HL$fOC_susp    <- 0.1                              #mass fraction organic carbon in suspended solids (-), proposed default value based on Fantke et al (2016)
    HL$fOC_sd      <- 0.05                             #mass fraction organic carbon in sediments (-), proposed default value based on Fantke et al (2016)
    if(is.null(HL$H_av)) HL$H_av = HL$Depth_avg        #if variable does not exist find in via Depth_avg
    HL$Wind[is.na(HL$Wind)] = mean(HL$Wind,na.rm=TRUE) #remove NAs from wind variable

  }

  #Setting up local parameters with (default) values relevant for emission estimations from WWTPs
  #size of WWTP (preferably load entering, else capacity, else default of SimpleTreat) (PE)
  #needed for calculation of removal fractions, but later return NA on sludge concentrations if default is used
  # Determine the inhabitant equivalent (PE) for each WWTP node, used by SimpleTreat
  pts$Inh=ifelse(is.na(pts$uwwLoadEnt),NA,ifelse(pts$uwwLoadEnt!=0,pts$uwwLoadEnt,ifelse(pts$uwwCapacit!=0,pts$uwwCapacit,10000)))

  # --- Emission calculations water----
  #first calculate WWTP inflow of chem_idx
  # Two branches: without prodrug (simple) or with prodrug (combined metabolism)
  if(is.null(chem$API_metab)) chem$API_metab = NA
  if(is.na(chem$API_metab[chem_idx])){
    # No prodrug: WWTP inflow = consumption * usage fraction * connection rate
    pts$E_in <- ifelse(pts$Pt_type=="WWTP",
                       (cons_chem[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx])) *pts$f_STP,
                        NA) #emission towards WWTP (kg/year)
  #first calculate WWTP inflow of chem_idx and its prodrugs chem_zz
  }else{
    # Prodrug: WWTP inflow = (parent consumption * usage fraction + metabolite consumption * metabolism fraction) * connection rate
    chem_zz <- ifelse(is.na(chem$API_metab[chem_idx]),1,which(chem$API==chem$API_metab[chem_idx])) #ID of prodrug
    pts$E_in <- ifelse(pts$Pt_type=="WWTP",
                       (cons[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx]) +
                          cons[match(pts$rptMStateK,cons$cnt),"metab"]*(chem$metab[chem_idx])) *
                         pts$f_STP,NA) #emission towards WWTP (kg/year)
  }

  # --- WWTP removal: SimpleTreat vs. custom removal ----------------------------
  # Calculate removal in WWTPs.
  # If custom_wwtp_removal = NA, SimpleTreat is used.
  # If custom_wwtp_removal != NA, custom_wwtp_removal value is used directly as removal.
  # custom_wwtp_removal is given in values 0 to 1 in main script.

  pts$f_rem_WWTP = NA
  idx_WWTPs = which(pts$Pt_type=="WWTP")
  # Decide whether to use SimpleTreat: if either primary or secondary custom removal is NA
  useSimpleTreat4_0 = (is.na(chem$custom_wwtp_primary_removal[chem_idx])) | (is.na(chem$custom_wwtp_secondary_removal[chem_idx]))

  # WWTPs first and secondary treatment (with SimpleTreat)
  if(useSimpleTreat4_0){
    # Loop over each WWTP node and compute removal via SimpleTreat 4.0 model
    for (j in idx_WWTPs) {
      if (pts$Pt_type[j]=="WWTP") {
        #if primary and secondary removal rate is unknown, SimpleTreat 4.0 is used.
        #Pay attention on the condition pts$f_STP[j]==0. If this is valid, no population is connected and there is not WWTP inflow. THerefore pts$f_rem_WWTP[j] = 0 to avoid infinities in SimpleTreat
        pts$f_rem_WWTP[j] <-  ifelse(pts$f_STP[j]==0,0,
                                     SimpleTreat4_0(chem$class[chem_idx],chem$MW[chem_idx],chem$Pv[chem_idx],chem$S[chem_idx],chem$pKa[chem_idx],
                                             chem$Kp_ps_n[chem_idx],chem$Kp_as_n[chem_idx],chem$k_bio_wwtp_n[chem_idx],pts$T_AIR[j],
                                             pts$Wind[j],pts$Inh[j],pts$E_in[j]/365,pts$uwwPrimary[j],pts$uwwSeconda[j])$f_rem)
      }else{
        pts$f_rem_WWTP[j] <- NA  #if the "i" point is not a WWTP put removal = NA
      }
    }

  #if primary and secondary removal rate is known, custom removal values are used (without SimpleTreat)
  }else{
    # Apply user-specified primary and secondary removal fractions sequentially.
    # f_leftover_WWTP tracks the fraction remaining after each treatment stage.
    pts$f_rem_WWTP[pts$Pt_type=="WWTP"] = 0;
    pts$f_leftover_WWTP = NA
    pts$f_leftover_WWTP[pts$Pt_type=="WWTP"] = 1

    # Primary treatment: uwwPrimary == -1 indicates primary treatment is present
    idx_Primary = which(pts$uwwPrimary==-1)
    pts$f_leftover_WWTP[idx_Primary] = 1-chem$custom_wwtp_primary_removal[chem_idx]

    # Secondary treatment: uwwSeconda == -1 indicates secondary treatment is present
    idx_Secondary = which(pts$uwwSeconda==-1)
    pts$f_leftover_WWTP[idx_Secondary] =  pts$f_leftover_WWTP[idx_Secondary] * (1-chem$custom_wwtp_secondary_removal[chem_idx])

    pts$f_rem_WWTP[pts$Pt_type=="WWTP"] = 1 - pts$f_leftover_WWTP[pts$Pt_type=="WWTP"]
  }

  #print(pts$f_rem_WWTP[pts$Pt_type=="WWTP"])
  # Recompute leftover fraction after primary+secondary for the tertiary step below
  pts$f_leftover_WWTP = NA
  pts$f_leftover_WWTP[pts$Pt_type=="WWTP"] = 1-pts$f_rem_WWTP[pts$Pt_type=="WWTP"]
  #print(pts$f_rem_WWTP[pts$Pt_type=="WWTP"])
  #print(pts$f_leftover_WWTP[pts$Pt_type=="WWTP"])
  #stop("check!")

  # --- Tertiary treatment removal -----------------------------------------------
  # check if tertiary removals are provided, else set to 0
  # Each tertiary treatment type has a corresponding custom removal fraction in chem
  # and a flag column in pts indicating whether that treatment is present (-1 = yes)
  checkCols = c("custom_wwtp_N_removal","custom_wwtp_P_removal",
                "custom_wwtp_UV_removal","custom_wwtp_Cl_removal",
                "custom_wwtp_O3_removal","custom_wwtp_sandfilter_removal",
                "custom_wwtp_microfilter_removal")
  for(cc in checkCols) chem = CheckIfColumnExistsCreateEmpty(chem,cc,0)

  # Ensure all treatment flag columns exist in pts and replace NAs with 0
  wwtp_treatment_cols <- c("uwwNRemova","uwwPRemova","uwwUV","uwwChlorin","uwwOzonati","uwwSandFil","uwwMicroFi")
  for(tc in wwtp_treatment_cols) {
    if(!(tc %in% names(pts))) pts[[tc]] <- 0
    pts[[tc]][is.na(pts[[tc]])] <- 0
  }

  # Nitrogen removal: additive (increases total removal directly)
  idx_rm = which(pts$uwwNRemova==-1)
  pts$f_rem_WWTP[idx_rm] = pts$f_rem_WWTP[idx_rm] + chem$custom_wwtp_N_removal[chem_idx]

  # Phosphorus removal: multiplicative on leftover fraction
  idx_rm = which(pts$uwwPRemova==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_P_removal[chem_idx])

  # UV disinfection: multiplicative on leftover fraction
  idx_rm = which(pts$uwwUV==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_UV_removal[chem_idx])

  # Chlorination: multiplicative on leftover fraction
  idx_rm = which(pts$uwwChlorin==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_Cl_removal[chem_idx])

  # Ozonation: multiplicative on leftover fraction
  idx_rm = which(pts$uwwOzonati==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_O3_removal[chem_idx])

  # Sand filtration: multiplicative on leftover fraction
  idx_rm = which(pts$uwwSandFil==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_sandfilter_removal[chem_idx])

  # Micro filtration: multiplicative on leftover fraction
  idx_rm = which(pts$uwwMicroFi==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_microfilter_removal[chem_idx])

  # Final removal: 1 - leftover, clamped to [0, 1]
  pts$f_rem_WWTP[pts$Pt_type=="WWTP"] = 1-pts$f_leftover_WWTP[pts$Pt_type=="WWTP"]
  pts$f_rem_WWTP[pts$f_rem_WWTP>1] = 1
  pts$f_rem_WWTP[pts$f_rem_WWTP<0] = 0
  pts$f_leftover_WWTP = NULL
  #print(cbind(pts$uwwPrimary[pts$Pt_type=="WWTP"],pts$uwwSeconda[pts$Pt_type=="WWTP"],pts$f_rem_WWTP[pts$Pt_type=="WWTP"]))
  #stop("check!")

  # --- Surface water emissions from WWTPs and agglomerations --------------------
  # Emission towards surface water from WWTPs and from agglomerations (total chemical: dissolved & associated) (kg/yr)
  # For WWTPs: E_w = E_in * (1 - f_rem_WWTP)
  # For agglomerations: E_w = consumption * usage_fraction * f_direct
  #   where f_direct is the fraction discharged directly (unconnected households)
  # BUG NOTE: Column 'f_direct' (lowercase) is used here. Historical versions of
  #   the input data used 'F_direct' (uppercase). Verify pts column names match.
  # TODO(MULTI-PATHOGEN): For pathogens, the emission calculation will differ
  #   (no metabolism/prodrug concept; emissions based on infection prevalence
  #   and shedding rates rather than consumption data).
  if(is.na(chem$API_metab[chem_idx])){
    pts$E_w <- ifelse(pts$Pt_type=="WWTP",pts$E_in*(1-pts$f_rem_WWTP),
                      ifelse(pts$Pt_type=="Agglomerations",
                             (cons[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx])) * pts$f_direct,0))
  }else{
    chem_zz <- ifelse(is.na(chem$API_metab[chem_idx]),1,which(chem$API==chem$API_metab[chem_idx])) #ID of prodrug
    pts$E_w <- ifelse(pts$Pt_type=="WWTP",pts$E_in*(1-pts$f_rem_WWTP),
                      ifelse(pts$Pt_type=="Agglomerations",
                             (cons[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx]) +
                                cons[match(pts$rptMStateK,cons$cnt),"metab"]*chem$metab[chem_idx]) *
                               pts$f_direct,0))
  }

  #Observe that only the fraction F_direct is discharged directly from agglomeration to surface waters (This is the fraction of not connected households)

  # --- Aggregate emissions into lake nodes --------------------------------------
  #Add emissions from WWTPs / agglomerations to lakes
  if (nrow(HL)!=0) {
    pts$Hylak_id <- pts$HL_ID_new
    pts$HL_ID_new <- NULL
    HL$E_in = NA

    # Sum all point-source emissions that drain into each lake
    if (nrow(HL)!=0) {
      for (j in 1:nrow(HL)) {
        HL$E_in[j] = sum(pts$E_w[which(pts$Hylak_id==HL$Hylak_id[j])],na.rm=TRUE)
      }
    }
  }

  # --- (Re)setting local variables to be adapted per API ----
  pts$E_up            <- 0                            #emission to surface water from upstream sources (kg*yr-1)
  pts$E_w_NXT         <- 0                            #contribution to emission at next downstream point (kg/yr)
  pts$C_w             <- NA                           #total concentration in surface water (ug/L)
  pts$C_sd            <- NA                           #total concentration in sediment (ug/kg)
  pts$fin             <- 0                            #tracking counter (0/1)
  pts$upcount         <- pts$Freq                     #tracking number of upstream points

  if (nrow(HL)!=0) {
    HL$C_w          <- NA
    HL$C_sd         <- NA
    HL$fin          <- 0
  }

  # --- Chemical- and environment-dependent characteristics ----------------------
  # The model distinguishes two ionisation species: neutral (_n) and ionised (_alt).
  # For each property below, the effective value is a weighted sum:
  #   value = fn * value_n + (1 - fn) * value_alt
  # where fn is the neutral fraction (pH- and pKa-dependent).

  # --- Ionisation: neutral fraction fn ------------------------------------------
  # Governing equations (Henderson-Hasselbalch):
  #   neutral molecule: fn = 1
  #   acid:             fn = 1 / (1 + 10^(pH - pKa))
  #   base:             fn = 1 / (1 + 10^(pKa - pH))
  #neutral fraction
  # pts$fn <- ifelse(chem$class[chem_idx]=="neutral",1,
  #                ifelse(chem$class[chem_idx]=="acid",1/(1+10^(pts$pH-chem$pKa[chem_idx])),
  #                       ifelse(chem$class[chem_idx]=="base",1/(1+10^(chem$pKa[chem_idx]-pts$pH)),NA)))
  if(chem$class[chem_idx]=="neutral"){
    pts$fn = 1
  } else if(chem$class[chem_idx]=="acid"){
    pts$fn = 1/(1+10^(pts$pH-chem$pKa[chem_idx]))
  } else if(chem$class[chem_idx]=="base"){
    pts$fn = 1/(1+10^(chem$pKa[chem_idx]-pts$pH))
  } else {
    pts$fn = NA
  }

  if (nrow(HL)!=0){
    #  HL$fn <- ifelse(chem$class[chem_idx]=="neutral",1,
    #                                  ifelse(chem$class[chem_idx]=="acid",1/(1+10^(HL$pH-chem$pKa[chem_idx])),
    #                                         ifelse(chem$class[chem_idx]=="base",1/(1+10^(chem$pKa[chem_idx]-HL$pH)),NA)))
    if(chem$class[chem_idx]=="neutral"){
      HL$fn = 1
    } else if(chem$class[chem_idx]=="acid"){
      HL$fn = 1/(1+10^(HL$pH-chem$pKa[chem_idx]))
    } else if(chem$class[chem_idx]=="base"){
      HL$fn = 1/(1+10^(chem$pKa[chem_idx]-HL$pH))
    } else {
      HL$fn = NA
    }
  }

  # --- Partition coefficients: ensure chem columns exist ------------------------
  # check additional chem columns, remove these from the default inputs
  # If a chem column is missing, create it filled with NA so the fallback logic works
  checkCols = c("Kp_susp_n","Kp_susp_alt","Kp_DOC_n","Kp_DOC_alt","Kp_sd_n","Kp_sd_alt","k_bio_sd1_n","k_bio_sd1_alt","k_hydro_sd_n","k_hydro_sd_alt")
  for(cc in checkCols) chem = CheckIfColumnExistsCreateEmpty(chem,cc,NA)


  # --- Partition coefficient: suspended solids (Kp_susp) -------------------------
  # Governing equation (fallback): Kp_susp = KOC * fOC_susp
  # If a user-specified Kp_susp is available (not NA), use it directly.
  #local (pH-dependent) partition coefficients
  if (is.na(chem$Kp_susp_n[chem_idx])) {
    pts$Kp_susp_n <- chem$KOC_n[chem_idx] * pts$fOC_susp
    if (nrow(HL)!=0) HL$Kp_susp_n <- chem$KOC_n[chem_idx] * HL$fOC_susp
  } else {
    pts$Kp_susp_n <- chem$Kp_susp_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_susp_n <- chem$Kp_susp_n[chem_idx]
  }

  if (is.na(chem$Kp_susp_alt[chem_idx])) {
    pts$Kp_susp_alt <- chem$KOC_alt[chem_idx] * pts$fOC_susp
    if (nrow(HL)!=0) HL$Kp_susp_alt <- chem$KOC_alt[chem_idx] * HL$fOC_susp
  } else {
    pts$Kp_susp_alt <- chem$Kp_susp_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_susp_alt <- chem$Kp_susp_alt[chem_idx]
  }

  # --- Partition coefficient: dissolved organic carbon (Kp_DOC) ------------------
  # Governing equation (fallback): Kp_DOC = 0.08 * KOW
  # The factor 0.08 is an empirical relationship from Burkhard (2000).
  if (is.na(chem$Kp_DOC_n[chem_idx])) {
    pts$Kp_DOC_n <- 0.08 * chem$KOW_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_n <- 0.08 * chem$KOW_n[chem_idx]
  } else {
    pts$Kp_DOC_n <- chem$Kp_DOC_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_n <- chem$Kp_DOC_n[chem_idx]
  }

  if (is.na(chem$Kp_DOC_alt[chem_idx])) {
    pts$Kp_DOC_alt <- 0.08 * chem$KOW_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_alt <- 0.08 * chem$KOW_alt[chem_idx]
  } else {
    pts$Kp_DOC_alt <- chem$Kp_DOC_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_alt <- chem$Kp_DOC_alt[chem_idx]
  }

  # --- Partition coefficient: sediment (Kp_sd) ----------------------------------
  # Governing equation (fallback): Kp_sd = KOC * fOC_sd
  #local partitioning to sediment (if NA, based on KOC and fOC sediments)
  if (is.na(chem$Kp_sd_n[chem_idx])) {
    pts$Kp_sd_n <- chem$KOC_n[chem_idx] * pts$fOC_sd
    if (nrow(HL)!=0) HL$Kp_sd_n <- chem$KOC_n[chem_idx] * HL$fOC_sd
  } else {
    pts$Kp_sd_n <- chem$Kp_sd_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_sd_n <- chem$Kp_sd_n[chem_idx]
  }

  if (is.na(chem$Kp_sd_alt[chem_idx])) {
    pts$Kp_sd_alt <- chem$KOC_alt[chem_idx] * pts$fOC_sd
    if (nrow(HL)!=0) HL$Kp_sd_alt <- chem$KOC_alt[chem_idx] * HL$fOC_sd
  } else {
    pts$Kp_sd_alt <- chem$Kp_sd_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_sd_alt <- chem$Kp_sd_alt[chem_idx]
  }

  # --- Fraction truly dissolved in water and sediment ----------------------------
  # Governing equation (water):
  #   f_diss = 1 / (1 + Kp_susp * C_susp + Kp_DOC * C_DOC)
  # Governing equation (sediment pore water):
  #   f_diss_sed = 1 / (1 + Kp_sd * rho_sd * (1 - poros) / poros)
  #local fraction truly dissolved (-)
  pts$f_diss_n <- 1 / (1 + pts$Kp_susp_n * pts$C_susp + pts$Kp_DOC_n * pts$C_DOC)
  pts$f_diss_alt <- 1 / (1 + pts$Kp_susp_alt * pts$C_susp + pts$Kp_DOC_alt * pts$C_DOC)
  if (nrow(HL)!=0) {
    HL$f_diss_n <- 1 / (1 + HL$Kp_susp_n * HL$C_susp + HL$Kp_DOC_n * HL$C_DOC)
    HL$f_diss_alt <- 1 / (1 + HL$Kp_susp_alt * HL$C_susp + HL$Kp_DOC_alt * HL$C_DOC)
  }

  pts$f_diss_sed_n <- 1 / (1 + pts$Kp_sd_n * pts$rho_sd * ((1 - pts$poros) / pts$poros))
  pts$f_diss_sed_alt <- 1 / (1 + pts$Kp_sd_alt * pts$rho_sd * ((1 - pts$poros) / pts$poros))
  if (nrow(HL)!=0) {
    HL$f_diss_sed_n <- 1 / (1 + HL$Kp_sd_n * HL$rho_sd * ((1 - HL$poros) / HL$poros))
    HL$f_diss_sed_alt <- 1 / (1 + HL$Kp_sd_alt * HL$rho_sd * ((1 - HL$poros) / HL$poros))
  }

  # --- Biodegradation rate in surface water (k_bio_w) ---------------------------
  # Governing equation:
  #   k_bio_w = fn * (k_bio_sw2_n * BACT_sw * f_diss_n * 2^((T_sw - T_ref_n)/10))
  #           + (1-fn) * (k_bio_sw2_alt * BACT_sw * f_diss_alt * 2^((T_sw - T_ref_alt)/10))
  # The Q10 temperature correction (2^(dT/10)) assumes doubling per 10 K increase.
  # BACT_sw is bacterial density; k_bio_sw2 is the 2nd-order rate constant per cell.
  # TODO(MULTI-PATHOGEN): Pathogen inactivation is modelled separately in
  #   Process_formulas.R (calc_temp_decay). This chemical biodegradation block
  #   does not apply to pathogens.
  #pseudo-1st order biodegradation rate constant in surface water (s-1) (homogeneous distribution of bacteria through the water column assumed (no depth-dependence))
  pts$k_bio_w <- pts$fn * (chem$k_bio_sw2_n[chem_idx] * pts$BACT_sw * pts$f_diss_n * 2 ^ ((pts$T_sw - chem$T_bio_sw_n[chem_idx]) / 10)) +
    (1 - pts$fn) * (chem$k_bio_sw2_alt[chem_idx] * pts$BACT_sw * pts$f_diss_alt * 2 ^ ((pts$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10))

  if (nrow(HL)!=0) HL$k_bio_w <- HL$fn * (chem$k_bio_sw2_n[chem_idx] * HL$BACT_sw * HL$f_diss_n * 2 ^ ((HL$T_sw - chem$T_bio_sw_n[chem_idx]) / 10)) +
    (1 - HL$fn) * (chem$k_bio_sw2_alt[chem_idx] * HL$BACT_sw * HL$f_diss_alt * 2 ^ ((HL$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10))

  # --- Biodegradation rate in sediment (k_bio_sd) -------------------------------
  # Governing equation (fallback if k_bio_sd1 is NA):
  #   k_bio_sd = k_bio_sw2 * BACT_sed * f_diss_sed * Q10_correction
  # If k_bio_sd1 is provided, use it directly with its own reference temperature.
  #pseudo-1st order biodegradation rate constant in sediment (s-1)
  pts$k_bio_sd_n <- ifelse(is.na(chem$k_bio_sd1_n[chem_idx]),chem$k_bio_sw2_n[chem_idx] * pts$BACT_sed * pts$f_diss_sed_n * 2 ^ ((pts$T_sw - chem$T_bio_sw_n[chem_idx]) / 10),
                           chem$k_bio_sd1_n[chem_idx] * pts$f_diss_sed_n * 2 ^ ((pts$T_sw - chem$T_bio_sd_n[chem_idx]) / 10))
  pts$k_bio_sd_alt <- ifelse(is.na(chem$k_bio_sd1_alt[chem_idx]),chem$k_bio_sw2_alt[chem_idx] * pts$BACT_sed * pts$f_diss_sed_alt * 2 ^ ((pts$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10),
                             chem$k_bio_sd1_alt[chem_idx] * pts$f_diss_sed_alt * 2 ^ ((pts$T_sw - chem$T_bio_sd_alt[chem_idx]) / 10))
  # Weighted by ionisation fractions
  pts$k_bio_sd <- pts$fn * pts$k_bio_sd_n + (1 - pts$fn) * pts$k_bio_sd_alt

  if (nrow(HL)!=0) {
    HL$k_bio_sd_n <- ifelse(is.na(chem$k_bio_sd1_n[chem_idx]),chem$k_bio_sw2_n[chem_idx] * HL$BACT_sed * HL$f_diss_sed_n * 2 ^ ((HL$T_sw - chem$T_bio_sw_n[chem_idx]) / 10),
                            chem$k_bio_sd1_n[chem_idx] * HL$f_diss_sed_n * 2 ^ ((HL$T_sw - chem$T_bio_sd_n[chem_idx]) / 10))
    HL$k_bio_sd_alt <- ifelse(is.na(chem$k_bio_sd1_alt[chem_idx]),chem$k_bio_sw2_alt[chem_idx] * HL$BACT_sed * HL$f_diss_sed_alt * 2 ^ ((HL$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10),
                              chem$k_bio_sd1_alt[chem_idx] * HL$f_diss_sed_alt * 2 ^ ((HL$T_sw - chem$T_bio_sd_alt[chem_idx]) / 10))
    HL$k_bio_sd <- HL$fn * HL$k_bio_sd_n + (1 - HL$fn) * HL$k_bio_sd_alt
  }

  # --- Hydrolysis rate in surface water (k_hydro_w) -----------------------------
  # Governing equation:
  #   k_hydro_w = fn * (k_hydro_sw_n * Q10 * f_diss_n) + (1-fn) * (k_hydro_sw_alt * Q10 * f_diss_alt)
  #1st order hydrolysis rate constant in water (s-1)
  pts$k_hydro_w <- pts$fn * (chem$k_hydro_sw_n[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * pts$f_diss_n) +
    (1 - pts$fn) * (chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * pts$f_diss_alt)

  if (nrow(HL)!=0) HL$k_hydro_w <- HL$fn * (chem$k_hydro_sw_n[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * HL$f_diss_n) +
    (1 - HL$fn) * (chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * HL$f_diss_alt)

  # --- Hydrolysis rate in sediment (k_hydro_sd) ---------------------------------
  # Governing equation (fallback): uses surface water hydrolysis rate if no
  # sediment-specific value is given. Assumes equal temperature in water and sediment.
  #1st order hydrolysis rate constant in sediment (s-1) (assumption of equal temperature in surface water and sediment below it)
  pts$k_hydro_sd_n <- ifelse(is.na(chem$k_hydro_sd_n[chem_idx]), chem$k_hydro_sw_n[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * pts$f_diss_sed_n, chem$k_hydro_sd_n[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sd_n[chem_idx]) / 10) * pts$f_diss_sed_n)
  pts$k_hydro_sd_alt <- ifelse(is.na(chem$k_hydro_sd_alt[chem_idx]), chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * pts$f_diss_sed_alt, chem$k_hydro_sd_alt[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sd_alt[chem_idx]) / 10) * pts$f_diss_sed_alt)
  # Weighted by ionisation fractions
  pts$k_hydro_sd <- pts$fn * pts$k_hydro_sd_n + (1 - pts$fn) * pts$k_hydro_sd_alt

  if (nrow(HL)!=0) {
    HL$k_hydro_sd_n <- ifelse(is.na(chem$k_hydro_sd_n[chem_idx]), chem$k_hydro_sw_n[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * HL$f_diss_sed_n, chem$k_hydro_sd_n[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sd_n[chem_idx]) / 10) * HL$f_diss_sed_n)
    HL$k_hydro_sd_alt <- ifelse(is.na(chem$k_hydro_sd_alt[chem_idx]), chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * HL$f_diss_sed_alt, chem$k_hydro_sd_alt[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sd_alt[chem_idx]) / 10) * HL$f_diss_sed_alt)
    HL$k_hydro_sd <- HL$fn * HL$k_hydro_sd_n + (1 - HL$fn) * HL$k_hydro_sd_alt
  }

  # --- Photolysis rate in surface water (k_photo_w) -----------------------------
  # Governing equation:
  #   k_photo = k_photo12 * f_diss * f_light * ((1 - 10^(-1.2*alpha*100*H)) / (ln(10)*1.2*alpha*100*H)) * Q10
  # The Beer-Lambert term ((1 - 10^(-eps)) / (ln(10)*eps)) computes depth-averaged
  # light penetration, where alpha is the attenuation coefficient and H is depth.
  # TODO(MULTI-PATHOGEN): Pathogen solar inactivation uses a different formulation
  #   (see calc_solar_decay in Process_formulas.R). Not directly comparable.
  #pseudo-1st order photolysis rate constant (s-1)
  pts$k_photo_w <- pts$fn * (chem$k_photo12_sw_n[chem_idx] * pts$f_diss_n * pts$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_n[chem_idx] * 100 * pts$H)) / (log(10) * 1.2 * chem$alpha_n[chem_idx] * 100 * pts$H)) * 2 ^ ((pts$T_sw - chem$T_photo12_sw_n[chem_idx]) / 10)) +
    (1 - pts$fn) * (chem$k_photo12_sw_alt[chem_idx] * pts$f_diss_alt * pts$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_alt[chem_idx] * 100 * pts$H)) / (log(10) * 1.2 * chem$alpha_alt[chem_idx] * 100 * pts$H)) * 2 ^ ((pts$T_sw - chem$T_photo12_sw_alt[chem_idx]) / 10))
  if (nrow(HL)!=0) {
    HL$k_photo_w <- HL$fn * (chem$k_photo12_sw_n[chem_idx] * HL$f_diss_n * HL$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_n[chem_idx] * 100 * HL$H_av)) / (log(10) * 1.2 * chem$alpha_n[chem_idx] * 100 * HL$H_av)) * 2 ^ ((HL$T_sw - chem$T_photo12_sw_n[chem_idx]) / 10)) +
    (1 - HL$fn) * (chem$k_photo12_sw_alt[chem_idx] * HL$f_diss_alt * HL$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_alt[chem_idx] * 100 * HL$H_av)) / (log(10) * 1.2 * chem$alpha_alt[chem_idx] * 100 * HL$H_av)) * 2 ^ ((HL$T_sw - chem$T_photo12_sw_alt[chem_idx]) / 10))
  }

  # --- Sediment-water exchange velocities ---------------------------------------
  #pseudo 1st order rate constant for transport from water to sediment and vice versa (s-1)
  #adsorption velocity from water to sediment (m/s)
  # Two-resistance model: harmonic mean of water-side and sediment-side mass transfer
  pts$v_ads <- pts$fn * (((pts$v_mw_wsd * pts$v_msd_wsd) / (pts$v_mw_wsd + pts$v_msd_wsd)) * pts$f_diss_n) + (1 - pts$fn) * (((pts$v_mw_wsd * pts$v_msd_wsd) / (pts$v_mw_wsd + pts$v_msd_wsd)) * pts$f_diss_alt)
  if (nrow(HL)!=0) HL$v_ads <- HL$fn * (((HL$v_mw_wsd * HL$v_msd_wsd) / (HL$v_mw_wsd + HL$v_msd_wsd)) * HL$f_diss_n) + (1 - HL$fn) * (((HL$v_mw_wsd * HL$v_msd_wsd) / (HL$v_mw_wsd + HL$v_msd_wsd)) * HL$f_diss_alt)

  #desorption velocity from sediment to water (m/s)
  pts$v_des <- ((pts$v_mw_wsd * pts$v_msd_wsd) / (pts$v_mw_wsd + pts$v_msd_wsd)) * (1 / (pts$poros + (1 - pts$poros) * pts$rho_sd * (pts$fn * pts$Kp_sd_n + (1 - pts$fn) * pts$Kp_sd_alt)))
  if (nrow(HL)!=0) HL$v_des <- ((HL$v_mw_wsd * HL$v_msd_wsd) / (HL$v_mw_wsd + HL$v_msd_wsd)) * (1 / (HL$poros + (1 - HL$poros) * HL$rho_sd * (HL$fn * HL$Kp_sd_n + (1 - HL$fn) * HL$Kp_sd_alt)))

  #gross sedimentation rate from water (m/s)
  # Takes the maximum of settling-driven and accumulation-driven sedimentation
  pts$v_sd_gross <- ifelse(pts$v_set * (pts$C_susp / (pts$poros + (1 - pts$poros) * pts$rho_sd)) < pts$v_sd_acc, pts$v_sd_acc, pts$v_set * (pts$C_susp / (pts$poros + (1 - pts$poros) * pts$rho_sd)))
  if (nrow(HL)!=0) HL$v_sd_gross <- ifelse(HL$v_set * (HL$C_susp / (HL$poros + (1 - HL$poros) * HL$rho_sd)) < HL$v_sd_acc, HL$v_sd_acc, HL$v_set * (HL$C_susp / (HL$poros + (1 - HL$poros) * HL$rho_sd)))

  #sedimentation velocity from water to sediment (m/s)
  # Accounts for sorption to suspended solids via Kp_susp * f_diss
  pts$v_sed <- (1 - pts$poros) * pts$rho_sd * (pts$fn * pts$Kp_susp_n * pts$f_diss_n + (1 - pts$fn) * pts$Kp_susp_alt * pts$f_diss_alt) * pts$v_sd_gross
  if (nrow(HL)!=0) HL$v_sed <- (1 - HL$poros) * HL$rho_sd * (HL$fn * HL$Kp_susp_n * HL$f_diss_n + (1 - HL$fn) * HL$Kp_susp_alt * HL$f_diss_alt) * HL$v_sd_gross

  #resuspension velocity from sediment to water (m/s)
  pts$v_res <- pts$v_sd_gross - pts$v_sd_acc
  if (nrow(HL)!=0) HL$v_res <- HL$v_sd_gross - HL$v_sd_acc

  # --- Net sediment-water mass transfer rate constants ---------------------------
  # k_ws: water -> sediment (s-1)
  # k_sw: sediment -> water (s-1), accounting for degradation in sediment
  # k_sed: net balance = k_ws - k_sw
  #pseudo first order mass transport (s-1)
  pts$k_ws <- ((pts$v_ads + pts$v_sed) / pts$H)  #water to sediment
  pts$k_sw <- (((pts$v_ads + pts$v_sed) / pts$H) * ((pts$v_res + pts$v_des) / pts$H_sed)) / ((pts$v_res + pts$v_des + pts$v_sd_acc) / pts$H_sed + pts$k_bio_sd + pts$k_hydro_sd) #sediments to water
  pts$k_sed <- pts$k_ws - pts$k_sw  #balance of the two directions
  if (nrow(HL)!=0) {
    HL$k_ws <- ((HL$v_ads + HL$v_sed) / HL$H_av) #water to sediment
    HL$k_sw <- (((HL$v_ads + HL$v_sed) / HL$H_av) * ((HL$v_res + HL$v_des) / HL$H_sed)) / ((HL$v_res + HL$v_des + HL$v_sd_acc) / HL$H_sed + HL$k_bio_sd + HL$k_hydro_sd) #sediments to water
    HL$k_sed <- HL$k_ws - HL$k_sw #balance of the two directions
  }

  # --- Volatilization rate ------------------------------------------------------
  # Two-resistance model at the air-water interface (Whitman two-film theory).
  # v_ma_aw: air-side mass transfer coefficient (m/s)
  # v_mw_aw: water-side mass transfer coefficient (m/s)
  # Kaw: dimensionless air-water partition coefficient (Henry's law)
  # pseudo-1st order volatilization rates
  #partial mass transfer coefficient at air side of air-water interface (m/s)
  pts$v_ma_aw <- 0.01 * (0.3 + 0.2 * pts$Wind) * (18 / chem$MW[chem_idx]) ^ (0.67 * 0.5)
  if (nrow(HL)!=0) HL$v_ma_aw <- 0.01 * (0.3 + 0.2 * HL$Wind) * (18 / chem$MW[chem_idx]) ^ (0.67 * 0.5)

  #partial mass transfer coefficient at water side of air-water interface (m/s)
  pts$v_mw_aw <- 0.01 * (0.0004 + 0.00004 * pts$Wind ^ 2) * (32 / chem$MW[chem_idx]) ^ (0.5 * 0.5)
  if (nrow(HL)!=0) HL$v_mw_aw <- 0.01 * (0.0004 + 0.00004 * HL$Wind ^ 2) * (32 / chem$MW[chem_idx]) ^ (0.5 * 0.5)

  #dimensionless air-water partition coefficient, depending on local temperature (-)
  # Kaw = Pv * MW / (S * R * T)  where R = 8.314 J/(mol*K)
  pts$Kaw <-  chem$Pv[chem_idx] * chem$MW[chem_idx] / (chem$S[chem_idx] * 8.314 * pts$T_AIR)
  if (nrow(HL)!=0) HL$Kaw <- chem$Pv[chem_idx] * chem$MW[chem_idx] / (chem$S[chem_idx] * 8.314 * HL$T_AIR)

  #volatilization velocity from water to air (m/s)
  # Overall velocity through both films, weighted by ionisation fraction
  pts$v_vol <- pts$fn * (((pts$v_ma_aw * pts$v_mw_aw) / (pts$v_ma_aw * pts$Kaw + pts$v_mw_aw)) * pts$Kaw * pts$f_diss_n) +
    (1 - pts$fn) * (((pts$v_ma_aw * pts$v_mw_aw) / (pts$v_ma_aw * pts$Kaw + pts$v_mw_aw)) * pts$Kaw * pts$f_diss_alt)
  if (nrow(HL)!=0) HL$v_vol <- HL$fn * (((HL$v_ma_aw * HL$v_mw_aw) / (HL$v_ma_aw * HL$Kaw + HL$v_mw_aw)) * HL$Kaw * HL$f_diss_n) +
    (1 - HL$fn) * (((HL$v_ma_aw * HL$v_mw_aw) / (HL$v_ma_aw * HL$Kaw + HL$v_mw_aw)) * HL$Kaw * HL$f_diss_alt)

  #pseudo-1st order volatilization rate (s-1)
  # k_vol = v_vol / H  (divide by water depth to convert velocity to rate)
  pts$k_vol <- pts$v_vol / pts$H
  if (nrow(HL)!=0) HL$k_vol <- HL$v_vol / HL$H_av

  # --- Total dissipation rate ---------------------------------------------------
  # Sum of all first-order removal pathways:
  #   k = k_bio_w + k_photo_w + k_hydro_w + k_sed + k_vol   (s-1)
  # TODO(MULTI-PATHOGEN): For pathogens, k would instead come from
  #   calc_total_dissipation_rate() in Process_formulas.R, which sums
  #   K_T + K_R + K_S and converts to s-1.
  #total dissipation first order rate constants (s-1)
  pts$k <- pts$k_bio_w + pts$k_photo_w + pts$k_hydro_w + pts$k_sed + pts$k_vol
  if (nrow(HL)!=0) HL$k <- HL$k_bio_w + HL$k_photo_w + HL$k_hydro_w + HL$k_sed + HL$k_vol

  # --- Average dissipation rate between node and its downstream neighbour -------
  # For river transport, k_NXT is the arithmetic mean of k at the current node
  # and k at the next downstream node. This accounts for the change in
  # environmental conditions along the river reach.
  # Lakes and junctions are excluded (they have their own mixing models).
  #average total dissipation rate from water over distance to next point in network (NXT) (s-1)
  pts$k_NXT <- pts$k
  basin_ID = paste0(pts$ID,"_",pts$basin_id)
  basin_ID_nxt = paste0(pts$ID_nxt,"_",pts$basin_id)
  idx_next = match(basin_ID_nxt,basin_ID)
  k_nxt_tmp = pts$k[idx_next]
  loop_indices = which(!is.na(pts$ID_nxt) & pts$Down_type != "Hydro_Lake" & pts$Down_type != "JNCT")
  pts$k_NXT[loop_indices] <- (pts$k[loop_indices] + k_nxt_tmp[loop_indices])/2

  return(list(pts=pts,hl=HL))

}

  chem_name = chem$API[chem_ii]
  if(any(grepl("cnt",names(cons)))){
    cons_chem = cons[,c("cnt",chem_name)]
  }else if(any(grepl("country",names(cons)))){
    cons_chem = cons[,c("country",chem_name)]
  }

  # add consumption data prodrugs, if relevant
  if(!is.na(chem$API_metab)){
    cons_chem$metab = cons[,which(names(cons)==chem$API_metab)]
  }

  # chem_ii chem idx data
  chem_idx = which(chem$API==chem_name)

  # --- Setting local parameters with (default) values relevant for concentration estimations ----

  #Geographically explicit parameters
  pts$T_AIR       <- pts$T_AIR+273.15            #air temperature in K
  default_pH      <- 7.4                        #pH of local surface water, proposed default pH of 7.4 (Meybeck et al 1995)
  if(is.null(pts$pH)) pts$pH = default_pH #pH of local surface water, proposed default pH of 7.4 (Meybeck et al 1995)
  pts$pH[is.na(pts$pH)] = default_pH
  if(nrow(HL)!=0) {
    HL$T_AIR <- HL$T_AIR+273.15   #air temperature in K
    if(is.null(HL$pH)) HL$pH = default_pH
    HL$pH[is.na(HL$pH)] = default_pH
  }

  #Default values (should be assigned as new fields to pts and HL when available)
  pts$BACT_sw     <- 1E6         #bacterial density in surface water (cells/L), range 1E6-1E9 (REF)
  pts$BACT_sed    <- 1E5         #bacterial density in sediments (cells/L), assumed factor 10 lower than surface waters
  pts$T_sw        <- 285         #local water temperature (K), for now: 285 K (ECHA 2016)
  pts$f_light     <- 0.5         #local fraction of light per day, proposed 0.5 default
  pts$C_susp      <- 0.015E-3    #concentration suspended solids in water (kg*L-1), proposed default value based on Humbert et al. (2011)
  pts$C_DOC       <- 0.005E-3    #concentration DOC in water (kg*L-1), proposed default value based on Asselman (1997)
  pts$H_sed       <- 0.03        #mixed depth of sediment column relevant for exchange (m), proposed default value based on Fantke et al (2016)
  pts$v_mw_wsd    <- 2.778E-6    #partial mass transfer coefficient at water side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
  pts$v_msd_wsd   <- 2.778E-8    #partial mass transfer coefficient at sediment side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
  pts$poros       <- 0.8         #porosity of the sediment (Lwater/Lsed), proposed default value based on Paterson & Mackay (1995) & Honti et al (2016)
  pts$rho_sd      <- 2.33165     #mineral density of sediment (kg*L-1), proposed default value based on Fantke et al (2016) and Honti et al (2016)
  pts$v_set       <- 2.89E-5     #settling velocity of suspended particles (m*s-1), proposed default value based on den Hollander et al (2004)
  pts$v_sd_acc    <- 0           #net sediment accumulation rate in water (m*s-1), no proposed default value yet
  pts$fOC_susp    <- 0.1         #mass fraction organic carbon in suspended solids (-), proposed default value based on Fantke et al (2016)
  pts$fOC_sd      <- 0.05        #mass fraction organic carbon in sediments (-), proposed default value based on Fantke et al (2016)

  if (nrow(HL)!=0) {
    HL$BACT_sw     <- 1E6                              #bacterial density in surface water (cells/L), range 1E6-1E9 (REF)
    HL$BACT_sed    <- 1E5                              #bacterial density in sediments (cells/L), same assumed as surface waters
    HL$T_sw        <- 285                              #local water temperature (K), for now: 285 K (ECHA 2016)
    HL$f_light     <- 0.5                              #local fraction of light per day, proposed 0.5 default
    HL$C_OH_w      <- 1e-18                            #concentration OH-radicals in water (M), summer day, mid-latitude range 10e-18 - 10e-16 M (Latch et al 2003)
    HL$C_O2_w      <- 1e-14                            #concentration of singlet oxygen in water (M), summer day, mid-latitude range 7e-11 - 11e-11 M (Latch et al 2003)
    HL$C_susp      <- 0.015E-3                         #concentration suspended solids in water (kg*L-1), proposed default value based on Humbert et al. (2011)
    HL$C_DOC       <- 0.005E-3                         #concentration DOC in water (kg*L-1), proposed default value based on Asselman (1997)
    HL$H_sed       <- 0.03                             #mixed depth of sediment column relevant for exchange (m), proposed default value based on Fantke et al (2016)
    HL$v_mw_wsd    <- 2.778E-6                         #partial mass transfer coefficient at water side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
    HL$v_msd_wsd   <- 2.778E-8                         #partial mass transfer coefficient at sediment side of water/sediment interface (m*s-1), proposed default value based on Mackay (2001)
    HL$poros       <- 0.8                              #porosity of the sediment (Lwater/Lsed), proposed default value based on Paterson & Mackay (1995) & Honti et al (2016)
    HL$rho_sd      <- 2.1663                           #mineral density of sediment (kg*L-1), proposed default value based on Fantke et al (2016)
    HL$v_set       <- 2.89E-5                          #settling velocity of suspended particles (m*s-1), proposed default value based on den Hollander et al (2004)
    HL$v_sd_acc    <- 0                                #net sediment accumulation rate in water (m*s-1), no proposed default value yet
    HL$fOC_susp    <- 0.1                              #mass fraction organic carbon in suspended solids (-), proposed default value based on Fantke et al (2016)
    HL$fOC_sd      <- 0.05                             #mass fraction organic carbon in sediments (-), proposed default value based on Fantke et al (2016)
    if(is.null(HL$H_av)) HL$H_av = HL$Depth_avg        #if variable does not exist find in via Depth_avg
    HL$Wind[is.na(HL$Wind)] = mean(HL$Wind,na.rm=TRUE) #remove NAs from wind variable

  }

  #Setting up local parameters with (default) values relevant for emission estimations from WWTPs
  #size of WWTP (preferably load entering, else capacity, else default of SimpleTreat) (PE)
  #needed for calculation of removal fractions, but later return NA on sludge concentrations if default is used
  pts$Inh=ifelse(is.na(pts$uwwLoadEnt),NA,ifelse(pts$uwwLoadEnt!=0,pts$uwwLoadEnt,ifelse(pts$uwwCapacit!=0,pts$uwwCapacit,10000)))

  # --- Emission calculations water----
  #first calculate WWTP inflow of chem_idx
  if(is.null(chem$API_metab)) chem$API_metab = NA
  if(is.na(chem$API_metab[chem_idx])){
    pts$E_in <- ifelse(pts$Pt_type=="WWTP",
                       (cons_chem[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx])) *pts$f_STP,
                        NA) #emission towards WWTP (kg/year)
  #first calculate WWTP inflow of chem_idx and its prodrugs chem_zz
  }else{
    chem_zz <- ifelse(is.na(chem$API_metab[chem_idx]),1,which(chem$API==chem$API_metab[chem_idx])) #ID of prodrug
    pts$E_in <- ifelse(pts$Pt_type=="WWTP",
                       (cons[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx]) +
                          cons[match(pts$rptMStateK,cons$cnt),"metab"]*(chem$metab[chem_idx])) *
                         pts$f_STP,NA) #emission towards WWTP (kg/year)
  }

  # Calculate removal in WWTPs.
  # If custom_wwtp_removal = NA, SimpleTreat is used.
  # If custom_wwtp_removal != NA, custom_wwtp_removal value is used directly as removal.
  # custom_wwtp_removal is given in values 0 to 1 in main script.

  pts$f_rem_WWTP = NA
  idx_WWTPs = which(pts$Pt_type=="WWTP")
  useSimpleTreat4_0 = (is.na(chem$custom_wwtp_primary_removal[chem_idx])) | (is.na(chem$custom_wwtp_secondary_removal[chem_idx]))

  # WWTPs first and secondary treatment (with SimpleTreat)
  if(useSimpleTreat4_0){
    for (j in idx_WWTPs) {
      if (pts$Pt_type[j]=="WWTP") {
        #if primary and secondary removal rate is unknown, SimpleTreat 4.0 is used.
        #Pay attention on the condition pts$f_STP[j]==0. If this is valid, no population is connected and there is not WWTP inflow. THerefore pts$f_rem_WWTP[j] = 0 to avoid infinities in SimpleTreat
        pts$f_rem_WWTP[j] <-  ifelse(pts$f_STP[j]==0,0,
                                     SimpleTreat4_0(chem$class[chem_idx],chem$MW[chem_idx],chem$Pv[chem_idx],chem$S[chem_idx],chem$pKa[chem_idx],
                                             chem$Kp_ps_n[chem_idx],chem$Kp_as_n[chem_idx],chem$k_bio_wwtp_n[chem_idx],pts$T_AIR[j],
                                             pts$Wind[j],pts$Inh[j],pts$E_in[j]/365,pts$uwwPrimary[j],pts$uwwSeconda[j])$f_rem)
      }else{
        pts$f_rem_WWTP[j] <- NA  #if the "i" point is not a WWTP put removal = NA
      }
    }

  #if primary and secondary removal rate is known, custom removal values are used (without SimpleTreat)
  }else{

    pts$f_rem_WWTP[pts$Pt_type=="WWTP"] = 0;
    pts$f_leftover_WWTP = NA
    pts$f_leftover_WWTP[pts$Pt_type=="WWTP"] = 1

    idx_Primary = which(pts$uwwPrimary==-1)
    pts$f_leftover_WWTP[idx_Primary] = 1-chem$custom_wwtp_primary_removal[chem_idx]

    idx_Secondary = which(pts$uwwSeconda==-1)
    pts$f_leftover_WWTP[idx_Secondary] =  pts$f_leftover_WWTP[idx_Secondary] * (1-chem$custom_wwtp_secondary_removal[chem_idx])

    pts$f_rem_WWTP[pts$Pt_type=="WWTP"] = 1 - pts$f_leftover_WWTP[pts$Pt_type=="WWTP"]
  }

  #print(pts$f_rem_WWTP[pts$Pt_type=="WWTP"])
  pts$f_leftover_WWTP = NA
  pts$f_leftover_WWTP[pts$Pt_type=="WWTP"] = 1-pts$f_rem_WWTP[pts$Pt_type=="WWTP"]
  #print(pts$f_rem_WWTP[pts$Pt_type=="WWTP"])
  #print(pts$f_leftover_WWTP[pts$Pt_type=="WWTP"])
  #stop("check!")

  # check if tertiary removals are provided, else set to 0
  checkCols = c("custom_wwtp_N_removal","custom_wwtp_P_removal",
                "custom_wwtp_UV_removal","custom_wwtp_Cl_removal",
                "custom_wwtp_O3_removal","custom_wwtp_sandfilter_removal",
                "custom_wwtp_microfilter_removal")
  for(cc in checkCols) chem = CheckIfColumnExistsCreateEmpty(chem,cc,0)

  wwtp_treatment_cols <- c("uwwNRemova","uwwPRemova","uwwUV","uwwChlorin","uwwOzonati","uwwSandFil","uwwMicroFi")
  for(tc in wwtp_treatment_cols) {
    if(!(tc %in% names(pts))) pts[[tc]] <- 0
    pts[[tc]][is.na(pts[[tc]])] <- 0
  }

  idx_rm = which(pts$uwwNRemova==-1)
  pts$f_rem_WWTP[idx_rm] = pts$f_rem_WWTP[idx_rm] + chem$custom_wwtp_N_removal[chem_idx]

  idx_rm = which(pts$uwwPRemova==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_P_removal[chem_idx])

  idx_rm = which(pts$uwwUV==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_UV_removal[chem_idx])

  idx_rm = which(pts$uwwChlorin==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_Cl_removal[chem_idx])

  idx_rm = which(pts$uwwOzonati==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_O3_removal[chem_idx])

  idx_rm = which(pts$uwwSandFil==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_sandfilter_removal[chem_idx])

  idx_rm = which(pts$uwwMicroFi==-1)
  pts$f_leftover_WWTP[idx_rm] = pts$f_leftover_WWTP[idx_rm] * (1-chem$custom_wwtp_microfilter_removal[chem_idx])

  pts$f_rem_WWTP[pts$Pt_type=="WWTP"] = 1-pts$f_leftover_WWTP[pts$Pt_type=="WWTP"]
  pts$f_rem_WWTP[pts$f_rem_WWTP>1] = 1
  pts$f_rem_WWTP[pts$f_rem_WWTP<0] = 0
  pts$f_leftover_WWTP = NULL
  #print(cbind(pts$uwwPrimary[pts$Pt_type=="WWTP"],pts$uwwSeconda[pts$Pt_type=="WWTP"],pts$f_rem_WWTP[pts$Pt_type=="WWTP"]))
  #stop("check!")

  #Emission towards surface water from WWTPs and from agglomerations (total chemical: dissolved & associated) (kg/yr)
  if(is.na(chem$API_metab[chem_idx])){
    pts$E_w <- ifelse(pts$Pt_type=="WWTP",pts$E_in*(1-pts$f_rem_WWTP),
                      ifelse(pts$Pt_type=="Agglomerations",
                             (cons[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx])) * pts$f_direct,0))
  }else{
    chem_zz <- ifelse(is.na(chem$API_metab[chem_idx]),1,which(chem$API==chem$API_metab[chem_idx])) #ID of prodrug
    pts$E_w <- ifelse(pts$Pt_type=="WWTP",pts$E_in*(1-pts$f_rem_WWTP),
                      ifelse(pts$Pt_type=="Agglomerations",
                             (cons[match(pts$rptMStateK,cons$cnt),chem_name]*(chem$f_uf[chem_idx]) +
                                cons[match(pts$rptMStateK,cons$cnt),"metab"]*chem$metab[chem_idx]) *
                               pts$f_direct,0))
  }

  #Observe that only the fraction F_direct is discharged directly from agglomeration to surface waters (This is the fraction of not connected households)

  #Add emissions from WWTPs / agglomerations to lakes
  if (nrow(HL)!=0) {
    pts$Hylak_id <- pts$HL_ID_new
    pts$HL_ID_new <- NULL
    HL$E_in = NA

    if (nrow(HL)!=0) {
      for (j in 1:nrow(HL)) {
        HL$E_in[j] = sum(pts$E_w[which(pts$Hylak_id==HL$Hylak_id[j])],na.rm=TRUE)
      }
    }
  }

  # --- (Re)setting local variables to be adapted per API ----
  pts$E_up            <- 0                            #emission to surface water from upstream sources (kg*yr-1)
  pts$E_w_NXT         <- 0                            #contribution to emission at next downstream point (kg/yr)
  pts$C_w             <- NA                           #total concentration in surface water (ug/L)
  pts$C_sd            <- NA                           #total concentration in sediment (ug/kg)
  pts$fin             <- 0                            #tracking counter (0/1)
  pts$upcount         <- pts$Freq                     #tracking number of upstream points

  if (nrow(HL)!=0) {
    HL$C_w          <- NA
    HL$C_sd         <- NA
    HL$fin          <- 0
  }

  # --- Chemical- and environment-dependent characteristics ----
  #neutral fraction
  # pts$fn <- ifelse(chem$class[chem_idx]=="neutral",1,
  #                ifelse(chem$class[chem_idx]=="acid",1/(1+10^(pts$pH-chem$pKa[chem_idx])),
  #                       ifelse(chem$class[chem_idx]=="base",1/(1+10^(chem$pKa[chem_idx]-pts$pH)),NA)))
  if(chem$class[chem_idx]=="neutral"){
    pts$fn = 1
  } else if(chem$class[chem_idx]=="acid"){
    pts$fn = 1/(1+10^(pts$pH-chem$pKa[chem_idx]))
  } else if(chem$class[chem_idx]=="base"){
    pts$fn = 1/(1+10^(chem$pKa[chem_idx]-pts$pH))
  } else {
    pts$fn = NA
  }

  if (nrow(HL)!=0){
    #  HL$fn <- ifelse(chem$class[chem_idx]=="neutral",1,
    #                                  ifelse(chem$class[chem_idx]=="acid",1/(1+10^(HL$pH-chem$pKa[chem_idx])),
    #                                         ifelse(chem$class[chem_idx]=="base",1/(1+10^(chem$pKa[chem_idx]-HL$pH)),NA)))
    if(chem$class[chem_idx]=="neutral"){
      HL$fn = 1
    } else if(chem$class[chem_idx]=="acid"){
      HL$fn = 1/(1+10^(HL$pH-chem$pKa[chem_idx]))
    } else if(chem$class[chem_idx]=="base"){
      HL$fn = 1/(1+10^(chem$pKa[chem_idx]-HL$pH))
    } else {
      HL$fn = NA
    }
  }

  # check additional chem columns, remove these from the default inputs
  checkCols = c("Kp_susp_n","Kp_susp_alt","Kp_DOC_n","Kp_DOC_alt","Kp_sd_n","Kp_sd_alt","k_bio_sd1_n","k_bio_sd1_alt","k_hydro_sd_n","k_hydro_sd_alt")
  for(cc in checkCols) chem = CheckIfColumnExistsCreateEmpty(chem,cc,NA)


  #local (pH-dependent) partition coefficients
  if (is.na(chem$Kp_susp_n[chem_idx])) {
    pts$Kp_susp_n <- chem$KOC_n[chem_idx] * pts$fOC_susp
    if (nrow(HL)!=0) HL$Kp_susp_n <- chem$KOC_n[chem_idx] * HL$fOC_susp
  } else {
    pts$Kp_susp_n <- chem$Kp_susp_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_susp_n <- chem$Kp_susp_n[chem_idx]
  }

  if (is.na(chem$Kp_susp_alt[chem_idx])) {
    pts$Kp_susp_alt <- chem$KOC_alt[chem_idx] * pts$fOC_susp
    if (nrow(HL)!=0) HL$Kp_susp_alt <- chem$KOC_alt[chem_idx] * HL$fOC_susp
  } else {
    pts$Kp_susp_alt <- chem$Kp_susp_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_susp_alt <- chem$Kp_susp_alt[chem_idx]
  }

  if (is.na(chem$Kp_DOC_n[chem_idx])) {
    pts$Kp_DOC_n <- 0.08 * chem$KOW_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_n <- 0.08 * chem$KOW_n[chem_idx]
  } else {
    pts$Kp_DOC_n <- chem$Kp_DOC_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_n <- chem$Kp_DOC_n[chem_idx]
  }

  if (is.na(chem$Kp_DOC_alt[chem_idx])) {
    pts$Kp_DOC_alt <- 0.08 * chem$KOW_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_alt <- 0.08 * chem$KOW_alt[chem_idx]
  } else {
    pts$Kp_DOC_alt <- chem$Kp_DOC_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_DOC_alt <- chem$Kp_DOC_alt[chem_idx]
  }

  #local partitioning to sediment (if NA, based on KOC and fOC sediments)
  if (is.na(chem$Kp_sd_n[chem_idx])) {
    pts$Kp_sd_n <- chem$KOC_n[chem_idx] * pts$fOC_sd
    if (nrow(HL)!=0) HL$Kp_sd_n <- chem$KOC_n[chem_idx] * HL$fOC_sd
  } else {
    pts$Kp_sd_n <- chem$Kp_sd_n[chem_idx]
    if (nrow(HL)!=0) HL$Kp_sd_n <- chem$Kp_sd_n[chem_idx]
  }

  if (is.na(chem$Kp_sd_alt[chem_idx])) {
    pts$Kp_sd_alt <- chem$KOC_alt[chem_idx] * pts$fOC_sd
    if (nrow(HL)!=0) HL$Kp_sd_alt <- chem$KOC_alt[chem_idx] * HL$fOC_sd
  } else {
    pts$Kp_sd_alt <- chem$Kp_sd_alt[chem_idx]
    if (nrow(HL)!=0) HL$Kp_sd_alt <- chem$Kp_sd_alt[chem_idx]
  }

  #local fraction truly dissolved (-)
  pts$f_diss_n <- 1 / (1 + pts$Kp_susp_n * pts$C_susp + pts$Kp_DOC_n * pts$C_DOC)
  pts$f_diss_alt <- 1 / (1 + pts$Kp_susp_alt * pts$C_susp + pts$Kp_DOC_alt * pts$C_DOC)
  if (nrow(HL)!=0) {
    HL$f_diss_n <- 1 / (1 + HL$Kp_susp_n * HL$C_susp + HL$Kp_DOC_n * HL$C_DOC)
    HL$f_diss_alt <- 1 / (1 + HL$Kp_susp_alt * HL$C_susp + HL$Kp_DOC_alt * HL$C_DOC)
  }

  pts$f_diss_sed_n <- 1 / (1 + pts$Kp_sd_n * pts$rho_sd * ((1 - pts$poros) / pts$poros))
  pts$f_diss_sed_alt <- 1 / (1 + pts$Kp_sd_alt * pts$rho_sd * ((1 - pts$poros) / pts$poros))
  if (nrow(HL)!=0) {
    HL$f_diss_sed_n <- 1 / (1 + HL$Kp_sd_n * HL$rho_sd * ((1 - HL$poros) / HL$poros))
    HL$f_diss_sed_alt <- 1 / (1 + HL$Kp_sd_alt * HL$rho_sd * ((1 - HL$poros) / HL$poros))
  }

  #pseudo-1st order biodegradation rate constant in surface water (s-1) (homogeneous distribution of bacteria through the water column assumed (no depth-dependence))
  pts$k_bio_w <- pts$fn * (chem$k_bio_sw2_n[chem_idx] * pts$BACT_sw * pts$f_diss_n * 2 ^ ((pts$T_sw - chem$T_bio_sw_n[chem_idx]) / 10)) +
    (1 - pts$fn) * (chem$k_bio_sw2_alt[chem_idx] * pts$BACT_sw * pts$f_diss_alt * 2 ^ ((pts$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10))

  if (nrow(HL)!=0) HL$k_bio_w <- HL$fn * (chem$k_bio_sw2_n[chem_idx] * HL$BACT_sw * HL$f_diss_n * 2 ^ ((HL$T_sw - chem$T_bio_sw_n[chem_idx]) / 10)) +
    (1 - HL$fn) * (chem$k_bio_sw2_alt[chem_idx] * HL$BACT_sw * HL$f_diss_alt * 2 ^ ((HL$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10))

  #pseudo-1st order biodegradation rate constant in sediment (s-1)
  pts$k_bio_sd_n <- ifelse(is.na(chem$k_bio_sd1_n[chem_idx]),chem$k_bio_sw2_n[chem_idx] * pts$BACT_sed * pts$f_diss_sed_n * 2 ^ ((pts$T_sw - chem$T_bio_sw_n[chem_idx]) / 10),
                           chem$k_bio_sd1_n[chem_idx] * pts$f_diss_sed_n * 2 ^ ((pts$T_sw - chem$T_bio_sd_n[chem_idx]) / 10))
  pts$k_bio_sd_alt <- ifelse(is.na(chem$k_bio_sd1_alt[chem_idx]),chem$k_bio_sw2_alt[chem_idx] * pts$BACT_sed * pts$f_diss_sed_alt * 2 ^ ((pts$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10),
                             chem$k_bio_sd1_alt[chem_idx] * pts$f_diss_sed_alt * 2 ^ ((pts$T_sw - chem$T_bio_sd_alt[chem_idx]) / 10))
  pts$k_bio_sd <- pts$fn * pts$k_bio_sd_n + (1 - pts$fn) * pts$k_bio_sd_alt

  if (nrow(HL)!=0) {
    HL$k_bio_sd_n <- ifelse(is.na(chem$k_bio_sd1_n[chem_idx]),chem$k_bio_sw2_n[chem_idx] * HL$BACT_sed * HL$f_diss_sed_n * 2 ^ ((HL$T_sw - chem$T_bio_sw_n[chem_idx]) / 10),
                            chem$k_bio_sd1_n[chem_idx] * HL$f_diss_sed_n * 2 ^ ((HL$T_sw - chem$T_bio_sd_n[chem_idx]) / 10))
    HL$k_bio_sd_alt <- ifelse(is.na(chem$k_bio_sd1_alt[chem_idx]),chem$k_bio_sw2_alt[chem_idx] * HL$BACT_sed * HL$f_diss_sed_alt * 2 ^ ((HL$T_sw - chem$T_bio_sw_alt[chem_idx]) / 10),
                              chem$k_bio_sd1_alt[chem_idx] * HL$f_diss_sed_alt * 2 ^ ((HL$T_sw - chem$T_bio_sd_alt[chem_idx]) / 10))
    HL$k_bio_sd <- HL$fn * HL$k_bio_sd_n + (1 - HL$fn) * HL$k_bio_sd_alt
  }

  #1st order hydrolysis rate constant in water (s-1)
  pts$k_hydro_w <- pts$fn * (chem$k_hydro_sw_n[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * pts$f_diss_n) +
    (1 - pts$fn) * (chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * pts$f_diss_alt)

  if (nrow(HL)!=0) HL$k_hydro_w <- HL$fn * (chem$k_hydro_sw_n[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * HL$f_diss_n) +
    (1 - HL$fn) * (chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * HL$f_diss_alt)

  #1st order hydrolysis rate constant in sediment (s-1) (assumption of equal temperature in surface water and sediment below it)
  pts$k_hydro_sd_n <- ifelse(is.na(chem$k_hydro_sd_n[chem_idx]), chem$k_hydro_sw_n[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * pts$f_diss_sed_n, chem$k_hydro_sd_n[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sd_n[chem_idx]) / 10) * pts$f_diss_sed_n)
  pts$k_hydro_sd_alt <- ifelse(is.na(chem$k_hydro_sd_alt[chem_idx]), chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * pts$f_diss_sed_alt, chem$k_hydro_sd_alt[chem_idx] * 2 ^ ((pts$T_sw - chem$T_hydro_sd_alt[chem_idx]) / 10) * pts$f_diss_sed_alt)
  pts$k_hydro_sd <- pts$fn * pts$k_hydro_sd_n + (1 - pts$fn) * pts$k_hydro_sd_alt

  if (nrow(HL)!=0) {
    HL$k_hydro_sd_n <- ifelse(is.na(chem$k_hydro_sd_n[chem_idx]), chem$k_hydro_sw_n[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_n[chem_idx]) / 10) * HL$f_diss_sed_n, chem$k_hydro_sd_n[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sd_n[chem_idx]) / 10) * HL$f_diss_sed_n)
    HL$k_hydro_sd_alt <- ifelse(is.na(chem$k_hydro_sd_alt[chem_idx]), chem$k_hydro_sw_alt[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sw_alt[chem_idx]) / 10) * HL$f_diss_sed_alt, chem$k_hydro_sd_alt[chem_idx] * 2 ^ ((HL$T_sw - chem$T_hydro_sd_alt[chem_idx]) / 10) * HL$f_diss_sed_alt)
    HL$k_hydro_sd <- HL$fn * HL$k_hydro_sd_n + (1 - HL$fn) * HL$k_hydro_sd_alt
  }

  #pseudo-1st order photolysis rate constant (s-1)
  pts$k_photo_w <- pts$fn * (chem$k_photo12_sw_n[chem_idx] * pts$f_diss_n * pts$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_n[chem_idx] * 100 * pts$H)) / (log(10) * 1.2 * chem$alpha_n[chem_idx] * 100 * pts$H)) * 2 ^ ((pts$T_sw - chem$T_photo12_sw_n[chem_idx]) / 10)) +
    (1 - pts$fn) * (chem$k_photo12_sw_alt[chem_idx] * pts$f_diss_alt * pts$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_alt[chem_idx] * 100 * pts$H)) / (log(10) * 1.2 * chem$alpha_alt[chem_idx] * 100 * pts$H)) * 2 ^ ((pts$T_sw - chem$T_photo12_sw_alt[chem_idx]) / 10))
  if (nrow(HL)!=0) {
    HL$k_photo_w <- HL$fn * (chem$k_photo12_sw_n[chem_idx] * HL$f_diss_n * HL$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_n[chem_idx] * 100 * HL$H_av)) / (log(10) * 1.2 * chem$alpha_n[chem_idx] * 100 * HL$H_av)) * 2 ^ ((HL$T_sw - chem$T_photo12_sw_n[chem_idx]) / 10)) +
    (1 - HL$fn) * (chem$k_photo12_sw_alt[chem_idx] * HL$f_diss_alt * HL$f_light * ((1 - 10 ^ (-1.2 * chem$alpha_alt[chem_idx] * 100 * HL$H_av)) / (log(10) * 1.2 * chem$alpha_alt[chem_idx] * 100 * HL$H_av)) * 2 ^ ((HL$T_sw - chem$T_photo12_sw_alt[chem_idx]) / 10))
  }

  #pseudo 1st order rate constant for transport from water to sediment and vice versa (s-1)
  #adsorption velocity from water to sediment (m/s)
  pts$v_ads <- pts$fn * (((pts$v_mw_wsd * pts$v_msd_wsd) / (pts$v_mw_wsd + pts$v_msd_wsd)) * pts$f_diss_n) + (1 - pts$fn) * (((pts$v_mw_wsd * pts$v_msd_wsd) / (pts$v_mw_wsd + pts$v_msd_wsd)) * pts$f_diss_alt)
  if (nrow(HL)!=0) HL$v_ads <- HL$fn * (((HL$v_mw_wsd * HL$v_msd_wsd) / (HL$v_mw_wsd + HL$v_msd_wsd)) * HL$f_diss_n) + (1 - HL$fn) * (((HL$v_mw_wsd * HL$v_msd_wsd) / (HL$v_mw_wsd + HL$v_msd_wsd)) * HL$f_diss_alt)

  #desorption velocity from sediment to water (m/s)
  pts$v_des <- ((pts$v_mw_wsd * pts$v_msd_wsd) / (pts$v_mw_wsd + pts$v_msd_wsd)) * (1 / (pts$poros + (1 - pts$poros) * pts$rho_sd * (pts$fn * pts$Kp_sd_n + (1 - pts$fn) * pts$Kp_sd_alt)))
  if (nrow(HL)!=0) HL$v_des <- ((HL$v_mw_wsd * HL$v_msd_wsd) / (HL$v_mw_wsd + HL$v_msd_wsd)) * (1 / (HL$poros + (1 - HL$poros) * HL$rho_sd * (HL$fn * HL$Kp_sd_n + (1 - HL$fn) * HL$Kp_sd_alt)))

  #gross sedimentation rate from water (m/s)
  pts$v_sd_gross <- ifelse(pts$v_set * (pts$C_susp / (pts$poros + (1 - pts$poros) * pts$rho_sd)) < pts$v_sd_acc, pts$v_sd_acc, pts$v_set * (pts$C_susp / (pts$poros + (1 - pts$poros) * pts$rho_sd)))
  if (nrow(HL)!=0) HL$v_sd_gross <- ifelse(HL$v_set * (HL$C_susp / (HL$poros + (1 - HL$poros) * HL$rho_sd)) < HL$v_sd_acc, HL$v_sd_acc, HL$v_set * (HL$C_susp / (HL$poros + (1 - HL$poros) * HL$rho_sd)))

  #sedimentation velocity from water to sediment (m/s)
  pts$v_sed <- (1 - pts$poros) * pts$rho_sd * (pts$fn * pts$Kp_susp_n * pts$f_diss_n + (1 - pts$fn) * pts$Kp_susp_alt * pts$f_diss_alt) * pts$v_sd_gross
  if (nrow(HL)!=0) HL$v_sed <- (1 - HL$poros) * HL$rho_sd * (HL$fn * HL$Kp_susp_n * HL$f_diss_n + (1 - HL$fn) * HL$Kp_susp_alt * HL$f_diss_alt) * HL$v_sd_gross

  #resuspension velocity from sediment to water (m/s)
  pts$v_res <- pts$v_sd_gross - pts$v_sd_acc
  if (nrow(HL)!=0) HL$v_res <- HL$v_sd_gross - HL$v_sd_acc

  #pseudo first order mass transport (s-1)
  pts$k_ws <- ((pts$v_ads + pts$v_sed) / pts$H)  #water to sediment
  pts$k_sw <- (((pts$v_ads + pts$v_sed) / pts$H) * ((pts$v_res + pts$v_des) / pts$H_sed)) / ((pts$v_res + pts$v_des + pts$v_sd_acc) / pts$H_sed + pts$k_bio_sd + pts$k_hydro_sd) #sediments to water
  pts$k_sed <- pts$k_ws - pts$k_sw  #balance of the two directions
  if (nrow(HL)!=0) {
    HL$k_ws <- ((HL$v_ads + HL$v_sed) / HL$H_av) #water to sediment
    HL$k_sw <- (((HL$v_ads + HL$v_sed) / HL$H_av) * ((HL$v_res + HL$v_des) / HL$H_sed)) / ((HL$v_res + HL$v_des + HL$v_sd_acc) / HL$H_sed + HL$k_bio_sd + HL$k_hydro_sd) #sediments to water
    HL$k_sed <- HL$k_ws - HL$k_sw #balance of the two directions
  }

  # pseudo-1st order volatilization rates
  #partial mass transfer coefficient at air side of air-water interface (m/s)
  pts$v_ma_aw <- 0.01 * (0.3 + 0.2 * pts$Wind) * (18 / chem$MW[chem_idx]) ^ (0.67 * 0.5)
  if (nrow(HL)!=0) HL$v_ma_aw <- 0.01 * (0.3 + 0.2 * HL$Wind) * (18 / chem$MW[chem_idx]) ^ (0.67 * 0.5)

  #partial mass transfer coefficient at water side of air-water interface (m/s)
  pts$v_mw_aw <- 0.01 * (0.0004 + 0.00004 * pts$Wind ^ 2) * (32 / chem$MW[chem_idx]) ^ (0.5 * 0.5)
  if (nrow(HL)!=0) HL$v_mw_aw <- 0.01 * (0.0004 + 0.00004 * HL$Wind ^ 2) * (32 / chem$MW[chem_idx]) ^ (0.5 * 0.5)

  #dimensionless air-water partition coefficient, depending on local temperature (-)
  pts$Kaw <-  chem$Pv[chem_idx] * chem$MW[chem_idx] / (chem$S[chem_idx] * 8.314 * pts$T_AIR)
  if (nrow(HL)!=0) HL$Kaw <- chem$Pv[chem_idx] * chem$MW[chem_idx] / (chem$S[chem_idx] * 8.314 * HL$T_AIR)

  #volatilization velocity from water to air (m/s)
  pts$v_vol <- pts$fn * (((pts$v_ma_aw * pts$v_mw_aw) / (pts$v_ma_aw * pts$Kaw + pts$v_mw_aw)) * pts$Kaw * pts$f_diss_n) +
    (1 - pts$fn) * (((pts$v_ma_aw * pts$v_mw_aw) / (pts$v_ma_aw * pts$Kaw + pts$v_mw_aw)) * pts$Kaw * pts$f_diss_alt)
  if (nrow(HL)!=0) HL$v_vol <- HL$fn * (((HL$v_ma_aw * HL$v_mw_aw) / (HL$v_ma_aw * HL$Kaw + HL$v_mw_aw)) * HL$Kaw * HL$f_diss_n) +
    (1 - HL$fn) * (((HL$v_ma_aw * HL$v_mw_aw) / (HL$v_ma_aw * HL$Kaw + HL$v_mw_aw)) * HL$Kaw * HL$f_diss_alt)

  #pseudo-1st order volatilization rate (s-1)
  pts$k_vol <- pts$v_vol / pts$H
  if (nrow(HL)!=0) HL$k_vol <- HL$v_vol / HL$H_av

  #total dissipation first order rate constants (s-1)
  pts$k <- pts$k_bio_w + pts$k_photo_w + pts$k_hydro_w + pts$k_sed + pts$k_vol
  if (nrow(HL)!=0) HL$k <- HL$k_bio_w + HL$k_photo_w + HL$k_hydro_w + HL$k_sed + HL$k_vol

  #average total dissipation rate from water over distance to next point in network (NXT) (s-1)
  pts$k_NXT <- pts$k
  basin_ID = paste0(pts$ID,"_",pts$basin_id)
  basin_ID_nxt = paste0(pts$ID_nxt,"_",pts$basin_id)
  idx_next = match(basin_ID_nxt,basin_ID)
  k_nxt_tmp = pts$k[idx_next]
  loop_indices = which(!is.na(pts$ID_nxt) & pts$Down_type != "Hydro_Lake" & pts$Down_type != "JNCT")
  pts$k_NXT[loop_indices] <- (pts$k[loop_indices] + k_nxt_tmp[loop_indices])/2

  return(list(pts=pts,hl=HL))

}



