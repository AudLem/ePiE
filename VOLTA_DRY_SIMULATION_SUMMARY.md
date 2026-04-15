# Summary of Volta Dry Simulation Attempts

## Task
Run 5 Volta dry simulations using ePiE at /Users/gtazzi/aude/ePiE:
1. VoltaDryChemicalIbuprofen → substance = "Ibuprofen"
2. VoltaDryPathogenCrypto → substance = "cryptosporidium"
3. VoltaDryPathogenCampylobacter → substance = "campylobacter"
4. VoltaDryPathogenRotavirus → substance = "rotavirus"
5. VoltaDryPathogenGiardia → substance = "giardia"

## Method Attempted
The approach was to:
1. Load library(ePiE)
2. Load sim_cfg using LoadScenarioConfig(scenario_name, "Inputs", "Outputs")
3. Load pre-built network from Outputs/volta_dry/FinalEnv.RData
4. Merge sim_cfg into state
5. Run RunSimulationPipeline(state, substance)
6. Verify results

## Findings

### 1. Pre-built Network Status
- **Location**: `Outputs/volta_dry/FinalEnv.RData`
- **Network loaded successfully**: YES
  - Points: 178 nodes
  - Rivers: 15 segments
  - Lakes: 7 lakes

### 2. Issues Encountered

#### Issue 1: Missing basin_id Field
- **Problem**: The NormalizeScenarioState function does not add `basin_id` to the normalized network nodes
- **Impact**: Required for downstream processing and split operations
- **Attempted Fix**: Manually added `basin_id` to points and lake nodes
- **Status**: Partial fix, but other issues remained

#### Issue 2: State Object Structure Mismatch
- **Problem**: The RunSimulationPipeline expects a state object from BuildNetworkPipeline, not from loading pre-built FinalEnv.RData
- **Impact**: Multiple field mismatches and missing required columns
- **Root Cause**: The pre-built network structure differs from the state object structure expected by the simulation pipeline

#### Issue 3: Lake Data Over-normalization
- **Problem**: The normalization process adds WWTP-related columns to lake data (f_STP, uwwLoadEnt, etc.)
- **Impact**: Lake data structure becomes corrupted with inappropriate columns
- **Attempted Fix**: Manually removed inappropriate columns from lake data
- **Status**: Partial fix, but simulation still fails

#### Issue 4: Chemical Simulation Error
- **Error**: "non-numeric argument to binary operator" in chemical calculations
- **Location**: SimpleTreat4_0.R: `* chem$fn_WWTP chem$k_bio_wwtp_n`
- **Impact**: Chemical (Ibuprofen) simulation cannot proceed

#### Issue 5: Pathogen Simulation Error
- **Error**: "length of 'dimnames' [2] not equal to array extent"
- **Location**: Compute_env_concentrations_v4.R matrix creation
- **Impact**: All 4 pathogen simulations (Crypto, Campylobacter, Rotavirus, Giardia) fail
- **Root Cause**: Data structure mismatch in matrix operations, likely related to lake data handling

### 3. Network Structure Comparison
Compared volta_dry (178 nodes) with volta_wet (351 nodes):
- Both have 35 columns in point data
- Both have 37 columns in lake data
- Column names are identical between wet and dry networks
- Main difference is number of active nodes (seasonal variation)

### 4. Successful Test Reference
The existing test `test-e2e-volta-crypto.R` demonstrates successful simulation when:
- Building network from scratch using BuildNetworkPipeline
- Using the freshly built state object
- Running RunSimulationPipeline with cryptosporidium

## Summary of Results

**All 5 simulations FAILED**

| Scenario | Substance | Type | Status | Error |
|----------|-----------|------|--------|-------|
| VoltaDryChemicalIbuprofen | Ibuprofen | Chemical | FAILED | Non-numeric argument in binary operator |
| VoltaDryPathogenCrypto | cryptosporidium | Pathogen | FAILED | Matrix dimension mismatch |
| VoltaDryPathogenCampylobacter | campylobacter | Pathogen | FAILED | Matrix dimension mismatch |
| VoltaDryPathogenRotavirus | rotavirus | Pathogen | FAILED | Matrix dimension mismatch |
| VoltaDryPathogenGiardia | giardia | Pathogen | FAILED | Matrix dimension mismatch |

## Recommendation

The current approach of using pre-built networks from FinalEnv.RData with RunSimulationPipeline is **not compatible** with the ePiE simulation architecture. The simulation pipeline expects state objects created by BuildNetworkPipeline, not loaded from saved network files.

To successfully run the Volta dry simulations, the recommended approach would be:
1. Build the volta_dry network using BuildNetworkPipeline (not pre-built)
2. Use the resulting state object directly with RunSimulationPipeline
3. This would require the full build process including hydrology assignment and other initialization steps

## Files Created
- `/Users/gtazzi/aude/ePiE/run_volta_dry_simulations.R` - Main simulation script attempted
- `/Users/gtazzi/aude/ePiE/VOLTA_DRY_SIMULATION_SUMMARY.md` - This summary document
