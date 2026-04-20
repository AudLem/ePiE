# Configuration Reference

This document provides a complete reference for configuring ePiE basins and scenarios. Configuration is split into two layers:

1. **Basin Configs** - Define physical data locations for each river basin
2. **Scenario Configs** - Define simulation parameters for specific runs

## Configuration File Locations

```
Package/inst/config/
├── basins/
│   ├── bega.R                   # BegaBasinConfig()
│   ├── volta.R                  # VoltaBasinConfig()
│   └── volta_geoglows.R         # VoltaGeoGLOWSConfig()
└── scenarios/
    ├── bega_network.R           # BegaNetwork()
    ├── bega_simulations.R       # BegaChemicalIbuprofen(), BegaPathogen*()
    ├── volta_wet_network.R      # VoltaWetNetwork()
    ├── volta_dry_network.R      # VoltaDryNetwork()
    ├── volta_simulations.R      # VoltaWetChemicalIbuprofen(), VoltaDryPathogen*()
    ├── volta_geoglows_network.R # VoltaGeoGLOWSNetwork()
    └── volta_geoglows_simulations.R # VoltaGeoGLOWSWetChemicalIbuprofen(), etc.
```

## Basin Configuration

Each basin config function (e.g., `BegaBasinConfig(data_root)`) returns a list with physical data paths for that basin.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `basin_id` | character | Unique basin identifier (e.g., `"bega"`, `"volta"`) |
| `study_country` | character | ISO country code (e.g., `"RO"` for Romania, `"GH"` for Ghana) |
| `country_population` | numeric | Total country population (for consumption estimates) |
| `default_wind` | numeric | Default wind speed (m/s) when raster is missing |
| `default_temp` | numeric | Default air temperature (C) when raster is missing |
| `utm_crs_string` | character | PROJ string for local UTM zone (used for distance calculations) |

### Spatial Data Paths

| Field | Type | Description |
|-------|------|-------------|
| `basin_shp_path` | character | Path to basin boundary polygon (Shapefile) |
| `lakes_shp_path` | character | Path to lake polygons (Shapefile) |
| `wet_river_shp_path` | character | Path to wet-season river network (Shapefile or GPKG) |
| `dry_river_shp_path` | character/null | Path to dry-season river network. NULL if only one season |
| `flow_dir_path` | character/null | Path to HydroSHEDS flow direction grid. NULL for GeoGLOWS |
| `canal_shp_path` | character/null | Path to artificial canal Shapefile |
| `canal_discharge_table` | character/null | Path to CSV with canal discharge values |

### Environmental Raster Paths

| Field | Type | Description |
|-------|------|-------------|
| `slope_raster_path` | character/null | Path to slope raster (GeoTIFF) |
| `wind_raster_path` | character/null | Path to wind speed raster |
| `temp_raster_path` | character/null | Path to temperature raster |
| `pop_raster_path` | character/null | Path to population raster (GHS-POP). NULL = no agglomeration extraction |
| `flow_raster_path` | character/null | Path to flow discharge raster or NetCDF |
| `flow_raster_dry_path` | character/null | Path to dry-season flow raster |

### Data Paths

| Field | Type | Description |
|-------|------|-------------|
| `wwtp_csv_path` | character/null | Path to WWTP point data CSV. NULL = no WWTP mapping |
| `chem_data_path` | character/null | Path to chemical properties Excel file |

### Simplification Options

| Field | Type | Description |
|-------|------|-------------|
| `simplification` | list | List with simplification tolerances (see below) |

**Simplification sub-fields:**

| Field | Type | Description |
|-------|------|-------------|
| `lake_tolerance` | numeric/null | Douglas-Peucker tolerance for lake polygons (meters). NULL = no simplification |
| `river_tolerance` | numeric | Douglas-Peucker tolerance for river lines (meters). 0 = no simplification |
| `canal_simplify` | logical | Whether to simplify canal geometries |

### GeoGLOWS-Specific Fields

For GeoGLOWS basins, these additional fields are required:

| Field | Type | Description |
|-------|------|-------------|
| `network_source` | character | Must be `"geoglows"` |
| `discharge_gpkg_path` | character | Path to GeoGLOWS discharge GPKG (monthly per-segment Q) |
| `river_id_field` | character | Column name for segment ID (e.g., `"LINKNO"`) |
| `river_downstream_id_field` | character | Column name for downstream segment ID (e.g., `"DSLINKNO"`) |
| `river_upstream_area_field` | character | Column name for upstream area (e.g., `"USContArea"`) |

### Example: Volta Basin Config

```r
VoltaBasinConfig <- function(data_root) {
  b <- file.path(data_root, "basins", "volta")
  h <- file.path(data_root, "baselines", "hydrosheds")
  e <- file.path(data_root, "baselines", "environmental")

  list(
    basin_id = "volta",
    study_country = "GH",
    default_wind = 4.5,
    default_temp = 27.5,
    utm_crs_string = "+proj=utm +zone=31 +datum=WGS84 +units=m +no_defs",

    basin_shp_path = file.path(b, "small_sub_basin_volta_dissolved.shp"),
    lakes_shp_path = file.path(b, "cropped_lakes_Akuse_no_kpong.shp"),
    flow_dir_path = file.path(h, "af_dir_30s_grid", "af_dir_30s", "af_dir_30s", "w001001.adf"),
    wet_river_shp_path = file.path(h, "af_riv_30s", "af_riv_30s.shp"),
    dry_river_shp_path = file.path(b, "af_riv_dry_season.shp"),
    canal_shp_path = file.path(b, "KIS_canals.shp"),
    canal_discharge_table = file.path(b, "KIS_canal_discharge.csv"),
    slope_raster_path = file.path(b, "slope_Volta_sub_basin.tif"),
    wind_raster_path = file.path(e, "wind_LTM_yearly_averaged_raster_1981_2010.tif"),
    temp_raster_path = file.path(e, "temp.tif"),
    pop_raster_path = file.path(e, "GHS_POP_E2025_GLOBE_R2023A_54009_100_V1_0_R9_C19.tif"),
    chem_data_path = file.path(data_root, "user", "chem_Oldenkamp2018_SI.xlsx"),
    flow_raster_path = file.path(e, "FLO1K.30min.ts.1960.2015.qav.nc"),
    flow_raster_dry_path = file.path(e, "FLO1k.lt.2000.2015.qmi.tif"),
    country_population = 35100000,
    simplification = list(
      lake_tolerance = NULL,
      river_tolerance = 100,
      canal_simplify = FALSE
    )
  )
}
```

## Network Scenario Configuration

Each network scenario (e.g., `VoltaWetNetwork(data_root, output_root)`) returns configuration for building a network.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `basin_id` | character | From basin config |
| `study_country` | character | From basin config |
| `is_dry_season` | logical | TRUE = use dry-season rivers/flow |
| `river_shp_path` | character | River Shapefile path (primary) |
| `basin_shp_path` | character | Basin boundary path |
| `lakes_shp_path` | character | Lake polygon path |
| `flow_dir_path` | character/null | Flow direction grid path |
| `run_output_dir` | character | Where to save network outputs |
| `simplification` | list | Simplification tolerances |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `reference_river_shp_path` | character/null | Reference river network for topology validation |
| `preserve_downstream_from_reference` | logical | If TRUE, preserve downstream links from reference network |
| `enable_lakes` | logical | Whether to process lakes (TRUE recommended) |
| `enable_canals` | logical | Whether to process canals |
| `canal_shp_path` | character/null | Canal Shapefile path |
| `canal_discharge_table` | character/null | Canal discharge CSV path |
| `pop_raster_path` | character/null | Population raster path |
| `slope_raster_path` | character/null | Slope raster path |
| `wind_raster_path` | character/null | Wind speed raster path |
| `temp_raster_path` | character/null | Temperature raster path |

### Example: Volta Wet Network Config

```r
VoltaWetNetwork <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    is_dry_season = FALSE,
    river_shp_path = bc$wet_river_shp_path,
    reference_river_shp_path = NULL,
    preserve_downstream_from_reference = FALSE,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = TRUE,
    canal_shp_path = bc$canal_shp_path,
    canal_discharge_table = bc$canal_discharge_table,
    pop_raster_path = bc$pop_raster_path,
    slope_raster_path = bc$slope_raster_path,
    wind_raster_path = bc$wind_raster_path,
    temp_raster_path = bc$temp_raster_path,
    run_output_dir = file.path(output_root, "volta_wet"),
    simplification = bc$simplification
  )
}
```

## Simulation Scenario Configuration

Each simulation scenario (e.g., `VoltaWetPathogenCrypto(data_root, output_root)`) returns configuration for running a simulation.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `basin_id` | character | From basin config |
| `study_country` | character | From basin config |
| `substance_type` | character | `"chemical"` or `"pathogen"` |
| `target_substance` | character | Substance name (e.g., `"Ibuprofen"`, `"cryptosporidium"`) |
| `is_dry_season` | logical | Season flag |
| `default_wind` | numeric | Default wind speed |
| `default_temp` | numeric | Default temperature |
| `use_cpp` | logical | Use C++ engine (TRUE recommended, FALSE = R fallback) |
| `run_output_dir` | character | Where to save simulation outputs and maps |
| `input_paths` | list | Paths to pre-built network files |
| `dataDir` | character | Root data directory |
| `country_population` | numeric | Total country population |

### Pathogen-Specific Fields

| Field | Type | Description |
|-------|------|-------------|
| `pathogen_name` | character/null | Pathogen name (pathogen scenarios only) |
| `pathogen_units` | character/null | Concentration units (e.g., `"CFU/100mL"`, `"oocysts/L"`) |

### GeoGLOWS-Specific Simulation Fields

| Field | Type | Description |
|-------|------|-------------|
| `network_source` | character | `"geoglows"` |
| `simulation_year` | integer | Year to select from GPKG discharge columns (e.g., `2020`) |
| `simulation_months` | integer vector | Months to average (e.g., `9:10` for wet, `3:4` for dry) |
| `discharge_aggregation` | character | How to aggregate months: `"mean"`, `"min"`, `"max"` |
| `discharge_gpkg_path` | character | Path to GeoGLOWS discharge GPKG |

### input_paths Sub-Fields

| Field | Type | Description |
|-------|------|-------------|
| `pts` | character | Path to `pts.csv` from network build |
| `hl` | character | Path to `HL.csv` from network build |
| `rivers` | character | Path to `network_rivers.shp` from network build |
| `basin` | character | Path to basin boundary Shapefile |
| `chem_data` | character/null | Path to chemical properties Excel (chemical scenarios only) |
| `flow_raster` | character/null | Path to flow raster/NetCDF (HydroSHEDS scenarios) |

### Example: Volta Wet Cryptosporidium Config

```r
VoltaWetPathogenCrypto <- function(data_root, output_root) {
  bc <- VoltaBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "pathogen",
    target_substance = "cryptosporidium",
    pathogen_name = "cryptosporidium",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_crypto_wet"),
    input_paths = list(
      pts = file.path(output_root, "volta_wet", "pts.csv"),
      hl = file.path(output_root, "volta_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}
```

### Example: Volta GeoGLOWS Wet Ibuprofen Config

```r
VoltaGeoGLOWSWetChemicalIbuprofen <- function(data_root, output_root) {
  bc <- VoltaGeoGLOWSConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    substance_type = "chemical",
    target_substance = "Ibuprofen",
    is_dry_season = FALSE,
    default_wind = bc$default_wind,
    default_temp = bc$default_temp,
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "volta_geoglows_wet_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "volta_geoglows_wet", "pts.csv"),
      hl = file.path(output_root, "volta_geoglows_wet", "HL.csv"),
      rivers = file.path(output_root, "volta_geoglows_wet", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path
    ),
    network_source = "geoglows",
    simulation_year = 2020,
    simulation_months = 9:10,
    discharge_aggregation = "mean",
    discharge_gpkg_path = bc$discharge_gpkg_path,
    dataDir = data_root,
    country_population = bc$country_population
  )
}
```

## Adding a New Basin

To add a new basin (e.g., Danube):

1. **Create basin config** (`Package/inst/config/basins/danube.R`):
```r
DanubeBasinConfig <- function(data_root) {
  d <- file.path(data_root, "basins", "danube")
  e <- file.path(data_root, "baselines", "environmental")

  list(
    basin_id = "danube",
    study_country = "RO",
    default_wind = 3.0,
    default_temp = 10.0,
    utm_crs_string = "+proj=utm +zone=34 +datum=WGS84 +units=m +no_defs",
    basin_shp_path = file.path(d, "danube_basin.shp"),
    lakes_shp_path = file.path(d, "lakes.shp"),
    wet_river_shp_path = file.path(d, "rivers.shp"),
    flow_dir_path = file.path(data_root, "baselines", "hydrosheds", "eu_dir_30s_grid", "..."),
    # ... add all required fields
    country_population = 19200000,
    simplification = list(
      lake_tolerance = NULL,
      river_tolerance = 100,
      canal_simplify = FALSE
    )
  )
}
```

2. **Create network scenario** (`Package/inst/config/scenarios/danube_network.R`):
```r
DanubeNetwork <- function(data_root, output_root) {
  bc <- DanubeBasinConfig(data_root)
  list(
    basin_id = bc$basin_id,
    study_country = bc$study_country,
    is_dry_season = FALSE,
    river_shp_path = bc$wet_river_shp_path,
    basin_shp_path = bc$basin_shp_path,
    lakes_shp_path = bc$lakes_shp_path,
    flow_dir_path = bc$flow_dir_path,
    enable_lakes = TRUE,
    enable_canals = FALSE,
    run_output_dir = file.path(output_root, "danube"),
    simplification = bc$simplification
  )
}
```

3. **Create simulation scenarios** (`Package/inst/config/scenarios/danube_simulations.R`):
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
    use_cpp = FALSE,
    run_output_dir = file.path(output_root, "danube_ibuprofen"),
    input_paths = list(
      pts = file.path(output_root, "danube", "pts.csv"),
      hl = file.path(output_root, "danube", "HL.csv"),
      rivers = file.path(output_root, "danube", "network_rivers.shp"),
      basin = bc$basin_shp_path,
      chem_data = bc$chem_data_path,
      flow_raster = bc$flow_raster_path
    ),
    dataDir = data_root,
    country_population = bc$country_population
  )
}
```

4. **Rebuild the package**: `R CMD INSTALL Package`

5. **Update `ListScenarios()`** in `Package/R/30_LoadScenarioConfig.R` to include new scenarios

## Adding a New Pathogen

Pathogen parameters are stored in `Package/inst/pathogen_input/<name>.R`:

1. Create parameter file following existing templates (e.g., `cryptosporidium.R`):
```r
simulation_parameters <- list(
  # Emissions
  prevalence_rate = 0.05,        # 5% of population infected
  excretion_rate = 1e8,           # oocysts/infected person/year

  # Decay parameters
  decay_rate_base = 0.0051,      # day^-1 at 4°C
  temp_corr_factor = 0.158,      # Arrhenius correction
  solar_rad_factor = 4.798e-4,   # m^2 kJ^-1
  doc_attenuation = 9.831,       # L mg^-1 m^-1
  settling_velocity = 0.1,       # m/day

  # WWTP removal
  wwtp_primary_removal = 0.23,   # 23% removal
  wwtp_secondary_removal = 0.96  # 96% removal
)
```

2. Add scenario configs that set `substance_type = "pathogen"` and `target_substance = "<name>"`

## Configuration Validation

Validate your configuration before running:

```r
library(ePiE)

# Load and validate basin config
bc <- VoltaBasinConfig("Inputs")

# Check all paths exist
for (field in names(bc)) {
  if (grepl("_path$", field) && !is.null(bc[[field]])) {
    path <- bc[[field]]
    if (!file.exists(path)) {
      cat("Missing:", field, "=", path, "\n")
    }
  }
}

# Load and validate simulation config
cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs")

# Check network files exist
for (field in names(cfg$input_paths)) {
  path <- cfg$input_paths[[field]]
  if (!file.exists(path)) {
    cat("Missing:", field, "=", path, "\n")
  }
}
```

## Common Configuration Issues

### Issue: "File not found" errors
- **Cause**: Incorrect path in config or file not downloaded
- **Fix**: Verify paths in config, run `./scripts/setup-data.sh`

### Issue: "CRS mismatch" warnings
- **Cause**: Spatial data in different coordinate systems
- **Fix**: The pipeline reprojects automatically, but verify inputs are valid

### Issue: "Empty network after clipping"
- **Cause**: Basin boundary too small or in wrong location
- **Fix**: Verify basin boundary polygon geometry

### Issue: GeoGLOWS columns not found
- **Cause**: GeoGLOWS GPKG doesn't have expected column names
- **Fix**: Verify column names in GPKG match config (LINKNO, DSLINKNO, monthly columns)

See [DEBUGGING.md](DEBUGGING.md) for more troubleshooting.
