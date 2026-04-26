# ePiE — Environmental Concentrations of Pharmaceuticals and Pathogens

ePiE is a spatially explicit model that estimates environmental concentrations of active pharmaceutical ingredients (APIs) and pathogens (e.g. *Cryptosporidium*) in surface waters. It combines a parameterised river catchment network with WWTP infrastructure data, substance fate modelling (SimpleTreat 4.0 for chemicals, pathogen-specific decay models), and a C++ engine for fast concentration computation.

## Installation

```r
# From source (requires C++11 compiler)
install.packages("path/to/Package", repos = NULL, type = "source")
```

## Quick Example — European Basins (Chemical)

The original ePiE workflow for European basins with pre-loaded data:

```r
library(ePiE)

chem <- LoadExampleChemProperties()
chem <- CompleteChemProperties(chem)
cons <- LoadExampleConsumption()
basins <- LoadEuropeanBasins()
basins <- SelectBasins(basins, basin_ids = c(124863, 107287))  # Rhine, Ouse
cons <- CheckConsumptionData(basins$pts, chem, cons)
flow_avg <- LoadLongTermFlow("average")
basins_avg <- AddFlowToBasinData(basins, flow_rast = flow_avg)
results <- ComputeEnvConcentrations(basins_avg, chem, cons, verbose = TRUE, cpp = TRUE)
# Results are in results$pts
head(results$pts[, c("ID", "C_w")])
```

## Pipeline Workflow — Custom Basins

For non-European basins (e.g. Volta, Bega), use the config-driven pipeline.
Data is stored in the project's `Inputs/` and `Outputs/` directories (see `DATA_REQUIREMENTS.md`).

### 0. Set Up Paths

```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
data_root <- file.path(repo, "Inputs")
output_root <- file.path(repo, "Outputs")
```

### 1. Build a Network

```r
net_cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
state <- BuildNetworkPipeline(net_cfg)
```

### 2. Run a Simulation

```r
# Chemical (Ibuprofen)
sim_cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
state <- modifyList(state, sim_cfg)  # Merge simulation config into state
results <- RunSimulationPipeline(state, substance = "Ibuprofen")

# Pathogen (Cryptosporidium)
sim_cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
state <- modifyList(state, sim_cfg)  # Merge simulation config into state
results <- RunSimulationPipeline(state, substance = "cryptosporidium")
```

### Available Scenarios

```r
ListScenarios()
#  [1] "BegaChemicalIbuprofen"              "BegaNetwork"
#  [3] "BegaPathogenCampylobacter"          "BegaPathogenCrypto"
#  [5] "BegaPathogenGiardia"                 "BegaPathogenRotavirus"
#  [7] "VoltaDryChemicalIbuprofen"           "VoltaDryNetwork"
#  [9] "VoltaDryPathogenCampylobacter"       "VoltaDryPathogenCrypto"
# [11] "VoltaDryPathogenGiardia"            "VoltaDryPathogenRotavirus"
# [13] "VoltaGeoGLOWSNetwork"               "VoltaGeoGLOWSDryNetwork"
# [15] "VoltaGeoGLOWSDryChemicalIbuprofen"   "VoltaGeoGLOWSDryPathogenCampylobacter"
# [17] "VoltaGeoGLOWSDryPathogenCrypto"      "VoltaGeoGLOWSDryPathogenGiardia"
# [19] "VoltaGeoGLOWSDryPathogenRotavirus"   "VoltaGeoGLOWSWetChemicalIbuprofen"
# [21] "VoltaGeoGLOWSWetPathogenCampylobacter" "VoltaGeoGLOWSWetPathogenCrypto"
# [23] "VoltaGeoGLOWSWetPathogenGiardia"     "VoltaGeoGLOWSWetPathogenRotavirus"
# [25] "VoltaWetChemicalIbuprofen"           "VoltaWetNetwork"
# [27] "VoltaWetPathogenCampylobacter"       "VoltaWetPathogenCrypto"
# [29] "VoltaWetPathogenGiardia"            "VoltaWetPathogenRotavirus"
```

## Adding a New Basin

1. Create `inst/config/basins/mybasin.R` defining `MyBasinConfig(data_root)` — see existing configs for the required fields.
2. Create `inst/config/scenarios/mybasin_simulations.R` with scenario constructors for chemical and/or pathogen runs.
3. Add the scenario names to `ListScenarios()` in `R/30_LoadScenarioConfig.R`.
4. Place basin data under `Inputs/basins/mybasin/` (see `DATA_REQUIREMENTS.md`).

## Adding a New Pathogen

1. Create `inst/pathogen_input/newpathogen.R` defining a `simulation_parameters` list with fields: `type`, `name`, `dose_response`, `infectivity`, `decay_rate`, `settling_velocity`, and optional WWTP removal rates.
2. The pipeline will automatically route through pathogen decay formulas when `substance_type = "pathogen"`.

## External Data

Geospatial data (HydroSHEDS, FLO1K, climate rasters, WWTP databases) lives in the project's `Inputs/` directory (git-ignored). Pre-built networks are in `Outputs/`. See **DATA_REQUIREMENTS.md** for the full manifest.

## Input Files Needed for Installed ePiE

To use the `ePiE` package after installation, ensure you have the following data files available in your working directory (or paths configured via `LoadScenarioConfig`):

1. **River Network**: HydroSHEDS or GeoGLOWS shapefiles/geopackages.
2. **Environmental Rasters**: Discharge (FLO1K), Temperature (WorldClim), Population (GHS-POP).
3. **Substance Data**: Chemical properties Excel file.
4. **Emission Sources**: EEF (European) or HydroWASTE (Global) WWTP CSV files.

Refer to `DATA_REQUIREMENTS.md` for the exact folder structure (`Inputs/` and `Outputs/`) expected by the pipeline.

## Testing

```r
testthat::test_dir("tests/testthat")
```

144 tests cover: regression (Ouse/Ibuprofen), pathogen decay formulas, pipeline unit tests (normalise, hydrology, emissions), and end-to-end tests for Volta and Bega basins.

## Citation

Hoeks, S., Oldenkamp, R., & Lemme, A. ePiE: Exposure model for Pharmaceuticals in the Environment.

## License

GPL (>= 3)
