# ePiE Pathogen Modelling: Proposal vs Implementation Audit

## 1. Overview

This document cross-references Aude Lemme's PhD proposal, two presentation decks
(WP2_Aude_updates_jan_2026.pptx, WP2_Aude_Water_Quality_Modelling.pptx), and the
PE&RC project proposal (PE&RC_PhD_PP_AJLemme.pdf) against the current ePiE codebase.

It lists every formula mentioned in the research documents, maps it to the code
implementation (or notes its absence), and flags gaps.

---

## 2. Proposal References

| # | Reference | Cited for | Used in code |
|---|-----------|-----------|-------------|
| 1 | Oldenkamp et al. (2018). A High-Resolution Spatial Model to Predict Exposure to Pharmaceuticals in European Surface Waters: EPIE. Environ. Sci. Technol., 52(21), 12494-12503. DOI: 10.1021/acs.est.8b03862 | Original ePiE model, chemical fate & transport | Yes -- all chemical kinetics, partition coefficients, SimpleTreat integration |
| 2 | Vermeulen, L.C. et al. (2019). Cryptosporidium concentrations in rivers worldwide. Water Research, 149, 202-214. DOI: 10.1016/j.watres.2018.10.069 | Pathogen decay rates (K4, theta, kl, kd, v_settling), emission methodology, CSTR lake model | Yes -- Process_formulas.R, config/parameters/cryptosporidium.R |
| 3 | Peng, X. et al. (2008). Cryptosporidium and Giardia in rural groundwater systems in the USA. Environ. Sci. Technol. | Temperature-dependent inactivation | Yes -- cited in calc_temp_decay() |
| 4 | Mancini, J.L. (1978). Numerical estimates of coliform mortality rates under various conditions. J. WPCF, 50(11), 2477-2484 | Solar radiation inactivation | Yes -- cited in calc_solar_decay() |
| 5 | Thomann, R.V. and Mueller, J.A. (1987). Principles of Surface Water Quality Modeling and Control. Harper & Row | Solar inactivation framework | Yes -- cited in calc_solar_decay() |
| 6 | Vermeulen, L.C. (2018). Modelling Cryptosporidium. PhD thesis, VU Amsterdam | Light attenuation from DOC | Yes -- cited in calc_light_attenuation() |
| 7 | Barbarossa, V. et al. (2018). FLO1K: global maps of mean, maximum and minimum annual streamflow at 1 km resolution. Scientific Data, 5(1). DOI: 10.1038/sdata.2018.52 | Streamflow data | Yes -- used via FLO1K NetCDF rasters |
| 8 | Pistocchi, A. and Pennington, D. (2006). | Manning-Strickler hydrology, river width from Q | Yes -- 01_AddFlowToBasinData.R |
| 9 | Schwarzenbach, R.P. et al. (2016). Environmental Organic Chemistry, 2nd ed. | Volatilization two-film model, photolysis | Yes -- chemical kinetics |
| 10 | Mackay, D. (2001). Multimedia Environmental Models: The Fugacity Approach. | Sediment-water exchange, mass transfer | Yes -- chemical kinetics |
| 11 | Burkhard, L.P. (2000). DOI: 10.1002/etc.223 | Kp_DOC = 0.08 * KOW | Yes -- apply_chemical_kinetics() |
| 12 | Sabljic et al. (1995) | KOC from KOW for neutral compounds | Yes -- 02_CompleteChemProperties.R |
| 13 | Franco, A. and Trapp, S. (2008) | KOC from KOW for acids/bases | Yes -- 02_CompleteChemProperties.R |
| 14 | Troeger et al. (2019); Reiner et al. (2020); WHO (2024) | Diarrheal disease burden | Background only (proposal context) |
| 15 | Ferguson et al. (2003) | Need for pathogen-specific models | Background only |
| 16 | Rose et al. (2023) | Global microbial water quality data gaps | Background only |
| 17 | Hofstra et al. (2018/2019) | Modelling framework priorities | Background only |
| 18 | Collender et al. (2016) | Pathogen dynamics during floods | NOT implemented -- flood module is future work |
| 19 | Torres et al. (2012) | Pathogen emissions from flooded areas | NOT implemented |
| 20 | Islam et al. (2017) | Socio-economic pathways impact | NOT implemented -- future scenarios |
| 21 | de Brauwere et al. (2014) | Process-based modelling review | Background only |
| 22 | Semenza et al. (2012) | Climate change and waterborne disease | Background only |
| 23 | Colston et al. (2021) | Pathogen-climate associations | Background only |

---

## 3. Formulas Described in Proposal/Presentations vs Code

### 3.1 PATHOGEN DECAY KINETICS

#### Formula P1: Total decay rate k

**Proposal (slide 9, Water Quality PPT):**
```
k = K_T + K_R + K_S
```

**Code (Process_formulas.R:110-113):**
```r
calc_total_dissipation_rate <- function(temp_decay, solar_decay, sed_decay) {
  total_day <- temp_decay + solar_decay + sed_decay
  return(total_day / 86400)  # convert day-1 to s-1
}
```

**Verdict:** CONFORMS. The code adds the three pathways and converts to s-1 for transport.

---

#### Formula P2: Temperature-dependent decay K_T

**Proposal (slide 9, Water Quality PPT):**
```
K_T = K4 * exp(theta * (T_sw - 273.15 - 4))
```

**Code (Process_formulas.R:27-29):**
```r
calc_temp_decay <- function(base_rate, temp_water, theta) {
  return(base_rate * exp(theta * (temp_water - 4)))
}
```
Called with `temp_water = temp_w - 273.15` (Kelvin to Celsius conversion at
Set_local_parameters_custom_removal_fast2.R:147).

**Verdict:** CONFORMS. Kelvin-to-Celsius conversion happens at the call site.

---

#### Formula P3: Solar radiation inactivation K_R

**Proposal (not explicitly shown in presentations, described in proposal text):**
```
K_R = f(solar radiation, light attenuation, depth)
```

**Code (Process_formulas.R:52-59):**
```r
calc_solar_decay <- function(solar_rad, kl, ke, depth) {
  res[valid] <- (solar_rad[valid] / (ke[valid] * depth[valid])) *
                (1 - exp(-ke[valid] * depth[valid])) * kl
}
```

**Governing equation:** K_R = (I / (ke * H)) * (1 - exp(-ke * H)) * kl

**Source:** Mancini (1978); Thomann & Mueller (1987); Vermeulen (2019)

**Verdict:** CONFORMS.

---

#### Formula P4: Light attenuation from DOC

**Code (Process_formulas.R:74-76):**
```r
calc_light_attenuation <- function(doc_conc, kd) {
  return(kd * doc_conc)
}
```

**Governing equation:** ke = kd * C_DOC

**Source:** Vermeulen (2018) PhD thesis

**Verdict:** CONFORMS.

---

#### Formula P5: Sedimentation inactivation K_S

**Code (Process_formulas.R:87-93):**
```r
calc_sedimentation_decay <- function(settling_vel, depth) {
  res[valid] <- settling_vel / depth[valid]
}
```

**Governing equation:** K_S = v_settling / H

**Verdict:** CONFORMS.

---

### 3.2 PATHOGEN EMISSIONS

#### Formula P6: WWTP point-source emission

**Presentation (slide 7, Water Quality PPT):**
```
Parameters:
  Total Population, Prevalence Rate, Oocysts Excreted per Person
  f_conn = proportion connected to WWTP
```

**Code (Set_local_parameters_custom_removal_fast2.R:92-101):**
```r
number_of_infected_people <- total_population * prevalence_rate
total_oocysts_excreted <- number_of_infected_people * oocysts_excreted_per_person
network_nodes$E_in[wwtp_indices] <- total_oocysts_excreted * network_nodes$f_STP[wwtp_indices]
```

**Governing equation:** E_in_WWTP = pop * prevalence * excretion * f_connection

**Verdict:** CONFORMS.

---

#### Formula P7: WWTP removal efficiency

**Presentation (slide 8, Water Quality PPT):**
```
f_prim = 0.23  (primary treatment)
f_sec  = 0.96  (secondary treatment)
f_remain = (1 - f_prim) * (1 - f_sec)
E_w = E_in * f_remain
```

**Code (Set_local_parameters_custom_removal_fast2.R:103-108):**
```r
f_prim <- ifelse(network_nodes$uwwPrimary[idx] == -1, 0.23, 0)
f_sec <- ifelse(network_nodes$uwwSeconda[idx] == -1, 0.96, 0)
network_nodes$f_rem_WWTP[idx] <- 1 - (1 - f_prim) * (1 - f_sec)
```

**Code (Set_local_parameters_custom_removal_fast2.R:115-119):**
```r
network_nodes$E_w <- ifelse(
  network_nodes$Pt_type == "WWTP",
  network_nodes$E_in * (1 - network_nodes$f_rem_WWTP),
  ifelse(network_nodes$Pt_type == "agglomeration", network_nodes$E_in, 0)
)
```

**Verdict:** CONFORMS. The removal fractions and remaining-fraction logic match exactly.
Note: the code uses actual UWWTD flags (uwwPrimary, uwwSeconda) to determine whether
primary/secondary treatment is present, rather than assuming both always apply.

---

#### Formula P8: Diffuse emission from population (agglomerations)

**Presentation (slide 9, updates_jan_2026 PPT):**
```
Diffuse emission = pop * f_diff * Bact_p * f_runoff
```

**Code (Set_local_parameters_custom_removal_fast2.R:110-113):**
```r
agglomeration_indices <- which(network_nodes$Pt_type == "agglomeration")
network_nodes$E_in[agglomeration_indices] <-
  network_nodes$total_population[agglomeration_indices] * prevalence_rate * oocysts_excreted_per_person
```

**Verdict:** PARTIAL CONFORMANCE.
- The formula in the presentation includes f_diff (fraction without sanitation) and
  f_runoff (fraction reaching surface water), but the code does NOT apply these factors.
- The code applies `pop * prevalence * excretion` directly to agglomeration nodes without
  accounting for sanitation access fraction or runoff transport fraction.
- This is a GAP -- the proposal specifically identifies diffuse emission modelling as
  a next step. The current code treats all agglomeration points as direct discharge.

---

### 3.3 IN-STREAM TRANSPORT

#### Formula P9: Node concentration (pathogen)

**Code (Compute_env_concentrations.R:132):**
```r
pts.concentration_water[j] <- (node_total_load / (365 * 24 * 3600)) / (pts.river_discharge[j] * 1000)
```

**Governing equation:** C_w = (E_total / seconds_per_year) / (Q * L_per_m3) [oocysts/L]

**Verdict:** CONFORMS to steady-state mass balance: C = emission_rate / flow_rate.

---

#### Formula P10: Downstream transport with first-order decay

**Code (Compute_env_concentrations.R:140):**
```r
pts.emission_to_next[j] <- node_total_load * exp(-k_nxt * dist_nxt / V_nxt)
```

**Governing equation:** E_downstream = E_total * exp(-k * travel_time)
where travel_time = distance / velocity

**Verdict:** CONFORMS. First-order exponential decay along travel distance.

---

#### Formula P11: Lake concentration (CSTR model)

**Code (Compute_env_concentrations.R:98):**
```r
pts.concentration_water[j] <- (node_total_load / (Q + k * V) / 86400) * 1000
```

**Governing equation:** C_lake = E / (Q + k * V) [oocysts/L]

This is the steady-state Completely Stirred Tank Reactor (CSTR) approximation.

**Verdict:** CONFORMS. Standard CSTR assumption for lakes.

---

### 3.4 CHEMICAL FATE & TRANSPORT (5 dissipation pathways)

#### Formula C1: Partition coefficients

**Code (Set_local_parameters_custom_removal_fast2.R:181-222):**
- Kp_susp = KOC * fOC_susp
- Kp_DOC = 0.08 * KOW (Ref: Burkhard 2000)
- Kp_sd = KOC * fOC_sd

**Source:** Oldenkamp et al. (2018), Eq. S2-S3

**Verdict:** CONFORMS.

---

#### Formula C2: Dissolved fractions

**Code (Set_local_parameters_custom_removal_fast2.R:224-234):**
- f_diss = 1 / (1 + Kp_susp * C_susp + Kp_DOC * C_DOC) [Ref: Oldenkamp 2018 Eq. S4]
- f_diss_sed = 1 / (1 + Kp_sd * rho_sd * (1-poros)/poros) [Ref: Oldenkamp 2018 Eq. S5]

**Verdict:** CONFORMS.

---

#### Formula C3: Total chemical dissipation

**Code (Set_local_parameters_custom_removal_fast2.R:339):**
```r
nodes$k <- k_bio_w + k_photo_w + k_hydro_w + k_sed + k_vol
```

Five pathways: biodegradation + photolysis + hydrolysis + net sedimentation + volatilization.

**Source:** Oldenkamp et al. (2018), Eq. S6-S20

**Verdict:** CONFORMS.

---

#### Formula C4: KOC estimation from KOW

**Code (02_CompleteChemProperties.R:74-84):**
- Neutral: KOC = 1.26 * KOW^0.81 (Sabljic et al. 1995)
- Acid: log(KOC) = 0.54 * log(KOW) + 1.11 (Franco & Trapp 2008)
- Base: log(KOC) = 0.37 * log(KOW) + 1.70 (Franco & Trapp 2008)

**Verdict:** CONFORMS.

---

### 3.5 HYDROLOGY

#### Formula H1: Manning-Strickler velocity and depth from Q

**Code (01_AddFlowToBasinData.R:294-313):**
```r
W <- 7.3607 * Q^0.52425                     # river width from Q
V <- n^(-3/5) * Q^(2/5) * W^(-2/5) * S^(3/10)  # velocity (Manning)
H <- Q / (V * W)                             # depth
```

**Source:** Pistocchi and Pennington (2006)

**Verdict:** CONFORMS. Standard hydraulic geometry relations.

---

#### Formula H2: Section-based canal discharge (KIS)

**Code (02_prepare_canal_layers.R):**
```r
assign_canal_discharge(canals, cfg)  # reads KIS_canal_discharge.csv
```

Each canal segment gets a discharge interpolated between head and tail values
from the JICA APGIP report.

**Source:** JICA APGIP Annex C Fig C.6(2)

**Verdict:** IMPLEMENTED. Replaces previous uniform 7.2 m3/s with section-based values.

---

## 4. GAPS: What the Proposal Describes but Is NOT Yet Implemented

### GAP 1: Multi-pathogen support

**Proposal objective 1:** "Extend ePiE to four diverse microbiological contaminants:
Rotavirus, Campylobacter, Cryptosporidium, and Giardia."

**Current state:** Only Cryptosporidium has a parameter file
(config/parameters/cryptosporidium.R). No parameter files exist for Rotavirus,
Campylobacter, or Giardia. The decay formula structure supports them (same K_T, K_R, K_S
framework with pathogen-specific parameters), but the parameters are not defined.

**Files needed:**
- config/parameters/rotavirus.R
- config/parameters/campylobacter.R
- config/parameters/giardia.R

**What changes:** Each file needs pathogen-specific K4, theta, kl, kd, v_settling,
prevalence_rate, excretion_rate, and total_population.

---

### GAP 2: Diffuse emission from land (agricultural runoff)

**Proposal (slide 9, updates PPT):**
```
Diffuse emission from humans = pop * f_diff * Bact_p * f_runoff
```
**Proposal text:** "Assess diffuse sources by modelling pathogen runoff from land
surfaces, utilizing land cover data and zoonotic emissions."

**Current state:** Agglomeration nodes use `pop * prevalence * excretion` without
f_diff (sanitation access fraction) or f_runoff (overland transport fraction).

**What needs to change:**
- Add f_diff per agglomeration (from sanitation access data, e.g. JMP dataset)
- Add f_runoff per land cover type (from literature, e.g. Vermeulen 2017)
- Use land cover rasters (CORINE for Europe) to identify agricultural proximity
- Integrate zoonotic emission from livestock (manure application timing)

---

### GAP 3: Flood/inundation module

**Proposal objective 3:** "Use flood maps provided by IHE Delft and adapt ePiE model
for stagnant water to estimate the loading, fate and spread of the four pathogens
at a catchment scale during and following a flood."

**Current state:** Not implemented. No flood map integration, no stagnant water module,
no inundation-dependent emission calculations.

**What needs to change:**
- New module: load inundation maps (provided by IHE Delft)
- Modify emission calculations to include flooded-area loading
- Add stagnant water decay (no advection, only K_T + K_R + K_S)
- Account for resuspension of settled oocysts from riverbed sediments
- Account for flooded pit latrines and grazing land contamination

---

### GAP 4: Dam spillage scenarios (Kpong Dam)

**Proposal objective 2 / text:** "Data on the Kpong Dam manoeuvres, including the
outflow and the conditions triggering controlled spillage will be integrated."

**Current state:** Not implemented. The Volta flow is taken from FLO1K rasters
or manual overrides for KIS canals. No dam outflow model or spillage scenarios.

**What needs to change:**
- Define spillage trigger conditions (reservoir level thresholds)
- Create spillage scenario configs with elevated downstream Q
- Possibly couple with reservoir water balance model

---

### GAP 5: Future climate projections (RCPs + SSPs)

**Proposal objective 4:** "Use climate projections to estimate the impact of climate
change and changes in socio-economic factors on pathogen fate and transport."

**Current state:** Not implemented. Model runs under current/historical conditions only.

**What needs to change:**
- Accept downscaled climate projections (from MET Norway, WP2 partner) as input
- Map projected temperature changes to T_sw (affects K_T)
- Map projected precipitation changes to Q (affects dilution, overflow)
- Map SSP pathways to sanitation access (affects f_diff) and population (affects emission)
- Run probabilistic ensembles across climate model spread

---

### GAP 6: Seasonal shedding rates

**Proposal text:** "Incorporate seasonal shedding rates and infection fractions for
each pathogen from literature sources."

**Current state:** Prevalence rate is a single static value (0.05) in
config/parameters/cryptosporidium.R. No seasonal variation.

**What needs to change:**
- Make prevalence_rate time-dependent (monthly or seasonal)
- Add seasonal shedding multipliers per pathogen
- Link to epidemiological data (e.g. Rotavirus peaks in dry/cold season)

---

### GAP 7: Sediment resuspension for pathogens

**Proposal text:** "Sedimentation and resuspension are sometimes considered...
pathogens dynamics are significantly altered when river networks change during
or following overbank flows."

**Current state:** Pathogen model uses a simple settling rate K_S = v_settling / H
(permanent removal). No resuspension. The chemical model DOES have resuspension
(v_res in apply_chemical_kinetics), but the pathogen branch does not.

**What needs to change:**
- Add resuspension rate during high-flow events
- Track settled oocyst pool in sediment
- Resuspend during floods (GAP 3 coupling)

---

### GAP 8: Zoonotic emissions

**Proposal text:** "For zoonotic pathogens the management of the manure and the
timing of its application will be considered."

**Current state:** Not implemented. All emissions are human-derived (WWTP + agglomeration).

**What needs to change:**
- Add livestock population rasters
- Add manure application timing (seasonal)
- Add pathogen shedding rates per livestock species
- Add land-cover-dependent runoff fraction

---

### GAP 9: Second study site (Densu Delta, Ghana)

**Proposal (DMP section):** "Densu Delta and Lower Volta, both in Ghana"

**Current state:** Only Bega (Romania) and Volta (Ghana/Akuse) are configured.
Densu Delta has no config, no data, no shapefiles.

**What needs to change:**
- New config files: config/densu.R, config/densu_simulation.R
- New basin shapefiles and data layers
- New network build and simulation runs

---

## 5. Implementation Status Summary

| Component | Proposal | PPT Jan 2026 | PPT Mar 2025 | Code Status |
|-----------|----------|-------------|-------------|-------------|
| Cryptosporidium decay (K_T + K_R + K_S) | Obj 1 | Slide 9 | Slide 9 | DONE |
| Pathogen emission at WWTP | Obj 1 | Slide 7-8 | Slide 7-8 | DONE |
| WWTP removal (f_prim, f_sec) | Obj 1 | Slide 8 | Slide 8 | DONE |
| Agglomeration emission (no treatment) | Obj 1 | Slide 8 | Slide 9 | DONE (partial: no f_diff, f_runoff) |
| In-stream transport with decay | Obj 1 | Slide 4 | Slide 3 | DONE |
| Lake CSTR model | Obj 1 | -- | -- | DONE |
| Chemical fate (5 pathways) | Background | -- | -- | DONE (ibuprofen) |
| SimpleTreat 4.0 WWTP model | Background | -- | -- | DONE |
| Solar radiation estimation | Background | -- | -- | DONE |
| Manning-Strickler hydrology | Background | -- | -- | DONE |
| KIS section-based canal discharge | Obj 2 | Slide 5-7 | -- | DONE |
| Multi-pathogen (Rotavirus, Campylobacter, Giardia) | Obj 1 | Slide 2-3 | Slide 2-3 | NOT DONE |
| Diffuse emission (f_diff, f_runoff) | Obj 1 | Slide 9 | Slide 4 | NOT DONE |
| Zoonotic emission (livestock) | Obj 1 | -- | Slide 4 | NOT DONE |
| Seasonal shedding rates | Obj 1 | -- | -- | NOT DONE |
| Dam spillage scenarios | Obj 2 | Slide 5-7 | Slide 6 | NOT DONE |
| Flood/inundation module | Obj 3 | -- | Slide 11 | NOT DONE |
| Climate projections (RCPs + SSPs) | Obj 4 | -- | Slide 11 | NOT DONE |
| Pathogen resuspension | Proposal text | -- | -- | NOT DONE |
| Densu Delta study site | DMP section | -- | -- | NOT DONE |
| Validation with sampling data | Obj 5 | Slide 10 | Slide 10 | NOT DONE (awaiting WP4 data) |

---

## 6. Key Milestones from Proposal

| Milestone | Date | Status |
|-----------|------|--------|
| Temporary model for WP3/WP4 (Bega, current climate) | June 2025 | PARTIAL -- Bega works for Cryptosporidium; needs multi-pathogen |
| Model uses climate projections | August 2026 | NOT STARTED |
| Final projections for all study sites | December 2027 | NOT STARTED |

---

## 7. Parameter Completeness: Cryptosporidium

| Parameter | Value in Code | Source | Status |
|-----------|--------------|--------|--------|
| K4 (decay rate at 4C) | 0.0051 day-1 | Vermeulen 2019 | Present |
| theta (temp correction) | 0.158 | Vermeulen 2019 | Present |
| kl (solar proportionality) | 4.798e-4 m2/kJ | Vermeulen 2019 | Present |
| kd (DOC attenuation) | 9.831 L mg-1 m-1 | Vermeulen 2019 | Present |
| v_settling | 0.1 m/day | Vermeulen 2019 | Present |
| prevalence_rate | 0.05 | Literature | Present |
| excretion_rate | 1e8 oocysts/person/year | Literature | Present |
| total_population | 35,100,000 | Basin config | Present (Bega) |
| f_diff (no-sanitation fraction) | -- | NOT SET | MISSING |
| f_runoff (overland transport) | -- | NOT SET | MISSING |
| seasonal_shedding | -- | NOT SET | MISSING |

---

## 8. Conclusion

The core engine is sound and conforms to the proposal's mathematical framework for
Cryptosporidium. The five main gaps -- multi-pathogen parameters, diffuse emissions,
flood scenarios, dam spillage, and climate projections -- align with the proposal's
explicit "next steps" and future objectives. The code architecture (modular pipeline,
config-driven parameters, formula library) is well-suited to support these extensions.
