# Pathogen Profile Methods

## Purpose

Pathogen emissions must not reuse one region's epidemiological assumptions in another basin. The model now separates pathogen biology from area-specific emission profiles:

- `Package/inst/pathogen_input/<pathogen>.R`: pathogen biology, decay, settling, and legacy defaults used by direct developer calls.
- `Package/inst/pathogen_profiles/pathogen_profiles.R`: area-specific prevalence, excretion, WWTP removal, units, country/region, source URLs, and data-period notes.

Scenario runs use strict profile selection. If a pathogen scenario cannot resolve a compatible profile, it stops before emissions are calculated.

## Current Profile Sets

| Profile set | Basin/country | Intended use |
|---|---|---|
| `ghana_ssa_screening` | Volta / Ghana (`GH`) | Ghana/Sub-Saharan-Africa screening setup |
| `romania_eu_screening` | Bega / Romania (`RO`) | Romania/Europe screening setup |

These are screening profiles, not final calibrated epidemiological products. Values with `screening_requires_calibration` should be replaced when local prevalence, wastewater, or clinical-surveillance-derived shedding estimates are available.

## Code Path

1. `LoadScenarioConfig()` applies scientific defaults and sets `pathogen_profile_set` plus `pathogen_profile_policy = "strict"` for pathogen scenarios.
2. `RunSimulationPipeline()` carries those fields in state.
3. `InitializeSubstance()` calls `LoadPathogenParameters()` with the profile settings.
4. `ResolvePathogenProfile()` selects one profile from the registry.
5. `ApplyPathogenProfile()` overlays profile prevalence, excretion, WWTP removal, and units onto the base pathogen parameters.
6. `AssignPathogenEmissions()` uses the resolved profile values and writes profile metadata into node outputs.
7. `ExportPathogenProvenance()` writes `pathogen_provenance_summary.csv`.

## References Encoded In The Initial Registry

- Vermeulen et al. (2019), *Cryptosporidium concentrations in rivers worldwide*, Water Research. https://pubmed.ncbi.nlm.nih.gov/30447525/
- Imre et al. (2017), *Survey of the Occurrence and Human Infective Potential of Giardia duodenalis and Cryptosporidium spp. in Wastewater and Different Surface Water Sources of Western Romania*. https://pubmed.ncbi.nlm.nih.gov/28832257/
- ECDC Annual Epidemiological Reports. https://www.ecdc.europa.eu/en/publications-data/monitoring/all-annual-epidemiological-reports
- ECDC Campylobacteriosis Annual Epidemiological Report. https://www.ecdc.europa.eu/en/publications-data/campylobacteriosis-annual-epidemiological-report-2019
- Kiulia et al. (2015), *Global Occurrence and Emission of Rotaviruses to Surface Waters*. https://www.mdpi.com/2076-0817/4/2/229
- Karikari et al. (2016), *Occurrence and susceptibility patterns of Campylobacter isolated from environmental water sources*. https://doi.org/10.5897/AJMR2016.8296
- Ghana giardiasis scoping review record. https://pure.ug.edu.gh/en/publications/human-giardiasis-in-ghana-a-scoping-review-of-studies-from-2004-t/

## Validation Commands

```bash
R CMD INSTALL Package
Rscript scripts/smoke-test.R
Rscript -e 'library(testthat); library(ePiE); test_file("Package/tests/testthat/test-pathogen-profiles.R")'
Rscript -e 'library(testthat); library(ePiE); test_file("Package/tests/testthat/test-pathogen-formulas.R")'
Rscript -e 'library(testthat); library(ePiE); test_file("Package/tests/testthat/test-e2e-volta-crypto.R")'
```

For release validation, also run one Bega pathogen scenario and one Volta pathogen scenario and inspect `pathogen_provenance_summary.csv`.

## VS Code Debugging

The workspace `.vscode/` files provide reproducible debug entry points:

- `R: Test Pathogen Profiles` runs the profile selection tests with local `Package/` source loaded by `pkgload`.
- `R: Validate Profile Scenario Defaults` confirms Bega resolves `romania_eu_screening` and Volta resolves `ghana_ssa_screening`.
- `Debug: Bega Crypto Profile Simulation` and `Debug: Volta Wet Crypto Profile Simulation` run targeted simulations from existing `pts.csv`/`HL.csv` and write to temporary output directories.

The R path is set to `/Library/Frameworks/R.framework/Resources/bin` for this workstation. If R is installed elsewhere, update `.vscode/settings.json` and `.vscode/tasks.json` together.
