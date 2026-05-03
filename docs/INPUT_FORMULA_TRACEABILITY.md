# Input and Formula Traceability

This page explains where ePiE inputs are stored, which scenario field selects
each input, and which formula or model step uses it.

It is written for students and reviewers. The goal is traceability: a reader
should be able to follow each model value from input file to output table.

## Two Input Layers

ePiE uses two input layers.

`Inputs/` stores project data. These files are usually large and are not kept in
Git. They include basin shapes, river networks, lake layers, flow rasters,
population rasters, WWTP files, and chemical workbooks.

`Package/inst/` stores package inputs. These files are small enough to ship with
the package. They include scenario configs, basin configs, pathogen biology,
pathogen profiles, and packaged reference chemical or consumption files.

`Outputs/` stores built networks and simulation results. Simulation scenarios
read pre-built network files from `Outputs/`, especially `pts.csv`, `HL.csv`,
and `transport_edges.csv`.

## Key Symbols

| Symbol | Meaning | Unit |
|---|---|---|
| `Q` | River or canal discharge used by the simulation | m3/s |
| `E_in` | Local source load before treatment or removal | chemical: kg/year; pathogen: pathogen units/year |
| `E_w` | Local load entering surface water after treatment/removal | chemical: kg/year; pathogen: pathogen units/year |
| `E_up` | Load arriving from upstream nodes | chemical: kg/year; pathogen: pathogen units/year |
| `C_w` | Water concentration | chemical: ug/L; pathogen: profile units/L |
| `C_sd` | Sediment concentration | chemical model only |
| `f_pathogen_direct` | Fraction of local agglomeration pathogen load assumed to reach water directly | unitless fraction |
| `k` | Total first-order dissipation rate used in transport | 1/s |
| `K_T` | Temperature decay term for pathogens | 1/day |
| `K_R` | Solar radiation decay term for pathogens | 1/day |
| `K_S` | Sedimentation decay term for pathogens | 1/day |

## Input-to-Formula Map

| Input group | Storage path | Selected by scenario field | Used by function | Formula or process | Unit | Provenance output |
|---|---|---|---|---|---|---|
| Basin boundary | `Inputs/basins/<basin>/` | `basin_shp_path`, `input_paths$basin` | `LoadNetworkInputs()` | Spatial crop and map boundary | geometry | `run_provenance_summary.csv` |
| Rivers | `Inputs/baselines/hydrosheds/` or GeoGLOWS files | `river_shp_path`, `network_source` | `ProcessRiverGeometry()` | River topology | geometry | network shapefiles |
| Flow direction | `Inputs/baselines/hydrosheds/` | `flow_dir_path` | `BuildNetworkTopology()` | Downstream network direction | grid | network diagnostics |
| Flow/discharge | `Inputs/baselines/environmental/` or GeoGLOWS GPKG | `input_paths$flow_raster`, `flow_source`, `discharge_gpkg_path` | `AssignHydrology()` | Assign `Q` | m3/s | `hydrology_nodes.csv`, `run_provenance_summary.csv` |
| Canal Q | `Package/inst/config/canal_q_sources/kis_canal_q_sources.csv` plus canal inputs | `canal_q_source_id` | `AssignCanalDischarge()`, `ApplyCanalDischargeOverrides()` | Override canal `Q` with `Q_model_m3s` | m3/s | `canal_q_assignment_summary.csv` |
| Lakes | `Inputs/basins/<basin>/` and built `HL.csv` | `lakes_shp_path`, `input_paths$hl`, `lake_transport_mode` | `ProcessLakeGeometries()`, `ApplyLakeThroughflow()` | Lake routing and optional CSTR | geometry, km3, m3/s | `lake_connections.csv`, `lake_connection_diagnostics.csv` |
| Population raster | `Inputs/baselines/environmental/` | `pop_raster_path` | `ExtractPopulationSources()` | Agglomeration source placement | people/grid cell | `step_05_agglomeration_trace.csv` when diagnostics are enabled |
| WWTP data | `Inputs/user/` or basin data | `wwtp_csv_path`, `hydrowaste_csv_path` | `MapWWTPLocations()` | WWTP source nodes and treatment fields | people equivalent, treatment flags | `pts.csv`, `hydrology_nodes.csv` |
| Chemical properties | `Inputs/user/chem_Oldenkamp2018_SI.xlsx` or packaged examples | `input_paths$chem_data` | `InitializeSubstance()`, `Set_local_parameters_custom_removal_fast3()` | Chemical fate, partitioning, SimpleTreat | chemical-specific | `run_provenance_summary.csv` |
| Chemical consumption | `LoadExampleConsumption()` in `Package/R/01_ExampleData.R` | `study_country`, `target_substance` | `PrepareCountryConsumption()` | Chemical source load | kg/year | active assumption; see note below |
| Pathogen biology | `Package/inst/pathogen_input/<pathogen>.R` | `target_substance`, `pathogen_name` | `LoadPathogenParameters()` | Decay parameters `K_T`, `K_R`, `K_S` | pathogen-specific | `pathogen_provenance_summary.csv` |
| Pathogen regional profile | `Package/inst/pathogen_profiles/pathogen_profiles.R` | `pathogen_profile_set`, `pathogen_profile_policy`, `study_country` | `ResolvePathogenProfile()`, `ApplyPathogenProfile()` | Prevalence, excretion, WWTP removal | profile-specific | `pathogen_provenance_summary.csv` |
| Pathogen direct fraction | `Package/inst/config/scenarios/volta_simulations.R` | `pathogen_direct_fraction_overrides` | `ApplyPathogenDirectFractionOverrides()`, `AssignPathogenEmissions()` | Agglomeration `E_in = local_pop * prevalence_rate * excretion_rate * f_pathogen_direct` | unitless fraction | `simulation_results.csv`, `run_provenance_summary.csv` |
| Built network nodes | `Outputs/<network>/pts.csv` | `input_paths$pts` | `NormalizeScenarioState()` | Node topology and source fields | table | `simulation_results.csv`, `hydrology_nodes.csv` |
| Transport edges | `Outputs/<network>/transport_edges.csv` or rebuilt from nodes | network state | `BuildTransportEdges()` | Branch-aware load routing | table | `transport_edges.csv` |

## Hydrology Inputs

Hydrology assigns the discharge column `Q`.

For HydroSHEDS scenarios, `AssignHydrology()` reads a flow raster from
`input_paths$flow_raster` or a high-resolution raster selected by `flow_source`.
The active selector is stored in the scenario config.

For GeoGLOWS scenarios, `AssignHydrology()` reads per-segment discharge from the
configured GeoGLOWS GPKG. The scenario also stores the year, months, and
aggregation rule.

For Volta canal scenarios, canal discharge can override raster discharge.
The canal source is controlled by `canal_q_source_id`. The active KIS canal
source registry is `Package/inst/config/canal_q_sources/kis_canal_q_sources.csv`.

Main implementation files:

- `Package/R/21_AssignHydrology.R`
- `Package/R/11_PrepareCanalLayers.R`
- `Package/R/24_ProvenanceExports.R`

Main review outputs:

- `hydrology_nodes.csv`
- `transport_edges.csv`
- `canal_q_assignment_summary.csv`
- `run_provenance_summary.csv`

## Chemical Model Inputs

Chemical scenarios use `substance_type = "chemical"`.

`InitializeSubstance()` reads the chemical workbook from
`input_paths$chem_data`. The selected chemical row is matched by `API`, for
example `Ibuprofen`.

`PrepareCountryConsumption()` builds the consumption table used for emissions.
At the moment, this table comes from `LoadExampleConsumption()` in
`Package/R/01_ExampleData.R`. This is an active model assumption. It should be
reported when chemical results are used in a paper.

`Set_local_parameters_custom_removal_fast3()` then prepares chemical emissions
and WWTP removal:

- If custom primary or secondary WWTP removal is missing, SimpleTreat is used.
- If custom removal values are present, they override SimpleTreat.
- Tertiary treatment fields can further change WWTP removal.

Chemical concentration is computed in `Compute_env_concentrations_v4.R`.
For river nodes, the documented mass balance is:

`C_w = E_total / Q * 1e6 / seconds_per_year`

where `E_total = E_w + E_up`.

Main implementation files:

- `Package/R/00_substance_abstraction.R`
- `Package/R/22_CalculateEmissions.R`
- `Package/R/Set_local_parameters_custom_removal_fast3.R`
- `Package/R/Compute_env_concentrations_v4.R`

## Pathogen Model Inputs

Pathogen scenarios use `substance_type = "pathogen"`.

Base pathogen biology is stored in `Package/inst/pathogen_input/`. Each file
defines `simulation_parameters`. These values include decay and settling
parameters.

Regional emission assumptions are stored in
`Package/inst/pathogen_profiles/pathogen_profiles.R`. These profiles define
prevalence, excretion, WWTP removal, units, region, country, and citation notes.

Scenario runs use strict profile resolution. This prevents a Ghana profile from
being silently reused in Romania, or the reverse.

Pathogen emissions are assigned in `AssignPathogenEmissions()`:

- WWTP nodes use local source population, prevalence, excretion, and treatment
  removal.
- Agglomeration nodes use local population, prevalence, excretion, and
  `f_pathogen_direct`.
- Diffuse sanitation and runoff factors are not applied yet.

For agglomeration nodes:

`E_in = local_pop * prevalence_rate * excretion_rate * f_pathogen_direct`

`f_pathogen_direct` is pathogen-only. It is not the same as `f_direct`.
`f_direct` is used by the chemical/sanitation emission code.

Default value:

- `f_pathogen_direct = 1` for agglomeration sources.
- non-agglomeration nodes do not use this factor.

Current Volta pathogen override:

- Akuse: `Source00080`, `Source00081`, `Source00116`, `Source00117`
- Asutsuare: `Source00087`, `Source00088`
- value: `f_pathogen_direct = 0.5`
- reference coordinates: stored in `VoltaPathogenDirectFractionOverrides()`
- match radius: `200 m`

This is a scenario assumption for SPRINGS/VU Amsterdam research use.
Akuse and Asutsuare have more infrastructure than smaller settlements. Some
households, schools, clinics, health centres, and public facilities may use
septic tanks or pit latrines. Therefore, not all fecal load is assumed to enter
canals or rivers directly.

This value is not a measured sanitation fraction. It is not derived from a
sanitation layer yet.

The wet and dry Volta networks can generate different source IDs. The model
therefore applies the override in two steps:

- first, match the original wet `source_id`;
- second, for unmatched IDs, match agglomeration sources within `200 m` of the
  stored reference coordinate.

The output table stores:

- `f_pathogen_direct`
- `f_pathogen_direct_place`
- `f_pathogen_direct_basis`

`f_pathogen_direct_basis` shows whether the value came from `source_id`,
`coordinate_radius`, `default`, or `not_applicable`.

Pathogen decay is assigned in `AssignPathogenDecayParameters()`:

- `K_T` is temperature-dependent inactivation.
- `K_R` is solar radiation inactivation.
- `K_S` is sedimentation removal.
- `k = (K_T + K_R + K_S) / 86400`.

Main implementation files:

- `Package/R/00_substance_abstraction.R`
- `Package/R/02_PathogenModel.R`
- `Package/R/Process_formulas.R`
- `Package/R/Compute_env_concentrations_v4.R`

Main review output:

- `pathogen_provenance_summary.csv`

## Transport and Lake Formulas

The simulation routes load from upstream to downstream nodes.

Network files come from the network build:

- `Outputs/<network>/pts.csv`
- `Outputs/<network>/HL.csv`
- `Outputs/<network>/transport_edges.csv`

`RunSimulationPipeline()` normalizes the node schema, assigns hydrology, builds
transport edges, initializes the substance, and calls the concentration engine.

River concentration uses local plus upstream load:

`E_total = E_w + E_up`

For pathogens:

`C_w = (E_total / seconds_per_year) / (Q * 1000)`

For chemicals:

`C_w = E_total / Q * 1e6 / seconds_per_year`

Downstream transport applies first-order decay:

`E_downstream = E_total * exp(-k * distance / velocity)`

Lake behavior is controlled by `lake_transport_mode`:

- `legacy_pass_through` keeps historical pass-through behavior.
- `cstr` uses a completely stirred tank reactor.

The CSTR lake formula is:

`C_lake = E_total / (Q + k * V)`

Main implementation files:

- `Package/R/32_RunSimulationPipeline.R`
- `Package/R/22_TransportEdges.R`
- `Package/R/Compute_env_concentrations_v4.R`

## Current Traceability Weakness

Chemical properties are traceable to a workbook.

Pathogen profiles are traceable to package data with source notes and URLs.

Pathogen direct fractions are scenario assumptions. For Volta pathogen runs,
Akuse/Asutsuare source locations are set to `0.5`; other agglomeration sources
use `1`. The stored source IDs are the original wet-network IDs. Coordinate
matching keeps the same assumption active when dry-network source IDs change.
This is stored in `Package/inst/config/scenarios/volta_simulations.R` as
`pathogen_direct_fraction_overrides`.

Chemical consumption is less traceable. The active consumption table is created
in code by `LoadExampleConsumption()` in `Package/R/01_ExampleData.R`. For
peer-reviewed use, report this as an active assumption. If chemical consumption
values are changed, prefer a versioned input file with source citation and data
period.

## Reviewer Checklist

Before using outputs in a publication, record:

- scenario name from `LoadScenarioConfig()`
- Git commit or release version
- all `input_paths` from the loaded scenario
- selected flow source, including `flow_source` or GeoGLOWS year/months
- active lake transport mode
- active canal Q source, if canals are enabled
- pathogen profile ID and profile set, if this is a pathogen run
- `f_pathogen_direct` overrides, if this is a Volta pathogen run
- `f_pathogen_direct_basis`, if this is a Volta pathogen run
- chemical workbook path and chemical consumption assumption, if this is a chemical run
- `run_provenance_summary.csv`
- `pathogen_provenance_summary.csv`, if this is a pathogen run
- `canal_q_assignment_summary.csv`, if canals are enabled
- `hydrology_nodes.csv`
- `transport_edges.csv`

## Quick Inspection Commands

List scenarios:

```r
library(ePiE)
ListScenarios()
```

Inspect one pathogen scenario:

```bash
Rscript scripts/inspect_scenarios.R --scenario BegaPathogenCrypto
```

Inspect one chemical scenario:

```bash
Rscript scripts/inspect_scenarios.R --scenario VoltaWetChemicalIbuprofen
```

Export a reviewer table:

```bash
Rscript scripts/inspect_scenarios.R --csv Outputs/scenario_setup_audit.csv
```
