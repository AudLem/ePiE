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
basins_avg <- AddFlowToBasinData(basins, flow_avg)
results <- ComputeEnvConcentrations(basins_avg, chem, cons, verbose = TRUE, cpp = TRUE)
InteractiveResultMap(results, basin_id = 107287)
```

## Pipeline Workflow — Custom Basins

For non-European basins (e.g. Volta, Bega), use the config-driven pipeline:

### 1. Build a Network

```r
library(ePiE)
data_root <- "/path/to/data"       # see DATA_REQUIREMENTS.md
output_root <- "/path/to/outputs"

net_cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
state <- BuildNetworkPipeline(net_cfg)
```

### 2. Run a Simulation

```r
# Chemical (Ibuprofen)
sim_cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
results <- RunSimulationPipeline(sim_cfg)

# Pathogen (Cryptosporidium)
sim_cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
results <- RunSimulationPipeline(sim_cfg)
```

### Available Scenarios

```r
ListScenarios()
#  [1] "VoltaWetNetwork"             "VoltaDryNetwork"
#  [3] "BegaNetwork"                 "VoltaWetChemicalIbuprofen"
#  [5] "VoltaDryChemicalIbuprofen"   "VoltaWetPathogenCrypto"
#  [7] "VoltaDryPathogenCrypto"      "BegaChemicalIbuprofen"
#  [9] "BegaPathogenCrypto"
```

## Adding a New Basin

1. Create `inst/config/basins/mybasin.R` defining `MyBasinConfig(data_root)` — see existing configs for the required fields.
2. Create `inst/config/scenarios/mybasin_simulations.R` with scenario constructors for chemical and/or pathogen runs.
3. Add the scenario names to `ListScenarios()` in `R/30_LoadScenarioConfig.R`.
4. Place basin data under `data_root/basins/mybasin/` (see `DATA_REQUIREMENTS.md`).

## Adding a New Pathogen

1. Create `inst/pathogen_input/newpathogen.R` defining a `simulation_parameters` list with fields: `type`, `name`, `dose_response`, `infectivity`, `decay_rate`, `settling_velocity`, and optional WWTP removal rates.
2. The pipeline will automatically route through pathogen decay formulas when `substance_type = "pathogen"`.

## External Data

The package requires geospatial data (HydroSHEDS, FLO1K, climate rasters, WWTP databases) not included in the package. See **DATA_REQUIREMENTS.md** for the full manifest and download sources.

## Testing

```r
testthat::test_dir("tests/testthat")
```

144 tests cover: regression (Ouse/Ibuprofen), pathogen decay formulas, pipeline unit tests (normalise, hydrology, emissions), and end-to-end tests for Volta and Bega basins.

## Citation

Hoeks, S., Oldenkamp, R., & Lemme, A. ePiE: Exposure model for Pharmaceuticals in the Environment.

## License

GPL (>= 3)
