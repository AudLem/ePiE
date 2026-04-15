# ePiE Improvement Checklist

Generated: 2026-04-14
Branch: `feature/lake-segment-crossing`

---

## 1. Lake-River Connectivity

### 1.1 Multi-Inlet / Multi-Outlet Lakes

- [x] Allow lakes to have more than 1 inlet and 1 outlet
- [x] Rewire ALL upstream nodes to LakeIn (not just the "best" one)
- [x] Fix dangling edge bug: upstream nodes from non-selected inlets reference deleted interior node IDs
- [x] Wire secondary inlets to LakeIn node (aggregated CSTR per SWAT standard)
- [x] Wire secondary outlets from LakeOut node to their respective downstream nodes
- [ ] Update simulation engine to handle multiple upstream parents converging into one LakeIn
  - File: `Package/R/Compute_env_concentrations_v4.R` Case 3 (lines 165+)
  - File: `Package/src/compenvcons_v4.cpp` lines 317-331
- [ ] Consider naming convention for multi-inlet/outlet nodes (e.g., `LakeIn_1405735_1`, `LakeIn_1405735_2`)

### 1.2 Segment-Based Crossing Detection (already implemented, needs cleanup)

- [x] Create `DetectLakeSegmentCrossings()` function
  - File: `Package/R/18_DetectLakeSegmentCrossings.R`
- [x] Detect lakes with no interior nodes but river segments crossing boundaries
- [x] Handle tangential crossings (segment midpoint inside lake)
- [x] Fix `sfg` vs `sfc` geometry type check for exit point extraction
- [x] Remove debug messages left during development
  - File: `Package/R/18_DetectLakeSegmentCrossings.R`
- [x] Refactor `DetectLakeSegmentCrossings` to eliminate redundant logic duplication:
  - Consolidate dual blocks for `crossing_point` calculation and crossing classification.
  - Extract segment/lake intersection logic into a helper function `AnalyzeSegmentCrossing()`.
- [ ] Add selection criteria for multiple segment crossings (currently picks first row, no LD-based sorting)
  - File: `Package/R/18_DetectLakeSegmentCrossings.R` -> Phase 4.5 in `17_ConnectLakesToNetwork.R`

### 1.3 Lake CSTR Model Consistency

- [x] Document the single-CSTR assumption (1 lake = 1 well-mixed volume) per SWAT/WASP standard
  - Created `docs/LAKE_MODEL.md` with comprehensive documentation
  - Includes formula: C_out = C_in × exp(-k × V/Q)
  - Documents SWAT, WASP, and Bolin & Rodhe (1973) references
  - Lists limitations and applicability criteria
- [x] Verify HL.E_in does not double-count inlet node emissions
  - File: `Package/R/Set_local_parameters_custom_removal_fast3.R` lines 244-254
  - Added detailed comment explaining the calculation order
  - Confirmed: E_in calculation runs BEFORE lake connectivity, so no double-counting
- [x] Add validation: LakeIn x,y and LakeOut x,y must differ (catches coincident-node bug)
  - Added validation in `Package/R/17_ConnectLakesToNetwork.R` lines 72-84
  - Warns if coordinates differ by less than 1e-6 degrees
  - Automatically adjusts LakeOut if coincident
  - Added unit tests in `test-network-lake-connectivity.R`
- [ ] Consider adding a stratification modifier for deep lakes (>30m) as future work

---

## 2. Data Integrity: No Manipulation of Source Data

### 2.1 Lake Polygon Simplification

- [x] Remove `st_simplify()` from lake processing OR make it configurable
  - Current: `st_simplify(HL_basin, preserveTopology = TRUE, dTolerance = 0.001)` (~111m in degrees)
  - File: `Package/R/13_ProcessLakeGeometries.R` line 86
- [x] If keeping simplification: project to UTM first, simplify in meters, project back
  - Pattern already used for rivers in `Package/R/12_ProcessRiverGeometry.R` lines 84-87
- [x] Use `GetUtmCrs()` (already available in `00_utils.R`) for meter-based projection
- [x] Recommended tolerance: 0m (no simplification) or ~10-30m matching HydroLAKES source accuracy (Messager 2016)
- [x] Move tolerance to basin config

### 2.2 River Geometry Simplification

- [x] Make river simplification tolerance configurable from basin config
  - Current: hardcoded `dTolerance = 100` meters (GeoGLOWS mode only)
  - File: `Package/R/12_ProcessRiverGeometry.R` line 86
- [x] For HydroSHEDS mode: consider removing simplification (source is already 30 arc-sec / ~900m)
- [x] Move tolerance to basin config

### 2.3 Canal Geometry

- [x] Exclude canals from river simplification (currently simplified as side effect)
  - File: `Package/R/12_ProcessRiverGeometry.R` lines 84-88 (canals merged into `hydro_sheds_rivers` at step 02b)
- [x] Add `canal_simplify = FALSE` config option
- [x] Canal source accuracy is 5-15m (manually digitized) -> simplification is inappropriate

### 2.4 Basin Config Parameters

- [x] Add spatial processing parameters to all basin configs
  - Files: `Package/inst/config/basins/volta.R`, `volta_geoglows.R`, `bega.R`
  ```r
  lake_simplify_tolerance_m  = 0,
  river_simplify_tolerance_m = 100,
  canal_simplify             = FALSE,
  preserve_topology          = TRUE
  ```
- [x] Update `BuildNetworkPipeline()` to pass these to processing functions
- [x] Update `ProcessLakeGeometries()` to accept tolerance parameter
- [x] Update `ProcessRiverGeometry()` to accept tolerance parameter

---

## 3. Test Infrastructure & Consistency

### 3.1 Checkpoint Infrastructure (midpoint exports)

- [x] Add `stop_after_step` parameter to `BuildNetworkPipeline()`
  - File: `Package/R/31_BuildNetworkPipeline.R`
- [x] Add `checkpoint_dir` parameter to `BuildNetworkPipeline()`
- [x] Save `state_step{N}.rds` after each step when `checkpoint_dir` is set
- [x] Add `PrintCheckpointSummary()` utility function
  - File: `Package/R/00_utils.R`
  - Print nrow, column names, key stats, elapsed time
- [x] Refactor `RunSimulationPipeline()` to use accumulating `sim_state` list
  - File: `Package/R/32_RunSimulationPipeline.R`
  - Currently uses local variables that get overwritten at each stage
- [x] Add same `stop_after_step` / `checkpoint_dir` to simulation pipeline

### 3.2 Pipeline Consistency Tests

- [x] Create `tests/testthat/helper-checkpoints.R` with shared utilities
  - `expect_valid_network()` (checks dangling edges)
  - `expect_consistent_schema()` (checks mandatory topology columns)
- [x] Create `tests/testthat/test-network-schema.R`
  - Required columns present with correct types in `pts` and `HL`
  - Coordinate ranges per basin (Volta: x[-2,2], y[5,12]; Bega: x[24,30], y[44,48])
  - No duplicate IDs
  - No dangling edges (all `ID_nxt` values reference existing `ID`)
  - `lake_in` / `lake_out` flags consistent with `pt_type`
- [x] Create `tests/testthat/test-network-determinism.R`
  - Run pipeline twice, assert `identical()` on all outputs
- [x] Create `tests/testthat/test-network-lake-connectivity.R`
  - Expected number of lakes connected (Volta: 6)
  - Expected lake IDs connected: 1405722, 1405733, 180414, 1405735, 1405736, 1405738
  - Each LakeIn has matching LakeOut for same Hylak_id
  - LakeIn and LakeOut at different coordinates (not coincident)
  - No upstream node references a deleted interior node
- [x] Create `tests/testthat/test-network-topology.R`
  - No cycles in ID_nxt chain
  - Exactly one MOUTH per connected component
  - LD monotonically decreases upstream
  - d_nxt positive and finite for non-terminal nodes

### 3.3 Midpoint Value Assertions

- [ ] Step 3 (river processing): segment count > 0, valid LINESTRING, no empty geometries
- [ ] Step 4 (lake processing): lake count matches source, all polygons valid, area > 0
- [ ] Step 8b (lake connectivity): LakeIn count = LakeOut count = connected lake count

### 3.4 Golden Master

- [ ] Regenerate golden master for v1.26 (lake volume 1e6->1e9 fix changed results)
  - Current: `tests/testthat/golden_master/gm_ouse_ibuprofen_r_v1.25.rds` is stale
  - File: `Package/tests/testthat/test-regression.R` lines 49, 71 have known-fail comments
- [ ] Add Volta pathogen golden master (`gm_volta_crypto_wet.rds`)
- [ ] Add dry season golden master

---

## 4. Visualization & Output Standards

### 4.1 Map Generation

- [ ] Replace base R `plot()` static PNGs with `tmap` for publication quality
  - Current: `png() + plot() + dev.off()` in `Package/R/1A_VisualizeNetwork.R` lines 156-173
  - Base R spatial plots have no legend, no scale bar
- [ ] Standardize `selfcontained = FALSE` with libdir for all leaflet exports
  - Currently mixed: network tries TRUE then fallback; concentration always FALSE; legacy always TRUE
- [ ] Add `addScaleBar()` to all leaflet maps
- [ ] Fix static PNGs to use EPSG:4326 (currently plot in original CRS)
  - File: `Package/R/1A_VisualizeNetwork.R` lines 157-165
- [ ] Remove `setwd()` from `CreateHTMLMaps()`
  - File: `Package/R/Create_multi_maps_scaled_v2.R` lines 54-56

### 4.2 CSV Output Standards

- [ ] Add explicit `fileEncoding = "UTF-8"` to all `write.csv()` calls
- [ ] Deprecate `HL.csv` (uppercase), keep only `hl.csv`
  - Both are written by `Package/R/19_SaveNetworkArtifacts.R`
  - Some configs reference `HL.csv`, some `hl.csv`
- [ ] Standardize file naming: `{prefix}_{basin}_{season}_{scenario}.csv`
- [ ] Consider `data.table::fwrite()` for performance (10-100x faster)
- [ ] Define and validate output schema (column set, types) before writing

### 4.3 Output Directory Structure

```
{run_output_dir}/
  network/
    pts.csv
    hl.csv
    network_points.shp
    network_rivers.shp
    network_lakes.shp
  simulation/
    results_pts_{substance}.csv
    results_hl_{substance}.csv
  plots/
    interactive_network_map.html
    interactive_concentration_map.html
    static_network_overview.png
    static_node_types.png
  checkpoints/
    state_step01.rds
    summary_step01.txt
    state_step02b.rds
    summary_step02b.txt
    ...
  logs/
    pipeline_{timestamp}.log
    config_{timestamp}.yml
```

---

## 5. Logging & Reproducibility

### 5.1 Logging Framework

- [ ] Add `lgr` or `logger` package to Imports
- [ ] Replace `message()` calls with structured logger (INFO, WARN, ERROR levels)
- [ ] Add timestamps to all log messages
- [ ] Add file-based logging (`pipeline_{timestamp}.log`)
- [ ] Log elapsed time per pipeline step
- [ ] Log data file hashes (MD5) at load time for provenance tracking
- [ ] Log all config parameters at pipeline start

### 5.2 Checkpoint Messages

- [ ] Standardize `[CHECKPOINT]` markers at every major output
  - Currently only 2 exist (map saves in `1A_VisualizeNetwork.R:176`, `23_VisualizeConcentrations.R:168`)
- [ ] Print summary table at each checkpoint (nrow, key statistics)

### 5.3 Reproducibility

- [ ] Add `renv::snapshot()` to create `renv.lock`
- [ ] Add `renv::restore()` to CI setup
- [ ] Consider GitHub Actions CI workflow

---

## 6. Dependency Cleanup

### 6.1 Remove Unused Dependencies

- [ ] Remove `knitr` from Suggests (no .Rmd files in package)
- [ ] Remove `future` from Suggests (not used anywhere)
- [ ] Remove `mapview` reference from `BuildPkg.R` (not in DESCRIPTION, not used)
- [ ] Remove dead code: `InteractiveResultMap()`, `ViewBasinMap()` in `RunExample.R`

### 6.2 Modernize Dependencies

- [ ] Replace `raster::extract()` with `terra::extract()`
  - `terra` handles sf natively, avoiding `methods::as(pts, "Spatial")` coercion
  - File: `Package/R/19_SaveNetworkArtifacts.R`
- [ ] Remove `raster` from Imports once migration is complete
- [ ] Consider replacing `plyr::rbind.fill` with `dplyr::bind_rows` or `vctrs::vec_rbind`

### 6.3 Code Quality

- [ ] Add `.lintr` configuration for static analysis
- [ ] Add `styler` for consistent formatting
- [ ] Replace `options(warn=-1)` in `Calculate_stats.R` with `suppressWarnings()`
  - File: `Package/R/Calculate_stats.R` lines 12, 29
- [ ] Remove `assign("HL", ..., envir = .GlobalEnv)` from `RunSimulationPipeline`
  - File: `Package/R/32_RunSimulationPipeline.R` line 201

---

## 7. Hydraulic System: Single Merge at End

- [ ] Ensure the hydraulic network ends with a single merged outlet
  - Currently may have multiple disconnected components after lake connectivity
- [ ] Validate that all river segments ultimately connect to a single mouth
- [ ] Handle the case where lake segment crossings create parallel flow paths
- [ ] Ensure canal-river merges produce a single coherent network

---

## 8. Literature Compliance Summary

| Issue | Literature says | Current ePiE | Action |
|------|----------------|-------------|--------|
| Lake simplification | Use source accuracy (~10-30m, Messager 2016) | 111m in degrees, WGS84 | Remove or use UTM + meters |
| River simplification | Oldenkamp 2018 used raw 30 arc-sec data | 100m UTM (GeoGLOWS only) | Keep, make configurable |
| Canal simplification | No literature supports it | Unintentional 100m side effect | Exclude canals |
| Multi-inlet lakes | SWAT aggregates to single inflow | 1 in / 1 out with dangling edges | Wire all inlets to LakeIn |
| Single CSTR | Standard for screening (Rueda 2006) | Implemented correctly | Document assumption |
| Simplify in projected coords | OGC/ISO 19107 | Lakes: degrees; Rivers: UTM | Use UTM for all |
| Units | Meters for spatial operations | Mixed (degrees + meters) | Standardize to meters |
| Data provenance | Essential for reproducibility (SWAT/MODFLOW) | None | Add file hashing + logging |

---

## References

- Oldenkamp et al. (2018) - ePiE original model, ES&T 52(21) - DOI: 10.1021/acs.est.8b03862
- Vermeulen et al. (2019) - GloWPa-Crypto, Water Research 149 - DOI: 10.1016/j.watres.2018.10.069
- Messager et al. (2016) - HydroLAKES, Nature Communications 7 - DOI: 10.1038/ncomms13603
- Vermeulen et al. (2015) - Advancing waterborne pathogen modelling, Current Opinion in Environmental Sustainability
- Rueda et al. (2006) - CSTR residence time, Ecological Modelling
- Hofstra & Vermeulen (2019) - Modelling framework priorities, Current Opinion in Environmental Sustainability
- Pistocchi & Pennington (2006) - Manning-Strickler hydrology
- Douglas & Peucker (1973) - Simplification algorithm, assumes planar coordinates
