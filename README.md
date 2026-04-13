# ePiE

ePiE is a spatially explicit model that estimates concentrations of active pharmaceutical ingredients (APIs) and pathogens in surface waters. It combines river catchment networks, WWTP infrastructure, substance fate modelling (SimpleTreat 4.0 for chemicals, pathogen-specific decay), and a C++ engine for fast concentration computation.

Supports basins in Africa (Volta/Ghana) and Europe (Bega/Romania) using HydroSHEDS and GeoGLOWS v2 river networks. Currently models Cryptosporidium, Campylobacter, Rotavirus, and Giardia alongside chemical APIs (e.g. Ibuprofen).

## Prerequisites

- **R >= 4.0** with a **C++11 compiler**
- [GDAL](https://gdal.org/) (required by `sf` and `terra`)
- [GEOS](https://libgeos.org/) (required by `sf`)
- [PROJ](https://proj.org/) (required by `sf`)

On macOS: `brew install gdal geos proj`

## Quick Start

```bash
git clone git@github.com:AudLem/ePiE.git
cd ePiE
./scripts/setup-data.sh
R CMD INSTALL Package
Rscript scripts/smoke-test.R
```

### 1. Clone

```bash
git clone git@github.com:AudLem/ePiE.git
cd ePiE
```

### 2. Install R dependencies

```r
install.packages(c(
  "Rcpp", "sf", "terra", "raster", "dplyr", "plyr", "stringr",
  "fasterize", "mapview", "leaflet", "htmlwidgets", "htmltools",
  "openxlsx", "RcppThread"
))
```

### 3. Download data

The setup script downloads basin data, chemical properties, and pre-built networks from GitHub Releases (~18 MB total):

```bash
./scripts/setup-data.sh
```

Baseline rasters (HydroSHEDS, FLO1K, WorldClim, GHS-POP) must be downloaded separately — see [Required Baseline Data](#required-baseline-data) below.

### 4. Install the package

```bash
R CMD INSTALL Package
```

> Do NOT use `devtools::install_local()` — `devtools` has heavy dependencies that may fail to install.

### 5. Verify installation

```bash
Rscript scripts/smoke-test.R
```

## Running Simulations

```r
library(ePiE)

data_root   <- "Inputs"
output_root <- "Outputs"

cfg     <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
results <- RunSimulationPipeline(cfg)

print(head(results$pts[, c("ID", "C_w", "E_w")]))
```

**Pathogen example:**

```r
cfg     <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
results <- RunSimulationPipeline(cfg)

print(head(results$pts[, c("ID", "C_w", "E_w")]))
```

## Available Scenarios

| Scenario | Basin | Season | Source | Type |
|----------|-------|--------|--------|------|
| `VoltaWetChemicalIbuprofen` | Volta | Wet | HydroSHEDS | Chemical |
| `VoltaDryChemicalIbuprofen` | Volta | Dry | HydroSHEDS | Chemical |
| `VoltaGeoGLOWSWetChemicalIbuprofen` | Volta | Wet | GeoGLOWS | Chemical |
| `VoltaGeoGLOWSDryChemicalIbuprofen` | Volta | Dry | GeoGLOWS | Chemical |
| `BegaChemicalIbuprofen` | Bega | — | HydroSHEDS | Chemical |
| `VoltaWetPathogenCrypto` | Volta | Wet | HydroSHEDS | Pathogen |
| `VoltaWetPathogenGiardia` | Volta | Wet | HydroSHEDS | Pathogen |
| `VoltaWetPathogenRotavirus` | Volta | Wet | HydroSHEDS | Pathogen |
| `VoltaWetPathogenCampylobacter` | Volta | Wet | HydroSHEDS | Pathogen |
| `VoltaDryPathogenCrypto` | Volta | Dry | HydroSHEDS | Pathogen |
| `VoltaDryPathogenGiardia` | Volta | Dry | HydroSHEDS | Pathogen |
| `VoltaDryPathogenRotavirus` | Volta | Dry | HydroSHEDS | Pathogen |
| `VoltaDryPathogenCampylobacter` | Volta | Dry | HydroSHEDS | Pathogen |
| `VoltaGeoGLOWSWetPathogenCrypto` | Volta | Wet | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSWetPathogenGiardia` | Volta | Wet | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSWetPathogenRotavirus` | Volta | Wet | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSWetPathogenCampylobacter` | Volta | Wet | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSDryPathogenCrypto` | Volta | Dry | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSDryPathogenGiardia` | Volta | Dry | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSDryPathogenRotavirus` | Volta | Dry | GeoGLOWS | Pathogen |
| `VoltaGeoGLOWSDryPathogenCampylobacter` | Volta | Dry | GeoGLOWS | Pathogen |
| `BegaPathogenCrypto` | Bega | — | HydroSHEDS | Pathogen |
| `BegaPathogenGiardia` | Bega | — | HydroSHEDS | Pathogen |
| `BegaPathogenRotavirus` | Bega | — | HydroSHEDS | Pathogen |
| `BegaPathogenCampylobacter` | Bega | — | HydroSHEDS | Pathogen |
| `VoltaWetNetwork` | Volta | Wet | HydroSHEDS | Network only |
| `VoltaDryNetwork` | Volta | Dry | HydroSHEDS | Network only |
| `VoltaGeoGLOWSNetwork` | Volta | Wet | GeoGLOWS | Network only |
| `BegaNetwork` | Bega | — | HydroSHEDS | Network only |

List all scenarios from R: `ePiE::ListScenarios()`

## Required Baseline Data

Baseline raster data is not bundled due to licensing and size. Download from official sources and place in `Inputs/baselines/`:

| Dataset | Source | Place in |
|---------|--------|----------|
| HydroSHEDS HydroRIVERS | [hydrosheds.org](https://www.hydrosheds.org/) | `Inputs/baselines/hydrosheds/` |
| FLO1K discharge | [PANGAEA](https://doi.org/10.1594/PANGAEA.868758) | `Inputs/baselines/hydrosheds/` |
| WorldClim v2 (temperature) | [worldclim.org](https://www.worldclim.org/data/worldclim21.html) | `Inputs/baselines/environmental/` |
| GHS-POP population | [GHS-POP](https://ghsl.jrc.ec.europa.eu/ghs_pop2019.php) | `Inputs/baselines/environmental/` |

## Project Structure

```
ePiE/
├── Package/                  # R package source
│   ├── R/                    # R functions (numbered by pipeline stage)
│   ├── src/                  # C++ engine (Rcpp)
│   ├── inst/config/          # Basin and scenario configurations
│   ├── inst/pathogen_input/  # Pathogen parameter files
│   └── tests/testthat/       # Unit tests (214 tests)
├── Inputs/
│   ├── basins/volta/         # Volta basin data (river, lakes, canals, GeoGLOWS)
│   ├── basins/bega/          # Bega basin data (river, lakes)
│   ├── baselines/            # Baseline rasters (not in git — download separately)
│   └── user/                 # Chemical properties, EEF points
├── Outputs/                  # Pre-built networks and simulation results
├── scripts/
│   ├── setup-data.sh         # Download data from GitHub Releases
│   └── smoke-test.R          # Installation verification
├── data_manifest.json        # Archive checksums for download verification
└── docs/                     # Documentation
```

## Documentation

- [Getting Started](docs/GETTING_STARTED.md) — detailed setup and troubleshooting
- [Usage & Examples](docs/USAGE.md) — scenario descriptions and custom runs
- [Debugging Guide](docs/DEBUGGING.md) — RStudio and VS Code debugger setup

## Citation

Lemme, A. J., Hoeks, S., & Oldenkamp, R. (2026). ePiE — environmental Pharmaceuticals in the Environment (v1.26.0). GitHub. https://github.com/AudLem/ePiE

## License

GPL-3.0
