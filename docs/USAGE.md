# Using ePiE

This guide covers common usage scenarios for the ePiE R package.

## 1. Running Simulations

### Full Scenario Execution
For large-scale simulations (e.g., all pathogens for Volta, plus Bega scenarios), use the scenario runner provided in the `scripts/` directory:

```bash
Rscript scripts/run_all_scenarios.R
```

This script runs scenarios sequentially (for clearer logging/error attribution) and writes results/maps into `Outputs/`, organized by scenario.

`scripts/run_all_scenarios.R` now prefers loading local source code from `Package/` via `pkgload::load_all()` when available. This ensures scenario runs use the current workspace renderer/style changes instead of an older installed `ePiE` package version.

If you need to re-style previously generated maps without recomputing simulations, re-run `VisualizeConcentrations()` for each existing `simulation_results.csv`.

### RStudio Workflow

Open `ePiE.Rproj`, restart R, then run:

```r
setwd(dirname(rstudioapi::getActiveProject()))
pkgload::load_all("Package")
source("scripts/run_all_scenarios.R")
```

If `rstudioapi` is unavailable:

```r
setwd("/path/to/ePiE")
pkgload::load_all("Package")
source("scripts/run_all_scenarios.R")
```

During active development, prefer `pkgload::load_all("Package")` so RStudio uses the current source tree. Use `R CMD INSTALL Package` when you specifically want to test the installed package.

To run one scenario through the same helper used by the full suite:

```r
lines <- readLines("scripts/run_all_scenarios.R")
cutoff <- which(grepl("# Scenario list", lines))[1] - 1
eval(parse(text = lines[1:cutoff]), envir = .GlobalEnv)
run_single_scenario(list(
  name = "volta_wet_crypto",
  type = "pathogen",
  config_name = "VoltaWetPathogenCrypto",
  network_dir = "volta_wet"
))
```

### Debugging with Pipeline Checkpoints
You can pause, inspect, and resume the network generation process by utilizing the pipeline's checkpointing infrastructure.

To stop execution after a specific step:
```R
cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
state <- BuildNetworkPipeline(cfg, 
                              checkpoint_dir = "Outputs/checkpoints", 
                              stop_after_step = "04_process_lake_geometries")
```

To resume from a checkpoint:
```R
# Load an intermediate state from a previous run
state <- readRDS("Outputs/checkpoints/04_process_lake_geometries.rds")
# ... continue with manual pipeline steps ...
```


### Step D: View results

```r
# Print concentration summary
summary(results_chem$pts$C_w)
summary(results_crypto$pts$C_w)

# Open interactive map in browser
browseURL(file.path(cfg_chem$run_output_dir, "plots", "concentration_map.html"))
browseURL(file.path(cfg_crypto$run_output_dir, "plots", "concentration_map.html"))
```

## 2. Quick Start: Volta with GeoGLOWS v2 Data

GeoGLOWS v2 provides per-segment monthly discharge data, replacing the FLO1K raster approach. It uses explicit topology (`DSLINKNO`) instead of flow-direction rasters.

```r
library(ePiE)
data_root  <- file.path(repo, "Inputs")
output_root <- file.path(repo, "Outputs")

# Build network (GeoGLOWS)
cfg_net <- LoadScenarioConfig("VoltaGeoGLOWSNetwork", data_root, output_root)
network <- BuildNetworkPipeline(cfg_net)

# Run simulation (Sep-Oct 2020 mean discharge)
cfg_sim <- LoadScenarioConfig("VoltaGeoGLOWSWetChemicalIbuprofen", data_root, output_root)
results <- RunSimulationPipeline(network, substance = "Ibuprofen")
```

The GeoGLOWS discharge extraction supports configurable year, months, and aggregation:

| Parameter | Description | Example |
|---|---|---|
| `simulation_year` | Year to select from monthly columns | `2020` |
| `simulation_months` | Months to aggregate | `9:10` (Sep-Oct) |
| `discharge_aggregation` | Aggregation method | `"mean"`, `"min"`, `"max"`, `"specific"` |

## 3. Legacy Chemical Run (European Basins)

This is the original ePiE workflow for Ibuprofen in the Rhine and Ouse basins:

```r
library(ePiE)

chem <- LoadExampleChemProperties()
chem <- CompleteChemProperties(chem = chem)
cons <- LoadExampleConsumption()

basins <- LoadEuropeanBasins()
basins <- SelectBasins(basins_data = basins, basin_ids = c(124863, 107287))
cons <- CheckConsumptionData(basins$pts, chem, cons)

flow_avg <- LoadLongTermFlow("average")
basins_avg <- AddFlowToBasinData(basin_data = basins, flow_rast = flow_avg)

results <- ComputeEnvConcentrations(
  basin_data = basins_avg, chem = chem, cons = cons, 
  verbose = TRUE, cpp = TRUE
)
```

## 4. Available Scenarios

Run `ListScenarios()` to get the full list programmatically.

### Network Build

| Scenario Name | Basin | Data Source | Season |
|---|---|---|---|
| `VoltaWetNetwork` | Volta | HydroSHEDS | Wet |
| `VoltaDryNetwork` | Volta | HydroSHEDS | Dry |
| `VoltaGeoGLOWSNetwork` | Volta | GeoGLOWS v2 | Wet |
| `VoltaGeoGLOWSDryNetwork` | Volta | GeoGLOWS v2 | Dry |
| `BegaNetwork` | Bega | HydroSHEDS | — |

### Simulation (Chemicals)

| Scenario Name | Basin | Data Source | Season | Substance |
|---|---|---|---|---|
| `VoltaWetChemicalIbuprofen` | Volta | HydroSHEDS | Wet | Ibuprofen |
| `VoltaDryChemicalIbuprofen` | Volta | HydroSHEDS | Dry | Ibuprofen |
| `VoltaGeoGLOWSWetChemicalIbuprofen` | Volta | GeoGLOWS v2 | Wet | Ibuprofen |
| `VoltaGeoGLOWSDryChemicalIbuprofen` | Volta | GeoGLOWS v2 | Dry | Ibuprofen |
| `BegaChemicalIbuprofen` | Bega | HydroSHEDS | — | Ibuprofen |

### Simulation (Pathogens)

| Scenario Name | Basin | Data Source | Season | Pathogen |
|---|---|---|---|---|
| `VoltaWetPathogenCrypto` | Volta | HydroSHEDS | Wet | Cryptosporidium |
| `VoltaWetPathogenGiardia` | Volta | HydroSHEDS | Wet | Giardia |
| `VoltaWetPathogenRotavirus` | Volta | HydroSHEDS | Wet | Rotavirus |
| `VoltaWetPathogenCampylobacter` | Volta | HydroSHEDS | Wet | Campylobacter |
| `VoltaDryPathogenCrypto` | Volta | HydroSHEDS | Dry | Cryptosporidium |
| `VoltaDryPathogenGiardia` | Volta | HydroSHEDS | Dry | Giardia |
| `VoltaDryPathogenRotavirus` | Volta | HydroSHEDS | Dry | Rotavirus |
| `VoltaDryPathogenCampylobacter` | Volta | HydroSHEDS | Dry | Campylobacter |
| `VoltaGeoGLOWSWetPathogenCrypto` | Volta | GeoGLOWS v2 | Wet | Cryptosporidium |
| `VoltaGeoGLOWSWetPathogenGiardia` | Volta | GeoGLOWS v2 | Wet | Giardia |
| `VoltaGeoGLOWSWetPathogenRotavirus` | Volta | GeoGLOWS v2 | Wet | Rotavirus |
| `VoltaGeoGLOWSWetPathogenCampylobacter` | Volta | GeoGLOWS v2 | Wet | Campylobacter |
| `VoltaGeoGLOWSDryPathogenCrypto` | Volta | GeoGLOWS v2 | Dry | Cryptosporidium |
| `VoltaGeoGLOWSDryPathogenGiardia` | Volta | GeoGLOWS v2 | Dry | Giardia |
| `VoltaGeoGLOWSDryPathogenRotavirus` | Volta | GeoGLOWS v2 | Dry | Rotavirus |
| `VoltaGeoGLOWSDryPathogenCampylobacter` | Volta | GeoGLOWS v2 | Dry | Campylobacter |
| `BegaPathogenCrypto` | Bega | HydroSHEDS | — | Cryptosporidium |
| `BegaPathogenGiardia` | Bega | HydroSHEDS | — | Giardia |
| `BegaPathogenRotavirus` | Bega | HydroSHEDS | — | Rotavirus |
| `BegaPathogenCampylobacter` | Bega | HydroSHEDS | — | Campylobacter |

## 5. HydroSHEDS vs GeoGLOWS v2

| Feature | HydroSHEDS | GeoGLOWS v2 |
|---|---|---|
| River network | Shapefile + flow-direction raster | GeoPackage with explicit topology (DSLINKNO) |
| Discharge | FLO1K gridded raster (30min or 1km) | Per-segment monthly time series (2000-2025) |
| Flow direction | D8 raster | DSLINKNO column (explicit downstream link) |
| Seasonality | Separate wet/dry rasters | Select year + months from 312 monthly columns |
| Coverage | Global | Global (by basin extraction) |

## 6. Output Files

### Network build

```text
<run_output_dir>/
├── pts.csv                          # Network nodes (ID, x, y, topology, env fields)
├── HL.csv                           # Lake nodes (CSTR parameters)
├── network_rivers.shp (+ .dbf, .shx) # River geometry
├── slope.tif                        # Extracted slope raster
├── T_AIR.tif                        # Extracted temperature raster
├── Wind.tif                         # Extracted wind speed raster
└── plots/
    └── interactive_network_map.html # Leaflet map of the network
```

### Simulation

```text
<run_output_dir>/
├── results_pts_<basin>_<substance>.csv   # Node concentrations
├── results_hl_<basin>_<substance>.csv    # Lake concentrations
└── plots/
    └── concentration_map.html            # Interactive Leaflet map
```

## 7. Volta Usage Examples

### 7.1 Volta Wet Season - Cryptosporidium

**Terminal commands:**
```bash
cd /path/to/ePiE
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaWetNetwork", dr, or); state <- BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", dr, or); cfg$input_paths$pts <- file.path(or, "volta_wet", "pts.csv"); cfg$input_paths$hl <- file.path(or, "volta_wet", "HL.csv"); cfg$input_paths$rivers <- file.path(or, "volta_wet", "network_rivers.shp"); sim_state <- RunSimulationPipeline(state, substance = "cryptosporidium")'
```

**RStudio console:**
```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
dr <- file.path(repo, "Inputs")
or <- file.path(repo, "Outputs")

# Build network
cfg_net <- LoadScenarioConfig("VoltaWetNetwork", dr, or)
state <- BuildNetworkPipeline(cfg_net)

# Run simulation
cfg_sim <- LoadScenarioConfig("VoltaWetPathogenCrypto", dr, or)
sim_state <- RunSimulationPipeline(state, substance = "cryptosporidium")
```

**Output files:**
- Network: `Outputs/volta_wet/pts.csv`, `Outputs/volta_wet/HL.csv`, `Outputs/volta_wet/network_rivers.shp`
- Simulation: `Outputs/volta_crypto_wet/results_pts_volta_cryptosporidium.csv`
- Maps: `Outputs/volta_wet/plots/static_network_overview.png`, `Outputs/volta_wet/plots/interactive_network_map.html`

### 7.2 Volta Dry Season - Cryptosporidium

**Terminal commands:**
```bash
cd /path/to/ePiE
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaDryNetwork", dr, or); state <- BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaDryPathogenCrypto", dr, or); sim_state <- RunSimulationPipeline(state, substance = "cryptosporidium")'
```

**RStudio console:**
```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
dr <- file.path(repo, "Inputs")
or <- file.path(repo, "Outputs")

# Build network
cfg_net <- LoadScenarioConfig("VoltaDryNetwork", dr, or)
state <- BuildNetworkPipeline(cfg_net)

# Run simulation
cfg_sim <- LoadScenarioConfig("VoltaDryPathogenCrypto", dr, or)
cfg_sim$input_paths$pts <- file.path(or, "volta_dry", "pts.csv")
cfg_sim$input_paths$hl <- file.path(or, "volta_dry", "HL.csv")
cfg_sim$input_paths$rivers <- file.path(or, "volta_dry", "network_rivers.shp")
sim_state <- RunSimulationPipeline(state, substance = "cryptosporidium")
```

**Output files:**
- Network: `Outputs/volta_dry/pts.csv`, `Outputs/volta_dry/HL.csv`, `Outputs/volta_dry/network_rivers.shp`
- Simulation: `Outputs/volta_crypto_dry/results_pts_volta_cryptosporidium.csv`
- Maps: `Outputs/volta_dry/plots/static_network_overview.png`, `Outputs/volta_dry/plots/interactive_network_map.html`

### 7.3 Volta Wet Season - Ibuprofen

**Terminal commands:**
```bash
cd /path/to/ePiE
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaWetNetwork", dr, or); state <- BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", dr, or); cfg$input_paths$pts <- file.path(or, "volta_wet", "pts.csv"); cfg$input_paths$hl <- file.path(or, "volta_wet", "HL.csv"); cfg$input_paths$rivers <- file.path(or, "volta_wet", "network_rivers.shp"); sim_state <- RunSimulationPipeline(state, substance = "Ibuprofen")'
```

**RStudio console:**
```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
dr <- file.path(repo, "Inputs")
or <- file.path(repo, "Outputs")

# Build network
cfg_net <- LoadScenarioConfig("VoltaWetNetwork", dr, or)
state <- BuildNetworkPipeline(cfg_net)

# Run simulation
cfg_sim <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", dr, or)
cfg_sim$input_paths$pts <- file.path(or, "volta_wet", "pts.csv")
cfg_sim$input_paths$hl <- file.path(or, "volta_wet", "HL.csv")
cfg_sim$input_paths$rivers <- file.path(or, "volta_wet", "network_rivers.shp")
sim_state <- RunSimulationPipeline(state, substance = "Ibuprofen")
```

**Output files:**
- Network: `Outputs/volta_wet/pts.csv`, `Outputs/volta_wet/HL.csv`, `Outputs/volta_wet/network_rivers.shp`
- Simulation: `Outputs/volta_wet_ibuprofen/results_pts_volta_Ibuprofen.csv`
- Maps: `Outputs/volta_wet/plots/static_network_overview.png`, `Outputs/volta_wet/plots/interactive_network_map.html`

### 7.4 Volta Dry Season - Ibuprofen

**Terminal commands:**
```bash
cd /path/to/ePiE
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaDryNetwork", dr, or); state <- BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("VoltaDryChemicalIbuprofen", dr, or); cfg$input_paths$pts <- file.path(or, "volta_dry", "pts.csv"); cfg$input_paths$hl <- file.path(or, "volta_dry", "HL.csv"); cfg$input_paths$rivers <- file.path(or, "volta_dry", "network_rivers.shp"); sim_state <- RunSimulationPipeline(state, substance = "Ibuprofen")'
```

**RStudio console:**
```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
dr <- file.path(repo, "Inputs")
or <- file.path(repo, "Outputs")

# Build network
cfg_net <- LoadScenarioConfig("VoltaDryNetwork", dr, or)
state <- BuildNetworkPipeline(cfg_net)

# Run simulation
cfg_sim <- LoadScenarioConfig("VoltaDryChemicalIbuprofen", dr, or)
cfg_sim$input_paths$pts <- file.path(or, "volta_dry", "pts.csv")
cfg_sim$input_paths$hl <- file.path(or, "volta_dry", "HL.csv")
cfg_sim$input_paths$rivers <- file.path(or, "volta_dry", "network_rivers.shp")
sim_state <- RunSimulationPipeline(state, substance = "Ibuprofen")
```

**Output files:**
- Network: `Outputs/volta_dry/pts.csv`, `Outputs/volta_dry/HL.csv`, `Outputs/volta_dry/network_rivers.shp`
- Simulation: `Outputs/volta_dry_ibuprofen/results_pts_volta_Ibuprofen.csv`
- Maps: `Outputs/volta_dry/plots/static_network_overview.png`, `Outputs/volta_dry/plots/interactive_network_map.html`

## 8. Bega Usage Examples

### 8.1 Bega - Ibuprofen

**Terminal commands:**
```bash
cd /path/to/ePiE
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("BegaNetwork", dr, or); state <- BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); repo <- rprojroot::find_root(rprojroot::is_git_root); dr <- file.path(repo, "Inputs"); or <- file.path(repo, "Outputs"); cfg <- LoadScenarioConfig("BegaChemicalIbuprofen", dr, or); cfg$input_paths$pts <- file.path(or, "bega", "pts.csv"); cfg$input_paths$hl <- file.path(or, "bega", "HL.csv"); cfg$input_paths$rivers <- file.path(or, "bega", "network_rivers.shp"); sim_state <- RunSimulationPipeline(state, substance = "Ibuprofen")'
```

**RStudio console:**
```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
dr <- file.path(repo, "Inputs")
or <- file.path(repo, "Outputs")

# Build network
cfg_net <- LoadScenarioConfig("BegaNetwork", dr, or)
state <- BuildNetworkPipeline(cfg_net)

# Run simulation
cfg_sim <- LoadScenarioConfig("BegaChemicalIbuprofen", dr, or)
cfg_sim$input_paths$pts <- file.path(or, "bega", "pts.csv")
cfg_sim$input_paths$hl <- file.path(or, "bega", "HL.csv")
cfg_sim$input_paths$rivers <- file.path(or, "bega", "network_rivers.shp")
sim_state <- RunSimulationPipeline(state, substance = "Ibuprofen")
```

**Output files:**
- Network: `Outputs/bega/pts.csv`, `Outputs/bega/HL.csv`, `Outputs/bega/network_rivers.shp`
- Network maps: `Outputs/bega/plots/static_network_overview.png`, `Outputs/bega/plots/interactive_network_map.html`
- Simulation: `Outputs/bega_ibuprofen/results_pts_bega_Ibuprofen.csv`
- Concentration map: `Outputs/bega_ibuprofen/plots/concentration_map.html`

Open the HTML files in any browser to explore results interactively.
