# ePiE Testing Manual

## 0. Setup

Open RStudio, restart R (Cmd+Shift+F10), then run:

```r
library(ePiE)
setwd("/Users/gtazzi/aude/ePiE")
```

If the package was modified, rebuild first:

```r
setwd("/Users/gtazzi/aude/ePiE/Package")
system("R CMD build .")
system("R CMD INSTALL ePiE_1.26.0.tar.gz")
setwd("/Users/gtazzi/aude/ePiE")
library(ePiE)
```

---

## 1. Network Generation

Network generation builds the river topology: loads spatial data, clips rivers to the basin boundary, processes lakes, maps population sources and WWTPs, builds node topology (IDs, downstream links, distances), integrates sources, and saves outputs to disk.

### 1.1 Available Networks

| Scenario Name | Basin | Season | River Source | Output Dir |
|---|---|---|---|---|
| `BegaNetwork` | Bega (Romania) | n/a | HydroSHEDS | `Outputs/bega/` |
| `VoltaWetNetwork` | Volta (Ghana) | Wet | HydroSHEDS | `Outputs/volta_wet/` |
| `VoltaDryNetwork` | Volta (Ghana) | Dry | HydroSHEDS | `Outputs/volta_dry/` |
| `VoltaGeoGLOWSNetwork` | Volta (Ghana) | Wet | GeoGLOWS | `Outputs/volta_geoglows_wet/` |
| `VoltaGeoGLOWSDryNetwork` | Volta (Ghana) | Dry | GeoGLOWS | `Outputs/volta_geoglows_dry/` |

### 1.2 Run a Single Network

```r
cfg <- LoadScenarioConfig("BegaNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg, diagnostics = "full")
cat("Points:", nrow(state$points), "| Lakes:", nrow(state$HL_basin), "\n")
```

Expected output:

| Network | Points | Lakes |
|---|---|---|
| BegaNetwork | 482 | 9 |
| VoltaWetNetwork | 351 | 7 |
| VoltaDryNetwork | 178 | 7 |
| VoltaGeoGLOWSNetwork | 924 | 7 |
| VoltaGeoGLOWSDryNetwork | 924 | 7 |

### 1.3 Run All Networks

```r
networks <- c("BegaNetwork", "VoltaWetNetwork", "VoltaDryNetwork",
              "VoltaGeoGLOWSNetwork", "VoltaGeoGLOWSDryNetwork")
for (n in networks) {
  cfg <- LoadScenarioConfig(n, "Inputs", "Outputs")
  state <- BuildNetworkPipeline(cfg, diagnostics = "full")
  cat(n, ":", nrow(state$points), "pts,", nrow(state$HL_basin), "lakes\n")
}
```

### 1.4 Network Build Outputs

Each network produces these files in its output directory:

| File | Description |
|---|---|
| `pts.csv` | Network nodes with topology (ID, ID_nxt, x, y, distances, types) |
| `HL.csv` | Lake node data (volume, depth, basin assignment) |
| `network_rivers.shp` | River line geometries (Shapefile) |
| `FinalEnv.RData` | Full R environment checkpoint |
| `plots/interactive_network_map.html` | Leaflet interactive map |
| `plots/static_network_overview.png` | Static overview map |
| `plots/static_node_types.png` | Map colored by node type |

### 1.5 Build Pipeline Steps

| Step | Function | Description |
|---|---|---|
| 01 | `LoadNetworkInputs` | Loads river, basin, lake shapefiles |
| 02b | `PrepareCanalLayers` | Tags artificial canals, assigns manual Q |
| 03 | `ProcessRiverGeometry` | Clips rivers to basin, simplifies, detects mouth |
| 04 | `ProcessLakeGeometries` | Clips lakes, simplifies polygons |
| 05 | `ExtractPopulationSources` | Extracts population from raster, creates agglomeration points |
| 06 | `MapWWTPLocations` | Loads WWTPs from CSV, snaps to nearest river segment |
| 07 | `BuildNetworkTopology` | Creates nodes from river endpoints, assigns IDs and downstream links |
| 08 | `IntegratePointsAndLines` | Merges agglomeration/WWTP points into river network |
| 08b | `ConnectLakesToNetwork` | Detects lake-river crossings, assigns inlet/outlet |
| 09 | `SaveNetworkArtifacts` | Saves CSV/Shapefile/RData, extracts slope/temp/wind rasters |
| 10 | `VisualizeNetwork` | Generates interactive and static maps |

---

## 2. Simulation

Simulation takes a pre-built network and computes environmental concentrations for a given substance (chemical or pathogen). It normalizes topology, adds flow data, initializes substance parameters, runs the concentration engine, and generates concentration maps.

### 2.1 Available Simulations

#### Bega (1 scenario)

| Scenario Name | Substance | Output Dir |
|---|---|---|
| `BegaChemicalIbuprofen` | Ibuprofen | `Outputs/bega_ibuprofen/` |

#### Volta HydroSHEDS Wet (5 scenarios)

| Scenario Name | Substance | Output Dir |
|---|---|---|
| `VoltaWetChemicalIbuprofen` | Ibuprofen | `Outputs/volta_wet_ibuprofen/` |
| `VoltaWetPathogenCrypto` | Cryptosporidium | `Outputs/volta_crypto_wet/` |
| `VoltaWetPathogenCampylobacter` | Campylobacter | `Outputs/volta_campy_wet/` |
| `VoltaWetPathogenRotavirus` | Rotavirus | `Outputs/volta_rota_wet/` |
| `VoltaWetPathogenGiardia` | Giardia | `Outputs/volta_giardia_wet/` |

#### Volta HydroSHEDS Dry (5 scenarios)

| Scenario Name | Substance | Output Dir |
|---|---|---|
| `VoltaDryChemicalIbuprofen` | Ibuprofen | `Outputs/volta_dry_ibuprofen/` |
| `VoltaDryPathogenCrypto` | Cryptosporidium | `Outputs/volta_crypto_dry/` |
| `VoltaDryPathogenCampylobacter` | Campylobacter | `Outputs/volta_campy_dry/` |
| `VoltaDryPathogenRotavirus` | Rotavirus | `Outputs/volta_rota_dry/` |
| `VoltaDryPathogenGiardia` | Giardia | `Outputs/volta_giardia_dry/` |

#### Volta GeoGLOWS Wet (5 scenarios)

| Scenario Name | Substance | Output Dir |
|---|---|---|
| `VoltaGeoGLOWSWetChemicalIbuprofen` | Ibuprofen | `Outputs/volta_geoglows_wet_ibuprofen/` |
| `VoltaGeoGLOWSWetPathogenCrypto` | Cryptosporidium | `Outputs/volta_geoglows_crypto_wet/` |
| `VoltaGeoGLOWSWetPathogenCampylobacter` | Campylobacter | `Outputs/volta_geoglows_campy_wet/` |
| `VoltaGeoGLOWSWetPathogenRotavirus` | Rotavirus | `Outputs/volta_geoglows_rota_wet/` |
| `VoltaGeoGLOWSWetPathogenGiardia` | Giardia | `Outputs/volta_geoglows_giardia_wet/` |

#### Volta GeoGLOWS Dry (5 scenarios)

| Scenario Name | Substance | Output Dir |
|---|---|---|
| `VoltaGeoGLOWSDryChemicalIbuprofen` | Ibuprofen | `Outputs/volta_geoglows_dry_ibuprofen/` |
| `VoltaGeoGLOWSDryPathogenCrypto` | Cryptosporidium | `Outputs/volta_geoglows_crypto_dry/` |
| `VoltaGeoGLOWSDryPathogenCampylobacter` | Campylobacter | `Outputs/volta_geoglows_campy_dry/` |
| `VoltaGeoGLOWSDryPathogenRotavirus` | Rotavirus | `Outputs/volta_geoglows_rota_dry/` |
| `VoltaGeoGLOWSDryPathogenGiardia` | Giardia | `Outputs/volta_geoglows_giardia_dry/` |

### 2.2 Helper Function

Run this once per R session:

```r
run_sim <- function(scenario_name) {
  cfg <- LoadScenarioConfig(scenario_name, "Inputs", "Outputs")
  state <- list(
    points           = read.csv(cfg$input_paths$pts, stringsAsFactors = FALSE),
    HLL_basin        = read.csv(cfg$input_paths$hl, stringsAsFactors = FALSE),
    study_country    = cfg$study_country,
    country_population = cfg$country_population,
    input_paths      = cfg$input_paths,
    basin_id         = cfg$basin_id,
    simulation_year  = cfg$simulation_year,
    simulation_months = cfg$simulation_months,
    discharge_gpkg_path = cfg$discharge_gpkg_path,
    discharge_aggregation = cfg$discharge_aggregation,
    network_source   = cfg$network_source,
    run_output_dir   = cfg$run_output_dir
  )
  results <- RunSimulationPipeline(state, substance = cfg$target_substance)
  cw <- results$results$pts$C_w
  cat(scenario_name, "| C_w>0:", sum(cw > 0, na.rm = TRUE),
      " NA:", sum(is.na(cw)), "/", length(cw), "\n")
  invisible(results)
}
```

### 2.3 Run a Single Simulation

```r
run_sim("BegaChemicalIbuprofen")
```

### 2.4 Run All Simulations

```r
all_sims <- c(
  "BegaChemicalIbuprofen",
  "VoltaWetChemicalIbuprofen", "VoltaWetPathogenCrypto",
  "VoltaWetPathogenCampylobacter", "VoltaWetPathogenRotavirus", "VoltaWetPathogenGiardia",
  "VoltaDryChemicalIbuprofen", "VoltaDryPathogenCrypto",
  "VoltaDryPathogenCampylobacter", "VoltaDryPathogenRotavirus", "VoltaDryPathogenGiardia",
  "VoltaGeoGLOWSWetChemicalIbuprofen", "VoltaGeoGLOWSWetPathogenCrypto",
  "VoltaGeoGLOWSWetPathogenCampylobacter", "VoltaGeoGLOWSWetPathogenRotavirus",
  "VoltaGeoGLOWSWetPathogenGiardia",
  "VoltaGeoGLOWSDryChemicalIbuprofen", "VoltaGeoGLOWSDryPathogenCrypto",
  "VoltaGeoGLOWSDryPathogenCampylobacter", "VoltaGeoGLOWSDryPathogenRotavirus",
  "VoltaGeoGLOWSDryPathogenGiardia"
)
for (s in all_sims) run_sim(s)
```

### 2.5 Expected Results

| Scenario | C_w > 0 | NA | Total | Notes |
|---|---|---|---|---|
| BegaChemicalIbuprofen | 163 | 6 | 482 | Has WWTPs with emissions |
| VoltaWetChemicalIbuprofen | 0 | 7 | 351 | No WWTPs, f_direct=0 |
| VoltaWetPathogen* | 276 | 41 | 351 | All 4 pathogens same |
| VoltaDryChemicalIbuprofen | 0 | 178 | 178 | No flow data for Africa |
| VoltaDryPathogen* | 0 | 178 | 178 | All NA: no flow |
| VoltaGeoGLOWSWetChemicalIbuprofen | 0 | 5 | 924 | No WWTPs, f_direct=0 |
| VoltaGeoGLOWSWetPathogen* | 812 | 35 | 924 | Good flow data |
| VoltaGeoGLOWSDryChemicalIbuprofen | 0 | 5 | 924 | No WWTPs, f_direct=0 |
| VoltaGeoGLOWSDryPathogen* | 812 | 35 | 924 | Good flow data |

### 2.6 Simulation Outputs

Each simulation produces:

| File | Description |
|---|---|
| `plots/concentration_map.html` | Interactive Leaflet map with concentrations |
| `plots/static_concentration_map.png` | Static concentration map (PNG) |
| `plots/concentration_map_files/` | Supporting files for interactive map |

Access results programmatically:

```r
results <- run_sim("BegaChemicalIbuprofen")
results$results$pts$C_w    # concentration at each node
results$results$pts$Q      # discharge at each node
results$results$pts$Pt_type # node type (node, WWTP, agglomeration, etc.)
```

### 2.7 Simulation Pipeline Steps

| Step | Function | Description |
|---|---|---|
| - | `NormalizeScenarioState` | Reprojects to WGS84, propagates distances, maps Pt_types, fills defaults |
| - | `AddFlowToBasinData` | Extracts Q from raster or GeoGLOWS GPKG, computes H, V via Manning-Strickler |
| - | `Set_upstream_points_v2` | Counts upstream nodes (Freq) |
| - | `InitializeSubstance` | Loads chemical properties or pathogen parameters, computes emissions |
| - | `ComputeEnvConcentrations` | Runs the concentration engine (C++ or R) |
| - | `VisualizeConcentrations` | Generates interactive + static concentration maps |

---

## 3. Configuration Files

Configuration is split into two layers: **basin configs** (shared data paths) and **scenario configs** (per-scenario parameters).

### 3.1 File Locations

```
Package/inst/config/
  basins/
    bega.R                    # BegaBasinConfig()
    volta.R                   # VoltaBasinConfig()
    volta_geoglows.R          # VoltaGeoGLOWSConfig()
  scenarios/
    bega_network.R            # BegaNetwork()
    bega_simulations.R        # BegaChemicalIbuprofen(), BegaPathogen*()
    volta_wet_network.R       # VoltaWetNetwork()
    volta_dry_network.R       # VoltaDryNetwork()
    volta_simulations.R       # VoltaWetChemicalIbuprofen(), VoltaDryPathogen*(), etc.
    volta_geoglows_network.R  # VoltaGeoGLOWSNetwork()
    volta_geoglows_dry_network.R # VoltaGeoGLOWSDryNetwork()
    volta_geoglows_simulations.R # VoltaGeoGLOWSWetChemicalIbuprofen(), etc.
```

### 3.2 Basin Config Fields

Each basin config function (e.g. `BegaBasinConfig(data_root)`) returns a list with:

| Field | Type | Description |
|---|---|---|
| `basin_id` | character | Unique basin identifier (e.g. `"bega"`, `"volta"`) |
| `study_country` | character | ISO country code (e.g. `"RO"` for Romania, `"GH"` for Ghana) |
| `default_wind` | numeric | Default wind speed (m/s) when raster is missing |
| `default_temp` | numeric | Default air temperature (C) when raster is missing |
| `utm_crs_string` | character | PROJ string for the local UTM zone (used for distance calculations) |
| `basin_shp_path` | character | Path to basin boundary polygon (Shapefile) |
| `lakes_shp_path` | character | Path to lake polygons (Shapefile) |
| `wet_river_shp_path` | character | Path to wet-season river network (Shapefile or GPKG) |
| `dry_river_shp_path` | character/null | Path to dry-season river network. NULL if only one season |
| `flow_dir_path` | character/null | Path to HydroSHEDS flow direction grid. NULL for GeoGLOWS |
| `canal_shp_path` | character/null | Path to artificial canal Shapefile |
| `canal_discharge_table` | character/null | Path to CSV with canal discharge values |
| `slope_raster_path` | character/null | Path to slope raster (GeoTIFF) |
| `wind_raster_path` | character/null | Path to wind speed raster |
| `temp_raster_path` | character/null | Path to temperature raster |
| `pop_raster_path` | character/null | Path to population raster (GHS-POP). NULL = no agglomeration extraction |
| `wwtp_csv_path` | character/null | Path to WWTP point data CSV. NULL = no WWTP mapping |
| `chem_data_path` | character/null | Path to chemical properties Excel file |
| `flow_raster_path` | character/null | Path to flow discharge raster or NetCDF |
| `flow_raster_dry_path` | character/null | Path to dry-season flow raster |
| `country_population` | numeric | Total country population (for consumption estimates) |
| `simplification` | list | Simplification tolerances (see below) |

**GeoGLOWS-only fields:**

| Field | Type | Description |
|---|---|---|
| `network_source` | character | Must be `"geoglows"` |
| `discharge_gpkg_path` | character | Path to GeoGLOWS discharge GPKG (monthly per-segment Q) |
| `river_id_field` | character | Column name for segment ID (e.g. `"LINKNO"`) |
| `river_downstream_id_field` | character | Column name for downstream segment ID (e.g. `"DSLINKNO"`) |
| `river_upstream_area_field` | character | Column name for upstream area (e.g. `"USContArea"`) |

**Simplification options:**

| Field | Type | Description |
|---|---|---|
| `lake_tolerance` | numeric/null | Douglas-Peucker tolerance for lake polygons (meters). NULL = no simplification |
| `river_tolerance` | numeric | Douglas-Peucker tolerance for river lines (meters). 0 = no simplification |
| `canal_simplify` | logical | Whether to simplify canal geometries |

### 3.3 Network Scenario Config Fields

Each network scenario (e.g. `VoltaWetNetwork(data_root, output_root)`) returns:

| Field | Type | Description |
|---|---|---|
| `basin_id` | character | From basin config |
| `study_country` | character | From basin config |
| `is_dry_season` | logical | TRUE = use dry-season rivers/flow |
| `river_shp_path` | character | River Shapefile path (primary) |
| `reference_river_shp_path` | character/null | Reference river network for topology validation |
| `preserve_downstream_from_reference` | logical | If TRUE, preserve downstream links from reference network |
| `basin_shp_path` | character | Basin boundary path |
| `lakes_shp_path` | character | Lake polygon path |
| `flow_dir_path` | character/null | Flow direction grid path |
| `enable_lakes` | logical | Whether to process lakes (TRUE recommended) |
| `enable_canals` | logical | Whether to process canals |
| `canal_shp_path` | character/null | Canal Shapefile path |
| `canal_discharge_table` | character/null | Canal discharge CSV path |
| `pop_raster_path` | character/null | Population raster path |
| `slope_raster_path` | character/null | Slope raster path |
| `wind_raster_path` | character/null | Wind raster path |
| `temp_raster_path` | character/null | Temperature raster path |
| `run_output_dir` | character | Where to save network outputs |
| `simplification` | list | Simplification tolerances |

### 3.4 Simulation Scenario Config Fields

Each simulation scenario (e.g. `VoltaWetPathogenCrypto(data_root, output_root)`) returns:

| Field | Type | Description |
|---|---|---|
| `basin_id` | character | From basin config |
| `study_country` | character | From basin config |
| `substance_type` | character | `"chemical"` or `"pathogen"` |
| `target_substance` | character | Substance name (e.g. `"Ibuprofen"`, `"cryptosporidium"`) |
| `pathogen_name` | character/null | Pathogen name (pathogen scenarios only) |
| `is_dry_season` | logical | Season flag |
| `default_wind` | numeric | Default wind speed |
| `default_temp` | numeric | Default temperature |
| `use_cpp` | logical | Use C++ engine (TRUE recommended, FALSE = R fallback) |
| `run_output_dir` | character | Where to save simulation outputs and maps |
| `input_paths` | list | Paths to pre-built network files (see below) |
| `dataDir` | character | Root data directory |
| `country_population` | numeric | Total country population |

**GeoGLOWS-only simulation fields:**

| Field | Type | Description |
|---|---|---|
| `network_source` | character | `"geoglows"` |
| `simulation_year` | integer | Year to select from GPKG discharge columns (e.g. `2020`) |
| `simulation_months` | integer vector | Months to average (e.g. `9:10` for wet, `3:4` for dry) |
| `discharge_aggregation` | character | How to aggregate months: `"mean"`, `"min"`, `"max"` |
| `discharge_gpkg_path` | character | Path to GeoGLOWS discharge GPKG |

**`input_paths` sub-fields:**

| Field | Type | Description |
|---|---|---|
| `pts` | character | Path to `pts.csv` from network build |
| `hl` | character | Path to `HL.csv` from network build |
| `rivers` | character | Path to `network_rivers.shp` from network build |
| `basin` | character | Path to basin boundary Shapefile |
| `chem_data` | character/null | Path to chemical properties Excel (chemical scenarios only) |
| `flow_raster` | character/null | Path to flow raster/NetCDF (HydroSHEDS scenarios) |

### 3.5 Adding a New Basin

To add a new basin (e.g. Danube):

1. Create `Package/inst/config/basins/danube.R` with a `DanubeBasinConfig(data_root)` function returning the fields from section 3.2.

2. Create network scenario(s) in `Package/inst/config/scenarios/danube_network.R`:

```r
DanubeNetwork <- function(data_root, output_root) {
  bc <- DanubeBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    run_output_dir = file.path(output_root, "danube"),
    simplification = list(lake_tolerance = NULL, river_tolerance = 100,
                          canal_simplify = FALSE)
  )
}
```

3. Create simulation scenarios in `Package/inst/config/scenarios/danube_simulations.R`:

```r
DanubeChemicalIbuprofen <- function(data_root, output_root) {
  bc <- DanubeBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    run_output_dir = file.path(output_root, "danube_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "danube", "pts.csv"),
      hl = file.path(output_root, "danube", "HL.csv"),
      rivers = file.path(output_root, "danube", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    country_population = bc$country_population
  )
}
```

4. Rebuild the package: `R CMD build . && R CMD INSTALL ePiE_1.26.0.tar.gz` from `Package/`.

### 3.6 Adding a New Pathogen

Pathogen parameters are stored in `Package/inst/pathogen_input/<name>.R`. Each file defines a `simulation_parameters` list. Existing pathogens:

| File | Pathogen |
|---|---|
| `cryptosporidium.R` | Cryptosporidium |
| `campylobacter.R` | Campylobacter |
| `rotavirus.R` | Rotavirus |
| `giardia.R` | Giardia |

To add a new pathogen, create a new `.R` file following the same structure, then add scenario configs that set `substance_type = "pathogen"` and `target_substance = "<name>"`.

---

## 4. Wet vs Dry Season

### HydroSHEDS

Wet and dry use **different river shapefiles** (different network topology) AND different flow rasters:

| | Wet | Dry |
|---|---|---|
| River network | Full river network | Seasonal subset (fewer flowing rivers) |
| Flow raster | Long-term average discharge | Minimum discharge |
| Network size | More nodes | Fewer nodes |

Note: The FLO1K flow rasters in the current setup cover Western Europe only. For African basins (Volta), HydroSHEDS scenarios produce Q=0 for all nodes, which results in all-NA concentrations for pathogens.

### GeoGLOWS

The river network is **identical** for wet and dry. Seasonality is captured through monthly discharge values:

| | Wet | Dry |
|---|---|---|
| River network | Same GPKG | Same GPKG |
| Months selected | `9:10` (Sep-Oct, rainy) | `3:4` (Mar-Apr, dry) |
| Aggregation | Mean of selected months | Mean of selected months |

---

## 5. Known Data Limitations

| Issue | Affected Scenarios | Impact |
|---|---|---|
| FLO1K rasters don't cover Africa | All HydroSHEDS Volta | Q=0, C_w=NA for all nodes |
| No WWTPs in Volta networks | All Volta chemical | f_direct=0, C_w=0 for chemicals |
| No population raster for Bega | Bega network | No agglomeration points generated |
| Chemical emissions require WWTPs | All chemical scenarios | Agglomerations with f_direct=0 produce zero emissions |
| tmap v4 syntax incompatibility | All visualization | Static PNG maps fall back to base R plots |

These are data gaps, not code bugs. See `Notes/wet_dry_flow_data_difference.md` for details.

---

## 6. Quick Reference

```r
# List all available scenarios
ListScenarios()

# Load a config without running
cfg <- LoadScenarioConfig("BegaChemicalIbuprofen", "Inputs", "Outputs")
str(cfg)

# Inspect network nodes
pts <- read.csv("Outputs/bega/pts.csv")
table(pts$pt_type)

# Inspect simulation results
results <- run_sim("BegaChemicalIbuprofen")
hist(results$results$pts$C_w[results$results$pts$C_w > 0],
     main = "Ibuprofen concentrations (non-zero)",
     xlab = "C_w (ug/L)")
```
