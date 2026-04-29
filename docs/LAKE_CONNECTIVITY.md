# Lake-River Connectivity

## Overview

ePiE connects lakes to the hydraulic network by detecting directed river passages through lake boundaries. The current rule is conservative: a lake is connected only when the builder can identify at least one inlet and one outlet on the lake boundary. The model never creates `LakeIn` or `LakeOut` at a lake centroid as a fallback.

## Crossing Detection

`DetectLakeSegmentCrossings()` works in a projected CRS so distances and boundary checks are in meters. It uses directed river or transport edges and excludes canals by default.

Crossing classes:

- `inlet`: river edge enters the lake.
- `outlet`: river edge exits the lake.
- `through_lake`: river edge starts outside, crosses the lake polygon, and exits again; this creates one inlet row and one outlet row.
- `internal`: both edge endpoints are inside the lake.
- `tangential`: river touches the boundary without a credible passage through the lake.

Only inlet, outlet, and through-lake crossings can activate routing. Tangential contacts are diagnostics only.

## Strict Activation

`ConnectLakesToNetwork()` activates a lake when:

- `lake_require_inlet_and_outlet = TRUE`;
- at least one inlet crossing exists;
- at least one outlet crossing exists.

If the lake does not meet those rules, no `LakeIn` or `LakeOut` nodes are created. The skipped reason is written to `lake_connection_diagnostics.csv`.

Common skipped reasons:

- `tangential_only`
- `no_inlet`
- `no_outlet`
- `no_inlet_no_outlet`
- `near_miss_above_tolerance`
- `no_river_candidate`

## Node Creation

For an active lake, ePiE creates boundary nodes:

- first inlet: `LakeIn_<Hylak_id>`;
- additional inlets: `LakeIn_<Hylak_id>_02`, `LakeIn_<Hylak_id>_03`, etc.;
- primary outlet: `LakeOut_<Hylak_id>`.

Each upstream river node at an inlet is rewired to its corresponding `LakeIn`. Every `LakeIn` routes to the lake's `LakeOut`. The `LakeOut` routes to the selected downstream river node.

The outlet is chosen from exact outlet crossings. If HydroLAKES `Pour_long` and `Pour_lat` exist and `lake_use_pour_point = TRUE`, the outlet closest to the HydroLAKES pour point is preferred.

## Multiple Inlets And Outlets

Multiple inlets are supported and aggregate naturally through the transport edge graph: each inlet delivers load to the same `LakeOut`, where the lake CSTR mass balance is applied.

Multiple outlets are diagnosed, but only one primary outlet is routed by default. True multi-outlet lake routing should be implemented later as an explicit multi-outlet transport feature rather than silently splitting lake flow.

## Outputs

`lake_connections.csv` contains active lake routing rows:

- `Hylak_id`
- `lake_in_id`
- `lake_out_id`
- `inlet_upstream_id`
- `outlet_downstream_id`
- inlet and outlet boundary coordinates
- crossing method
- snap distances
- confidence
- inlet/outlet counts

`lake_connection_diagnostics.csv` contains one row per lake with:

- active/skipped status;
- skipped reason;
- counts of exact inlets, exact outlets, tangential crossings, internal crossings;
- number of interior/source nodes;
- nearest river distance.

`transport_edges.csv` is rebuilt after lake connection so simulation can route loads into lake inlets, through the lake reactor, and out of the selected outlet.

## Configuration Defaults

These defaults are defined in basin configs and forwarded by network scenarios:

```r
lake_snap_tolerance_m = 250
lake_snap_enabled = FALSE
lake_use_pour_point = TRUE
lake_require_inlet_and_outlet = TRUE
```

`lake_snap_tolerance_m` is used for diagnostics. Snapping is disabled by default because false lake connections are worse than clearly reported skipped lakes.

## Related Documentation

- [LAKE_MODEL.md](LAKE_MODEL.md) - CSTR lake mass balance and routing.
- [USAGE.md](USAGE.md) - Running simulations with lakes.
- [test-lake-segment-crossings.R](../Package/tests/testthat/test-lake-segment-crossings.R) - Synthetic crossing tests.
- [test-network-lake-connectivity.R](../Package/tests/testthat/test-network-lake-connectivity.R) - Network-level lake connectivity checks.
