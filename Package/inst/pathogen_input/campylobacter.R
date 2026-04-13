simulation_parameters <- list(
  type = "pathogen",

  # --- Population and infection parameters ---
  # total_population: total basin population. Set to NA here and resolved at
  #   runtime from basin config (country_population field).
  total_population = NA_real_,

  # prevalence_rate: fraction of population infected at a given time.
  #   Campylobacter: 0.11 (11%) — median for Sub-Saharan Africa.
  #   Source: Thomas et al. (2020), Lancet Infect Dis 20(8), 918–928.
  prevalence_rate = 0.11,

  # excretion_rate: number of CFU excreted per infected person per year.
  #   Campylobacter: 1e11 CFU/pers/year.
  #   Source: Soller et al. (2010), Water Research 44(16), 4910–4922.
  excretion_rate = 1e11,

  # --- Decay kinetics parameters ---
  # These five parameters define the three decay pathways (K_T, K_R, K_S).
  # Campylobacter is far less environmentally persistent than Cryptosporidium.
  # Source: Hofstra et al. (2023), DOI 10.1016/j.watres.2023.120397

  # decay_rate_base (K4): base decay rate at reference temperature 4 degC [day^-1].
  #   Campylobacter: 0.28. Dies quickly in cold water.
  decay_rate_base = 0.28,

  # temp_corr_factor (theta): Arrhenius-type temperature correction [-].
  #   Campylobacter: 0.09.
  temp_corr_factor = 0.09,

  # solar_rad_factor (kl): proportionality between solar radiation and
  #   inactivation rate [m^2 kJ^-1].
  #   Campylobacter: 1.0e-3. More sensitive to UV than Cryptosporidium.
  solar_rad_factor = 1.0e-3,

  # doc_attenuation (kd): specific light attenuation by dissolved organic
  #   carbon [L mg^-1 m^-1].
  #   Campylobacter: 9.831 (same as Crypto — water property, not pathogen).
  doc_attenuation = 9.831,

  # settling_velocity (v_settling): rate at which bacteria settle out of
  #   the water column [m/day].
  #   Campylobacter: 0.5. Bacteria-associated particles settle faster.
  settling_velocity = 0.5,

  # --- WWTP removal parameters ---
  # Fraction of bacteria removed by each treatment stage (applied sequentially).
  # Source: WHO (2020) Guidelines on Sanitation and Health; Hofstra et al. (2023).

  # wwtp_primary_removal: fraction removed during primary treatment (sedimentation).
  #   Campylobacter: 0.50 (50% removal).
  wwtp_primary_removal = 0.50,

  # wwtp_secondary_removal: fraction removed during secondary treatment (biological).
  #   Campylobacter: 0.99 (99% removal). Near-complete at secondary.
  wwtp_secondary_removal = 0.99,

  # --- Display units ---
  # Used by the visualization code to label the concentration map legend.
  units = "CFU/L"
)
