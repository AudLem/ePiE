# ePiE

ePiE is a spatially explicit model that estimates concentrations of active pharmaceutical ingredients (APIs) and pathogens in surface waters. It combines river catchment networks, WWTP infrastructure, substance fate modelling (SimpleTreat 4.0 for chemicals, pathogen-specific decay), and a C++ engine for fast concentration computation.

Supports basins in Africa (Volta/Ghana) and Europe (Bega/Romania) using HydroSHEDS and GeoGLOWS v2 river networks. Currently models Cryptosporidium, Campylobacter, Rotavirus, and Giardia alongside chemical APIs (e.g. Ibuprofen).

## Quick Start

```bash
git clone git@github.com:AudLem/ePiE.git
cd ePiE
./scripts/setup-data.sh
R CMD INSTALL Package
Rscript scripts/smoke-test.R
```

`./scripts/setup-data.sh` now installs missing R dependencies (from `Package/DESCRIPTION` + `pkgload`) before downloading data.

Maintainers: see [RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md) for publishing code releases and GitHub Release data assets.

## How ePiE Works

ePiE follows a **three-step workflow**:

```
1. Build Network → 2. Run Simulation → 3. Interpret Results
   (river topology)   (compute C_w)        (analyze maps/data)
```

- **Network**: River topology with nodes (e.g. junctions, WWTPs, agglomerations, lakes)
- **Simulation**: Computes concentrations at each node based on emissions and upcoming conecntrations from upstream nodes
- **Results**: Interactive maps showing where contaminants are present

## Step 1: Build a Network

The network is the foundation — it defines the river topology, connections, and sources (WWTPs, agglomerations). **You must build a network before running simulations.**

```r
library(ePiE)

# Build Volta wet-season network
cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg)

# Check the output
cat("Network built:\n")
cat("  Nodes:", nrow(state$points), "\n")
cat("  Lakes:", nrow(state$HL_basin), "\n")
cat("  Saved to:", cfg$run_output_dir, "\n")

# View the network map
open(file.path(cfg$run_output_dir, "plots", "interactive_network_map.html"))
```

**What gets created:**
- `pts.csv` - Network nodes with topology
- `HL.csv` - Lake nodes
- `network_rivers.shp` - River geometry
- `transport_edges.csv` - Routing edges used for branch-aware transport
- `lake_connections.csv` - Active lake inlet/outlet routing metadata
- `lake_connection_diagnostics.csv` - Connected/skipped lake diagnostics
- `plots/interactive_network_map.html` - Visual map of the network

**Available network builds:**
- `VoltaWetNetwork` - Volta basin, wet season
- `VoltaDryNetwork` - Volta basin, dry season
- `VoltaGeoGLOWSNetwork` - Volta basin, GeoGLOWS data
- `BegaNetwork` - Bega basin (Romania)

## Step 2: Run Simulations

Once you have a network, you can run simulations for different substances (chemicals or pathogens).

```r
library(ePiE)

# Load the network you built in Step 1
state <- list(
  points = read.csv("Outputs/volta_wet/pts.csv"),
  HL_basin = read.csv("Outputs/volta_wet/HL.csv"),
  input_paths = list(
    pts = "Outputs/volta_wet/pts.csv",
    hl = "Outputs/volta_wet/HL.csv",
    rivers = "Outputs/volta_wet/network_rivers.shp",
    basin = "Inputs/basins/volta/small_sub_basin_volta_dissolved.shp",
    flow_raster = "Inputs/baselines/environmental/FLO1K.30min.ts.1960.2015.qav.nc"
  ),
  study_country = "GH",
  pathogen_profile_set = "ghana_ssa_screening",
  pathogen_profile_policy = "strict",
  country_population = 35100000,
  basin_id = "volta"
)

# Run a pathogen simulation
cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs")
results <- RunSimulationPipeline(state, substance = cfg$target_substance)

# Run a chemical simulation
cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", "Inputs", "Outputs")
results <- RunSimulationPipeline(state, substance = cfg$target_substance)
```

**What gets created:**
- `simulation_results.csv` - Concentrations at each node
- `hydrology_nodes.csv` - Node-level Q, V, H, and concentration fields merged for inspection
- `transport_edges.csv` - Final routing edges used by the simulation
- `run_provenance_summary.csv` - Run-level source, period, and layer metadata
- `pathogen_provenance_summary.csv` - Pathogen profile, units, parameter values, and citation metadata for pathogen runs
- `canal_q_assignment_summary.csv` - Canal discharge source and final Q assignment summary, when canals are present
- `plots/concentration_map.html` - Interactive concentration map
- `plots/concentration_map_linear.html` - Linear-scale interactive concentration map
- `plots/concentration_map_log10.html` - Log-scale interactive concentration map
- `plots/static_concentration_map.png` - Static image

`pts.csv`, `hydrology_nodes.csv`, and `simulation_results.csv` are node tables. `transport_edges.csv` is the routing table used when the network contains branches. In branched canal transport, routing is edge-based and not inferred only from `ID_nxt`, which remains a single downstream pointer kept for compatibility.

Lake routing is also edge-based. Active lakes must have physical boundary inlet and outlet crossings; the builder writes `lake_connections.csv` for connected lakes and `lake_connection_diagnostics.csv` for skipped lakes. `LakeIn`/`LakeOut` centroid fallback nodes are not created.

Lake fate is configurable with `lake_transport_mode`. Bega literature scenarios use `legacy_pass_through`, which preserves the historical v1.25 ibuprofen plume behavior while keeping strict boundary geometry. CSTR lake routing is still available with `lake_transport_mode = "cstr"` for explicitly calibrated lake-reactor scenarios. `lake_residence_time_days` is meaningful only for active CSTR routing.

KIS canal discharge is selected through `canal_q_source_id`. The default Volta/KIS source is `jica_2012_peak`, based on the 2012 JICA report section 4.4.2: <https://openjicareport.jica.go.jp/pdf/12085874_01.pdf>. Supported KIS source IDs are `jica_2012_peak`, `jica_2012_average`, and `legacy_nllc_sllc`. The legacy source is preserved for comparison through `VoltaWetNetworkLegacyCanalQ` and `VoltaWetChemicalIbuprofenLegacyCanalQ`.

Pathogen emissions use strict area-specific profiles. Volta/Ghana scenarios default to `ghana_ssa_screening`; Bega/Romania scenarios default to `romania_eu_screening`. `inst/pathogen_input/` stores pathogen biology and decay defaults, while `inst/pathogen_profiles/` stores prevalence, excretion, WWTP removal, region/country, units, and citation metadata. A pathogen scenario fails if no compatible profile is available, preventing Africa-derived assumptions from silently being reused in Romania.

Each run exports canal Q provenance: source ID, citation tag, URL, data period, regime, value origin, and derivation rule. Use `run_provenance_summary.csv` for run-level metadata and `canal_q_assignment_summary.csv` for canal-section Q checks.

**Map rendering consistency note:**
- `scripts/run_all_scenarios.R` loads local source from `Package/` (via `pkgload::load_all()`) when available, so map styling changes in the workspace are used during scenario runs.
- If maps were generated before a style update, re-run `VisualizeConcentrations()` on existing `simulation_results.csv` to refresh only the visualization layer.

**VS Code debugging:**
- `.vscode/settings.json` points the R extension and terminal PATH to `/Library/Frameworks/R.framework/Resources/bin`, because this workstation has R there.
- Use `Terminal: Run Task` → `R: Install Package`, `R: Smoke Test`, `R: Test Pathogen Profiles`, or `R: Validate Profile Scenario Defaults`.
- Use `Terminal: Run Task` → `R: Bega Crypto Profile Simulation` or `R: Volta Wet Crypto Profile Simulation` for targeted pathogen runs. These tasks load local source with `pkgload::load_all("Package")`, read the pre-built `pts.csv`/`HL.csv`, and write temporary debug outputs instead of overwriting normal `Outputs/` folders.
- `.vscode/launch.json` intentionally avoids `"type": "R"` because that debug adapter is not available in this workspace. R workflows are task-based; the remaining launch entry is only for optional C++/lldb attachment.

**Available simulations:**
- **Chemicals**: `*ChemicalIbuprofen` (Ibuprofen concentrations)
- **Pathogens**: `*PathogenCrypto`, `*PathogenGiardia`, `*PathogenRotavirus`, `*PathogenCampylobacter`

## Step 3: Interpret Results

After simulation completes, examine the results:

```r
# Load results
results <- read.csv("Outputs/volta_crypto_wet/simulation_results.csv")

# Basic statistics
cat("Concentration summary:\n")
cat("  Mean:", mean(results$C_w, na.rm = TRUE), "\n")
cat("  Max:", max(results$C_w, na.rm = TRUE), "\n")
cat("  Non-zero:", sum(results$C_w > 0, na.rm = TRUE), "\n")

# View the concentration map
browseURL("Outputs/volta_crypto_wet/plots/concentration_map.html")
```

**What to look for:**
- **Legend is populated** - Not empty, shows concentration range
- **Color gradient visible** - Different colors for different concentrations
- **Concentrations decrease downstream** - Higher near sources, lower near mouth
- **Canals visible** (if applicable) - Cyan lines in the map

For detailed interpretation guidance, see [POST_SIMULATION_GUIDE.md](docs/POST_SIMULATION_GUIDE.md).

## Complete Example

```r
library(ePiE)

# === Step 1: Build Network ===
cfg_net <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg_net)

# === Step 2: Run Simulation ===
cfg_sim <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs")
results <- RunSimulationPipeline(state, substance = cfg_sim$target_substance)

# === Step 3: View Results ===
browseURL(file.path(cfg_sim$run_output_dir, "plots", "concentration_map.html"))
```

## Available Scenarios

| Step | Scenario Name | Basin | Output |
|------|---------------|-------|--------|
| **1. Network** | `VoltaWetNetwork` | Volta | `Outputs/volta_wet/` |
| | `VoltaDryNetwork` | Volta | `Outputs/volta_dry/` |
| | `VoltaGeoGLOWSNetwork` | Volta | `Outputs/volta_geoglows_wet/` |
| | `BegaNetwork` | Bega | `Outputs/bega/` |
| **2. Simulation** | `VoltaWetPathogen*` | Volta | `Outputs/volta_*_wet/` |
| | `VoltaDryPathogen*` | Volta | `Outputs/volta_*_dry/` |
| | `VoltaGeoGLOWS*Pathogen*` | Volta | `Outputs/volta_geoglows_*_wet/` |
| | `BegaPathogen*` | Bega | `Outputs/bega_*/` |
| | `*ChemicalIbuprofen` | All | `Outputs/*_ibuprofen/` |

List all scenarios: `ListScenarios()`

## Inspect Scenario Setups

Use the setup inspector before running or reviewing scenarios. It reports the
configured input files, concentration units, selected pathogen profile or canal Q
source, literature/source URLs, formula modules, lake/transport settings, and
expected provenance outputs.

```bash
# Show a compact table for every scenario
Rscript scripts/inspect_scenarios.R

# Show one scenario
Rscript scripts/inspect_scenarios.R --scenario BegaPathogenCrypto

# Export one-row-per-scenario CSV
Rscript scripts/inspect_scenarios.R --csv Outputs/scenario_setup_audit.csv

# Export long provenance-style key/value CSV
Rscript scripts/inspect_scenarios.R --format long --csv Outputs/scenario_setup_audit_long.csv
```

From R, use:

```r
InspectScenarioSetup("VoltaWetPathogenCrypto")
InspectScenarioSetup(format = "long", export_csv = "Outputs/scenario_setup_audit_long.csv")
```

The inspector reports configured/intended setup before a run. After simulation,
the generated files such as `run_provenance_summary.csv`,
`pathogen_provenance_summary.csv`, `canal_q_assignment_summary.csv`,
`transport_edges.csv`, and `hydrology_nodes.csv` remain the authoritative record
of what was actually produced. Runtime literature lookup is not performed;
references come from packaged registries such as
`Package/inst/pathogen_profiles/pathogen_profiles.R` and
`Package/inst/config/canal_q_sources/kis_canal_q_sources.csv`.

To draft a new scenario constructor without editing files by hand:

```bash
Rscript scripts/create_scenario_template.R --name MyScenario --copy-from VoltaWetPathogenCrypto
Rscript scripts/create_scenario_template.R --name MyBegaCrypto --basin bega --type pathogen --target cryptosporidium
```

The template helper prints by default and writes only when `--output-file` is
provided. It does not replace scientific review of the selected parameters,
profile, hydrology source, canal Q source, or lake transport mode. The current
template command is non-interactive; an interactive terminal wizard is planned
in `Notes/interactive_scenario_builder_plan.md`.

## Regenerating Networks

Patch release `v1.26.2` ships updated input archives only. After running `setup-data.sh`, build networks locally before simulations:

```bash
Rscript scripts/run_all_scenarios.R
```

This regenerates `Outputs/volta_wet/`, `Outputs/volta_dry/`, `Outputs/volta_geoglows_wet/`, `Outputs/volta_geoglows_dry/`, `Outputs/bega/`, and their simulation outputs using the current code and inputs.

During simulation, `RunSimulationPipeline()` can bootstrap from saved network artifacts such as `pts.csv` and `HL.csv`, but it reconstructs `transport_edges.csv` internally before computing branch-aware transport.

## Prerequisites

- **R >= 4.0** with a **C++11 compiler**
- [GDAL](https://gdal.org/) (required by `sf` and `terra`)
- [GEOS](https://libgeos.org/) (required by `sf`)
- [PROJ](https://proj.org/) (required by `sf`)

On macOS: `brew install gdal geos proj`

## Documentation

**Essential for scientists:**
- **[WORKFLOW.md](docs/WORKFLOW.md)** - Complete workflow with detailed examples
- **[PRE_NETWORK_VALIDATION.md](docs/PRE_NETWORK_VALIDATION.md)** - What to check before building networks
- **[POST_SIMULATION_GUIDE.md](docs/POST_SIMULATION_GUIDE.md)** - How to interpret simulation results

**For developers:**
- **[GETTING_STARTED.md](docs/GETTING_STARTED.md)** - Detailed setup and troubleshooting
- **[USAGE.md](docs/USAGE.md)** - Usage examples and API reference
- **[CONFIGURATION.md](docs/CONFIGURATION.md)** - Configuration reference
- **[DEBUGGING.md](docs/DEBUGGING.md)** - Debugging techniques

## Required Baseline Data

Building networks from scratch requires baseline raster data (not bundled due to licensing):

| Dataset | Source | Directory |
|---------|--------|-----------|
| HydroSHEDS HydroRIVERS | [hydrosheds.org](https://www.hydrosheds.org/) | `Inputs/baselines/hydrosheds/` |
| FLO1K discharge | [PANGAEA](https://doi.org/10.1594/PANGAEA.868758) | `Inputs/baselines/hydrosheds/` |
| WorldClim v2 temperature | [worldclim.org](https://www.worldclim.org/data/worldclim21.html) | `Inputs/baselines/environmental/` |
| GHS-POP population | [GHS-POP](https://ghsl.jrc.ec.europa.eu/ghs_pop2019.php) | `Inputs/baselines/environmental/` |

See [DATA_REQUIREMENTS.md](Package/DATA_REQUIREMENTS.md) for details.

## Input Files Needed for Installed ePiE

After installing the `ePiE` package, you need the following directory structure and files to run simulations and build networks:

- **`Inputs/`**: Must contain basin-specific data and global baselines.
    - **`baselines/`**: HydroSHEDS rivers, FLO1K discharge, WorldClim temperature, and GHS-POP population.
    - **`user/`**: `chem_Oldenkamp2018_SI.xlsx` (chemical properties) and `EEF_points_updated.csv` (WWTP data).
    - **`basins/`**: (Optional) `HydroWASTE_v10.csv` for global WWTP integration.
- **`Outputs/`**: Target directory for network artifacts and simulation results.

Use `./scripts/setup-data.sh` to automatically download the standard input dataset.

## Project Structure

```
ePiE/
├── Package/                  # R package source
│   ├── R/                    # R functions (numbered by pipeline stage)
│   ├── src/                  # C++ engine (Rcpp)
│   ├── inst/config/          # Basin and scenario configurations
│   ├── inst/pathogen_input/  # Pathogen parameter files
│   ├── inst/pathogen_profiles/ # Area-specific pathogen emission profiles
│   └── tests/testthat/       # Unit tests (214 tests)
├── docs/                     # Documentation
├── Inputs/                   # Basin data and user data
├── Outputs/                  # Generated networks and simulation results
├── scripts/                  # Setup and verification scripts
└── data_manifest.json        # Archive checksums
```

## Citation

Lemme, A. J., Hoeks, S., & Oldenkamp, R. (2026). ePiE — environmental Pharmaceuticals in the Environment (v1.26.2). GitHub. https://github.com/AudLem/ePiE

## License

GPL-3.0
