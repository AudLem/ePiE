# Using ePiE

This guide covers common usage scenarios and examples for the ePiE R package.

## 1. Simple Chemical Run (Ibuprofen)

This example demonstrates a basic run for Ibuprofen in the Rhine and Ouse basins.

```r
library(ePiE)

# 1. Load and complete chemical properties
chem <- LoadExampleChemProperties()
chem <- CompleteChemProperties(chem = chem)

# 2. Test SimpleTreat removal (optional)
removal <- SimpleTreat4_0(
  chem_class = chem$class[1], MW = chem$MW[1], Pv = chem$Pv[1], 
  S = chem$S[1], pKa = chem$pKa[1], Kp_ps = chem$Kp_ps[1], 
  Kp_as = chem$Kp_as[1], k_bio_WWTP = chem$k_bio_wwtp[1],
  T_air = 285, Wind = 4, Inh = 1000, E_rate = 1, PRIM = -1, SEC = -1
)

# 3. Load consumption data
cons <- LoadExampleConsumption()

# 4. Select Basins
basins <- LoadEuropeanBasins()
basin_ids <- c(124863, 107287) # Rhine & Ouse
basins <- SelectBasins(basins_data = basins, basin_ids = basin_ids)

# 5. Check Consumption for selected basins
cons <- CheckConsumptionData(basins$pts, chem, cons)

# 6. Hydrology
flow_avg <- LoadLongTermFlow("average")
basins_avg <- AddFlowToBasinData(basin_data = basins, flow_rast = flow_avg)

# 7. Run Concentration Engine
results <- ComputeEnvConcentrations(
  basin_data = basins_avg, chem = chem, cons = cons, 
  verbose = TRUE, cpp = TRUE
)

# 8. Visualize
InteractiveResultMap(results, basin_id = 107287, cex = 4)
```

## 2. Pathogen Run (Cryptosporidium)

Pathogen runs typically use the new configuration-driven pipeline.

```r
library(ePiE)

data_root <- "/path/to/data_root"
output_root <- "/path/to/outputs"

# Load Volta wet season scenario for Cryptosporidium
cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)

# Execute the full pipeline
results <- RunSimulationPipeline(cfg)

# Results are saved in cfg$run_output_dir and returned as a list
print(head(results$pts))
```

## 3. Available Scenarios

You can list all pre-configured scenarios using:
```r
ListScenarios()
```

Common scenarios include:
- `VoltaWetPathogenCrypto`
- `VoltaDryPathogenCrypto`
- `BegaPathogenCrypto`
- `BegaChemicalIbuprofen`
