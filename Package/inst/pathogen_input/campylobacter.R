simulation_parameters <- list(
  type = "pathogen",

  # --- Population and infection parameters ---
  # total_population: total basin population. Set to NA here and resolved at
  #   runtime from basin config (country_population field).
  total_population = NA_real_,

  # prevalence_rate: fraction of population infected at a given time.
  #   TODO(VERIFY): Value not yet sourced from literature. Using a reasonable
  #   estimate for Sub-Saharan Africa. Check Vermeulen et al. (2019) Table 2
  #   and Thomas et al. (2020), Lancet Infect Dis 20(8), 918-928.
  prevalence_rate = 0.11,

  # excretion_rate: number of CFU excreted per infected person per year.
  #   TODO(VERIFY): Value not yet sourced from literature. Check Soller et al.
  #   (2010), Water Research 44(16), 4910-4922 for correct CFU/pers/year.
  excretion_rate = 1e11,

  # --- Decay kinetics parameters ---
  # These five parameters define the three decay pathways (K_T, K_R, K_S).
  # Campylobacter is far less environmentally persistent than Cryptosporidium.
  # TODO(VERIFY): All decay parameters below are estimates. Correct values
  #   should come from the GloWPa framework supplementary tables:
  #   - Vermeulen (2018) PhD thesis, WUR, Supplementary Material Table S2
  #   - Sterk et al. (2016), Water Research, DOI 10.1016/j.watres.2015.12.022

  # decay_rate_base (K4): base decay rate at reference temperature 4 degC [day^-1].
  #   TODO(VERIFY): Estimated. Crypto uses 0.0051; Campylobacter dies much faster.
  #   Literature reports T90 values of 1-4 days in fresh water at moderate temps,
  #   implying k ~ 0.1-0.5 day^-1 at 4C. Verify from Sterk et al. (2016) Table 2.
  decay_rate_base = 0.28,

  # temp_corr_factor (theta): Arrhenius-type temperature correction [-].
  #   TODO(VERIFY): Estimated. Crypto uses 0.158. Verify from Sterk et al. (2016).
  temp_corr_factor = 0.09,

  # solar_rad_factor (kl): proportionality between solar radiation and
  #   inactivation rate [m^2 kJ^-1].
  #   TODO(VERIFY): Estimated. Crypto uses 4.798e-4. Campylobacter is more
  #   sensitive to UV. Verify from Sterk et al. (2016) or Vermeulen (2018).
  solar_rad_factor = 1.0e-3,

  # doc_attenuation (kd): specific light attenuation by dissolved organic
  #   carbon [L mg^-1 m^-1].
  #   NOTE: This is a water property, not pathogen-specific. Same as Crypto.
  #   Source: Vermeulen et al. (2019), Table S2.
  doc_attenuation = 9.831,

  # settling_velocity (v_settling): rate at which bacteria settle out of
  #   the water column [m/day].
  #   TODO(VERIFY): Estimated. Crypto uses 0.1 (small oocysts). Bacteria
  #   associated with particles settle faster. Verify from Sterk et al. (2016).
  settling_velocity = 0.5,

  # --- WWTP removal parameters ---
  # Fraction of bacteria removed by each treatment stage (applied sequentially).
  # TODO(VERIFY): Values are reasonable estimates based on general WWTP
  #   performance for bacteria. Verify from:
  #   - WHO (2020) Guidelines on Sanitation and Health
  #   - Vermeulen (2018) PhD thesis, Table S2 (if Campylobacter listed)

  # wwtp_primary_removal: fraction removed during primary treatment (sedimentation).
  #   TODO(VERIFY): Estimated 0.50. Literature range for bacteria: 0.3-0.7.
  wwtp_primary_removal = 0.50,

  # wwtp_secondary_removal: fraction removed during secondary treatment (biological).
  #   TODO(VERIFY): Estimated 0.99. Secondary treatment typically removes >99% bacteria.
  wwtp_secondary_removal = 0.99,

  # --- Display units ---
  # Used by the visualization code to label the concentration map legend.
  units = "CFU/L"
)
