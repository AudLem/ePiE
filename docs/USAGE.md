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

## 2. Legacy Chemical Run (European Basins)

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

## 3. Available Scenarios

| Scenario Name | Basin | Season | Substance |
|---|---|---|---|
| `VoltaWetNetwork` | Volta | Wet | — (network build) |
| `VoltaDryNetwork` | Volta | Dry | — (network build) |
| `VoltaWetChemicalIbuprofen` | Volta | Wet | Ibuprofen |
| `VoltaDryChemicalIbuprofen` | Volta | Dry | Ibuprofen |
| `VoltaWetPathogenCrypto` | Volta | Wet | Cryptosporidium |
| `VoltaDryPathogenCrypto` | Volta | Dry | Cryptosporidium |
| `BegaNetwork` | Bega | — | — (network build) |
| `BegaChemicalIbuprofen` | Bega | — | Ibuprofen |
| `BegaPathogenCrypto` | Bega | — | Cryptosporidium |

## 4. Output Files

After running a simulation, the output directory contains:

```text
<run_output_dir>/
├── results_pts_<basin>_<substance>.csv   # Node concentrations
├── results_hl_<basin>_<substance>.csv    # Lake concentrations
└── plots/
    └── concentration_map.html            # Interactive Leaflet map
```

Open the HTML file in any browser to explore results interactively.
