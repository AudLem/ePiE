## Existing functions renamed

-   [x] Add_new_flow_fast() + Select_hydrology_fast2() rename one function called AddFlowToBasin()
-   [x] Rename Check_cons_v2() to CheckConsumption()
-   [x] Rename Compute_env_concentration_cpp_custom_removal() to ComputeEnvConcentrations()

## New functions

-   [x] LoadExampleChemProperties(), this loads the standard chem properties example file for Ibuprofen
-   [x] LoadEuropeanBasins(), this loads a couple of European basins
-   [x] LoadExampleConsumption(), this loads example consumption data
-   [x] CompleteChemProperties() --\> Check_chem_WWTP_removal_data() + Chem_complete()
-   [x] CheckConsumptionData(), runs Check_cons_v2, is able to fill potential gaps in the future
-   [x] SelectBasins(), this selects a basin from the loaded file, it also calls Set_upstream_points_v2()

## Output and plotting functions

-   [ ] ...

## Current Exports (from NAMESPACE)

```r
export(LoadExampleChemProperties)
export(LoadExampleConsumption)
export(CompleteChemProperties)
export(CheckConsumptionData)
export(LoadEuropeanBasins)
export(SelectBasins)
export(LoadLongTermFlow)
export(AddFlowToBasinData)
export(ComputeEnvConcentrations)
export(CalculateWriteEnvStats)
export(CreateHTMLMaps)
export(ePiEPath)
export(ePiEVersion)
export(RunSimpleTreatBasinAvg)
export(SetLocalParameters)
export(SimpleTreat4_0)
export(LoadPathogenParameters)
export(ValidatePathogenParams)
export(ResolvePathogenParams)
export(InitializeSubstance)
export(LoadNetworkInputs)
export(PrepareCanalLayers)
export(ProcessRiverGeometry)
export(ProcessLakeGeometries)
export(DetectLakeSegmentCrossings)
export(ExtractPopulationSources)
export(MapWWTPLocations)
export(BuildNetworkTopology)
export(ConnectLakesToNetwork)
export(IntegratePointsAndLines)
export(SaveNetworkArtifacts)
export(VisualizeNetwork)
export(NormalizeScenarioState)
export(AssignHydrology)
export(CalculateEmissions)
export(VisualizeConcentrations)
export(LoadScenarioConfig)
export(ListScenarios)
export(BuildNetworkPipeline)
export(RunSimulationPipeline)
export(PrintCheckpointSummary)
export(VisualizeWithTmap)
```
