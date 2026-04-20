# Post-Simulation Interpretation Guide

This guide explains how to interpret and validate results after running the simulation pipeline (`RunSimulationPipeline`). It helps you understand what the outputs mean and how to identify potential issues.

## Quick Results Check

After a simulation completes, immediately check these key indicators:

```r
library(ePiE)

# Load results
results <- read.csv("Outputs/volta_campy_wet/simulation_results.csv")

# Basic statistics
cat("Simulation Results Summary:\n")
cat("  Total nodes:", nrow(results), "\n")
cat("  Concentrations > 0:", sum(results$C_w > 0, na.rm = TRUE), "\n")
cat("  Concentrations = 0:", sum(results$C_w == 0, na.rm = TRUE), "\n")
cat("  Concentrations = NA:", sum(is.na(results$C_w)), "\n")
cat("  Discharge > 0:", sum(results$Q > 0, na.rm = TRUE), "\n")
cat("  Discharge = NA:", sum(is.na(results$Q)), "\n")
```

## Understanding the Results Files

### simulation_results.csv
The main output file contains one row per network node with:

| Column | Description | Expected Range |
|--------|-------------|----------------|
| `ID` | Unique node identifier | - |
| `Pt_type` | Node type (node, WWTP, agglomeration, JNCT, etc.) | - |
| `ID_nxt` | Downstream node ID | Must exist in ID column (except MOUTH) |
| `x`, `y` | Coordinates (WGS84) | Longitude, latitude |
| `Q` | River discharge at node | > 0 m³/s |
| `C_w` | Water concentration (result) | Depends on substance |
| `C_sd` | Sediment concentration (pathogens only) | ≥ 0 |
| `WWTPremoval` | WWTP removal efficiency | 0-1 for chemical, NA for pathogen |
| `substance` | Substance name | - |
| `basin_id` | Basin identifier | - |

## Concentration Value Interpretation

### Chemical Concentrations (µg/L)

| Range | Interpretation | Typical Scenario |
|-------|----------------|------------------|
| 0 | No contamination | No upstream sources, complete removal |
| 0.001 - 0.01 | Low contamination | Distant sources, high dilution, high removal |
| 0.01 - 0.1 | Moderate contamination | Typical for WWTP-influenced rivers |
| 0.1 - 1.0 | High contamination | Direct discharge, low flow, low removal |
| > 1.0 | Very high contamination | Problematic: check data, may indicate error |

**Example: Ibuprofen**
```r
# Check concentration distribution
results <- read.csv("Outputs/bega_ibuprofen/results_pts_bega_Ibuprofen.csv")
summary(results$C_w)

# Plot histogram
hist(results$C_w[results$C_w > 0],
     main = "Ibuprofen Concentrations",
     xlab = "C_w (µg/L)")
```

### Pathogen Concentrations (CFU/100mL or oocysts/L)

| Pathogen | Typical Range | Interpretation |
|----------|---------------|----------------|
| Cryptosporidium | 0 - 1000 oocysts/L | Depends on treatment and prevalence |
| Giardia | 0 - 5000 oocysts/L | Higher than Cryptosporidium typically |
| Rotavirus | 0 - 1000 PFU/L | Varies seasonally |
| Campylobacter | 0 - 100 CFU/100mL | Bacteria, typically lower than protozoa |

**Example: Cryptosporidium**
```r
# Check concentration statistics
results <- read.csv("Outputs/volta_crypto_wet/simulation_results.csv")

cat("Cryptosporidium statistics:\n")
cat("  Mean:", mean(results$C_w, na.rm = TRUE), "oocysts/L\n")
cat("  Median:", median(results$C_w, na.rm = TRUE), "oocysts/L\n")
cat("  Max:", max(results$C_w, na.rm = TRUE), "oocysts/L\n")

# Plot log-scale histogram
hist(log10(results$C_w[results$C_w > 0]),
     main = "Cryptosporidium Concentrations (log10)",
     xlab = "log10(C_w)")
```

## Common Result Patterns and What They Mean

### Pattern 1: All Concentrations Are Zero
**Indicators:**
- `C_w = 0` for all nodes
- No contamination anywhere in the network

**Possible Causes:**
1. **No emission sources**: No WWTPs or agglomerations with population
2. **f_direct = 0**: Chemicals only emit from WWTPs, not agglomerations
3. **Complete treatment**: WWTP removal = 100%
4. **No consumption**: Zero chemical consumption in the basin

**Diagnosis:**
```r
# Check for emission sources
pts <- read.csv("Outputs/volta_wet/pts.csv")
cat("WWTPs:", sum(pts$Pt_type == "WWTP"), "\n")
cat("Agglomerations:", sum(pts$Pt_type == "agglomeration"), "\n")
cat("Agglomeration population:", sum(pts$total_population, na.rm = TRUE), "\n")

# For chemicals, check f_direct
if ("f_direct" %in% names(pts)) {
  cat("f_direct values:", unique(pts$f_direct), "\n")
}
```

**Solution:**
- Add WWTP data to your network
- Enable direct discharge from agglomerations (`f_direct > 0`)
- Add consumption data for chemicals

### Pattern 2: All Concentrations Are NA
**Indicators:**
- `C_w = NA` for all nodes
- Simulation completed but no valid results

**Possible Causes:**
1. **No discharge data**: `Q = NA` for all nodes
2. **Division by zero**: `Q = 0` everywhere
3. **Missing emissions**: Population = 0 for all sources

**Diagnosis:**
```r
# Check discharge
cat("Discharge statistics:\n")
cat("  NA:", sum(is.na(results$Q)), "\n")
cat("  Zero:", sum(results$Q == 0, na.rm = TRUE), "\n")
cat("  Positive:", sum(results$Q > 0, na.rm = TRUE), "\n")

# Check population sources
pts <- read.csv("Outputs/volta_wet/pts.csv")
wwtp_pop <- sum(pts$total_population[pts$Pt_type == "WWTP"], na.rm = TRUE)
agglo_pop <- sum(pts$total_population[pts$Pt_type == "agglomeration"], na.rm = TRUE)
cat("WWTP population:", wwtp_pop, "\n")
cat("Agglomeration population:", agglo_pop, "\n")
```

**Solution:**
- Ensure flow raster or GeoGLOWS data is properly loaded
- Verify Q propagation didn't fail (check logs for warnings)
- Fix population data (see Bega Campylobacter fix)

### Pattern 3: Concentrations Only at Emission Points
**Indicators:**
- `C_w > 0` only at WWTP or agglomeration nodes
- `C_w = 0` at all downstream nodes

**Possible Causes:**
1. **No downstream flow**: River network ends at emission points
2. **Topology broken**: Downstream links (`ID_nxt`) don't form a connected graph
3. **Instant decay**: Decay rate too high, contaminants don't reach downstream

**Diagnosis:**
```r
# Check topology
pts <- read.csv("Outputs/volta_wet/pts.csv")
cat("Nodes with C_w > 0:", sum(pts$C_w > 0), "\n")
cat("Nodes with valid ID_nxt:", sum(!is.na(pts$ID_nxt)), "\n")

# Check if downstream nodes have concentrations
with_conc <- pts[pts$C_w > 0, ]
cat("Nodes with concentration that have downstream links:",
    sum(!is.na(with_conc$ID_nxt)), "\n")

# Check decay rates (if available)
if ("k" %in% names(results)) {
  cat("Decay rate range:", range(results$k, na.rm = TRUE), "\n")
}
```

**Solution:**
- Verify river network is fully connected to river mouth
- Check that topology building completed successfully
- Review decay parameters (may be too high for short river segments)

### Pattern 4: Unrealistic Concentrations
**Indicators:**
- Extremely high concentrations (> 1000× typical values)
- Negative concentrations
- Concentrations increasing downstream (should decrease due to dilution/decay)

**Diagnosis:**
```r
# Check for extreme values
cat("Max concentration:", max(results$C_w, na.rm = TRUE), "\n")
cat("Min concentration:", min(results$C_w, na.rm = TRUE), "\n")

# Check for negative values
if (any(results$C_w < 0, na.rm = TRUE)) {
  cat("Negative concentrations:", sum(results$C_w < 0, na.rm = TRUE), "\n")
}

# Check concentration trends along the river
# Sort by distance to mouth and plot
if ("Dist_down" %in% names(results)) {
  plot(results$Dist_down, results$C_w,
       main = "Concentration vs Distance to Mouth",
       xlab = "Distance (m)", ylab = "C_w")
}
```

**Solution:**
- Check for division by very small Q values
- Verify decay parameters are realistic
- Review emission calculations (population × prevalence × excretion)

## Visualization Validation

### Interactive Map
Open the concentration map and verify:

```bash
open Outputs/volta_campy_wet/plots/concentration_map.html
```

**What to check:**
1. **Legend is populated**: Not empty or all zeros
2. **Color gradient is visible**: Not all the same color
3. **Rivers and canals display**: Canals should be cyan, rivers blue
4. **Emission sources visible**: Red dots for WWTPs/agglomerations
5. **Concentrations decrease downstream**: Higher near sources, lower near mouth

### Static Map
Check the PNG file:

```bash
open Outputs/volta_campy_wet/plots/static_concentration_map.png
```

**What to check:**
- Points are colored by concentration
- Color scale bar is visible
- Map is not blank or all one color

## Network Map Validation
Also check the network map to understand the topology:

```bash
open Outputs/volta_wet/plots/interactive_network_map.html
```

**What to check:**
- All river segments connect
- Lakes are shown (blue polygons)
- Canals are shown (cyan lines) if present
- Node types are color-coded
- Network flows toward the mouth

## Comparing Scenarios

### Wet vs Dry Season
For the same basin, compare wet and dry results:

```r
wet <- read.csv("Outputs/volta_crypto_wet/simulation_results.csv")
dry <- read.csv("Outputs/volta_crypto_dry/simulation_results.csv")

cat("Wet season:\n")
cat("  Mean C_w:", mean(wet$C_w, na.rm = TRUE), "\n")
cat("  Max C_w:", max(wet$C_w, na.rm = TRUE), "\n")
cat("  Mean Q:", mean(wet$Q, na.rm = TRUE), "\n\n")

cat("Dry season:\n")
cat("  Mean C_w:", mean(dry$C_w, na.rm = TRUE), "\n")
cat("  Max C_w:", max(dry$C_w, na.rm = TRUE), "\n")
cat("  Mean Q:", mean(dry$Q, na.rm = TRUE), "\n")
```

**Expected pattern:**
- Wet: Lower concentrations (higher dilution)
- Dry: Higher concentrations (lower dilution)

### HydroSHEDS vs GeoGLOWS
Compare different discharge sources:

```r
hydrosheds <- read.csv("Outputs/volta_crypto_wet/simulation_results.csv")
geoglows <- read.csv("Outputs/volta_geoglows_crypto_wet/simulation_results.csv")

cat("HydroSHEDS:\n")
cat("  Mean Q:", mean(hydrosheds$Q, na.rm = TRUE), "\n")
cat("  Mean C_w:", mean(hydrosheds$C_w, na.rm = TRUE), "\n\n")

cat("GeoGLOWS:\n")
cat("  Mean Q:", mean(geoglows$Q, na.rm = TRUE), "\n")
cat("  Mean C_w:", mean(geoglows$C_w, na.rm = TRUE), "\n")
```

**Expected pattern:**
- GeoGLOWS typically has better flow data (especially for Africa)
- Concentrations should be more realistic with GeoGLOWS

### Chemical vs Pathogen
Compare different substance types:

```r
chem <- read.csv("Outputs/volta_wet_ibuprofen/results_pts_volta_Ibuprofen.csv")
pathogen <- read.csv("Outputs/volta_crypto_wet/simulation_results.csv")

cat("Chemical (Ibuprofen):\n")
cat("  Non-zero C_w:", sum(chem$C_w > 0), "\n")
cat("  Mean C_w:", mean(chem$C_w, na.rm = TRUE), "\n\n")

cat("Pathogen (Cryptosporidium):\n")
cat("  Non-zero C_w:", sum(pathogen$C_w > 0), "\n")
cat("  Mean C_w:", mean(pathogen$C_w, na.rm = TRUE), "\n")
```

**Expected pattern:**
- Pathogens typically show more non-zero concentrations (agglomerations emit untreated)
- Chemicals may have more zeros if no WWTPs exist

## Exporting Results for Analysis

### Create summary table
```r
library(dplyr)

results <- read.csv("Outputs/volta_campy_wet/simulation_results.csv")

summary_table <- results %>%
  group_by(Pt_type) %>%
  summarise(
    n = n(),
    mean_C = mean(C_w, na.rm = TRUE),
    max_C = max(C_w, na.rm = TRUE),
    mean_Q = mean(Q, na.rm = TRUE)
  )

print(summary_table)
write.csv(summary_table, "Outputs/volta_campy_wet/summary_by_type.csv", row.names = FALSE)
```

### Export for GIS
```r
library(sf)

results <- read.csv("Outputs/volta_campy_wet/simulation_results.csv")

# Convert to spatial points
results_sf <- st_as_sf(results, coords = c("x", "y"), crs = 4326)

# Save as GeoPackage
st_write(results_sf, "Outputs/volta_campy_wet/concentrations.gpkg")

# Or as Shapefile (truncate long column names)
st_write(results_sf, "Outputs/volta_campy_wet/concentrations.shp")
```

## Troubleshooting Common Issues

### Issue: Legend is empty in concentration map
**Cause:** All concentrations are zero or NA

**Fix:**
- Check for valid emission sources (WWTPs or agglomerations with population)
- Verify discharge data loaded correctly
- See "Pattern 2: All Concentrations Are NA" above

### Issue: Canals not visible in map
**Cause:** Canals may not have been loaded or displayed

**Fix:**
- Verify canals exist in network: `sum(pts$is_canal == TRUE)`
- Check map layer control: Toggle "Canals" layer on
- Canals should be cyan (#00bcd4) with weight 2.5

### Issue: Concentrations don't decrease downstream
**Cause:** May indicate topology or data issues

**Fix:**
- Verify river network flows to mouth (check ID_nxt connections)
- Check for negative or very small discharge values
- Review decay parameters

## Best Practices

1. **Always check basic statistics** before diving into visualization
2. **Compare with expected ranges** for your substance and basin
3. **Validate against known points** if available (monitoring data)
4. **Run multiple scenarios** to understand sensitivity (wet/dry, HydroSHEDS/GeoGLOWS)
5. **Document your findings** for future reference
6. **Export results for further analysis** in R, Python, or GIS software

## Getting Help

If results don't make sense:

1. Check the simulation logs for warnings or errors
2. Verify input data quality (see [PRE_NETWORK_VALIDATION.md](PRE_NETWORK_VALIDATION.md))
3. Compare with a working scenario (e.g., Bega for Europe, Volta GeoGLOWS for Africa)
4. Review [DEBUGGING.md](DEBUGGING.md) for troubleshooting techniques
5. Check [TESTING.md](TESTING.md) for expected results

See [WORKFLOW.md](WORKFLOW.md) for the complete end-to-end workflow.
