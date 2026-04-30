# Internal Schema Refactor Plan

## Purpose

This note is a durable handoff for a future refactor to reduce repeated table
column initialization in ePiE. It should be executed after the current KIS canal
Q provenance work has been merged to `main`.

The specific problem is repeated ad hoc initialization of columns such as:

```r
points$Q_design_m3s <- NA_real_
points$Q_model_m3s <- NA_real_
points$Q_source <- NA_character_
points$Q_source_id <- NA_character_
```

This makes the code harder to audit because table shape is spread across many
functions instead of being defined in one place.

## Decision

Use an internal schema/normalization system only.

Do not add new dependencies to `Package/DESCRIPTION`.

Do not add `checkmate` for this first refactor. It is useful for assertions, but
the current need is a package-local table contract.

Do not add `validate` for this first refactor. It is better suited to later
scientific audit reports than core runtime normalization.

## Context Recovery Before Editing

Start from a clean `main` branch after the KIS canal Q provenance work is merged.

Confirm that the KIS provenance work is present:

```bash
test -f Package/inst/config/canal_q_sources/kis_canal_q_sources.csv
test -f Package/R/24_ProvenanceExports.R
Rscript -e 'library(pkgload); pkgload::load_all("Package", quiet = TRUE); stopifnot(length(ListScenarios()) == 33)'
```

Find the current duplication before editing:

```bash
rg -n "Q_design_m3s <-|Q_model_m3s <-|Q_source_id <-|EnsureColumns\\(" Package/R
```

## Implementation Target

Add `Package/R/00_schema.R` with these internal helpers:

- `NetworkNodeSchema()`
- `TransportEdgeSchema()`
- `LakeConnectionSchema()`
- `NormalizeTableSchema(df, schema, label, keep_extra = TRUE)`
- `ValidateTableSchema(df, schema, label)`
- `ValidateNetworkNodeInvariants(points, stage)`

Each schema entry should define:

- `column`
- `type`
- `default`
- `required`
- `description`

`NormalizeTableSchema()` must:

- add missing columns with typed defaults;
- coerce existing columns to the declared type;
- preserve `sf` geometry when present;
- keep extra columns by default for backward compatibility.

`ValidateTableSchema()` must:

- fail clearly on missing required columns;
- check that normalized columns have the declared type.

`ValidateNetworkNodeInvariants()` must hold domain-specific checks that are not
simple type checks.

## Network Node Schema Columns

Define canal Q and provenance columns once in `NetworkNodeSchema()`:

- `Q_design_m3s`
- `Q_model_m3s`
- `Q_source`
- `Q_source_id`
- `Q_reference_short`
- `Q_reference_url`
- `Q_regime`
- `Q_data_period`
- `Q_season`
- `Q_value_origin`
- `Q_derivation_rule`
- `Q_source_note`
- `Q_role`
- `Q_parent_m3s`
- `Q_out_sum_m3s`
- `Q_residual_m3s`

The schema should also include common node columns that are repeatedly required
by hydrology, transport, and visualization, including:

- `ID`
- `ID_nxt`
- `x`
- `y`
- `Pt_type`
- `pt_type`
- `basin_id`
- `is_canal`
- `Hylak_id`
- `HL_ID_new`
- `lake_in`
- `lake_out`
- `dist_nxt`
- `d_nxt`

## Replacement Pattern

Replace repeated direct initialization with:

```r
points <- NormalizeTableSchema(points, NetworkNodeSchema(), "network nodes")
```

Use targeted validation at stage boundaries:

```r
ValidateNetworkNodeInvariants(points, stage = "after_canal_q_assignment")
ValidateNetworkNodeInvariants(points, stage = "before_hydrology")
```

## Pipeline Boundaries

Apply normalization at these stable boundaries:

- after topology/node creation;
- before source integration and `rbind` operations;
- after canal annotation;
- before hydrology assignment;
- before transport edge construction;
- before CSV export.

Keep validation stage-specific:

- early network build allows canal Q fields to be `NA`;
- after canal Q assignment, every `is_canal == TRUE` node must have finite
  `Q_model_m3s`;
- before hydrology, canal `Q_model_m3s` must be finite and non-negative;
- before edge transport, every edge endpoint must exist in `points$ID`.

## Tests To Add

Add unit tests for schema helpers:

- missing numeric, character, and logical columns are created with typed
  defaults;
- existing columns are coerced safely;
- extra columns are preserved;
- `sf` geometry is preserved.

Add regression tests:

- a minimal node table normalizes to include canal Q/provenance fields;
- canal nodes fail post-Q-assignment validation when `Q_model_m3s` is missing;
- river nodes may keep `Q_model_m3s = NA`;
- transport edges fail validation when `from_id` or `to_id` does not exist in
  the node table.

## Validation Commands

Run these commands after implementation:

```bash
R CMD INSTALL Package
Rscript scripts/smoke-test.R
Rscript -e 'library(pkgload); pkgload::load_all("Package", quiet = TRUE); library(testthat); test_file("Package/tests/testthat/test-canal-q-source-config.R")'
Rscript -e 'library(pkgload); pkgload::load_all("Package", quiet = TRUE); library(testthat); test_file("Package/tests/testthat/test-transport-edges.R")'
Rscript -e 'library(pkgload); pkgload::load_all("Package", quiet = TRUE); library(testthat); test_file("Package/tests/testthat/test-lake-segment-crossings.R")'
Rscript -e 'library(pkgload); pkgload::load_all("Package", quiet = TRUE); library(testthat); test_file("Package/tests/testthat/test-e2e-volta-network.R", stop_on_failure = TRUE)'
Rscript -e 'library(pkgload); pkgload::load_all("Package", quiet = TRUE); cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs"); state <- cfg; state$points <- read.csv(cfg$input_paths$pts, stringsAsFactors = FALSE); state$hl <- read.csv(cfg$input_paths$hl, stringsAsFactors = FALSE); state$HL_basin <- state$hl; state$data_root <- cfg$dataDir; RunSimulationPipeline(state, cfg$target_substance, cpp = FALSE)'
```

## Acceptance Criteria

- No new package dependency is added.
- The refactor does not change model outputs intentionally.
- Repeated canal Q/provenance initialization is replaced by schema
  normalization.
- Canal hydrology still fails clearly if any canal node lacks finite
  `Q_model_m3s` before hydrology.
- Existing CSV outputs keep their current columns.
- Existing extra columns are not dropped by normalization.
- The validation commands above pass.
