# Wet vs Dry Season Flow Data Configuration

## HydroSHEDS Scenarios (`volta_simulations.R`)

| Aspect | Wet | Dry |
|--------|-----|-----|
| River network | `af_riv_30s.shp` (full river network, 351 nodes) | `af_riv_dry_season.shp` (seasonal, fewer flowing rivers, 178 nodes) |
| Flow raster | `FLO1K.30min.ts.1960.2015.qav.nc` (long-term average discharge) | `FLO1k.lt.2000.2015.qmi.tif` (minimum discharge) |
| Network size | 351 points, 7 lakes | 178 points, 7 lakes |

Both flow rasters cover Western Europe only (lon 7.96-29.92, lat 41.88-50.44). The Volta basin (lon -5 to 2, lat 6 to 15) falls entirely outside this extent, so Q=0 for all nodes in both seasons. The median Q fallback also produces zero because there are no non-zero Q values to take a median of.

## GeoGLOWS Scenarios (`volta_geoglows_simulations.R`)

| Aspect | Wet | Dry |
|--------|-----|-----|
| River network | `streams_in_volta_basin.gpkg` (924 nodes) | `streams_in_volta_basin.gpkg` (same network, 924 nodes) |
| Discharge source | `discharge_in_volta_basin.gpkg` | `discharge_in_volta_basin.gpkg` (same file) |
| Simulation months | Sep-Oct (`simulation_months = 9:10`) | Mar-Apr (`simulation_months = 3:4`) |
| GPKG columns used | `y2020_m09`, `y2020_m10` | `y2020_m03`, `y2020_m04` |
| Aggregation | mean of selected months | mean of selected months |
| Network size | 924 points, 7 lakes | 924 points, 7 lakes |

The GeoGLOWS discharge GPKG contains per-segment monthly mean discharge values with columns named `yYYYY_mMM`. Wet/dry seasonality is captured entirely by selecting different month columns from the same dataset — Sep-Oct represents the peak rainy season (high flow) and Mar-Apr represents the peak dry season (low flow).

## Key Difference

- **HydroSHEDS**: Wet and dry use entirely different river shapefiles (different network topology) AND different flow rasters. The dry network has ~50% fewer nodes because many seasonal tributaries stop flowing.
- **GeoGLOWS**: The river network is identical; only the monthly discharge values differ. Seasonality is expressed through the Q values at each segment, not through the network geometry.
