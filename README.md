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

## Documentation

**Start here:**
- **[WORKFLOW.md](docs/WORKFLOW.md)** - Complete end-to-end workflow with before/after guidance
- **[GETTING_STARTED.md](docs/GETTING_STARTED.md)** - Detailed setup and troubleshooting

**Essential guides:**
- **[PRE_NETWORK_VALIDATION.md](docs/PRE_NETWORK_VALIDATION.md)** - What to check before building networks
- **[POST_SIMULATION_GUIDE.md](docs/POST_SIMULATION_GUIDE.md)** - How to interpret simulation results

**Reference documentation:**
- **[USAGE.md](docs/USAGE.md)** - Usage examples and API reference
- **[CONFIGURATION.md](docs/CONFIGURATION.md)** - Configuration reference (NEW)
- **[DATA_REQUIREMENTS.md](docs/DATA_REQUIREMENTS.md)** - Data sources and formats
- **[PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)** - Package organization

**Specialized documentation:**
- **[DEBUGGING.md](docs/DEBUGGING.md)** - VS Code and RStudio debugging setup
- **[TESTING.md](docs/TESTING.md)** - Test procedures and expected results
- **[LAKE_MODEL.md](docs/LAKE_MODEL.md)** - Lake modeling details
- **[LAKE_CONNECTIVITY.md](docs/LAKE_CONNECTIVITY.md)** - Lake connectivity details
- **[SPATIAL_SIMPLIFICATION.md](docs/SPATIAL_SIMPLIFICATION.md)** - Spatial simplification details

## Prerequisites

- **R >= 4.0** with a **C++11 compiler**
- [GDAL](https://gdal.org/) (required by `sf` and `terra`)
- [GEOS](https://libgeos.org/) (required by `sf`)
- [PROJ](https://proj.org/) (required by `sf`)

On macOS: `brew install gdal geos proj`

## Running Simulations

Chemical and pathogen scenarios use the **pre-built networks** downloaded by `setup-data.sh`. They work immediately after install — **no baseline rasters required**.

```r
library(ePiE)

data_root   <- "Inputs"
output_root <- "Outputs"

# Pathogen simulation
cfg     <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
results <- RunSimulationPipeline(cfg)

# Chemical simulation
cfg     <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
results <- RunSimulationPipeline(cfg)

# View results
browseURL(file.path(cfg$run_output_dir, "plots", "concentration_map.html"))
```

## Building a Network from Scratch

The "Network only" scenarios rebuild the river topology from raw shapefiles and baseline rasters. These **do require baseline data**.

```r
cfg     <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
results <- BuildNetworkPipeline(cfg)
```

See [WORKFLOW.md](docs/WORKFLOW.md) for the complete workflow.

## Available Scenarios

| Scenario | Basin | Season | Source | Type |
|----------|-------|--------|--------|------|
| **HydroSHEDS Chemicals** | | | | |
| `VoltaWetChemicalIbuprofen` | Volta | Wet | HydroSHEDS | Chemical |
| `VoltaDryChemicalIbuprofen` | Volta | Dry | HydroSHEDS | Chemical |
| `BegaChemicalIbuprofen` | Bega | — | HydroSHEDS | Chemical |
| **HydroSHEDS Pathogens** | | | | |
| `VoltaWetPathogen*` | Volta | Wet | HydroSHEDS | Pathogen (4 types) |
| `VoltaDryPathogen*` | Volta | Dry | HydroSHEDS | Pathogen (4 types) |
| `BegaPathogen*` | Bega | — | HydroSHEDS | Pathogen (4 types) |
| **GeoGLOWS v2** | | | | |
| `VoltaGeoGLOWS*ChemicalIbuprofen` | Volta | Wet/Dry | GeoGLOWS | Chemical |
| `VoltaGeoGLOWS*Pathogen*` | Volta | Wet/Dry | GeoGLOWS | Pathogen (4 types) |

List all scenarios: `ListScenarios()`

## Required Baseline Data

Baseline raster data is not bundled due to licensing and size. Download from official sources and place in `Inputs/baselines/`:

| Dataset | Source | Directory |
|---------|--------|-----------|
| HydroSHEDS HydroRIVERS | [hydrosheds.org](https://www.hydrosheds.org/) | `Inputs/baselines/hydrosheds/` |
| FLO1K discharge | [PANGAEA](https://doi.org/10.1594/PANGAEA.868758) | `Inputs/baselines/hydrosheds/` |
| WorldClim v2 temperature | [worldclim.org](https://www.worldclim.org/data/worldclim21.html) | `Inputs/baselines/environmental/` |
| GHS-POP population | [GHS-POP](https://ghsl.jrc.ec.europa.eu/ghs_pop2019.php) | `Inputs/baselines/environmental/` |

See [DATA_REQUIREMENTS.md](docs/DATA_REQUIREMENTS.md) for details.

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
├── Outputs/                  # Pre-built networks and simulation results
├── scripts/                  # Setup and verification scripts
└── data_manifest.json        # Archive checksums
```

See [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for details.

## Citation

Lemme, A. J., Hoeks, S., & Oldenkamp, R. (2026). ePiE — environmental Pharmaceuticals in the Environment (v1.26.0). GitHub. https://github.com/AudLem/ePiE

## License

GPL-3.0
