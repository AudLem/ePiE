# ePiE Bugfix Plan

> Generated: 2026-04-13
> Scope: All CRITICAL and MAJOR issues identified by full codebase audit, plus hydraulic intersection/overlap improvements.

---

## Phase 1: C++ Engine Safety (prevents crashes and memory corruption)

These fixes are in `Package/src/compenvcons_v4.cpp` and `Package/src/calc_topology.cpp`.

### 1.1 `which()` returns OOB index when match not found

**File:** `src/compenvcons_v4.cpp:29-37`
**Problem:** All three `which()` variants return `n` (vector size) when the element is not found. Every caller uses the return as an array index → out-of-bounds read/write.
**Fix:** Return `-1` on not-found. Guard every call site with `if (match_index >= 0)` before array access. This mirrors the R behaviour where `match()` returns `NA`.

```cpp
// BEFORE: returns n (OOB) when not found
int which(const std::vector<int>& vec, const int& match) {
  int counter = 0;
  int n = vec.size();
  for (int i = 0; i < n; i += 1) {
    if (vec[i] == match) break;
    else counter++;
  }
  return counter;
}

// AFTER: returns -1 on not-found; callers must check >= 0
int which(const std::vector<int>& vec, const int& match) {
  int n = vec.size();
  for (int i = 0; i < n; i += 1) {
    if (vec[i] == match) return i;
  }
  return -1;
}
```

Apply the same pattern to `which_string()` (line 39) and `which_string_double()` (line 73).

### 1.2 Terminal nodes (river mouths) crash — no downstream neighbor guard

**File:** `src/compenvcons_v4.cpp:299-301, 317-319, 329-331`
**Problem:** Mouth nodes have no downstream neighbor. `which_string_double()` returns OOB → writes to memory past vector end.
**Fix:** After the `which_string_double()` call, skip the `pts_E_up_tmp` update when `match_index_d < 0`.

```cpp
// All three call sites (river node, lake CSTR, lake interior) get the same guard:
match_index_d = which_string_double(pts_ID, pts_ID_nxt[j], pts_basin_id, pts_basin_id[j]);
if (match_index_d >= 0) {
  pts_E_up_tmp[match_index_d] = pts_E_up_tmp[match_index_d] + pts_E_w_NXT_tmp[j];
  pts_upcount_tmp[match_index_d] = pts_upcount_tmp[match_index_d] - 1;
}
```

### 1.3 Missing basin_id existence check before lake CSTR branch

**File:** `src/compenvcons_v4.cpp:273`
**Problem:** R version checks `match(pts.basin_id[j], HL.basin_id)` before entering CSTR; C++ always enters when `pts_lake_out[j] == 1`, even if the lake doesn't exist in HL data → triggers 1.1 OOB.
**Fix:** Add the `which()` call and guard.

```cpp
// BEFORE: unconditional entry
if (pts_lake_out[j] == 1) {

// AFTER: verify the lake exists in HL table first
int hl_check = which(hl_Hylak_id, pts_Hylak_id[j]);
if (pts_lake_out[j] == 1 && hl_check >= 0) {
```

### 1.4 Division by zero on `pts_Q[j]`

**File:** `src/compenvcons_v4.cpp:281, 307`
**Problem:** Zero discharge → Inf/NaN cascades downstream.
**Fix:** Clamp Q to a minimum value (same as R pipeline: 0.001 m³/s).

```cpp
// Before computing C_w, clamp Q:
double Q_safe = pts_Q[j] > 0.001 ? pts_Q[j] : 0.001;
pts_C_w[j] = E_total / Q_safe * 1e6 / (365.0 * 24.0 * 3600.0);
```

### 1.5 Division by zero on `pts_V_NXT[j]`, `pts_k_sw[j]`, `pts_H_sed[j]`

**File:** `src/compenvcons_v4.cpp:298, 316, 283, 309, 284, 310`
**Problem:** Zero velocity, zero solid-water partition, or zero sediment depth → Inf/NaN.
**Fix:** Add guards before each division.

```cpp
// V_NXT guard (appears in decay exponent):
double decay_exp = 0.0;
if (pts_V_NXT[j] > 0) {
  decay_exp = -pts_k_NXT[j] * pts_dist_nxt[j] / pts_V_NXT[j];
}
pts_E_w_NXT_tmp[j] = ... * std::exp(decay_exp);

// k_sw guard:
double chem_exchange = (hl_k_sw[match_index] > 0) ?
  hl_k_ws[match_index] / hl_k_sw[match_index] : 0.0;

// H_sed guard:
double H_ratio = (hl_H_sed[match_index] > 0) ?
  hl_Depth_avg[match_index] / hl_H_sed[match_index] : 0.0;
```

### 1.6 NaN propagation from input vectors

**File:** `src/compenvcons_v4.cpp:220-340`
**Problem:** R `NA_real_` becomes C++ `NaN`. NaN in `E_total` → all downstream concentrations become NaN.
**Fix:** At the start of the main loop, skip nodes where any input is NaN.

```cpp
if (std::isnan(pts_E_w[j]) || std::isnan(pts_E_up_tmp[j])) {
  pts_C_w[j] = std::numeric_limits<double>::quiet_NaN();
  pts_fin[j] = 1;
  continue;
}
```

### 1.7 Infinite loop on cyclic topology

**File:** `src/calc_topology.cpp:20`
**Problem:** No cycle detection in the while-true loop.
**Fix:** Add a visited set and max-iteration guard.

```cpp
// BEFORE:
while (true) {
  idx_nxt = idx_nxt_tmp[idx_nxt];
  if (isMouth[idx_nxt] == 1) break;
  dist_tmp += d_nxt[idx_nxt];
}

// AFTER:
std::vector<bool> visited(n, false);
int max_iter = n;
int iter = 0;
while (iter < max_iter) {
  if (visited[idx_nxt]) break;  // cycle detected
  visited[idx_nxt] = true;
  if (idx_nxt < 0 || idx_nxt >= n) break;  // OOB guard
  if (isMouth[idx_nxt] == 1) break;
  dist_tmp += d_nxt[idx_nxt];
  idx_nxt = idx_nxt_tmp[idx_nxt];
  iter++;
}
```

### 1.8 Lake volume conversion: `* 1e6` should be `* 1e9`

**File:** `src/compenvcons_v4.cpp:279` and `Package/R/Compute_env_concentrations_v4.R:83`
**Problem:** HydroLAKES `Vol_total` is in km³. 1 km³ = 10⁹ m³. Code multiplies by 10⁶, underestimating volume by 1000×.
**Impact:** Lake CSTR concentrations are dramatically overestimated (Volta Lake: treated as 0.15 km³ instead of 150 km³).
**Fix:** Change both R and C++ from `* 1e6` to `* 1e9`.

```cpp
// BEFORE:
V = hl_Vol_total[match_index] * 1e6;  // wrong: km^3 -> m^3 is 1e9
// AFTER:
V = hl_Vol_total[match_index] * 1e9;  // correct: 1 km^3 = 10^9 m^3
```

---

## Phase 2: R Engine — Formula Fixes (changes simulation results)

### 2.1 Pathogen lake CSTR concentration off by 10⁶

**File:** `Package/R/Compute_env_concentrations_v4.R:90`
**Problem:** Unit analysis:
- `E_total` [oocysts/year] / `(Q + k*V)` [m³/s] = oocysts·s / (m³·year)
- Dividing by `365*24*3600` [s/year] gives oocysts/m³
- Converting to oocysts/L requires dividing by 1000
- Code multiplies by 1000 → result is 10⁶ too large

**Fix:**

```r
# BEFORE:
pts.C_w[j] = (E_total / (pts.Q[j] + k * V)) / (365 * 24 * 3600) * 1000

# AFTER: oocysts/year / (m3/s) / (s/year) / (L/m3) = oocysts/L
pts.C_w[j] = (E_total / (pts.Q[j] + k * V)) / (365 * 24 * 3600) / 1000
```

### 2.2 Pathogen lake-outlet E_w_NXT has reciprocal unit error

**File:** `Package/R/Compute_env_concentrations_v4.R:111`
**Problem:** `C_w [oocysts/L] * Q [m³/s] * 1000 [L/m³] * seconds/year` = oocysts/year. Code has `/ 1000` instead of `* 1000`.
**Fix:**

```r
# BEFORE:
pts.E_w_NXT[j] = pts.C_w[j] * pts.Q[j] * 365 * 24 * 3600 / 1000 * exp(...)

# AFTER: convert C_w (oocysts/L) * Q (m3/s) to oocysts/year via L/m3 conversion
pts.E_w_NXT[j] = pts.C_w[j] * pts.Q[j] * 1000 * 365 * 24 * 3600 * exp(...)
```

**Note:** The bugs in 2.1 and 2.2 partially cancel each other in the current code (both off by 10⁶ in opposite directions), so downstream loads happen to be correct. Fixing both preserves correctness while making concentrations accurate.

### 2.3 WWTP emission overcounting — uses basin total instead of per-node population

**File:** `Package/R/02_PathogenModel.R:66-79`
**Problem:** `total_oocysts` is computed at basin level, then each WWTP receives `total_oocysts * f_STP[i]`. With 2 WWTPs at default f_STP=0.9, total distributed = 1.8× actual production. Also double-counts with agglomeration nodes.
**Fix:** Use per-node population, consistent with the agglomeration branch.

```r
# BEFORE (basin-level distribution):
total_pop <- pathogen_params$total_population
n_infected <- total_pop * prev_rate
total_oocysts <- n_infected * exc_rate
network_nodes$E_in[wwtp_idx] <- total_oocysts * network_nodes$f_STP[wwtp_idx]

# AFTER (per-node population, same logic as agglomerations):
# Each WWTP emits based on its local connected population.
# f_STP represents the fraction of local population connected to THIS WWTP.
wwtp_pop <- if ("total_population" %in% names(network_nodes)) {
  network_nodes$total_population[wwtp_idx]
} else {
  rep(pathogen_params$total_population, length(wwtp_idx))
}
network_nodes$E_in[wwtp_idx] <- wwtp_pop * prev_rate * exc_rate
```

### 2.4 Lake volume in R (same as 1.8)

**File:** `Package/R/Compute_env_concentrations_v4.R:83`

```r
# BEFORE:
V = HL.Vol_total[HL_index_match] * 1e6
# AFTER:
V = HL.Vol_total[HL_index_match] * 1e9
```

---

## Phase 3: Hydraulic Intersection / Overlap / Merging Improvements

This is the core structural improvement. The current codebase handles river-river, canal-river, and river-lake intersections inconsistently:

| Intersection type | HydroSHEDS | GeoGLOWS | Status |
|---|---|---|---|
| River–river confluence | Coordinate matching (float precision) | DSLINKNO attribute | HydroSHEDS misses due to float rounding |
| Canal–river junction | Not snapped | Snapped to nearest vertex | Neither creates DSLINKNO; canals are dead-ends |
| River–lake crossing | st_intersects on points | Same | Misses when no vertices inside lake polygon |
| Overlapping/collinear segments | Not detected | Not detected | Parallel paths with no connection |
| Multi-tributary fan-in | Only first upstream tagged | Later overwrites earlier | Most tributaries silently dropped |
| Segment split at basin boundary | N/A (no clipping) | Nearest-feature re-attach | Both pieces get same DSLINKNO (wrong) |

### 3.1 Coordinate snapping for HydroSHEDS junction detection

**File:** `Package/R/16_BuildNetworkTopology.R:61, 91-104`
**Problem:** `loc_ID_tmp <- paste0(X, "_", Y)` uses raw floats. Two vertices at the same confluence can differ by 1e-15, producing different strings.
**Fix:** Round coordinates to 1mm precision (~6 decimal places at equator) before building `loc_ID_tmp`.

```r
# BEFORE:
points$loc_ID_tmp <- paste0(points$X, "_", points$Y)

# AFTER: snap to ~1mm grid to handle floating-point drift at confluences
snap_tol <- 1e-6  # degrees (~1mm at equator)
points$loc_ID_tmp <- paste0(round(points$X / snap_tol) * snap_tol, "_",
                            round(points$Y / snap_tol) * snap_tol)
```

### 3.2 Multi-tributary fan-in support

**File:** `Package/R/16_BuildNetworkTopology.R:73-104`
**Problem:** When 3+ segments meet at one confluence, only the first is connected. In GeoGLOWS mode, a second segment with the same `ds_id` overwrites the first.
**Fix:** Collect all upstream segments for each junction node. Instead of a single `ID_nxt`, the junction node accumulates emissions from all upstream branches via `E_up` / `upcount` (which already supports fan-in in the concentration engine).

For HydroSHEDS — tag ALL other_starts as JNCT and wire ALL upstream `ID_nxt` to the junction:

```r
# BEFORE: only first upstream start tagged
if (length(other_starts) > 0) {
  points_df$ID_nxt[last_pt_idx] <- points_df$ID[other_starts[1]]
  points_df$pt_type[other_starts[1]] <- "JNCT"
}

# AFTER: wire ALL upstream segments to the junction
if (length(other_starts) > 0) {
  for (up_idx in other_starts) {
    points_df$ID_nxt[which(points_df$idx_in_line_seg ==
      which(points_df$ARCID == LineIDs[i])[1] &  # first vertex of current segment
      FALSE)] <- points_df$ID[up_idx]  # Note: need to track per-segment first vertex
    points_df$pt_type[up_idx] <- "JNCT"
  }
  points_df$ID_nxt[last_pt_idx] <- points_df$ID[other_starts[1]]
}
```

For GeoGLOWS — accumulate all upstream `ID_nxt` into the junction node's `upcount`:

```r
# BEFORE: single assignment, later overwrites earlier
points_df$ID_nxt[last_pt_idx] <- points_df$ID[ds_first]
points_df$pt_type[ds_first] <- "JNCT"

# AFTER: if another segment already points here, it's a fan-in — just tag it
if (is.na(points_df$ID_nxt[last_pt_idx])) {
  points_df$ID_nxt[last_pt_idx] <- points_df$ID[ds_first]
}
points_df$pt_type[ds_first] <- "JNCT"
```

### 3.3 Canal topology — assign downstream link via spatial matching

**File:** `Package/R/11_PrepareCanalLayers.R:28-38` and `Package/R/16_BuildNetworkTopology.R:73-89`
**Problem:** Canals get `DSLINKNO = NA` and have no downstream connection. They become isolated dead-ends.
**Fix:** After canal snapping (Phase 3.4), find the nearest river segment to the canal's downstream endpoint and assign its LINKNO as the canal's DSLINKNO.

```r
# New logic in PrepareCanalLayers (after snapping in ProcessRiverGeometry):
# For each canal, the downstream end (tail) should connect to a river segment.
# Find the nearest river segment to the snapped tail point and assign its ARCID.
AssignCanalTopology <- function(canals, rivers) {
  for (i in seq_len(nrow(canals))) {
    coords <- sf::st_coordinates(canals[i, ])
    tail_pt <- sf::st_sfc(sf::st_point(coords[nrow(coords), 1:2]),
                          crs = sf::st_crs(rivers))
    # Find nearest river segment
    nearest_idx <- sf::st_nearest_feature(tail_pt, rivers)
    # Assign downstream link
    if ("LINKNO" %in% names(rivers)) {
      canals$DSLINKNO[i] <- rivers$LINKNO[nearest_idx]
    } else if ("ARCID" %in% names(rivers)) {
      # For HydroSHEDS: store the downstream ARCID for coordinate-based matching
      canals$DSLINKNO[i] <- rivers$ARCID[nearest_idx]
    }
  }
  canals
}
```

### 3.4 Canal snapping — move out of GeoGLOWS-only branch

**File:** `Package/R/12_ProcessRiverGeometry.R:66-91`
**Problem:** Canal endpoint snapping only runs inside the `if ("LINKNO" %in% names(...))` branch. HydroSHEDS basins with canals never get snapped.
**Fix:** Move the canal snapping logic outside the GeoGLOWS branch so it runs for all network sources.

```r
# Move this block from inside the LINKNO branch to AFTER both branches merge:
if ("is_canal" %in% names(hydro_sheds_rivers_basin)) {
  canal_mask <- !is.na(hydro_sheds_rivers_basin$is_canal) &
                hydro_sheds_rivers_basin$is_canal
  if (any(canal_mask)) {
    # ... existing snapping logic (unchanged) ...
  }
}
# Place after line 98 (the else branch for HydroSHEDS)
```

### 3.5 Canal ARCID preservation when `lines$ARCID <- lines$LINKNO`

**File:** `Package/R/16_BuildNetworkTopology.R:34`
**Problem:** `lines$ARCID <- lines$LINKNO` sets canal ARCID to NA because canals have no LINKNO.
**Fix:** Preserve existing ARCID for rows where LINKNO is NA.

```r
# BEFORE:
lines$ARCID <- lines$LINKNO

# AFTER: only overwrite ARCID for rows that have a valid LINKNO
lines$ARCID <- ifelse(is.na(lines$LINKNO), lines$ARCID, lines$LINKNO)
```

### 3.6 River-lake crossing detection — segment intersection fallback

**File:** `Package/R/17_ConnectLakesToNetwork.R:100-109`
**Problem:** `st_intersects(points, HL_basin)` only tests point-in-polygon. If a river crosses a lake but no vertices fall inside, the lake is missed entirely.
**Fix:** After the point-in-polygon test, also test river segment–lake polygon intersections. For each lake that has zero interior points but is intersected by a river segment, compute the crossing points and create synthetic inlet/outlet nodes.

```r
# AFTER the point-in-polygon loop, for lakes with zero interior nodes:
for (lake_idx in seq_len(nrow(HL_basin))) {
  hylak_id <- HL_basin$Hylak_id[lake_idx]
  if (hylak_id %in% unique(points$HL_ID_new[points$HL_ID_new > 0])) next

  # Test if any river segment crosses this lake polygon
  lake_geom <- HL_basin[lake_idx, ]
  crossing_segs <- sf::st_intersects(lines, lake_geom, sparse = TRUE)
  segs_with_crossing <- which(lengths(crossing_segs) > 0)

  if (length(segs_with_crossing) > 0) {
    # Compute the intersection point(s) of each segment with the lake boundary
    for (seg_i in segs_with_crossing) {
      seg_geom <- lines[seg_i, ]
      crossing_pts <- sf::st_intersection(seg_geom, lake_geom)
      if (!is.null(crossing_pts) && nrow(crossing_pts) > 0) {
        # Add crossing point as a new node, tag with HL_ID_new
        # The upstream crossing becomes the inlet, downstream becomes outlet
        message(">>> Lake ", hylak_id, ": detected river crossing via segment intersection")
        # ... insert new node at crossing point ...
      }
    }
  }
}
```

### 3.7 Split-segment DSLINKNO correction after basin clipping

**File:** `Package/R/12_ProcessRiverGeometry.R:49-57`
**Problem:** When `st_intersection` splits a segment at the basin boundary, both pieces inherit the same `DSLINKNO` via nearest-feature matching. The downstream piece may need a different (or no) downstream link.
**Fix:** After re-attaching attributes, check if a segment's `DSLINKNO` points outside the basin. If so, check if the split created a downstream piece — if so, point to it instead; otherwise, set to `-1` (terminal).

```r
# After the nearest-feature re-attachment loop:
if ("DSLINKNO" %in% names(hydro_sheds_rivers_basin)) {
  basin_linknos <- as.character(hydro_sheds_rivers_basin$LINKNO)
  for (i in seq_len(nrow(hydro_sheds_rivers_basin))) {
    ds_id <- hydro_sheds_rivers_basin$DSLINKNO[i]
    if (!is.na(ds_id) && !(as.character(ds_id) %in% basin_linknos)) {
      # Downstream segment was clipped away — check for a split partner
      # that shares the same original segment's tail coordinates
      coords_i <- sf::st_coordinates(hydro_sheds_rivers_basin[i, ])
      tail_i <- coords_i[nrow(coords_i), 1:2]
      for (j in seq_len(nrow(hydro_sheds_rivers_basin))) {
        if (i == j) next
        coords_j <- sf::st_coordinates(hydro_sheds_rivers_basin[j, ])
        head_j <- coords_j[1, 1:2]
        if (all(abs(tail_i - head_j) < 1e-6)) {
          hydro_sheds_rivers_basin$DSLINKNO[i] <- hydro_sheds_rivers_basin$LINKNO[j]
          break
        }
      }
      # If no split partner found, this is a basin outlet
      if (!(as.character(ds_id) %in% basin_linknos) &&
          hydro_sheds_rivers_basin$DSLINKNO[i] == ds_id) {
        hydro_sheds_rivers_basin$DSLINKNO[i] <- -1
      }
    }
  }
}
```

### 3.8 Overlapping/collinear segment deduplication

**Currently:** No code detects overlapping segments. Two digitisations of the same river create parallel paths.
**Improvement:** Before topology construction, detect and merge collinear overlapping segments.

```r
DeduplicateOverlappingSegments <- function(rivers, snap_tol = 10) {
  utm_crs <- sf::st_crs(rivers)  # assume already in projected CRS
  if (is.na(utm_crs)) utm_crs <- 3857  # fallback to web mercator
  rivers_utm <- sf::st_transform(rivers, utm_crs)

  # Compute pairwise buffer-intersection matrix
  buffers <- sf::st_buffer(rivers_utm, dist = snap_tol)
  overlaps <- sf::st_intersects(buffers, sparse = TRUE)

  merged <- rep(TRUE, nrow(rivers))  # TRUE = keep
  for (i in seq_len(nrow(rivers))) {
    if (!merged[i]) next
    partners <- overlaps[[i]]
    partners <- setdiff(partners, i)
    for (j in partners) {
      if (!merged[j]) next
      # Check if segments are roughly collinear by comparing midpoints
      mid_i <- sf::st_centroid(rivers_utm[i, ])
      mid_j <- sf::st_centroid(rivers_utm[j, ])
      dist_m <- as.numeric(sf::st_distance(mid_i, mid_j))
      if (dist_m < snap_tol) {
        # Merge: keep the longer segment
        len_i <- as.numeric(sf::st_length(rivers_utm[i, ]))
        len_j <- as.numeric(sf::st_length(rivers_utm[j, ]))
        if (len_j > len_i) {
          merged[i] <- FALSE
        } else {
          merged[j] <- FALSE
        }
      }
    }
  }
  rivers[merged, ]
}
```

Call this in `BuildNetworkPipeline` before `BuildNetworkTopology`.

---

## Phase 4: R Engine — Data Integrity Fixes

### 4.1 `selected_flow_data` undefined in GeoGLOWS path

**File:** `Package/R/21_AssignHydrology.R:83`
**Problem:** `selected_flow_data` is only created in the HydroSHEDS `else` branch (line 45) but referenced at line 83 unconditionally.
**Fix:** Guard the reference with a flag.

```r
# BEFORE:
if (prefer_highres_flow && is_dry_season && selected_flow_data$flow_source != "qmi") {

# AFTER:
flow_source <- if (network_source == "geoglows") "geoglows" else selected_flow_data$flow_source
if (prefer_highres_flow && is_dry_season && flow_source != "qmi") {
```

### 4.2 `exists()` checks wrong environment

**File:** `Package/R/19_SaveNetworkArtifacts.R:101`
**Problem:** `exists("hl_df")` defaults to `parent.frame()`, not the function's local scope. Always returns FALSE when `hl_df` is defined locally.
**Fix:**

```r
# BEFORE:
HL = if (exists("hl_df")) hl_df else NULL

# AFTER: check the function's own environment
HL = if (exists("hl_df", envir = environment())) hl_df else NULL
```

### 4.3 Hardcoded UTM zone 31N

**File:** `Package/R/20_NormalizeScenarioState.R:52`
**Problem:** All basins are projected to EPSG:32631 regardless of actual location. Bega (Romania, zone 34) gets wrong projection.
**Fix:** Use the `GetUtmCrs()` utility that already exists in `00_utils.R`.

```r
# BEFORE:
pts_utm_sf <- sf::st_as_sf(pts_utm, coords = c("x", "y"), crs = 32631)

# AFTER: accept utm_crs from config, auto-detect from coordinates, or use GetUtmCrs
target_crs <- if (!is.null(network_nodes) && "geometry" %in% names(network_nodes)) {
  sf::st_crs(network_nodes)
} else {
  # Fallback: infer from coordinate range
  mean_lon <- mean(pts_utm$x, na.rm = TRUE)
  zone <- floor((mean_lon + 180) / 6) + 1
  epsg <- if (mean_y > 0) 32600 + zone else 32700 + zone
  epsg
}
pts_utm_sf <- sf::st_as_sf(pts_utm, coords = c("x", "y"), crs = target_crs)
```

### 4.4 `Dist_down` propagates from upstream instead of downstream

**File:** `Package/R/01_AddFlowToBasinData.R:311-313`
**Problem:** `pts$ID_nxt %in% pts$ID[i]` finds nodes whose downstream is `i` (upstream nodes), not the downstream neighbor.
**Fix:**

```r
# BEFORE: copies from upstream (wrong direction)
if (!is.na(pts$Dist_down[pts$ID_nxt %in% pts$ID[i] & pts$basin_id %in% pts$basin_id[i]])) {
  pts$Dist_down[i] <- pts$Dist_down[pts$ID_nxt %in% pts$ID[i] & pts$basin_id %in% pts$basin_id[i]]

# AFTER: copies from the actual downstream neighbor
if (!is.na(pts$ID_nxt[i])) {
  ds_idx <- match(pts$ID_nxt[i], pts$ID)
  if (!is.na(ds_idx) && !is.na(pts$Dist_down[ds_idx])) {
    pts$Dist_down[i] <- pts$Dist_down[ds_idx]
  }
}
```

### 4.5 NA crash in JNCT check

**File:** `Package/R/01_AddFlowToBasinData.R:250`
**Problem:** `if(pts$Down_type[i]=="JNCT")` throws error when `Down_type` is NA.
**Fix:**

```r
# BEFORE:
if(pts$Down_type[i]=="JNCT"){

# AFTER:
if(!is.na(pts$Down_type[i]) && pts$Down_type[i]=="JNCT"){
```

### 4.6 `stop(cat(...))` produces empty error message

**File:** `Package/R/00_Check_cons_v2.R:8`

```r
# BEFORE:
stop(cat("Prediction not possible...", unique(pts$basin_id), "\n"))

# AFTER: cat returns NULL; stop() on NULL gives empty message. Use paste() instead.
stop("Prediction not possible due to absence of contaminant source in the domains: ",
     paste(unique(pts$basin_id), collapse = ", "))
```

### 4.7 `alpha_range` out-of-bounds for extreme lambda values

**File:** `Package/R/02_CompleteChemProperties.R:133-135`

```r
# BEFORE:
idx <- findInterval(chem$lambda_solar_n[i], lambda_range)
chem$alpha_n[i] <- alpha_range[idx]

# AFTER: clamp index to valid range [1, length(alpha_range)]
idx <- findInterval(chem$lambda_solar_n[i], lambda_range)
idx <- pmax(1, pmin(idx, length(alpha_range)))
chem$alpha_n[i] <- alpha_range[idx]
```

### 4.8 DOC unit mismatch documentation

**File:** `Package/R/02_PathogenModel.R:155`
**Problem:** Comment says `C_DOC` is in kg/L but `calc_light_attenuation` expects mg/L (multiplied by `kd` in L/(mg·m)). Default `0.005e-3` kg/L = 5 mg/L — the numeric default is correct for mg/L but the comment is wrong.
**Fix:** Correct the comment; no code change needed.

```r
# BEFORE:
doc <- get_val(network_nodes, "doc_concentration", "C_DOC", 0.005e-3)  # kg/L

# AFTER:
doc <- get_val(network_nodes, "doc_concentration", "C_DOC", 0.005e-3)  # kg/L (= 5 mg/L)
# Note: calc_light_attenuation multiplies by kd [L/(mg*m)], so if data is in kg/L,
# divide by 1e-3 to convert to mg/L before passing.
doc <- doc / 1e-3  # kg/L -> mg/L
```

Wait — actually the default `0.005e-3` kg/L IS 5 mg/L, and the formula expects mg/L. So if the data IS in kg/L, we need to convert. If the data is already in mg/L, the default should be `5` not `0.005e-3`. This needs verification against the actual data files. For safety, add both a conversion and a unit assertion:

```r
# Detect and convert: if values are < 0.01, assume kg/L; if >= 0.01, assume mg/L
if (max(doc, na.rm = TRUE) < 0.01) {
  message("  DOC values < 0.01 detected — assuming kg/L, converting to mg/L")
  doc <- doc * 1e3  # kg/L -> mg/L
}
```

---

## Phase 5: Minor but Impactful Fixes

### 5.1 Bega default temperature

**File:** `Package/inst/config/basins/bega.R:10`
**Problem:** `default_temp = 27.5` is tropical (Volta). Bega (Romania) should be ~11°C.

```r
# BEFORE:
default_temp = 27.5,
# AFTER:
default_temp = 11.0,
```

### 5.2 Lake depth default

**File:** `Package/R/02_PathogenModel.R:173`
**Problem:** `depth_l <- get_val(lake_nodes, "river_depth", "H_av", 0.001)` — 1mm default causes extreme sedimentation.

```r
# BEFORE:
depth_l <- get_val(lake_nodes, "river_depth", "H_av", 0.001)
# AFTER: use 3m as a realistic default lake depth
depth_l <- get_val(lake_nodes, "river_depth", "H_av", 3.0)
```

### 5.3 Missing `units` field on cryptosporidium

**File:** `Package/inst/pathogen_input/cryptosporidium.R`
Add `units = "oocysts/L"` to the parameter list.

### 5.4 `excretion_rate` documentation fix

**File:** `Package/R/00_substance_abstraction.R:26`
Change comment from `[org/day]` to `[org/year]`.

### 5.5 Remove duplicate `ePiEPath()` definition

**Files:** `Package/R/01_LoadBasins.R:16` and `Package/R/01_LoadLongTermFlow.R:66`
Remove one; keep the definition in `00_utils.R`.

### 5.6 Scenario registry deduplication

**File:** `Package/R/30_LoadScenarioConfig.R`
Extract the 29-element vector to a shared constant used by both `LoadScenarioConfig` and `ListScenarios`.

### 5.7 `std::cout` → `Rcpp::Rcout`

**File:** `Package/src/compenvcons_v4.cpp:251-252`

```cpp
// BEFORE:
std::cout << "# points in pts: " << pts_not_finished << std::endl;
// AFTER:
Rcpp::Rcout << "# points in pts: " << pts_not_finished << std::endl;
```

---

## Phase 6: Test Coverage Gaps

### 6.1 Unit test for `AssignPathogenEmissions`
- Test with 1 WWTP + 1 agglomeration: verify per-node emission magnitudes
- Test with 2 WWTPs: verify total emission does not exceed basin production
- Test WWTP removal: verify `f_rem_WWTP` applied correctly for primary-only, secondary-only, both

### 6.2 Unit test for `Compute_env_concentrations_v4` (synthetic 3-node network)
- 3 nodes: START → JNCT → MOUTH, with known Q and emissions
- Verify C_w at each node matches hand-calculated values
- Test lake CSTR with known V and k

### 6.3 Pathogen regression golden master
- Run Volta Wet Crypto on pre-built network, store results
- Compare against stored results in future runs

### 6.4 Plausible-range assertions in E2E tests
- After computing C_w, assert `all(C_w > 0, na.rm = TRUE) && all(C_w < 1e10, na.rm = TRUE)`

---

## Commit Plan

| Commit | Description | Files |
|--------|-------------|-------|
| 1 | `fix(cpp): safe which() with -1 sentinel, OOB guards at all call sites` | `src/compenvcons_v4.cpp`, `src/calc_topology.cpp` |
| 2 | `fix(cpp): division-by-zero guards for Q, V_NXT, k_sw, H_sed` | `src/compenvcons_v4.cpp` |
| 3 | `fix(cpp+R): lake volume conversion 1e6 → 1e9 (km³ to m³)` | `src/compenvcons_v4.cpp`, `R/Compute_env_concentrations_v4.R` |
| 4 | `fix(R): pathogen lake CSTR unit conversion (*1000 → /1000)` | `R/Compute_env_concentrations_v4.R` |
| 5 | `fix(R): WWTP emission uses per-node population instead of basin total` | `R/02_PathogenModel.R` |
| 6 | `fix(R): hardcoded UTM zone 31N → auto-detect from coordinates` | `R/20_NormalizeScenarioState.R` |
| 7 | `fix(R): Dist_down propagation direction, NA guards, stop(cat())` | `R/01_AddFlowToBasinData.R`, `R/00_Check_cons_v2.R` |
| 8 | `fix(R): selected_flow_data undefined in GeoGLOWS path` | `R/21_AssignHydrology.R` |
| 9 | `fix(R): exists() environment scope in SaveNetworkArtifacts` | `R/19_SaveNetworkArtifacts.R` |
| 10 | `fix(R): alpha_range OOB clamp, SimpleTreat division guard` | `R/02_CompleteChemProperties.R`, `R/02_RunSimpleTreat4.R` |
| 11 | `fix(topology): coordinate snapping for HydroSHEDS junctions` | `R/16_BuildNetworkTopology.R` |
| 12 | `fix(topology): multi-tributary fan-in support` | `R/16_BuildNetworkTopology.R` |
| 13 | `fix(topology): canal ARCID preservation and DSLINKNO assignment` | `R/11_PrepareCanalLayers.R`, `R/16_BuildNetworkTopology.R` |
| 14 | `fix(topology): canal snapping for all network sources` | `R/12_ProcessRiverGeometry.R` |
| 15 | `fix(topology): split-segment DSLINKNO correction after clipping` | `R/12_ProcessRiverGeometry.R` |
| 16 | `feat(topology): river-lake crossing detection via segment intersection` | `R/17_ConnectLakesToNetwork.R` |
| 17 | `feat(topology): overlapping segment deduplication` | `R/00_utils.R`, `R/31_BuildNetworkPipeline.R` |
| 18 | `fix(config): Bega default temp, crypto units, excretion docs` | `inst/config/basins/bega.R`, `inst/pathogen_input/cryptosporidium.R`, `R/00_substance_abstraction.R` |
| 19 | `fix(config): lake depth default, DOC unit detection` | `R/02_PathogenModel.R` |
| 20 | `refactor: remove duplicate ePiEPath, dedup scenario registry` | `R/01_LoadBasins.R`, `R/01_LoadLongTermFlow.R`, `R/30_LoadScenarioConfig.R` |
| 21 | `test: pathogen emission unit tests, CSTR tests, range assertions` | `tests/testthat/` |
| 22 | `test: regression golden master for pathogen scenario` | `tests/testthat/` |

---

## Phase 7: Repository Cleanup — Remove Large Data Files from Git History

The `.git` folder is **1.6 GB** because large binary files (7z archives, CSV exports,
fst files, zip archives) were committed to the history in early commits. These files are
still present in old commit objects even though `Inputs/` and `Builds/` are now in `.gitignore`.

**Top offenders in git object store:**
- `data_export_2025_08_15.7z.001` through `.006` — 6 × 80 MB split 7z archives (480 MB)
- `pts_c75.fst` — 75 MB
- `ePiE_1.25.tar.gz`, `ePiE_1.25.zip`, etc. — build artifacts (170+ MB)
- 152 individual CSV export files — basin-wide discharge data (hundreds of MB)

### 7.1 Aggressive `.gitignore`

Add patterns for all binary data formats that should never be committed:

```gitignore
# --- Binary data (never commit) ---
*.7z
*.zip
*.tar.gz
*.tgz
*.fst
*.csv
*.xlsx
*.xls
*.shp
*.shx
*.dbf
*.prj
*.cpg
*.gpkg
*.tif
*.tiff
*.nc
*.pdf
*.html
*.rds
*.RData
*.png
*.jpg
*.jpeg
```

Note: `Outputs/`, `Inputs/`, and `Builds/` directories are already ignored. The file-type
patterns above are a safety net for any data files that accidentally land outside those dirs.

### 7.2 `setup-data.sh` — Download Script

Create a script at `scripts/setup-data.sh` that a new user runs once after cloning.
It downloads the required input data from a shared drive (e.g., VU SurfDrive or GitHub
Releases). The script:

1. Creates `Inputs/basins/`, `Inputs/baselines/`, `Inputs/user/`
2. Downloads each archive from the configured URL
3. Extracts to the correct subdirectory
4. Verifies file presence with checksums

```bash
#!/usr/bin/env bash
# setup-data.sh — Download and extract ePiE input data
set -euo pipefail

DATA_ROOT="${1:-Inputs}"
BASE_URL="${DATA_URL:-https://surfdrive.surf.nl/files/TODO}"
echo ">>> Downloading ePiE input data to ${DATA_ROOT}/ ..."

mkdir -p "${DATA_ROOT}/basins" "${DATA_ROOT}/baselines" "${DATA_ROOT}/user"

download_and_extract() {
  local url="$1" dest="$2"
  echo "  Downloading: $(basename "$url")"
  curl -fSL -o /tmp/ePie_data_tmp "$url"
  tar xzf /tmp/ePie_data_tmp -C "$dest"
  rm -f /tmp/ePie_data_tmp
}

# HydroSHEDS baselines (flow direction, river network)
# download_and_extract "${BASE_URL}/baselines_hydrosheds.tar.gz" "${DATA_ROOT}/baselines"

# Environmental rasters (temperature, wind, flow)
# download_and_extract "${BASE_URL}/baselines_environmental.tar.gz" "${DATA_ROOT}/baselines"

# Volta basin data
# download_and_extract "${BASE_URL}/basins_volta.tar.gz" "${DATA_ROOT}/basins/volta"

# Bega basin data
# download_and_extract "${BASE_URL}/basins_bega.tar.gz" "${DATA_ROOT}/basins/bega"

# User data (WWTP locations, chemical properties)
# download_and_extract "${BASE_URL}/user_data.tar.gz" "${DATA_ROOT}/user"

echo ">>> Setup complete. Verify by running: R CMD INSTALL Package"
```

The actual URLs are placeholder — they need to be populated once the data is uploaded
to SurfDrive, Google Drive, or GitHub Releases (large file storage).

### 7.3 Clean Git History with `git-filter-repo`

After updating `.gitignore`, purge all historical binary data:

```bash
# 1. Remove all binary data file types from the entire history
git filter-repo \
  --invert-paths \
  --path-glob '*.7z' \
  --path-glob '*.fst' \
  --path-glob '*.zip' \
  --path-glob '*.tar.gz' \
  --path-glob '*.tgz' \
  --path-glob 'Builds/' \
  --path-glob 'Inputs/2024_12_10/' \
  --path-glob 'Inputs/2025_08_29/'

# 2. Force garbage collection to actually free the space
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Expected result: .git shrinks from ~1.6 GB to ~50 MB
```

**Important:** This rewrites history. All commit hashes will change. Force-push required:
`git push --force origin main`. Coordinate with any collaborators before doing this.

### 7.4 Commit Plan (Phase 7)

| Commit | Description | Files |
|--------|-------------|-------|
| 23 | `chore: aggressive .gitignore for binary data formats` | `.gitignore` |
| 24 | `chore: add setup-data.sh for first-time data download` | `scripts/setup-data.sh` |
| 25 | `chore: remove large binary files from git history` | (history rewrite, no file changes) |
