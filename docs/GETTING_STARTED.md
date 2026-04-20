# Getting Started with ePiE

ePiE (environmental Pharmaceuticals in the Environment) is a spatially explicit model for estimating API and pathogen concentrations in surface waters. This guide covers the full setup from clone to first simulation.

## 1. Prerequisites

### System Requirements
- **R (>= 4.0)**
- **C++11 compiler** (required for the Rcpp/C++ engine)
- **GDAL**, **GEOS**, **PROJ** (required by `sf` and `terra`)

On macOS:
```bash
brew install gdal geos proj
```

On Ubuntu/Debian:
```bash
sudo apt-get install r-base libgdal-dev libgeos-dev libproj-dev libudunits2-dev
```

### R Dependencies
```r
install.packages(c(
  "Rcpp", "sf", "terra", "raster", "dplyr", "plyr", "stringr",
  "fasterize", "mapview", "leaflet", "htmlwidgets", "htmltools",
  "openxlsx", "RcppThread"
))
```

## 2. Clone and Install

```bash
git clone git@github.com:AudLem/ePiE.git
cd ePiE
./scripts/setup-data.sh
R CMD INSTALL Package
```

> **Do NOT use `devtools::install_local()`** — `devtools` has heavy dependencies (gert, usethis, libgit2) that may fail to install. `R CMD INSTALL` works without them.

## 3. Download Data

Run the setup script to download basin data, chemical properties, and pre-built networks (~18 MB):

```bash
./scripts/setup-data.sh
```

The script auto-detects the GitHub repo URL and downloads from the v1.26.0 release. It verifies SHA-256 checksums and skips files that are already present (safe to re-run).

### Baseline Data (download separately)

Baseline raster data is not bundled due to licensing and size. Download from official sources:

| Dataset | Source | Target directory |
|---------|--------|-----------------|
| HydroSHEDS HydroRIVERS | [hydrosheds.org](https://www.hydrosheds.org/) | `Inputs/baselines/hydrosheds/` |
| FLO1K discharge | [PANGAEA](https://doi.org/10.1594/PANGAEA.868758) | `Inputs/baselines/hydrosheds/` |
| WorldClim v2 temperature | [worldclim.org](https://www.worldclim.org/data/worldclim21.html) | `Inputs/baselines/environmental/` |
| GHS-POP population | [GHS-POP](https://ghsl.jrc.ec.europa.eu/ghs_pop2019.php) | `Inputs/baselines/environmental/` |

Download the data for your target region (Africa for Volta, Europe for Bega) and place in the directories above.

## 4. Verify Installation

```bash
Rscript scripts/smoke-test.R
```

This runs automated checks:
- `library(ePiE)` loads
- `ListScenarios()` returns 30 scenarios
- Scenario config loading works
- Pathogen parameter files are valid
- Data files are present
- Pre-built networks have valid structure

All checks should pass with `[PASS]`. Any `[FAIL]` indicates a problem that needs fixing before running simulations.

## 5. Directory Structure

```
ePiE/
├── Inputs/
│   ├── basins/
│   │   ├── volta/                    # Volta shapefiles, GeoGLOWS, canals
│   │   │   └── geoglows/            # GeoGLOWS v2 data
│   │   └── bega/                    # Bega shapefiles
│   ├── baselines/
│   │   ├── hydrosheds/              # HydroSHEDS + FLO1K (download separately)
│   │   └── environmental/           # WorldClim, GHS-POP (download separately)
│   └── user/
│       ├── chem_Oldenkamp2018_SI.xlsx
│       └── EEF_points_updated.csv
├── Outputs/
│   ├── volta_wet/                   # Pre-built Volta wet network
│   ├── volta_dry/                   # Pre-built Volta dry network
│   ├── volta_geoglows_wet/          # Pre-built Volta GeoGLOWS network
│   └── bega/                        # Pre-built Bega network
└── Package/                         # R package source
```

## 6. Configuration

The model uses a two-tier configuration system in `Package/inst/config/`:
1. **Basin Configs** — define physical data locations (shapefiles, rasters) for each basin
2. **Scenario Configs** — define simulation parameters (substance, season, output directory)

List all available scenarios:
```r
library(ePiE)
ListScenarios()
```

See [USAGE.md](./USAGE.md) for the full scenario table and custom run instructions.

## 7. Running Your First Simulation

**IMPORTANT**: Always run network builds and simulations with `diagnostics = "full"` enabled. This generates diagnostic plots and logs that are essential for troubleshooting and understanding model behavior. Diagnostic outputs are saved to `<output_dir>/plots/diagnostics/`.

### Using Pre-built Networks

The easiest way to run simulations is to use pre-built networks (included in the repository).

```r
library(ePiE)

data_root   <- "Inputs"
output_root <- "Outputs"

# Load scenario configuration for a pathogen simulation
cfg     <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

# Build the network state
state   <- BuildNetworkPipeline(cfg, diagnostics = "full")

# Run the simulation
results <- RunSimulationPipeline(state, substance = "cryptosporidium")

# View results (concentrations are in results$results$pts)
print(head(results$results$pts[, c("ID", "C_w")]))
```

For chemical simulations (Volta):
```r
library(ePiE)

# Load scenario configuration for a chemical simulation
cfg     <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)

# Build the network state
state   <- BuildNetworkPipeline(cfg, diagnostics = "full")

# Run the simulation
results <- RunSimulationPipeline(state, substance = "Ibuprofen")
```

For Bega basin (Europe):
```r
cfg     <- LoadScenarioConfig("BegaNetwork", data_root, output_root)
state   <- BuildNetworkPipeline(cfg, diagnostics = "full")

cfg_sim <- LoadScenarioConfig("BegaChemicalIbuprofen", data_root, output_root)
results <- RunSimulationPipeline(state, substance = "Ibuprofen")
```

## Troubleshooting

### `library(ePiE)` fails to load
- Ensure the package was installed: `R CMD INSTALL Package`
- Check R dependencies are installed (see Section 1)
- On macOS, make sure Xcode command line tools are installed: `xcode-select --install`

### `Error in sf::st_read()` — GDAL not found
- Install GDAL: `brew install gdal` (macOS) or `sudo apt install libgdal-dev` (Linux)
- Reinstall `sf`: `install.packages("sf")`

### `setup-data.sh` download fails
- Check internet connection
- Verify the GitHub repo is accessible: `git remote -v`
- The release must exist: `gh release view v1.26.0` or check https://github.com/AudLem/ePiE/releases

### Simulation produces all-zero concentrations
- Verify baseline data is in `Inputs/baselines/` (HydroSHEDS flow data required)
- Check `LoadScenarioConfig()` returns correct paths
- For pathogens, ensure `total_population` is set in the basin config

### C++ compilation errors during install
- Ensure Xcode command line tools (macOS) or `build-essential` (Linux) are installed
- R must be >= 4.0 with C++11 support

For debugging setup, see [DEBUGGING.md](./DEBUGGING.md).
