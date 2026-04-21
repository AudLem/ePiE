# ePiE Data Requirements

The package needs geospatial data for network generation and simulation.
These files are too large to include in the package repository and are stored in
the project's `Inputs/` and `Outputs/` directories (git-ignored).

## Directory Layout

The project root (the directory containing `Package/`, `Inputs/`, and `Outputs/`) contains:

```
ePiE/
  Inputs/                          # data_root — all source data
    basins/
      volta/                       # Volta basin boundaries and ancillary data
      bega/                        # Bega (Danube tributary) basin data
    baselines/
      hydrosheds/                  # HydroSHEDS global river and flow data
      environmental/               # Climate and flow rasters
    user/                          # WWTP and chemical property data
  Outputs/                         # output_root — pre-built networks & results
    volta_wet/                     # Volta wet-season network
    volta_dry/                     # Volta dry-season network
    bega/                          # Bega network
  Package/                         # R package source
```

## Usage

```r
library(ePiE)
repo <- rprojroot::find_root(rprojroot::is_git_root)
data_root <- file.path(repo, "Inputs")
output_root <- file.path(repo, "Outputs")

# Build network (first time only, or if Inputs data changed)
net_cfg <- LoadScenarioConfig("VoltaWetNetwork", data_root, output_root)
state <- BuildNetworkPipeline(net_cfg)

# Run simulation - merge simulation config into state
sim_cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
state <- modifyList(state, sim_cfg)
results <- RunSimulationPipeline(state, substance = "Ibuprofen")

# Run pathogen simulation
sim_cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", data_root, output_root)
state <- modifyList(state, sim_cfg)
results <- RunSimulationPipeline(state, substance = "cryptosporidium")
```

## Included Data (Volta + Bega)

The following data is already set up in `Inputs/`:

### HydroSHEDS (https://www.hydrosheds.org/)

| Path (relative to Inputs/) | Description |
|------|-------------|
| `baselines/hydrosheds/af_dir_30s_grid/af_dir_30s/af_dir_30s/` | Africa flow direction (30 arc-sec) |
| `baselines/hydrosheds/af_riv_30s/` | Africa river network (30 arc-sec) |
| `baselines/hydrosheds/eu_dir_30s_grid/eu_dir_30s/eu_dir_30s/` | Europe flow direction (30 arc-sec) |
| `baselines/hydrosheds/eu_riv_30s/` | Europe river network (30 arc-sec) |

### FLO1K (https://doi.org/10.5067/FLO1K-TEMP-A-1KM)

| Path | Description |
|------|-------------|
| `baselines/environmental/FLO1K.30min.ts.1960.2015.qav.nc` | Global mean discharge (30 arc-min) |
| `baselines/environmental/FLO1k.lt.2000.2015.qav.tif` | Long-term average discharge (1km) |
| `baselines/environmental/FLO1k.lt.2000.2015.qmi.tif` | Long-term minimum discharge (1km) |
| `baselines/environmental/FLO1k.lt.2000.2015.qma.tif` | Long-term maximum discharge (1km) |

### Climate & Population

| Path | Description |
|------|-------------|
| `baselines/environmental/temp.tif` | Long-term mean air temperature |
| `baselines/environmental/wind_LTM_yearly_averaged_raster_1981_2010.tif` | Long-term mean wind speed |
| `baselines/environmental/GHS_POP_E2025_GLOBE_R2023A_54009_100_V1_0_R9_C19.tif` | GHS-POP 2025 population |

### Volta Basin (`basins/volta/`)

- `small_sub_basin_volta_dissolved.shp` — Basin boundary polygon
- `cropped_lakes_Akuse_no_kpong.shp` — Lake polygons (HydroLAKES subset)
- `slope_Volta_sub_basin.tif` — Slope raster (derived from SRTM)
- `KIS_canals.shp` + `KIS_canal_discharge.csv` — Kpong Irrigation Scheme canals
- `af_riv_dry_season.shp` — Dry-season river network

### Bega Basin (`basins/bega/`)

- `bega_basin.shp` — Basin boundary polygon
- `HL_crop2.shp` — Lake polygons
- `PAGER_mean_slope_Danube.tif` — Slope raster

### User Data (`user/`)

| File | Description |
|------|-------------|
| `EEF_points_updated.csv` | European WWTP database (UWWTD) |
| `chem_Oldenkamp2018_SI.xlsx` | Chemical properties (Oldenkamp et al. 2018) |

## Pre-Built Networks (in Outputs/)

| Directory | Contents |
|-----------|----------|
| `volta_wet/` | `pts.csv`, `HL.csv`, `network_rivers.shp` |
| `volta_dry/` | `pts.csv`, `HL.csv`, `network_rivers.shp` |
| `bega/` | `pts.csv`, `HL.csv`, `network_rivers.shp` |

## Adding a New Basin

1. Create `basins/<name>/` under `Inputs/` with the required shapefiles
2. Add flow direction and river data to `baselines/hydrosheds/`
3. Create config in `Package/inst/config/basins/<name>.R`
4. Create scenario configs in `Package/inst/config/scenarios/`
5. Add scenario names to `ListScenarios()` in `R/30_LoadScenarioConfig.R`
