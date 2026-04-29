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
- `plots/concentration_map.html` - Interactive concentration map
- `plots/static_concentration_map.png` - Static image

**Map rendering consistency note:**
- `scripts/run_all_scenarios.R` loads local source from `Package/` (via `pkgload::load_all()`) when available, so map styling changes in the workspace are used during scenario runs.
- If maps were generated before a style update, re-run `VisualizeConcentrations()` on existing `simulation_results.csv` to refresh only the visualization layer.

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

## Regenerating Networks

Patch release `v1.26.2` ships updated input archives only. After running `setup-data.sh`, build networks locally before simulations:

```bash
Rscript scripts/run_all_scenarios.R
```

This regenerates `Outputs/volta_wet/`, `Outputs/volta_dry/`, `Outputs/volta_geoglows_wet/`, `Outputs/volta_geoglows_dry/`, `Outputs/bega/`, and their simulation outputs using the current code and inputs.

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
