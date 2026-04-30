# KIS Canal Q Source Methods

This note documents how Kpong Irrigation Scheme (KIS) canal discharge is selected, assigned, and exported in ePiE.

## Why This Exists

KIS canal hydraulics can differ by source, year, season, and interpretation. The model therefore treats canal Q as a scenario choice, not as a hidden hard-coded constant.

The active choice is controlled by `canal_q_source_id` in scenario configuration. The source registry is:

`Package/inst/config/canal_q_sources/kis_canal_q_sources.csv`

## Supported Source IDs

| source_id | Use | Reference |
|---|---|---|
| `jica_2012_peak` | Default KIS peak/reference discharge interpretation | JICA 2012 |
| `jica_2012_average` | Average-regime approximation using JICA scheme average-to-peak ratio | JICA 2012 |
| `legacy_nllc_sllc` | Preserved pre-refactor comparison system | ePiE legacy model table |

## Main Reference

Japan International Cooperation Agency (JICA). 2012. *Preparatory Survey on the Eastern Corridor Development Project in the Republic of Ghana*. Section 4.4.2, irrigation canals.

URL: <https://openjicareport.jica.go.jp/pdf/12085874_01.pdf>

The report gives KIS scheme-level and canal-section discharge information, including peak discharge, annual average intake volume/discharge, and section-specific canal discharge descriptions.

## Code Pathway

1. `LoadScenarioConfig()` fills default scientific settings, including `canal_q_source_id`.
2. `PrepareCanalLayers()` calls `AssignCanalDischarge()`.
3. `AssignCanalDischarge()` selects rows from the source registry and attaches section head/tail Q plus provenance to each canal line.
4. `AnnotateCanalTopology()` computes canal `chainage_m` and interpolates node-level `Q_design_m3s` / `Q_model_m3s`.
5. `ApplyCanalMassBalance()` enforces branch mass balance and records parent/outgoing/residual Q diagnostics.
6. `AssignHydrology()` uses canal `Q_model_m3s` for canal hydraulics and stops if a canal node lacks Q.
7. `ExportRunProvenance()` and `ExportCanalQAssignmentSummary()` write reviewer-facing provenance outputs.

## Output Files To Check

| Output | What To Check |
|---|---|
| `pts.csv` | node-level `Q_model_m3s`, `Q_source_id`, `Q_regime`, `Q_derivation_rule` |
| `canal_edges.csv` | branch/reach Q and flow fractions |
| `canal_q_diagnostics.csv` | branch mass balance |
| `canal_q_assignment_summary.csv` | final Q by canal section with citation/provenance |
| `run_provenance_summary.csv` | active source ID, citation tag, URL, period, and layer paths |

## Scientific Defaults

- Default KIS source: `jica_2012_peak`
- Comparison source: `legacy_nllc_sllc`
- Average-regime approximation: `jica_2012_average`
- Map variants: both `linear` and `log10`

Any future literature source should be added as new rows in the registry with a new `source_id`, full citation, URL, year/period, regime, value origin, and derivation rule.
