simulation_parameters <- list(
  type = "pathogen",

  # --- Population and infection parameters ---
  # total_population: total basin population. Set to NA here and resolved at
  #   runtime from basin config (country_population field).
  # TODO(MULTI-PATHOGEN): template for new pathogens — copy this file to
  #   inst/pathogen_input/<pathogen_name>.R and update the values below.
  total_population = NA_real_,

  # prevalence_rate: fraction of population infected at a given time.
  #   Cryptosporidium: 0.05 (5%) — conservative estimate for Sub-Saharan Africa.
  #   Source: Vermeulen et al. (2019), supplementary material.
  # TODO(SEASONAL): replace scalar with monthly vector, e.g.
  #   prevalence_rate = c(0.04, 0.04, 0.05, 0.05, 0.06, 0.07, 0.08, 0.08, 0.07, 0.05, 0.04, 0.04)
  #   then index by season/month in AssignPathogenEmissions().
  prevalence_rate = 0.05,

  # excretion_rate: number of oocysts excreted per infected person per year.
  #   Cryptosporidium: 1e8 oocysts/pers/year.
  #   Source: Vermeulen et al. (2019), Table 2.
  excretion_rate = 1e8,

  # --- Decay kinetics parameters ---
  # These five parameters define the three decay pathways (K_T, K_R, K_S).
  # All values from Vermeulen et al. (2019), Water Research 149, 202-214.

  # decay_rate_base (K4): base decay rate at reference temperature 4 degC [day^-1].
  #   Cryptosporidium: 0.0051. Very persistent pathogen.
  decay_rate_base = 0.0051,

  # temp_corr_factor (theta): Arrhenius-type temperature correction [-].
  #   Cryptosporidium: 0.158. Higher temperatures increase inactivation.
  temp_corr_factor = 0.158,

  # solar_rad_factor (kl): proportionality between solar radiation and
  #   inactivation rate [m^2 kJ^-1].
  #   Cryptosporidium: 4.798e-4. Moderately sensitive to UV.
  solar_rad_factor = 4.798e-4,

  # doc_attenuation (kd): specific light attenuation by dissolved organic
  #   carbon [L mg^-1 m^-1].
  #   Cryptosporidium: 9.831. Determines how deep light penetrates.
  doc_attenuation = 9.831,

  # settling_velocity (v_settling): rate at which oocysts settle out of
  #   the water column [m/day].
  #   Cryptosporidium: 0.1. Small oocysts settle slowly.
  settling_velocity = 0.1,

  # --- WWTP removal parameters ---
  # Fraction of oocysts removed by each treatment stage (applied sequentially).
  # Source: Vermeulen et al. (2019), WHO guidelines.

  # wwtp_primary_removal: fraction removed during primary treatment (sedimentation).
  #   Default 0.23 (23% removal). Applied only if uwwPrimary == -1 (present).
  wwtp_primary_removal = 0.23,

  # wwtp_secondary_removal: fraction removed during secondary treatment (biological).
  #   Default 0.96 (96% removal). Applied only if uwwSeconda == -1 (present).
  wwtp_secondary_removal = 0.96

  # --- Parameters NOT YET implemented (GAP 2: Diffuse emission) ---
  # TODO(DIFFUSE-EMISSION): Add these fields when data becomes available:
  # f_diff = NA        # fraction of population without sanitation access [-]
  # f_runoff = NA      # fraction of excreted pathogens reaching surface water [-]
  # livestock_prevalence = NA  # for zoonotic pathogens (GAP 8)
  # livestock_excretion = NA   # oocysts/animal/year
)
