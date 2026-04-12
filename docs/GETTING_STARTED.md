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

## 2. Directory Structure Setup

To run the full simulation pipeline, you must organize your external data in a `data_root` directory following this structure:

```text
data_root/
├── basins/
│   ├── volta/         # Shapefiles and local rasters for Volta
│   └── bega/          # Shapefiles and local rasters for Bega
├── baselines/
│   ├── hydrosheds/    # Global/Continental HydroSHEDS files
│   └── environmental/ # FLO1K, Population, Wind, Temp rasters
└── user/
    └── chem_Oldenkamp2018_SI.xlsx # Chemical properties table
```

## 3. Configuration

The model uses a two-tier configuration system found in `Package/inst/config/`:
1. **Basin Configs**: Define where the physical files (shapefiles, rasters) are for a specific basin (e.g., `volta.R`).
2. **Scenario Configs**: Define simulation parameters (e.g., substance, season, output directory) for a run.

## 4. Running your first simulation

You can run a simulation using the `RunSimulationPipeline` function:

```r
library(ePiE)

# Define your paths
data_root <- "path/to/your/data_root"
output_root <- "path/to/your/outputs"

# Load a scenario configuration
cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

# Run the pipeline
results <- RunSimulationPipeline(cfg)
```

For more details on available scenarios and custom runs, see [USAGE.md](./USAGE.md).
