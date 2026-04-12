calc_temp_decay <- function(base_rate, temp_water, theta) {
  base_rate * exp(theta * (temp_water - 4))
}

calc_light_attenuation <- function(doc_conc, kd) {
  kd * doc_conc
}

calc_solar_decay <- function(solar_rad, kl, ke, depth) {
  res <- rep(0, length(depth))
  valid <- !is.na(depth) & depth > 0 & !is.na(ke) & ke > 0
  if (any(valid)) {
    res[valid] <- (solar_rad[valid] / (ke[valid] * depth[valid])) *
      (1 - exp(-ke[valid] * depth[valid])) * kl
  }
  res
}

calc_sedimentation_decay <- function(settling_vel, depth) {
  res <- rep(0, length(depth))
  valid <- !is.na(depth) & depth > 0
  if (any(valid)) {
    res[valid] <- settling_vel / depth[valid]
  }
  res
}

calc_total_dissipation_rate <- function(temp_decay, solar_decay, sed_decay) {
  (temp_decay + solar_decay + sed_decay) / 86400
}
