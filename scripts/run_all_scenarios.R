library(parallel)
library(ePiE)
# Ensure tmap is loaded
library(tmap)

# Load dependencies for simulation
source('Package/R/00_utils.R'); source('Package/R/00_Check_cons_v2.R'); 
source('Package/R/01_LoadBasins.R'); source('Package/R/01_SelectBasins.R'); 
source('Package/R/01_ExampleData.R'); source('Package/R/CheckConsumptionData.R'); 
source('Package/R/01_LoadLongTermFlow.R'); source('Package/R/01_AddFlowToBasinData.R'); 
source('Package/R/02_ComputeEnvConcentrations.R'); source('Package/R/02_CompleteChemProperties.R'); 
source('Package/R/02_RunSimpleTreat4.R'); source('Package/R/SimpleTreat4_0.R'); 
source('Package/R/Adv_treatment.R'); source('Package/R/Process_formulas.R'); 
source('Package/R/Set_upstream_points_v2.R'); source('Package/R/RcppExports.R'); 
source('Package/R/Set_local_parameters_custom_removal_fast3.R'); 
source('Package/R/02_PathogenModel.R'); source('Package/R/Compute_env_concentrations_v4.R');
source('Package/R/VisualizeWithTmap.R');

# Simulation setup function
run_single_scenario <- function(s) {
  tryCatch({
    out_dir <- paste0("Outputs/", s$name)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    
    # Load basic chem/cons (as per ExampleData.R)
    chem <- CompleteChemProperties(LoadExampleChemProperties())
    cons <- LoadExampleConsumption()
    basins <- SelectBasins(basins_data = LoadEuropeanBasins(), basin_ids = s$basin)
    flow_avg <- LoadLongTermFlow("average")
    basins_avg <- AddFlowToBasinData(basin_data = basins, flow_rast = flow_avg)
    
    # Run simulation
    # Note: pathogen simulations would require setting pathogen parameters here
    res <- ComputeEnvConcentrations(basin_data = basins_avg, chem = chem, cons = cons, verbose = FALSE, cpp = TRUE)
    
    # Save map
    VisualizeWithTmap(res$pts, res$hl, filename = paste0(out_dir, "/map.html"))
    return(paste("Success:", s$name))
  }, error = function(e) {
    return(paste("Error in", s$name, ":", e$message))
  })
}

# Scenario list
scenarios <- list(
  list(name="pathogen_crypto", type="pathogen", basin="volta"),
  list(name="bega_ibuprofen", type="chem", basin="bega")
)

# Test run one scenario first to ensure logic is sound
print("Running single-scenario test...")
print(run_single_scenario(scenarios[[1]]))

# If test passes, run in parallel
print("Running all in parallel...")
mclapply(scenarios, run_single_scenario, mc.cores = detectCores() - 1)
