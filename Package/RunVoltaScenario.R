# Run Volta Pathogen Simulation
library(ePiE)

# 1. Setup Data
chem = CompleteChemProperties(LoadExampleChemProperties())
cons = LoadExampleConsumption()
basins = LoadEuropeanBasins()

# 2. Select Volta (using the basin ID 'volta')
# Ensure 'volta' is in the list provided by List_basins()
basin_ids = c('volta')
basins = SelectBasins(basins_data = basins, basin_ids = basin_ids)

# 3. Enrichment
# Using 'average' flow as a default; swap with 'minimum' for dry season
flow_avg = LoadLongTermFlow("average")
basins_avg = AddFlowToBasinData(basin_data = basins, flow_rast = flow_avg)

# 4. Simulation
# Replace these params with your specific pathogen values (e.g., prev_rate, exc_rate)
results = ComputeEnvConcentrations(basin_data = basins_avg, chem = chem, cons = cons, verbose=TRUE, cpp=TRUE)

# 5. Visualization
InteractiveResultMap(results, basin_id = 'volta', cex = 2)
