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