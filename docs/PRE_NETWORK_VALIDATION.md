# Pre-Network Creation Validation

This guide explains what to check and validate before running the network building pipeline (`BuildNetworkPipeline`). Proper validation prevents errors and ensures your network is built correctly.

## Required Data Files

Before building a network, ensure you have all required spatial data files in place:

### Basin Boundary
- **File**: Basin boundary polygon (Shapefile)
- **Purpose**: Clips all other spatial data to the study area
- **Validation**:
  - File exists at path specified in basin config
  - Contains valid polygon geometry
  - Coordinate reference system (CRS) is defined
  - Area is reasonable (not empty, not too large)

### River Network
- **File**: River line network (Shapefile or GeoPackage for GeoGLOWS)
- **Purpose**: Defines the river topology and flow paths
- **Validation**:
  - File exists at path specified in basin config
  - Contains valid line geometries
  - For HydroSHEDS: Has line segments with connectivity
  - For GeoGLOWS: Has `LINKNO` and `DSLINKNO` columns
  - Lines intersect with basin boundary (not completely outside)

### Flow Direction (HydroSHEDS only)
- **File**: Flow direction raster (ESRI ASCII grid or ArcGIS Binary)
- **Purpose**: Determines downstream flow direction for topology
- **Validation**:
  - File exists at path specified in basin config
  - Covers the basin extent completely
  - Values are valid D8 flow directions (1-128, powers of 2)
  - No NA values inside the basin boundary

### Lakes
- **File**: Lake polygons (Shapefile)
- **Purpose**: Defines lakes for CSTR modeling
- **Validation**:
  - File exists (optional if `enable_lakes = FALSE`)
  - Contains valid polygon geometries
  - Lakes intersect with river network
  - Polygon areas are reasonable (not tiny slivers, not unrealistic sizes)

### Canals (Optional)
- **File**: Artificial canal lines (Shapefile)
- **Purpose**: Adds artificial waterways to the network
- **Validation**:
  - File exists (optional)
  - Contains valid line geometries
  - Has discharge table if needed
  - Canals connect to river network

### Environmental Rasters

#### Slope
- **File**: Slope raster (GeoTIFF)
- **Purpose**: Used in Manning-Strickler flow calculations
- **Validation**:
  - File exists
  - Covers basin extent
  - Values in degrees or percentage
  - No extreme values (0-90 degrees typical)

#### Temperature
- **File**: Air temperature raster (GeoTIFF)
- **Purpose**: Used in pathogen decay calculations
- **Validation**:
  - File exists
  - Covers basin extent
  - Values in reasonable range for study area
  - Units are documented (Celsius or Kelvin)

#### Wind
- **File**: Wind speed raster (GeoTIFF)
- **Purpose**: Used in pathogen decay calculations
- **Validation**:
  - File exists
  - Covers basin extent
  - Values in reasonable range (0-20 m/s typical)

#### Population
- **File**: Population raster (GeoTIFF, e.g., GHS-POP)
- **Purpose**: Extracts population for agglomeration points
- **Validation**:
  - File exists (optional if not using agglomerations)
  - Covers basin extent
  - Values are non-negative integers
  - Resolution is appropriate (100m-1km typical)

### Discharge Data

#### Flow Raster (HydroSHEDS)
- **File**: Discharge raster (GeoTIFF or NetCDF)
- **Purpose**: Provides river discharge values
- **Validation**:
  - File exists
  - For wet season: Uses average or high flow
  - For dry season: Uses minimum flow
  - Units are documented (m³/s typical)
  - Values are non-negative

#### GeoGLOWS Discharge (GeoGLOWS only)
- **File**: Discharge GeoPackage with monthly columns
- **Purpose**: Provides per-segment monthly time series
- **Validation**:
  - File exists
  - Has required columns: `LINKNO`, `DSLINKNO`, monthly columns like `y2020_m01`
  - Monthly column values are numeric
  - No NA values in selected time period

## Configuration Validation

### Basin Config
Check your basin configuration function (e.g., `Package/inst/config/basins/volta.R`):

```r
# Example: VoltaBasinConfig(data_root)
bc <- VoltaBasinConfig("Inputs")

# Verify all paths exist
paths_to_check <- c(
  bc$basin_shp_path,
  bc$lakes_shp_path,
  bc$flow_dir_path,  # NULL for GeoGLOWS
  bc$wet_river_shp_path,
  bc$dry_river_shp_path,
  bc$canal_shp_path,
  bc$slope_raster_path,
  bc$wind_raster_path,
  bc$temp_raster_path,
  bc$pop_raster_path,
  bc$flow_raster_path,
  bc$flow_raster_dry_path
)

# Check each path
for (path in paths_to_check) {
  if (!is.null(path)) {
    exists <- file.exists(path)
    cat(basename(path), ":", ifelse(exists, "EXISTS", "MISSING"), "\n")
    if (!exists) {
      cat("  Expected at:", path, "\n")
    }
  }
}
```

### Scenario Config
Check your network scenario configuration:

```r
cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")

# Verify key fields
cat("Basin ID:", cfg$basin_id, "\n")
cat("Output directory:", cfg$run_output_dir, "\n")
cat("River shapefile:", file.exists(cfg$river_shp_path), "\n")
cat("Lakes enabled:", cfg$enable_lakes, "\n")
cat("Canals enabled:", cfg$enable_canals, "\n")
```

## Data Quality Checks

### Spatial Extent Validation
Ensure all spatial data cover the same geographic area:

```r
library(sf)

basin <- st_read(basin_shp_path)
rivers <- st_read(river_shp_path)
lakes <- st_read(lakes_shp_path)

# Check if layers intersect
basin_bbox <- st_bbox(basin)
rivers_bbox <- st_bbox(rivers)
lakes_bbox <- st_bbox(lakes)

cat("Basin extent:", paste(basin_bbox[c("xmin", "xmax")], collapse="-"),
    "x", paste(basin_bbox[c("ymin", "ymax")], collapse="-"), "y\n")
cat("Rivers intersect basin:", any(st_intersects(basin, rivers, sparse = FALSE)), "\n")
cat("Lakes intersect basin:", any(st_intersects(basin, lakes, sparse = FALSE)), "\n")
```

### River Network Topology
For HydroSHEDS, verify the flow direction and river network are compatible:

```r
library(terra)

# Load flow direction
flow_dir <- rast(flow_dir_path)

# Load rivers
rivers <- st_read(river_shp_path)

# Extract flow direction at river points
if (ncol(rivers) > 0) {
  # Sample points along rivers
  sample_pts <- st_sample(rivers, 100)
  flow_values <- terra::extract(flow_dir, sample_pts)

  # Check for valid D8 directions
  valid_directions <- flow_values %in% c(1, 2, 4, 8, 16, 32, 64, 128)
  cat("Valid flow directions:", sum(valid_directions, na.rm = TRUE),
      "out of", length(valid_directions), "\n")
}
```

### GeoGLOWS Topology
For GeoGLOWS, verify the downstream links are valid:

```r
library(sf)

# Load GeoGLOWS network
geoglows <- st_read(discharge_gpkg_path)

# Check DSLINKNO values
downstream_ids <- geoglows$DSLINKNO
all_ids <- geoglows$LINKNO

# Verify all downstream IDs exist in the network
valid_links <- downstream_ids %in% all_ids | is.na(downstream_ids)
cat("Valid downstream links:", sum(valid_links), "out of", length(valid_links), "\n")

# Check for cycles (node points to itself)
self_loops <- downstream_ids == all_ids
cat("Self-loops (cycles):", sum(self_loops), "\n")
```

## Pre-Build Validation Script

Run this comprehensive validation before building your network:

```r
library(ePiE)
library(sf)
library(terra)

validate_network_inputs <- function(basin_config) {
  cat("=== Network Input Validation ===\n\n")

  # Check file existence
  cat("1. Checking file existence...\n")
  required_files <- list(
    basin = basin_config$basin_shp_path,
    lakes = basin_config$lakes_shp_path,
    rivers_wet = basin_config$wet_river_shp_path,
    slope = basin_config$slope_raster_path,
    wind = basin_config$wind_raster_path,
    temp = basin_config$temp_raster_path,
    flow = basin_config$flow_raster_path
  )

  for (name in names(required_files)) {
    path <- required_files[[name]]
    if (!is.null(path) && !file.exists(path)) {
      cat("  ❌", name, "MISSING:", path, "\n")
    } else {
      cat("  ✓", name, "exists\n")
    }
  }

  # Check spatial overlap
  cat("\n2. Checking spatial overlap...\n")
  basin <- st_read(basin_config$basin_shp_path, quiet = TRUE)
  rivers <- st_read(basin_config$wet_river_shp_path, quiet = TRUE)

  if (nrow(st_intersection(basin, rivers)) > 0) {
    cat("  ✓ Rivers intersect basin\n")
  } else {
    cat("  ❌ Rivers do not intersect basin!\n")
  }

  # Check raster coverage
  cat("\n3. Checking raster coverage...\n")
  basin_bbox <- st_bbox(basin)

  for (raster_name in c("slope", "wind", "temp")) {
    raster_path <- basin_config[[paste0(raster_name, "_raster_path")]]
    if (!is.null(raster_path) && file.exists(raster_path)) {
      rast_obj <- rast(raster_path)
      rast_bbox <- ext(rast_obj)
      overlaps <- (rast_bbox$xmin <= basin_bbox$xmax &&
                   rast_bbox$xmax >= basin_bbox$xmin &&
                   rast_bbox$ymin <= basin_bbox$ymax &&
                   rast_bbox$ymax >= basin_bbox$ymin)
      if (overlaps) {
        cat("  ✓", raster_name, "covers basin\n")
      } else {
        cat("  ❌", raster_name, "does not cover basin!\n")
      }
    }
  }

  cat("\n=== Validation Complete ===\n")
}

# Usage
bc <- VoltaBasinConfig("Inputs")
validate_network_inputs(bc)
```

## Common Validation Issues

### Issue: "File not found" errors
- **Cause**: Incorrect path in basin config or file not downloaded
- **Fix**: Check paths in basin config, run `./scripts/setup-data.sh`

### Issue: "Rivers do not intersect basin"
- **Cause**: River network and basin are in different geographic areas
- **Fix**: Verify basin boundary and river network are for the same area

### Issue: "CRS mismatch" errors
- **Cause**: Spatial data in different coordinate systems
- **Fix**: All data will be reprojected automatically, but verify inputs are valid

### Issue: "Empty network after clipping"
- **Cause**: Basin boundary too small or in wrong location
- **Fix**: Verify basin boundary polygon geometry

### Issue: "Invalid flow direction values"
- **Cause**: Wrong flow direction file or corrupted data
- **Fix**: Download correct HydroSHEDS flow direction for your region

## Next Steps

After validation passes, you can build your network:

```r
library(ePiE)

# Load network scenario config
cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")

# Build the network
state <- BuildNetworkPipeline(cfg, diagnostics = "full")

# Verify output
cat("Network built successfully!\n")
cat("  Points:", nrow(state$points), "\n")
cat("  Lakes:", nrow(state$HL_basin), "\n")
cat("  Output directory:", cfg$run_output_dir, "\n")
```

See [WORKFLOW.md](WORKFLOW.md) for the complete end-to-end workflow.
