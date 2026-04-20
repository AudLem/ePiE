# End-to-End Workflow

This guide provides a complete workflow for using ePiE, from data preparation through simulation to results interpretation. It emphasizes what to do **before** network creation and **after** simulation completion.

## Overview

The ePiE workflow consists of two main phases:

1. **Network Building Phase** - Create river topology from spatial data
2. **Simulation Phase** - Run concentration calculations on a network

```
┌─────────────────────────────────────────────────────────────┐
│  PHASE 1: NETWORK BUILDING                                    │
│  ┌──────────────────┐                                        │
│  │ Data Validation  │ ← PRE_NETWORK_VALIDATION.md            │
│  └────────┬─────────┘                                        │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                        │
│  │ BuildNetwork     │ ← Creates pts.csv, HL.csv, rivers.shp │
│  │ Pipeline         │                                        │
│  └────────┬─────────┘                                        │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                        │
│  │ Network          │ ← Interactive and static maps          │
│  │ Visualization   │                                        │
│  └──────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 2: SIMULATION                                         │
│  ┌──────────────────┐                                        │
│  │ Load Scenario    │ ← Chemical or pathogen configuration  │
│  │ Config           │                                        │
│  └────────┬─────────┘                                        │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                        │
│  │ RunSimulation    │ ← Computes concentrations             │
│  │ Pipeline         │                                        │
│  └────────┬─────────┘                                        │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                        │
│  │ Results          │ ← POST_SIMULATION_GUIDE.md            │
│  │ Validation       │                                        │
│  └────────┬─────────┘                                        │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                        │
│  │ Concentration    │ ← Interactive and static maps          │
│  │ Visualization   │                                        │
│  └──────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: Network Building

### Step 0: Prepare Your Environment

```bash
# Clone repository
git clone git@github.com:AudLem/ePiE.git
cd ePiE

# Download data
./scripts/setup-data.sh

# Install package
R CMD INSTALL Package

# Verify installation
Rscript scripts/smoke-test.R
```

### Step 1: Validate Input Data (BEFORE Building)

**This is critical!** Before building your network, validate all required data files.

See **[PRE_NETWORK_VALIDATION.md](PRE_NETWORK_VALIDATION.md)** for detailed guidance.

Quick validation:
```r
library(ePiE)

# Load basin config
bc <- VoltaBasinConfig("Inputs")

# Check file existence
required_files <- c(
  bc$basin_shp_path,
  bc$lakes_shp_path,
  bc$wet_river_shp_path,
  bc$slope_raster_path,
  bc$wind_raster_path,
  bc$temp_raster_path,
  bc$flow_raster_path
)

for (path in required_files) {
  if (file.exists(path)) {
    cat("✓", basename(path), "\n")
  } else {
    cat("✗ MISSING:", path, "\n")
  }
}
```

### Step 2: Build the Network

```r
library(ePiE)

# Load network scenario config
cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")

# Build the network
state <- BuildNetworkPipeline(cfg, diagnostics = "full")
```

### Step 3: Verify Network Build

```r
# Check output
cat("Network build results:\n")
cat("  Points:", nrow(state$points), "\n")
cat("  Lakes:", nrow(state$HL_basin), "\n")
cat("  Output directory:", cfg$run_output_dir, "\n")

# Check output files
list.files(cfg$run_output_dir)

# Expected outputs:
# - pts.csv (network nodes)
# - HL.csv (lake nodes)
# - network_rivers.shp (river geometry)
# - plots/interactive_network_map.html
# - plots/static_network_overview.png
```

### Step 4: Inspect Network Maps

Open the network maps to verify topology:

```bash
# Interactive map
open Outputs/volta_wet/plots/interactive_network_map.html

# Static overview
open Outputs/volta_wet/plots/static_network_overview.png

# Node types map
open Outputs/volta_wet/plots/static_node_types.png
```

**What to check:**
- Rivers flow toward the mouth
- Lakes are connected to rivers
- Canals (if present) are visible
- Node types are color-coded
- Network is fully connected

### Expected Network Sizes

| Network | Points | Lakes | Source |
|---------|--------|-------|--------|
| Bega | 482 | 9 | HydroSHEDS |
| Volta Wet | 351 | 7 | HydroSHEDS |
| Volta Dry | 178 | 7 | HydroSHEDS |
| Volta GeoGLOWS Wet | 924 | 7 | GeoGLOWS v2 |
| Volta GeoGLOWS Dry | 924 | 7 | GeoGLOWS v2 |

## Phase 2: Simulation

### Step 5: Load Simulation Configuration

```r
library(ePiE)

# Load simulation scenario config
cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs")

# Inspect configuration
cat("Scenario:", cfg$target_substance, "\n")
cat("Type:", cfg$substance_type, "\n")
cat("Output directory:", cfg$run_output_dir, "\n")
```

### Step 6: Run Simulation

```r
# Run the simulation
results <- RunSimulationPipeline(state, substance = cfg$target_substance)
```

**What happens:**
1. Normalizes network topology
2. Adds discharge data (from raster or GeoGLOWS)
3. Initializes substance parameters
4. Computes emissions
5. Runs concentration engine
6. Generates concentration maps

### Step 7: Validate Results (AFTER Simulation)

**This is critical!** Always validate results before proceeding to analysis.

See **[POST_SIMULATION_GUIDE.md](POST_SIMULATION_GUIDE.md)** for detailed guidance.

Quick validation:
```r
# Load results
results <- read.csv("Outputs/volta_crypto_wet/results_pts_volta_cryptosporidium.csv")

# Basic statistics
cat("Results summary:\n")
cat("  Total nodes:", nrow(results), "\n")
cat("  Concentrations > 0:", sum(results$C_w > 0, na.rm = TRUE), "\n")
cat("  Concentrations = NA:", sum(is.na(results$C_w)), "\n")
cat("  Discharge > 0:", sum(results$Q > 0, na.rm = TRUE), "\n")
```

### Step 8: Inspect Concentration Maps

```bash
# Interactive map
open Outputs/volta_crypto_wet/plots/concentration_map.html

# Static map
open Outputs/volta_crypto_wet/plots/static_concentration_map.png
```

**What to check:**
- Legend is populated (not empty)
- Color gradient is visible
- Concentrations decrease downstream
- Canals are visible (cyan lines)
- Emission sources are visible (red dots)

### Step 9: Analyze Results

```r
# Load results
results <- read.csv("Outputs/volta_crypto_wet/simulation_results.csv")

# Summary statistics
summary(results$C_w)

# Histogram of concentrations
hist(log10(results$C_w[results$C_w > 0]),
     main = "Cryptosporidium Concentrations (log10)",
     xlab = "log10(C_w)")

# Concentration vs discharge
plot(results$Q, results$C_w,
     main = "Concentration vs Discharge",
     xlab = "Q (m³/s)", ylab = "C_w (oocysts/L)",
     log = "xy")
```

## Complete Workflow Examples

### Example 1: Volta Wet with Cryptosporidium

```r
library(ePiE)

# === PHASE 1: BUILD NETWORK ===

# Step 1: Validate inputs (see PRE_NETWORK_VALIDATION.md)
bc <- VoltaBasinConfig("Inputs")
# ... validation checks ...

# Step 2: Build network
cfg_net <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg_net)

# Step 3: Verify network
cat("Network:", nrow(state$points), "points,", nrow(state$HL_basin), "lakes\n")

# Step 4: View network map
browseURL(file.path(cfg_net$run_output_dir, "plots", "interactive_network_map.html"))

# === PHASE 2: RUN SIMULATION ===

# Step 5: Load simulation config
cfg_sim <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs")

# Step 6: Run simulation
results <- RunSimulationPipeline(state, substance = "cryptosporidium")

# Step 7: Validate results (see POST_SIMULATION_GUIDE.md)
res <- read.csv("Outputs/volta_crypto_wet/results_pts_volta_cryptosporidium.csv")
cat("Concentrations > 0:", sum(res$C_w > 0), "\n")
cat("Concentrations = NA:", sum(is.na(res$C_w)), "\n")

# Step 8: View concentration map
browseURL(file.path(cfg_sim$run_output_dir, "plots", "concentration_map.html"))

# Step 9: Analyze results
summary(res$C_w)
hist(log10(res$C_w[res$C_w > 0]))
```

### Example 2: Bega with Ibuprofen

```r
library(ePiE)

# === PHASE 1: BUILD NETWORK ===

# Step 1: Validate inputs
bc <- BegaBasinConfig("Inputs")
# ... validation checks ...

# Step 2: Build network
cfg_net <- LoadScenarioConfig("BegaNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg_net)

# Step 3: Verify network
cat("Network:", nrow(state$points), "points,", nrow(state$HL_basin), "lakes\n")

# Step 4: View network map
browseURL(file.path(cfg_net$run_output_dir, "plots", "interactive_network_map.html"))

# === PHASE 2: RUN SIMULATION ===

# Step 5: Load simulation config
cfg_sim <- LoadScenarioConfig("BegaChemicalIbuprofen", "Inputs", "Outputs")

# Step 6: Run simulation
results <- RunSimulationPipeline(state, substance = "Ibuprofen")

# Step 7: Validate results
res <- read.csv("Outputs/bega_ibuprofen/results_pts_bega_Ibuprofen.csv")
cat("Concentrations > 0:", sum(res$C_w > 0), "\n")
cat("Concentrations = NA:", sum(is.na(res$C_w)), "\n")

# Step 8: View concentration map
browseURL(file.path(cfg_sim$run_output_dir, "plots", "concentration_map.html"))

# Step 9: Analyze results
summary(res$C_w)
hist(res$C_w[res$C_w > 0])
```

### Example 3: GeoGLOWS with All Pathogens

```r
library(ePiE)

# === PHASE 1: BUILD NETWORK (once) ===

# Build GeoGLOWS network
cfg_net <- LoadScenarioConfig("VoltaGeoGLOWSNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg_net)

# === PHASE 2: RUN MULTIPLE SIMULATIONS ===

# Define pathogens
pathogens <- c("cryptosporidium", "campylobacter", "rotavirus", "giardia")

# Run all pathogen simulations
for (pathogen in pathogens) {
  # Load simulation config
  scenario_name <- paste0("VoltaGeoGLOWSWetPathogen",
                         tools::toTitleCase(pathogen))
  cfg_sim <- LoadScenarioConfig(scenario_name, "Inputs", "Outputs")

  # Run simulation
  results <- RunSimulationPipeline(state, substance = pathogen)

  # Validate results (pipeline returns data programmatically, CSV is written separately)
  res <- results$results$pts
  cat(pathogen, ": C_w > 0 =", sum(res$C_w > 0), ", NA =", sum(is.na(res$C_w)), "\n")

  # View concentration map
  browseURL(file.path(cfg_sim$run_output_dir, "plots", "concentration_map.html"))
}
```

## Parallel Execution

For running many scenarios, use the parallel runner:

```bash
# Run all scenarios in parallel
Rscript scripts/run_all_scenarios.R
```

This automatically:
- Builds all required networks
- Runs all simulations in parallel
- Saves all results and maps to `Outputs/`

## Troubleshooting

### Network Building Issues

**Problem**: "File not found" errors
- **Check**: File paths in basin config
- **Solution**: Run `./scripts/setup-data.sh`

**Problem**: "Rivers do not intersect basin"
- **Check**: Basin boundary and river network are for same area
- **Solution**: Verify coordinate systems and extents

**Problem**: Network has very few points
- **Check**: Basin extent is not too small
- **Solution**: Verify basin boundary polygon

### Simulation Issues

**Problem**: All concentrations are zero
- **Check**: Emission sources exist (WWTPs, agglomerations)
- **Check**: Population data is loaded
- **Solution**: Add WWTP data or enable direct discharge

**Problem**: All concentrations are NA
- **Check**: Discharge data loaded correctly
- **Check**: Q propagation didn't fail
- **Solution**: Verify flow raster or GeoGLOWS data

**Problem**: Concentrations don't decrease downstream
- **Check**: River network is fully connected
- **Check**: Decay parameters are realistic
- **Solution**: Verify topology and parameters

For detailed troubleshooting, see:
- [PRE_NETWORK_VALIDATION.md](PRE_NETWORK_VALIDATION.md) - Before network building
- [POST_SIMULATION_GUIDE.md](POST_SIMULATION_GUIDE.md) - After simulation
- [DEBUGGING.md](DEBUGGING.md) - Debugging techniques

## Documentation Reference

| Document | When to Read | Purpose |
|----------|--------------|---------|
| [GETTING_STARTED.md](GETTING_STARTED.md) | First time setup | Installation and initial configuration |
| [PRE_NETWORK_VALIDATION.md](PRE_NETWORK_VALIDATION.md) | Before building network | Validate input data and configuration |
| [POST_SIMULATION_GUIDE.md](POST_SIMULATION_GUIDE.md) | After simulation | Interpret and validate results |
| [USAGE.md](USAGE.md) | During simulation | API reference and usage examples |
| [DEBUGGING.md](DEBUGGING.md) | When errors occur | Debugging techniques |
| [TESTING.md](TESTING.md) | Development/testing | Test procedures and expected results |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | Understanding codebase | Package organization |
| [DATA_REQUIREMENTS.md](DATA_REQUIREMENTS.md) | Setting up data | Data sources and formats |
| [CONFIGURATION.md](CONFIGURATION.md) | Customizing scenarios | Configuration reference |

## Quick Command Reference

```bash
# Setup
./scripts/setup-data.sh                    # Download data
R CMD INSTALL Package                      # Install package
Rscript scripts/smoke-test.R             # Verify installation

# Build networks (examples)
Rscript -e 'library(ePiE); cfg <- LoadScenarioConfig("BegaNetwork", "Inputs", "Outputs"); BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs"); BuildNetworkPipeline(cfg)'
Rscript -e 'library(ePiE); cfg <- LoadScenarioConfig("VoltaGeoGLOWSNetwork", "Inputs", "Outputs"); BuildNetworkPipeline(cfg)'

# Run simulations (examples)
Rscript run_bega_campylobacter.R
Rscript run_volta_wet_campylobacter.R
Rscript run_volta_dry_campylobacter.R

# Run all scenarios in parallel
Rscript scripts/run_all_scenarios.R

# View maps (macOS)
open Outputs/volta_wet/plots/interactive_network_map.html
open Outputs/volta_campy_wet/plots/concentration_map.html
```

## Next Steps

After completing the workflow:

1. **Export results** for further analysis in R, Python, or GIS
2. **Compare scenarios** (wet vs dry, HydroSHEDS vs GeoGLOWS)
3. **Document findings** for your research
4. **Share results** via interactive HTML maps

See [POST_SIMULATION_GUIDE.md](POST_SIMULATION_GUIDE.md) for result export and analysis tips.
