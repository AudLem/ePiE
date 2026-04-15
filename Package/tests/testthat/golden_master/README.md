# Golden Master Files

This directory contains golden master (reference) outputs for regression testing.

## Files

### `gm_ouse_ibuprofen_r_v1.25.rds`
- **Version:** v1.25
- **Basin:** Ouse (UK)
- **Substance:** Ibuprofen
- **Description:** Contains chemical properties and concentration results for testing the SimpleTreat and concentration engine (ComputeEnvConcentrations)
- **Used by:** `test-regression.R`
- **Status:** Legacy - Note that v1.26 formula fixes (lake volume 1e6 -> 1e9) changed results, so some expectations in `test-regression.R` may fail

### `gm_volta_wet_v1.26.rds`
- **Version:** v1.26
- **Basin:** Volta (Ghana) - wet season
- **Description:** Contains network topology (points, lakes, rivers, agglomerations) with multi-inlet lake fix and simplification changes
- **Used by:** Network regression tests
- **Contents:**
  - `points`: 353 network nodes
  - `HL_basin`: 7 lakes
  - `agglomeration_points`: 140 agglomeration sources
  - `hydro_sheds_rivers_basin`: 37 river edges
  - `lines`: network line segments
- **Generated with:** `generate_volta_golden_master.R`

### `gm_bega_ibuprofen_v1.25.rds`
- **Version:** v1.25 (SHoeks)
- **Basin:** Bega (Romania)
- **Substance:** Ibuprofen
- **Description:** Contains v1.25 C++ engine results for the Bega river network, used to test v1.26 regression. The golden master captures v1.25 behavior including the lake volume bug (V = Vol_total * 1e6 instead of 1e9), HL$E_in double-counting, and missing LakeInlet/LakeOutlet exclusion in k_NXT averaging.
- **Used by:** `test-regression-bega-v1.25-vs-v1.26.R`
- **Contents:**
  - `chem`: Ibuprofen properties (from LoadExampleChemProperties + CompleteChemProperties)
  - `cons`: 51-country consumption table (from LoadExampleConsumption)
  - `results_cpp$pts`: 478 river nodes with C_w, C_sd, WWTPremoval
  - `results_cpp$hl`: 9 lake nodes
  - `metadata`: network summary and detailed v1.25-vs-v1.26 change documentation
- **Generated with:** `generate_bega_golden_master_v1.25.R` (reads from SHoeks v1.25 output CSVs)
- **Source data:** `/Users/gtazzi/SHoeks/ePiE/Outputs/bega_ibuprofen/`

#### v1.25 vs v1.26: What Produces Different Results

This golden master is specifically designed to test the following changes between v1.25 and v1.26:

| # | Change | File (v1.25 line -> v1.26 line) | Impact |
|---|--------|-------------------------------|--------|
| 1 | **Lake volume conversion bug fix**: `V = Vol_total * 1e6` -> `V = Vol_total * 1e9` (correct km3->m3) | `R/Compute_env_concentrations_v4.R:58` -> `:84` | **HIGH** — 1000x more dilution in lakes |
| 2 | **HL$E_in double-counting fix**: excludes LakeInlet, LakeOutlet, WWTP, agglomeration nodes from lake inflow sum | `R/Set_local_parameters_custom_removal_fast3.R:197-200` -> `:260-276` | **HIGH** — reduces lake C_w when sources inside lakes |
| 3 | **k_NXT excludes LakeInlet/LakeOutlet**: avoids averaging dissipation rate across lake boundaries | `R/Set_local_parameters_custom_removal_fast3.R:430` -> `:506` | **MEDIUM** — changes decay near lakes |
| 4 | **Consumption column normalization**: `cons$country` -> `cons$cnt` + `F_direct` -> `f_direct` | `R/Set_local_parameters_custom_removal_fast3.R:82,88,179` -> `:42-49,129,232` | **LOW** — no effect if cons uses `cnt` |
| 5 | **Tertiary treatment column safety**: defensive creation of uwwNRemova etc. when missing | `R/Set_local_parameters_custom_removal_fast3.R` (missing) -> `:194-198` | **LOW** — only affects NA handling |
| 6 | **C++ `which()` returns -1 on miss** instead of OOB index `n` | `src/compenvcons_v4.cpp:28-68` -> `:29-50` | **NONE** — only affects broken networks |
| 7 | **C++ `hl_fin.reserve` fix**: `reserve(nrow_pts)` -> `reserve(nrow_hl)` | `src/compenvcons_v4.cpp` (near reserve) -> (near reserve) | **NONE** — memory only |

#### Expected Test Outcomes

**Should match (tolerance 1e-6):** SimpleTreat4_0, CompleteChemProperties, WWTPremoval, C_w on river-only subnetwork, R vs C++ engine parity

**Should diverge (intentional):** Lake outlet C_w (~1000x lower in v1.26), downstream node C_w (cascading from lake fix), overall max C_w

## Regenerating Golden Masters

To regenerate a golden master:

1. Run the generation script (e.g., `generate_volta_golden_master.R`)
2. Review the changes to ensure they are intentional
3. Commit the updated `.rds` file
4. Update this README with any version or content changes

## Notes

- Golden masters should be regenerated when:
  - Network topology logic changes
  - Lake handling changes
  - Formula fixes that affect results
  - New data sources are integrated
- Always use a fixed seed (e.g., `set.seed(42)`) for reproducibility
- Document the reason for regeneration in the git commit message