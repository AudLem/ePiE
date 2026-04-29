# Changelog

All notable changes to ePiE are documented in this file.

## [1.26.2] - 2026-04-29

### Fixed

- Missing basin path configurations (river_shp_path, basin_shp_path, lakes_shp_path, flow_dir_path, enable_lakes, enable_canals, canal_shp_path, canal_discharge_table, etc.) in 23 simulation configs across Volta, Volta GeoGLOWS, and Bega basins. All simulation scenarios now correctly reference their basin-level data paths.
- GeoGLOWS basin configuration referenced wrong canal shapefile (`KIS_canals.shp` instead of `KIS_canals_types.shp`). Fixed path has no output impact since all GeoGLOWS scenarios set `enable_canals = FALSE`.
- Canal node discharge assignment now strictly uses `KIS_canal_discharge.csv` section head/tail values. Removed `AttachCanalQAnchors` function and `canal_q_anchor_table` config parameter (anchor-based interpolation no longer supported).
- Canal topology analysis now enforces junction-based connections. Nodes at the same coordinates (<1m tolerance) are connected in the geometric topology, preventing incorrect long-distance connections from line segment topology inference.
- Agglomeration and WWTP source nodes are now nudged off protected infrastructure nodes (junctions, canal nodes) via `ResolveCoincidentSourceNodes` to prevent topology corruption.
- Network map display now correctly shows junctions as `JNCT` while preserving model `pt_type` (CANAL_BRANCH, CANAL_NODE, etc.) via separate `display_pt_type` column.
- `AnnotateDisplayJunctions` function now exported to NAMESPACE to enable unit testing.
- Branched canal transport now uses the R edge-aware routing path with automatic fallback from `cpp = TRUE` when multi-downstream topology is present.
- Topology overlays now use transport edges where available, reducing misleading `ID_nxt`-only branch display.
- Lake connection no longer creates centroid fallback `LakeIn`/`LakeOut` nodes. Lakes are active only when directed boundary crossings provide at least one inlet and one outlet.
- Lake CSTR documentation now matches the implemented steady-state mass balance `C_lake = Load / (Q + kV)` rather than describing lake routing as plug-flow exponential decay.

### Added

- `transport_edges.csv` export for final branch-aware routing across rivers, lakes, and canals.
- `lake_connections.csv` and `lake_connection_diagnostics.csv` exports for active lake routing and skipped-lake reasons.
- `canal_edges.csv` diagnostic output with all canal topology edges (reach and branch) and Q metadata.
- `canal_q_diagnostics.csv` diagnostic output with mass balance checks at each branch split.
- New columns on `pts.csv`: `display_pt_type` (map display), `junction_role` (fan_in_receiver, coincident_confluence_node), `Q_role` (parent_branch_available, child_branch_outflow, through_flow, terminal_residual), `Q_parent_m3s`, `Q_out_sum_m3s`, `Q_residual_m3s`.
- New helper functions: `AnnotateDisplayJunctions`, `BuildCanalEdges`, `BuildCanalQDiagnostics`, `ApplyCanalPiecewiseResiduals`, `AnnotateCanalQRoles`, `ResolveCoincidentSourceNodes`.
- Canal topology and Q assignment documentation in `AGENTS.md`.
- `lake_residence_time_days` in simulation/hydrology exports when lake outlet Q is finite.

### Changed

- `data_manifest.json`, `setup-data.sh`, and all documentation now reference v1.26.2.
- Canal node Q interpolation uses piecewise residuals at branch points to preserve upstream flow availability when design Q exceeds available flow.
- Lake crossing detection now classifies directed inlet, outlet, through-lake, internal, and tangential contacts in projected coordinates; tangential-only contacts remain diagnostics only.

## [1.26.1] - 2026-04-28

### Fixed

- Canal hydrology now uses `Q_model_m3s` as the operational discharge before calculating `Q`, `V`, and `H`, instead of falling back to raster river discharge at canal node locations.
- Removed active `manual_Q` output/engine usage so canal discharge is no longer represented by two competing operational fields.
- Simplified KIS canal node discharge assignment to use only `KIS_canal_discharge.csv`; the older chainage anchor override table is no longer part of the active network build.
- Added branch-aware KIS canal discharge diagnostics (`canal_edges.csv`, `canal_q_diagnostics.csv`) and parent/outgoing/residual Q fields for inspecting canal splits and offtakes.
- Preserved KIS canal-to-canal topology from the hand-drawn shapefile while keeping the Ghana wet-season canal network disconnected from rivers/lakes.
- Added defensive simulation-state handling so freshly built network states carry `study_country` metadata into `RunSimulationPipeline()`.
- Fixed a hydrology fallback crash when `slope` was absent before slope propagation.
- Kept the network map fallback from drawing misleading topology links when full `VisualizeNetwork()` rendering fails on unsupported `GEOMETRYCOLLECTION` objects.

### Added

- `hydrology_nodes.csv` export after simulation, with node-level `Q`, `V`, `H`, canal flags, `Q_design_m3s`, `Q_model_m3s`, and concentration fields where available.
- Lake connectivity diagnostics for exact inlet/outlet crossings, tangential-only crossings, and lakes skipped because the river network is too far away.
- Input-only release support in `scripts/setup-data.sh`; archives are now read from `data_manifest.json`, and `Outputs/` are regenerated locally by running scenarios.

### Changed

- Release `v1.26.1` publishes updated input archives only: `epie_basins_volta.tar.gz`, `epie_basins_bega.tar.gz`, and `epie_user_data.tar.gz`.
- The KIS `Section C` canal name is now `HLC`, matching the updated hand-drawn canal shapefile.
- `README.md`, `AGENTS.md`, and release documentation now describe local scenario regeneration instead of relying on prebuilt output archives.

### Known limitations

- Bega ibuprofen remains a data-condition failure in the full scenario runner because the rebuilt Bega chemical network has no mapped contaminant source.
- Small Volta lakes are connected only when exact inlet/outlet crossings exist. Tangential contacts and near misses are diagnosed but not snapped into the network.

## [1.26.0] - 2026-04-16

### Added

**Pathogen modeling (new)**
- Full pathogen simulation pipeline: emission calculation, environmental decay, and concentration computation for 4 pathogens: Cryptosporidium, Campylobacter, Rotavirus, Giardia
- Pathogen parameter files (`Package/inst/pathogen_input/`) with decay rates, emission factors, and WWTP removal efficiencies
- Pathogen scenarios for all basins: 5 substances x 4 network variants (Volta wet, Volta dry, Volta GeoGLOWS wet, Volta GeoGLOWS dry) + 5 Bega scenarios = 25 simulation scenarios
- `InitializeSubstance()` — unified substance initialization handling both chemical and pathogen branches

**GeoGLOWS river network integration (new)**
- Alternative river network source using GeoGLOWS data (stream lines + per-segment monthly discharge from GPKG)
- `VoltaGeoGLOWSConfig` basin configuration with `network_source = "geoglows"`, `LINKNO`/`DSLINKNO`/`USContArea` field mapping
- Wet and dry season scenarios using different month selections from the same discharge GPKG (Sep-Oct for wet, Mar-Apr for dry)
- GeoGLOWS network builds produce ~924 nodes vs ~351/178 for HydroSHEDS (full network, no seasonal tributary loss)

**Pipeline infrastructure**
- `BuildNetworkPipeline()` — 10-step orchestrated network generation with checkpoint support
- `RunSimulationPipeline()` — end-to-end simulation: normalize → add flow → set upstream → initialize substance → compute concentrations → visualize
- `LoadScenarioConfig()` — scenario config system sourcing basin + scenario R files from `inst/config/`
- `ListScenarios()` — returns all available scenario names
- Checkpoint infrastructure for debugging: save intermediate state at each step

**Visualization**
- Interactive Leaflet maps for both network (`VisualizeNetwork`) and concentration results (`VisualizeConcentrations`) with satellite, streets, topo, and light basemaps
- Static PNG maps via tmap (with base R fallback for tmap v4 compatibility)
- Configurable pathogen units in concentration map legend (oocysts/L, cells/L, etc.)
- Basemap attribution and generation date in map overlays

**Lake connectivity**
- Segment-based lake-river crossing detection replaces geometry-based approach
- Explicit inlet/outlet node pairs with CSTR-compatible topology
- Fix for double-counting and broken edges in multi-inlet lakes

**Configuration**
- Basin configs: `BegaBasinConfig`, `VoltaBasinConfig`, `VoltaGeoGLOWSConfig`
- 5 network scenarios: `BegaNetwork`, `VoltaWetNetwork`, `VoltaDryNetwork`, `VoltaGeoGLOWSNetwork`, `VoltaGeoGLOWSDryNetwork`
- 21 simulation scenarios (chemical + pathogen x wet/dry x HydroSHEDS/GeoGLOWS + Bega)
- Configurable simplification tolerances (`lake_tolerance`, `river_tolerance`, `canal_simplify`) per basin

**Other**
- Diagnostic utilities for pipeline debugging (`DiagLevel`, `SaveDiagnosticMap`)
- `rptMStateK` (country code) added to agglomeration and WWTP points during network build
- Testing manual (`Notes/testing_manual.md`) with RStudio commands and configuration reference
- Wet/dry flow data documentation (`Notes/wet_dry_flow_data_difference.md`)

### Fixed

**Critical pipeline bugs**
- `NormalizeScenarioState` now stamps `basin_id` onto all network nodes (was only set on lake nodes, causing `split()` crashes in 6+ downstream functions)
- `RunSimulationPipeline` accepts lake data under `HL_basin`, `HLL_basin`, or `hl` field names
- `RunSimulationPipeline` falls back to `points$basin_id` if `state$basin_id` is NULL
- Missing pipeline steps restored: `NormalizeScenarioState`, `AddFlowToBasinData`, `Set_upstream_points_v2` were not called before substance initialization
- `sim_state$hl` not updated after normalization (only `sim_state$HL_basin` was)

**Network build bugs**
- `MapWWTPLocations`: river segments not broken into snap targets when passed-in `river_segments_sf` lacks `segment_id` column (added guard check)
- `MapWWTPLocations`: column name mismatch `nearest_segment_id` vs `segment_id` caused WWTP snapping to fail silently
- `state$points` vs `state$pts` naming inconsistency across pipeline functions
- `st_is_valid` scalar check error when processing canal geometries

**Chemical simulation bugs**
- Excel string `"NA"` not converted to R `NA` in chemical data, causing false prodrug detection and `"non-numeric argument to binary operator"` crash
- sf geometry column breaking `pts[,i]` column extraction in `ComputeEnvConcentrations` — now strips geometry before computation
- Tibble type coercion before `CompleteChemProperties` — converted to data.frame
- 3 critical column naming mismatches in chemical simulation branch
- `Set_local_parameters` restored from corrupted edit
- `slope` column fallback from `SLOPE__deg` for downstream hydrology functions

**Pathogen simulation bugs**
- GeoGLOWS pathogen configs had `target_substance = "Ibuprofen"` copy-paste bug
- `rptMStateK` not set on agglomeration/WWTP points (added `study_country` parameter to mapping functions)
- Pathogen engine fields not initialized for end-to-end pipeline
- Campylobacter parameters marked as `TODO(VERIFY)` pending literature review

**Visualization bugs**
- tmap v4 incompatibility (deprecated `palette` argument) now caught by `tryCatch` with base R fallback — no longer crashes the pipeline
- Double-drawing canals in network visualization
- Coordinates not reprojected to WGS84 in network visualization and CSV output
- `sprintf` syntax error in `SaveDiagnosticMap`

**C++ engine bugs**
- Safe `which()` with -1 sentinel, out-of-bounds and division-by-zero guards, cycle detection in `calc_topology.cpp`

**Topology bugs**
- Hydraulic intersection and overlap handling improvements
- GeoGLOWS river segments clipped to basin boundary before simplification
- Canal endpoints snapped to GeoGLOWS river network after simplification

**Other fixes**
- `openxlsx` moved from Suggests to Imports (required for reading chemical Excel data)
- Hardcoded paths replaced with `rprojroot` in `BuildPkg.R`
- `.Rbuildignore` regex patterns corrected
- Bega temperature, lake depth, and Cryptosporidium units corrected in configs

### Changed

- Lake connectivity rewritten with explicit inlet/outlet node pairs (CSTR-compatible)
- Visualization migrated from `mapview` to pure `leaflet` for consistent styling
- Network visualization uses tmap for static plots (with base R fallback)
- Simulation pipeline now generates concentration maps automatically at the end
- Coordinates stored as WGS84 (EPSG:4326) throughout, with UTM conversion only for distance calculations

### Removed

- 22 legacy R files consolidated into the new pipeline architecture
- `mapview`-based map functions removed (replaced by leaflet)
- Development artifacts and hardcoded paths cleaned up
