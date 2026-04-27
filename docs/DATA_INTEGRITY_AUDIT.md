# Data Integrity and Manipulation Audit: ePiE

This audit analyzes the `./AudLem/` codebase for non-physical alterations, specifically focusing on its performance for the "Ibuprofen" and "EU/Bega Basin" datasets.

## 1. Physical Scaling (Volume Bug Fix)

**Risk:** Major Result Shift (1000x Discontinuity)
**Location:** `AudLem/ePiE/Package/src/compenvcons_v4.cpp` (Line 178)
**Observation:** In the CSTR (Lake) model, `./SHoeks/` (legacy) used a volume conversion factor of `1e6` to convert $km^3$ to $m^3$. This was a physical bug ($1 km^3 = 10^9 m^3$).
**Refactored Logic:** `./AudLem/` corrects this to `1e9`. While this ensures physical correctness, it means any longitudinal dataset for lakes in the **Bega Basin** will show a **1000x decrease** in concentration when switching between repository versions.

## 2. Hidden Regularization (Flow Clamping)

**Risk:** Model Artifact (Regularized Noise Floor)
**Location:** `AudLem/ePiE/Package/src/compenvcons_v4.cpp` (Line 185, 218)
**Observation:** To prevent division-by-zero on "dry" river reaches (e.g., Volta Dry scenario), `./AudLem/` clamps the discharge ($Q$) to a minimum threshold.
**Refactored Logic:** 
```cpp
double Q_safe = pts_Q[j] > 0.001 ? pts_Q[j] : 0.001;
```
This acts as a global regularizer, preventing infinite concentration spikes in arid basins but also masking the model's inability to handle zero-flow conditions physically.

## 3. Thresholding and Denoising

**Risk:** Clipped Corruption
**Location:** `AudLem/ePiE/Package/src/compenvcons_v4.cpp` (Line 167)
**Observation:** `./AudLem/` explicitly checks for `NaN` emissions before processing a node.
**Refactored Logic:**
```cpp
if (std::isnan(pts_E_w[j]) || std::isnan(pts_E_up_tmp[j])) {
    // Skip node and continue
}
```
This "denoises" the simulation by preventing data corruption from cascading downstream, but it can hide structural issues in the input basin geometries.

## 4. Hardcoded Environmental Priors

**Risk:** Model Bias
**Location:** `AudLem/ePiE/Package/R/02_PathogenModel.R`
**Observation:** When local basin data is missing (e.g., in the **Bega Basin** dataset), the model falls back to hardcoded environmental parameters.
**Refactored Logic:**
- **Water Temp (T_sw):** Defaults to 285 K (11.85°C).
- **River Depth (H):** Defaults to 0.001 m.
- **DOC Concentration (C_DOC):** Defaults to 0.005 mg/L.
These "priors" provide stability but may not be representative of the actual environmental state in the specific datasets under test.
