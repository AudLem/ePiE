# ePiE Agents

## Package Installation

**Use `R CMD INSTALL Package` — not `devtools::install_local()`.** The `devtools` package has heavy dependencies (gert, usethis, libgit2) that may fail to install. `R CMD INSTALL` works without them.

After installing, run `Rscript scripts/smoke-test.R` as a quick environment check, then run at least one scenario (for example `VoltaWetChemicalIbuprofen`) for functional verification.

## Development Workflow

Use `pkgload::load_all("Package")` during development so changes to R source and map styling are used immediately without reinstalling. Use `R CMD INSTALL Package` only when validating the installed-package workflow.

## Test Commands

```r
# Run all tests
Rscript -e 'library(testthat); library(ePiE); test_check("ePiE")'

# Run a single test file
Rscript -e 'library(testthat); library(ePiE); test_file("Package/tests/testthat/test-network-topology.R")'

# Run tests with checkpoint helpers (load them first)
source("Package/tests/testthat/helper-checkpoints.R")
```

## Key Entry Points

- `LoadScenarioConfig(name, data_root, output_root)` — loads config from `Package/inst/config/`, returns a named list. No package install needed for config changes.
- `BuildNetworkPipeline(cfg, diagnostics = "full")` — builds river network, saves `pts.csv`, `HL.csv`, `network_rivers.shp`, and maps to `cfg$run_output_dir`. **Must run before simulation.**
- `RunSimulationPipeline(state, substance, cpp = FALSE)` — computes concentrations, generates maps. `state` must come from `BuildNetworkPipeline` (or a pre-built `pts.csv` + `HL.csv`).
- `ListScenarios()` — lists all 30 named scenarios.

## Pipeline Order

Network build is an 11-step pipeline: LoadInputs → PrepareCanals → ProcessRivers → ProcessLakes → ExtractPopulation → MapWWTPs → BuildTopology → IntegratePoints → ConnectLakes → SaveArtifacts → Visualize.

Simulation is a 6-step pipeline: Normalize → AssignHydrology → SetUpstream → InitializeSubstance → ComputeConcentrations → Visualize.

Hydrology node export (`hydrology_nodes.csv`) is written after simulation in `RunSimulationPipeline()` via `ExportHydrologyNodes()` so Q/V/H and concentration fields can be merged in one table.

## Data Setup

```bash
./scripts/setup-data.sh                    # download basin and user input data
./scripts/setup-data.sh . v1.26.2          # same, explicit args
EPIE_SKIP_R_DEPS=1 ./scripts/setup-data.sh # skip R package installation
```

Baseline raster data (HydroSHEDS, FLO1K, WorldClim, GHS-POP) is not bundled — download manually from official sources into `Inputs/baselines/`.

Release `v1.26.2` publishes input archives only. Regenerate `Outputs/` locally with `Rscript scripts/run_all_scenarios.R` after setup.

## Scenario Config Architecture

Config lives in `Package/inst/config/` (packaged with the library):

- `basins/*.R` — basin-level data paths (shapefiles, rasters, CRS). Basin configs are shared across network + simulation scenarios.
- `scenarios/*.R` — scenario-level parameters (substance type, output dir, input paths). Scenario configs reference basin configs.

`LoadScenarioConfig()` sources all basin + scenario configs into an environment, then calls the matching scenario function. To add a new basin or scenario, create the corresponding files and rebuild the package.

## C++ Engine

The C++ code lives in `Package/src/`. `Makevars` enforces C++11. `RcppExports.cpp` and `Package/R/RcppExports.R` are auto-generated. After changing exported C++ function signatures, run `Rscript -e 'Rcpp::compileAttributes("Package")'`, then rebuild/install (`R CMD INSTALL Package` or `R CMD build . && R CMD INSTALL ePiE_*.tar.gz`).

The R fallback is controlled by `cpp = FALSE` in `RunSimulationPipeline`; default is the R fallback unless `cpp = TRUE` is passed.

## Canal Metadata Passthrough

Canal identification (`is_canal`) and modeled discharge (`Q_model_m3s`) flow through both the C++ and R concentration engines. Both engines return these fields in their output data.frame so that visualization can distinguish canal segments from natural rivers.

The R fallback engine (`Compute_env_concentrations_v4`) has defensive fallbacks for missing columns (`is_canal` defaults to `FALSE`, `Q_model_m3s` to `NA_real_`, `dist_nxt` to `0`), matching the pattern used by the C++ engine call site in `02_ComputeEnvConcentrations.R`.

`ExportHydrologyNodes()` writes `hydrology_nodes.csv` after simulation with Q/V/H and concentration columns merged into a single inspection table.

## Lake Connectivity Diagnostics

Lake connectivity is determined by exact geometric intersection between lake boundaries and river segments. `DetectLakeSegmentCrossings()` identifies three crossing types:
- **inlet**: river enters lake (upstream outside, downstream inside)
- **outlet**: river leaves lake (upstream inside, downstream outside)
- **tangential**: river touches lake boundary without entering/exiting

Only lakes with both at least one inlet and one outlet crossing are connected to the network. Lakes with only tangential crossings (or no crossings at all) are skipped.

Diagnostic output includes:
- `DetectLakeSegmentCrossings`: reports nearest river distance and status for lakes without exact crossings
- `ConnectLakesToNetwork`: summary of connected vs skipped lakes with reasons (tangential only, inlet/outlet mismatch, no intersection)

Example Volta basin output:
- 2 lakes connected via exact inlet+outlet
- 3 lakes skipped (tangential only, 1.2-1.4km from river network)

The algorithm does not use tolerance-based snapping — lakes must have geometric river crossings to be connected.

## Canal Topology and Discharge

Canal topology is inferred from hand-drawn canal line geometry and junction-based connections. `AnnotateCanalTopology` computes upstream/downstream relationships, classifies nodes (CANAL_START, CANAL_NODE, CANAL_BRANCH, CANAL_JUNCTION, CANAL_END), and enforces junction-based connections (nodes at same coordinates, <1m tolerance).

Canal discharge (Q) is assigned from `KIS_canal_discharge.csv` using section head/tail values:
- `q_head` and `q_tail` per canal section define linear interpolation
- At branch offtakes, piecewise residuals preserve upstream flow availability
- `ApplyCanalMassBalance` scales downstream branches when design Q exceeds available Q
- The removed `AttachCanalQAnchors` function and `canal_q_anchor_table` config parameter are no longer used

Diagnostic outputs:
- `canal_edges.csv` — all canal topology edges (reach and branch) with Q metadata
- `canal_q_diagnostics.csv` — mass balance checks at each branch split
- New columns on `pts.csv`: `Q_role`, `Q_parent_m3s`, `Q_out_sum_m3s`, `Q_residual_m3s`

Display annotation (`AnnotateDisplayJunctions`) separates visualization from topology:
- `display_pt_type` — what maps show (JNCT, agglomeration, WWTP, etc.)
- `pt_type` — model behavior (CANAL_BRANCH, START, node, etc.)
- `junction_role` — fan_in_receiver, coincident_confluence_node

Source node placement (`ResolveCoincidentSourceNodes`) nudges agglomeration/WWTP points off protected infrastructure nodes (junctions, canal nodes) to prevent topology corruption.

## Known Data Gaps (Not Bugs)

- FLO1K rasters don't cover Africa: all HydroSHEDS Volta scenarios produce Q=0 (all-NA concentrations).
- No WWTPs in Volta networks: chemical scenarios produce zero emissions for Volta.
- GeoGLOWS wet and dry use the same river network; seasonality comes from monthly discharge columns.

## Map Rendering

`scripts/run_all_scenarios.R` uses `pkgload::load_all()` so map styling changes in the workspace are used during scenario runs. If maps were generated before a style update, re-run `VisualizeConcentrations()` on existing `simulation_results.csv` to refresh only the visualization layer.
