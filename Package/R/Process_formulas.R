# ==============================================================================
# Pathogen Decay Formulas
# ==============================================================================
# Each function computes one decay pathway (day^-1). The total dissipation rate
# is the sum of three pathways: temperature-dependent inactivation (K_T),
# solar radiation inactivation (K_R), and sedimentation (K_S).
#
# Reference framework: Vermeulen et al. (2019), Water Research 149, 202-214.
# DOI: 10.1016/j.watres.2018.10.069
#
# Governing equation (Proposal Formula P1):
#   k = K_T + K_R + K_S   [day^-1]
#
# These functions operate on vectors (one value per network node) to enable
# efficient batch computation across the entire basin.
# ==============================================================================

# --- Formula P2: Temperature-dependent decay K_T --------------------------------
# Governing equation:  K_T = K4 * exp(theta * (T_water_C - 4))
#   K4        = base decay rate at 4 deg C       [day^-1]
#   theta     = temperature correction factor     [-]
#   temp_water = water temperature in Celsius      [deg C]
#
# The subtraction of 4 normalises to the reference temperature (4 degC).
# For Cryptosporidium: K4 = 0.0051, theta = 0.158 (Vermeulen 2019, Table 2).
#
# Reference: Peng et al. (2008), Environ. Sci. Technol.
# TODO(MULTI-PATHOGEN): Each pathogen has its own K4 and theta values.
#   Create inst/pathogen_input/<name>.R with pathogen-specific values.
#   Current structure already supports this — only a new parameter file is needed.
# --------------------------------------------------------------------------------
calc_temp_decay <- function(base_rate, temp_water, theta) {
  base_rate * exp(theta * (temp_water - 4))
}

# --- Formula P4: Light attenuation coefficient ke --------------------------------
# Governing equation:  ke = kd * C_DOC
#   kd     = DOC-specific light attenuation coefficient  [L mg^-1 m^-1]
#   doc_conc = dissolved organic carbon concentration    [kg/L]
#
# ke represents how quickly light is attenuated through the water column.
# Higher DOC → more attenuation → less solar inactivation at depth.
#
# Reference: Vermeulen (2018), PhD thesis, VU Amsterdam.
# --------------------------------------------------------------------------------
calc_light_attenuation <- function(doc_conc, kd) {
  kd * doc_conc
}

# --- Formula P3: Solar radiation inactivation K_R --------------------------------
# Governing equation:  K_R = (I / (ke * H)) * (1 - exp(-ke * H)) * kl
#   I       = solar radiation at surface  [kJ m^-2 day^-1]
#   ke      = light attenuation coefficient [m^-1]
#   H       = water column depth            [m]
#   kl      = solar proportionality constant [m^2 kJ^-1]
#
# The term (1 - exp(-ke*H)) / (ke*H) computes the depth-averaged fraction
# of surface radiation penetrating the water column ( Beer-Lambert law).
# When ke or depth is zero/NA, K_R defaults to 0 (no solar inactivation).
#
# Reference: Mancini (1978), J. WPCF 50(11); Thomann & Mueller (1987).
# TODO(MULTI-PATHOGEN): kl is pathogen-specific (e.g. Rotavirus has different
#   solar sensitivity). Supply via the pathogen parameter file.
# --------------------------------------------------------------------------------
calc_solar_decay <- function(solar_rad, kl, ke, depth) {
  res <- rep(0, length(depth))
  valid <- !is.na(depth) & depth > 0 & !is.na(ke) & ke > 0
  if (any(valid)) {
    res[valid] <- (solar_rad[valid] / (ke[valid] * depth[valid])) *
      (1 - exp(-ke[valid] * depth[valid])) * kl
  }
  res
}

# --- Formula P5: Sedimentation inactivation K_S ----------------------------------
# Governing equation:  K_S = v_settling / H
#   v_settling = settling velocity of pathogen particles  [m/day]
#   depth      = water column depth                        [m]
#
# Assumes pathogens attached to particles settle out of the water column at a
# constant rate proportional to settling velocity and inversely proportional
# to depth. This is a permanent removal (no resuspension modelled).
#
# Reference: Vermeulen et al. (2019).
# TODO(SEASONAL): Resuspension during high-flow events is not modelled.
#   Future work could add a resuspension term triggered by Q exceeding a
#   threshold, coupling with the flood/inundation module (GAP 3).
# --------------------------------------------------------------------------------
calc_sedimentation_decay <- function(settling_vel, depth) {
  res <- rep(0, length(depth))
  valid <- !is.na(depth) & depth > 0
  if (any(valid)) {
    res[valid] <- settling_vel / depth[valid]
  }
  res
}

# --- Formula P1: Total dissipation rate k ----------------------------------------
# Governing equation:  k = (K_T + K_R + K_S) / 86400
#
# Converts from day^-1 to s^-1 for use in the transport engine, which computes
# travel times in seconds. The division by 86400 (seconds per day) is the
# unit conversion factor.
#
# This k is used downstream in:
#   - River transport: C_downstream = C * exp(-k * travel_time)  (Formula P10)
#   - Lake CSTR: C_lake = E / (Q + k*V)                          (Formula P11)
# --------------------------------------------------------------------------------
calc_total_dissipation_rate <- function(temp_decay, solar_decay, sed_decay) {
  (temp_decay + solar_decay + sed_decay) / 86400
}
