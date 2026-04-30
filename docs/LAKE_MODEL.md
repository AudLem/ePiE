# Lake Modeling Approach In ePiE

## Overview

ePiE supports two lake transport modes. Active lakes always use strict boundary `LakeIn`/`LakeOut` geometry, but the fate model at the outlet is configurable:

- `legacy_pass_through`: lake boundary nodes pass routed river load downstream without applying lake-reactor removal. This restores Bega ibuprofen literature-parity behavior from the v1.25 workflow.
- `cstr`: routed inflows and direct in-lake loads are mixed into one lake volume, and the outlet concentration is computed from a steady-state mass balance.

The CSTR option is intentionally simpler than a segmented hydrodynamic lake model. It is appropriate for calibrated catchment-scale screening, but large lakes, reservoirs with complex circulation, or lakes with multiple independent outlets should be flagged for future segmented routing.

## Lake Activation

Lake routing is conservative by default. A lake becomes hydraulically active only when the network builder identifies at least one credible inlet and one credible outlet on the lake boundary.

Active lake nodes:

- `LakeIn_<Hylak_id>`: boundary node where river load enters the lake.
- `LakeIn_<Hylak_id>_02`, `_03`, etc.: additional physical inlets when present.
- `LakeOut_<Hylak_id>`: primary boundary outlet selected from exact outlet crossings, with HydroLAKES pour-point proximity used as a tie-breaker when available.

Skipped lakes are not represented by centroid fallback nodes. Tangential contacts, missing inlets, missing outlets, and near misses are written to `lake_connection_diagnostics.csv`.

## Transport Modes

Bega default/literature scenarios set:

```r
lake_transport_mode = "legacy_pass_through"
```

This keeps the old Bega plume behavior: the lake intersection is represented by physical boundary nodes, first-order river/canal edge decay remains active, and concentrations are recomputed at downstream river nodes from the transported load and river Q. No lake residence-time removal is applied.

Use this only when the scenario is intended to match the historical river-intersection behavior or when a lake reactor has not been calibrated.

CSTR scenarios must opt in explicitly:

```r
lake_transport_mode = "cstr"
```

## CSTR Mass Balance

When `lake_transport_mode = "cstr"`, the lake concentration is computed as a steady-state completely stirred tank reactor (CSTR):

```text
C_lake = Load_total / (Q + k * V)
```

where:

- `C_lake` is the lake outlet concentration.
- `Load_total` is routed upstream load plus local/direct lake load.
- `Q` is the lake outlet discharge in m3/s.
- `k` is the first-order decay rate in 1/s after the code's unit conversion.
- `V` is lake volume in m3.

HydroLAKES volume (`Vol_total`) is stored in km3 and is converted to m3 with:

```text
V_m3 = Vol_total_km3 * 1e9
```

The model also exports, for CSTR-mode outlet nodes:

```text
lake_residence_time_days = V_m3 / (Q_m3s * 86400)
```

Residence time is diagnostic here and is meaningful only for active CSTR routing. The lake CSTR formula is not the same as plug-flow exponential decay. Exponential decay is used for travel along river/canal edges, not as the lake reactor equation.

## Routing Logic

Lake routing uses the same transport graph as rivers and canals:

- upstream river edges deliver load to one or more `LakeIn` nodes;
- each `LakeIn` routes load to the lake's `LakeOut`;
- `LakeOut` applies either legacy pass-through or the CSTR mass balance, depending on `lake_transport_mode`;
- the lake outlet load then routes downstream through the transport edge table.

The outlet Q used by the lake mode is derived from summed incoming lake inlet edges (`lake_throughflow_m3s` / `Q_lake_m3s`), not from raster extraction at the artificial boundary point.

`ID_nxt` remains in `pts.csv` for compatibility, but branch-aware and lake-aware simulation should be inspected through `transport_edges.csv`.

Direct source nodes physically inside an active lake are tagged with the lake ID and routed through the lake connection. The current default avoids double-counting: source emissions routed through the network are not also added as separate `HL$E_in` loads.

## Outputs

Network build outputs:

- `lake_connections.csv`: active lake inlet/outlet routing metadata.
- `lake_connection_diagnostics.csv`: skipped-lake reasons and crossing counts.
- `pts.csv`: node table with `LakeInlet` and `LakeOutlet` rows for active lakes only.
- `transport_edges.csv`: directed routing graph including lake inlet-to-outlet paths.

Simulation outputs:

- `simulation_results.csv`: node concentrations.
- `hydrology_nodes.csv`: Q, V, H, concentration fields, `Q_lake_m3s`, `lake_throughflow_m3s`, `lake_transport_mode`, and `lake_residence_time_days` where meaningful.

## Scientific Context

The one-CSTR representation follows common screening-scale water-quality practice when calibrated for the question being asked: lake/reservoir residence time is based on volume and through-flow, and first-order removal can be represented in a mixed compartment. This is consistent with the way lake volumes and residence times are used in HydroLAKES-based studies and with simple water-body assumptions in catchment-scale models.

The `legacy_pass_through` mode is a regression-protection mode for Bega literature scenarios. It preserves the v1.25 behavior where lakes acted like river/intersection routing points, so the Timisoara ibuprofen plume declines gradually downstream instead of being removed by an uncalibrated lake reactor.

For more complex lakes, a single CSTR can miss spatial gradients, stratification, density currents, wind-driven circulation, and multiple independent outlet pathways. Those cases should be handled later with segmented lakes or a coupled hydrodynamic model.

## References

- Messager, M. L., et al. (2016). "Estimating the volume and age of water stored in global lakes using a geo-statistical approach." Nature Communications, 7, 13603. https://www.nature.com/articles/ncomms13603
- US EPA. "Mechanistic Modeling." https://www.epa.gov/n-steps-online/mechanistic-modeling
- US EPA. "Water Quality Analysis Simulation Program (WASP)." https://www.epa.gov/hydrowq/water-quality-analysis-simulation-program-wasp
- SWAT+ Documentation. "Water Bodies." https://swatplus.gitbook.io/io-docs/theoretical-documentation/section-8-water-bodies/sediment-in-water-bodies

## Related Code

- `Package/R/17_ConnectLakesToNetwork.R`: creates strict boundary inlet/outlet nodes and diagnostics.
- `Package/R/18_DetectLakeSegmentCrossings.R`: detects directed river-lake boundary crossings.
- `Package/R/22_TransportEdges.R`: builds the routing edge table.
- `Package/R/22A_ComputeTransportEdges.R`: edge-aware R transport solver, including lake pass-through and CSTR routing.
- `Package/R/Compute_env_concentrations_v4.R`: legacy linear R solver with the same lake transport modes.
