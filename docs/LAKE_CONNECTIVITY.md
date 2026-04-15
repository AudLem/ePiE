# Lake-River Connectivity

## Overview

ePiE automatically detects and connects lakes to the river network by identifying where river segments cross lake boundaries. This enables through-lake routing using a Completely Stirred Tank Reactor (CSTR) model.

## Lake Detection

ePiE detects lakes using two methods:

### 1. Interior Node Detection

For lakes with network vertices inside the lake polygon:
- Interior nodes are tagged with lake ID (`HL_ID_new`)
- Inlet: where a segment enters the lake (outside → inside)
- Outlet: where a segment exits the lake (inside → outside)

### 2. Segment Crossing Detection (NEW)

For lakes with no interior vertices but river segments crossing the boundary:
- Detects LINESTRING segments that intersect the lake polygon
- Classifies crossings as:
  - **Inlet**: segment enters lake (outside → inside)
  - **Outlet**: segment exits lake (inside → outside)
  - **Tangential**: segment touches boundary without entering/exiting

## Lake Node Creation

For each detected lake, ePiE creates:

### LakeIn Node
- Positioned at the inlet crossing point
- Receives all upstream flows and emissions
- Type: `"LakeInlet"`
- Points to: `LakeOut_<lake_id>`

### LakeOut Node
- Positioned at the outlet crossing point
- Calculates CSTR concentration
- Type: `"LakeOutlet"`
- Points to: downstream river node

## Multi-Inlet Lakes

When a lake has multiple inlets:
- **LD-based selection**: Inlets sorted by cumulative downstream distance (LD) in descending order (higher LD = further upstream)
- **Primary inlet**: The furthest upstream inlet (highest LD) is used for coordinate placement
- **All inlets wired**: ALL upstream nodes from ALL inlets are rewired to point to LakeIn
- **Aggregated inflow**: All discharges and concentrations are summed at LakeIn

## CSTR Model

Lake concentration is calculated using the first-order decay CSTR equation:

```
C_out = C_in × exp(-k × τ)
```

Where:
- `C_out` = concentration at lake outlet
- `C_in` = concentration entering the lake
- `k` = first-order decay rate constant
- `τ` = residence time = V/Q (days)

See `docs/LAKE_MODEL.md` for complete documentation of the CSTR model.

## Configuration

Lake connectivity is controlled by basin configuration:

```r
# In basin config (e.g., volta.R):
enable_lakes = TRUE  # Enable lake routing

# In scenario config (e.g., volta_wet_network.R):
enable_lakes = TRUE  # Enable lake routing
```

## Implementation Details

- Function: `ConnectLakesToNetwork()` in `Package/R/17_ConnectLakesToNetwork.R`
- Crossing detection: `DetectLakeSegmentCrossings()` in `Package/R/18_DetectLakeSegmentCrossings.R`
- Validation: LakeIn and LakeOut coordinates must differ (catches coincident-node bug)
- LD-based selection: Inlets/outlets selected by cumulative downstream distance

## Related Documentation

- [LAKE_MODEL.md](LAKE_MODEL.md) - Complete CSTR model documentation
- [USAGE.md](USAGE.md) - Running simulations with lakes
- [test-network-lake-connectivity.R](Package/tests/testthat/test-network-lake-connectivity.R) - Unit tests
