# Using ePiE

This guide covers common usage scenarios for the ePiE R package.

## 1. Quick Start: Volta Wet Season (Chemical + Pathogen)

### Step A: Build the network (only needed once)

```r
library(ePiE)
repo <- "<path-to-ePiE>"        # e.g. "/Users/you/aude/ePiE"
data_root  <- file.path(repo, "Inputs")
output_root <- file.path(repo, "Outputs")

cfg_net <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
network <- BuildNetworkPipeline(cfg_net)
```

> **Skip this step** if `Outputs/volta_wet/pts.csv` already exists (pre-built network).

### Step B: Run a chemical simulation (Ibuprofen)

```r
cfg_chem <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
results_chem <- RunSimulationPipeline(cfg_chem)
```

### Step C: Run a pathogen simulation (Cryptosporidium)

```r
cfg_crypto <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
results_crypto <- RunSimulationPipeline(cfg_crypto)
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
results <- RunSimulationPipeline(cfg_sim)
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

InteractiveResultMap(results, basin_id = 107287, cex = 4)
```

## 4. Available Scenarios

### Network Build

| Scenario Name | Basin | Data Source | Season |
|---|---|---|---|
| `VoltaWetNetwork` | Volta | HydroSHEDS | Wet |
| `VoltaDryNetwork` | Volta | HydroSHEDS | Dry |
| `VoltaGeoGLOWSNetwork` | Volta | GeoGLOWS v2 | Wet |
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
| `VoltaDryPathogenCrypto` | Volta | HydroSHEDS | Dry | Cryptosporidium |
| `VoltaGeoGLOWSWetPathogenCrypto` | Volta | GeoGLOWS v2 | Wet | Cryptosporidium |
| `VoltaGeoGLOWSDryPathogenCrypto` | Volta | GeoGLOWS v2 | Dry | Cryptosporidium |
| `BegaPathogenCrypto` | Bega | HydroSHEDS | — | Cryptosporidium |

To list all scenarios programmatically:

```r
library(ePiE)
ListScenarios()
```

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

Open the HTML files in any browser to explore results interactively.
