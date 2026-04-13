# Getting Started with ePiE

ePiE (environmental Pharmaceutical in Europe) is a spatially explicit model for estimating API and pathogen concentrations in surface waters.

## 1. Prerequisites

### System Requirements
- **R (>= 4.0)**
- **C++11 compiler** (required for the Rcpp/C++ engine)
- **External Data**: The model requires large spatial datasets (baselines, rasters, shapefiles) that are not included in the git repository due to size.

### R Dependencies
Install the required packages:
```r
install.packages(c("Rcpp", "sf", "terra", "raster", "dplyr", "plyr", "stringr", 
                   "fasterize", "mapview", "leaflet", "htmlwidgets", "htmltools", 
                   "openxlsx", "RcppThread"))
```

## 2. Install the Package

From the repo root, run in your terminal:

```bash
R CMD INSTALL Package
```

> **Note:** Do NOT use `devtools::install_local()` — `devtools` has heavy dependencies (gert, usethis, libgit2) that may fail to install. `R CMD INSTALL` works without them.

Then in R:
```r
library(ePiE)
```

## 3. Directory Structure Setup

The project uses two directories:
- **`Inputs/`** — source data (shapefiles, rasters, chemical tables). Already populated for Volta and Bega basins.
- **`Outputs/`** — pre-built networks and simulation results. Git-ignored.

```text
ePiE/
├── Inputs/
│   ├── basins/
│   │   ├── volta/                    # Shapefiles and local rasters for Volta
│   │   │   └── geoglows/            # GeoGLOWS v2 data (alternative source)
│   │   │       ├── streams_in_volta_basin.gpkg
│   │   │       └── discharge_in_volta_basin.gpkg
│   │   └── bega/                    # Shapefiles and local rasters for Bega
│   ├── baselines/
│   │   ├── hydrosheds/              # Global HydroSHEDS files
│   │   └── environmental/           # FLO1K, Population, Wind, Temp rasters
│   └── user/
│       └── chem_Oldenkamp2018_SI.xlsx
├── Outputs/
│   ├── volta_wet/                   # Pre-built Volta wet network (HydroSHEDS)
│   ├── volta_dry/                   # Pre-built Volta dry network (HydroSHEDS)
│   ├── volta_geoglows_wet/          # Pre-built Volta network (GeoGLOWS)
│   └── bega/                        # Pre-built Bega network
└── Package/                         # R package source
```

## 4. Configuration

The model uses a two-tier configuration system found in `Package/inst/config/`:
1. **Basin Configs**: Define where the physical files (shapefiles, rasters) are for a specific basin (e.g., `volta.R`, `volta_geoglows.R`).
2. **Scenario Configs**: Define simulation parameters (e.g., substance, season, output directory) for a run.

To list all available scenarios:
```r
library(ePiE)
ListScenarios()
```

See [USAGE.md](./USAGE.md) for the full scenario table.

## 5. Running your first simulation

```r
library(ePiE)

# Paths (relative to repo root or absolute)
repo <- "<path-to-ePiE>"        # e.g. "/Users/you/aude/ePiE"
data_root  <- file.path(repo, "Inputs")
output_root <- file.path(repo, "Outputs")

# Load a scenario configuration
cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

# Run the pipeline
results <- RunSimulationPipeline(cfg)

# View results
print(head(results$pts[, c("ID", "C_w", "E_w")]))

# Open the interactive map in your browser
map_file <- file.path(cfg$run_output_dir, "plots", "concentration_map.html")
browseURL(map_file)
```

For more details on available scenarios and custom runs, see [USAGE.md](./USAGE.md).

For debugging setup, see [DEBUGGING.md](./DEBUGGING.md).
