# High-Resolution Flow Rollout Plan (Bega First, Volta in Steps)

## Summary
Roll out high-resolution flow in controlled phases:
1. Activate and stabilize high-resolution flow for all Bega simulations.
2. Lock behavior with regression checks.
3. Prepare Volta capability flags and guardrails.
4. Enable Volta high-resolution only after compatible source integration and validation.

## Phase 1 — Bega First (Implement Now)
- [x] Set `flow_source = "highres_qav"` as default for all Bega simulation scenarios.
- [x] Keep fallback support (`"configured"`) for reproducibility/debugging.
- [x] Ensure `scripts/run_all_scenarios.R` preserves scenario-level flow selection.
- [x] Add/keep startup validation: if `highres_qav` is selected and raster is missing, fail with clear error.
- [x] Keep verbose inline comments in config and hydrology selector code.

## Phase 2 — Bega Validation & Regression Lock
- [ ] Build/install and smoke test:
  - `R CMD INSTALL Package`
  - `Rscript scripts/smoke-test.R`
- [ ] Run all Bega simulations and confirm clean output regeneration.
- [ ] Run Bega ibuprofen regression test with explicit high-res flow selection.
- [ ] Add/check one batch assertion that flow source provenance is explicit in logs/outputs and no silent fallback occurs.

### Phase 2 Acceptance Criteria
- [ ] All Bega scenarios complete with high-res selected by default.
- [ ] Regression test is deterministic and passing.

## Phase 3 — Volta Preparation (No Activation Yet)
- [ ] Add basin capability flags:
  - `supports_highres_qav` (`TRUE`/`FALSE`)
  - optional `highres_reason_if_false`
- [ ] Add centralized validation in `AssignHydrology()` to block unsupported high-res selection with explicit guidance.
- [ ] Update docs (`AGENTS.md` + scenario docs) to state:
  - Bega high-res active
  - Volta high-res pending compatible source integration

## Phase 4 — Volta Enablement in Steps
- [ ] Step 4.1: define Volta-compatible high-res provider profile in config (no hardcoding).
- [ ] Step 4.2: implement harmonization layer (CRS/extent/resolution/nodata/units).
- [ ] Step 4.3: pilot on `VoltaWetChemicalIbuprofen`.
- [ ] Step 4.4: validate Q/V/H and concentration sanity vs baseline.
- [ ] Step 4.5: roll out to remaining Volta HydroSHEDS scenarios.
- [ ] Step 4.6: keep GeoGLOWS scenarios unchanged unless explicitly requested.

### Phase 4 Acceptance Criteria
- [ ] Volta pilot completes with coherent hydraulics and without artificial spikes from source mismatch.
- [ ] Full Volta HydroSHEDS suite passes after pilot signoff.

## Test Plan
- [ ] Unit/behavior tests for flow-source selection and guardrails.
- [ ] Integration tests for Bega high-res end-to-end simulation path.
- [ ] Batch run `scripts/run_all_scenarios.R` and verify no regressions outside Bega.
- [ ] Spot-check `hydrology_nodes.csv` and concentration outputs for plausible behavior.

## Assumptions and Defaults
- [ ] Bega default flow source is high-resolution.
- [ ] Volta stays on current flow path until a compatible high-res source is integrated and validated.
- [ ] GeoGLOWS Volta scenarios are out of scope for this rollout.
- [ ] Unsupported high-res selection fails fast (unless scenario explicitly uses `"configured"`).
