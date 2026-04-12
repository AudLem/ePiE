# ePiE External Data Requirements

The package needs external geospatial data for network generation and simulation.
These files are too large to include in the package and must be obtained separately.

## Directory Layout

Place all data under a single root directory (referred to as `data_root` in configs):

```
data_root/
  basins/
    volta/                        # Volta basin boundaries and ancillary data
    bega/                         # Bega (Danube tributary) basin data
  baselines/
    hydrosheds/                   # HydroSHEDS global river and flow data
    environmental/                # Climate and flow rasters
  user/                           # WWTP and chemical property data
```

## Required Files by Source

### HydroSHEDS (https://www.hydrosheds.org/)

| File | Path (relative to data_root) | Description |
|------|------|-------------|
| `w001001.adf` | `baselines/hydrosheds/af_dir_30s_grid/af_dir_30s/af_dir_30s/` | Africa flow direction (30 arc-sec) |
| `af_riv_30s.shp` | `baselines/hydrosheds/af_riv_30s/` | Africa river network (30 arc-sec) |
| `w001001.adf` | `baselines/hydrosheds/eu_dir_30s_grid/eu_dir_30s/eu_dir_30s/` | Europe flow direction (30 arc-sec) |
| `eu_riv_30s.shp` | `baselines/hydrosheds/eu_riv_30s/` | Europe river network (30 arc-sec) |

### FLO1K (https://doi.org/10.5067/FLO1K-TEMP-A-1KM)

| File | Path | Description |
|------|------|-------------|
| `FLO1K.30min.ts.1960.2015.qav.nc` | `baselines/environmental/` | Global mean monthly discharge (30 arc-min) |
| `FLO1k.lt.2000.2015.qav.tif` | `baselines/environmental/` | Long-term average discharge (1km) |
| `FLO1k.lt.2000.2015.qmi.tif` | `baselines/environmental/` | Long-term minimum discharge (1km) |
| `FLO1k.lt.2000.2015.qma.tif` | `baselines/environmental/` | Long-term maximum discharge (1km) |

### Climate Rasters

| File | Path | Description |
|------|------|-------------|
| `temp.tif` | `baselines/environmental/` | Long-term mean air temperature |
| `wind_LTM_yearly_averaged_raster_1981_2010.tif` | `baselines/environmental/` | Long-term mean wind speed |

### Population

| File | Path | Description |
|------|------|-------------|
| `GHS_POP_E2025_GLOBE_R2023A_54009_100_V1_0_R9_C19.tif` | `baselines/environmental/` | GHS-POP 2025 (100m, Mollweide, tile R9_C19) |

### Basin-Specific Data

**Volta basin** (`basins/volta/`):
- `small_sub_basin_volta_dissolved.shp` — Basin boundary polygon
- `cropped_lakes_Akuse_no_kpong` — Lake polygons (HydroLAKES subset)
- `slope_Volta_sub_basin.tif` — Slope raster (derived from SRTM)
- `KIS_canals.shp` — Kpong Irrigation Scheme canal network
- `sanitation_centroids_ghana.csv` — Ghana sanitation data

**Bega basin** (`basins/bega/`):
- `bega_basin.shp` — Basin boundary polygon
- `HL_crop2.shp` — Lake polygons
- `PAGER_mean_slope_Danube.tif` — Slope raster

### User Data (`user/`)

| File | Description |
|------|-------------|
| `EEF_points_updated.csv` | European WWTP database (UWWTD) |
| `chem_Oldenkamp2018_SI.xlsx` | Chemical properties (Oldenkamp et al. 2018) |

## Pre-Built Networks

Pre-built networks can be stored under an `outputs_root` directory:

```
outputs_root/
  volta_wet/          # Volta wet-season network
    pts.csv
    HL.csv
    network_rivers.shp
  bega/               # Bega network
    pts.csv
    HL.csv
    network_rivers.shp
```

## Quick Start

1. Download data from the sources listed above
2. Organise into the directory layout shown
3. Use `LoadScenarioConfig()` with `data_root` pointing to your data directory:

```r
library(ePiE)
data_root <- "/path/to/your/data"
output_root <- "/path/to/your/outputs"
cfg <- LoadScenarioConfig("VoltaWetChemicalIbuprofen", data_root, output_root)
results <- RunSimulationPipeline(cfg)
```
