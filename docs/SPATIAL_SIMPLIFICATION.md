# Spatial Simplification

## Overview

ePiE supports configurable spatial simplification of river and lake geometries to reduce computational complexity while preserving hydrological accuracy.

## River Simplification

### Configuration

River simplification is configured in basin configs:

```r
# In basin config (e.g., volta.R):
simplification = list(
  lake_tolerance = NULL,      # NULL = no simplification (use source-native resolution)
  river_tolerance = 100,      # 100m in UTM projected coordinates
  canal_simplify = FALSE     # FALSE = don't simplify canals
)
```

### How It Works

1. **Projection**: Geometries are projected to UTM for meter-based simplification
2. **Canal Exclusion**: Canals are excluded from simplification if `canal_simplify = FALSE`
3. **Douglas-Peucker Algorithm**: Rivers are simplified using `sf::st_simplify()` with `preserveTopology = TRUE`
4. **Back-Projection**: Simplified geometries are projected back to original CRS

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `river_tolerance` | numeric (meters) | 100 | Douglas-Peucker tolerance in UTM coordinates |
| `canal_simplify` | logical | FALSE | Whether to simplify canals (recommended: FALSE for manually digitized canals) |

### Canal Handling

Canals are manually digitized with ~5-15m accuracy. Simplifying them would lose this precision, so they are excluded by default:

```r
if (!canal_simplify) {
  canals <- rivers[is_canal, ]
  rivers_to_simplify <- rivers[!is_canal, ]
  simplified <- st_simplify(rivers_to_simplify, dTolerance = tolerance)
  return(rbind(simplified, canals))
}
```

## Lake Simplification

### Configuration

```r
simplification = list(
  lake_tolerance = NULL  # NULL = no simplification (recommended)
)
```

### Recommendation

**Do not simplify lakes** (set `lake_tolerance = NULL` or 0). Reasons:

1. **Source Accuracy**: HydroLAKES shoreline accuracy is ~10-30m (Messager 2016)
2. **Lake-Flow Path**: Simplification can distort the flow path through lakes
3. **CSTR Model**: Accurate lake geometry is important for correct volume/area calculations

### Implementation

If simplification is enabled:

```r
if (!is.null(lake_tolerance) && lake_tolerance > 0) {
  utm_crs <- GetUtmCrs(Basin)
  HL_basin_proj <- st_transform(HL_basin, utm_crs)
  
  HL_basin_simplified <- st_simplify(HL_basin_proj, 
                                      preserveTopology = TRUE, 
                                      dTolerance = lake_tolerance)
  HL_basin <- st_transform(HL_basin_simplified, st_crs(HL_basin))
}
```

## Literature Standards

- **Douglas-Peucker**: Should operate in projected coordinates (OGC/ISO 19107 standard)
- **HydroLAKES**: Shoreline accuracy ~10-30m (Messager 2016)
- **Canals**: Manually digitized accuracy ~5-15m
- **Oldenkamp 2018**: Used raw HydroSHEDS data without simplification

## Implementation Details

- River simplification: `SimplifyRiverGeometry()` in `Package/R/12_SimplifyRiverGeometry.R`
- Lake processing: `ProcessLakeGeometries()` in `Package/R/13_ProcessLakeGeometries.R`
- UTM projection: `GetUtmCrs()` in `Package/R/00_utils.R`

## Related Configuration

All basin configs include simplification parameters:

- `Package/inst/config/basins/volta.R`
- `Package/inst/config/basins/volta_geoglows.R`
- `Package/inst/config/basins/bega.R`

Scenario configs inherit basin config:

```r
# In scenario config (e.g., volta_wet_network.R):
simplification = bc$simplification  # Inherit from basin config
```
