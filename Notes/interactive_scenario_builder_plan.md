# Interactive Scenario Builder Plan

## Summary

This note documents a future terminal-based interactive scenario builder. It is
documentation only: no builder behavior, scenario registry, or test code is
changed by this note.

## Current State

- `scripts/create_scenario_template.R` supports non-interactive scenario
  template generation.
- `CreateScenarioTemplate()` can either:
  - copy the structure of an existing scenario with `--copy-from`, or
  - build a template from explicit `--basin`, `--type`, and `--target` flags.
- Generated scenarios are draft constructors. They still need scientific review
  before use, especially for hydrology source, pathogen profile, canal Q source,
  lake transport mode, and output naming.
- Generated scenarios are not automatically registered in
  `LoadScenarioConfig()` / `ListScenarios()`.

## Goal

Add an interactive mode:

```bash
Rscript scripts/create_scenario_template.R --interactive
```

The interactive mode should ask terminal questions instead of requiring
`--copy-from` or all constructor flags. Existing non-interactive commands must
remain backward compatible.

## Interactive Questions

The wizard should ask, in order:

1. Scenario name.
2. Basin:
   - `bega`
   - `volta`
   - `volta_geoglows`
3. Scenario kind:
   - `network`
   - `chemical`
   - `pathogen`
4. Season or network source where relevant:
   - wet
   - dry
   - GeoGLOWS wet/dry when using GeoGLOWS.
5. Target substance:
   - pathogen choices discovered from `Package/inst/pathogen_input/*.R`;
   - chemical choices discovered from `Inputs/user/chem_Oldenkamp2018_SI.xlsx`
     when that workbook is available.
6. Pathogen profile set for pathogen scenarios, defaulting from basin/country.
7. Flow source, with basin-aware defaults.
8. Lake transport mode:
   - `legacy_pass_through`
   - `cstr`
9. Canal Q source for Volta/KIS scenarios.
10. Output directory name.
11. Final action:
    - print only;
    - write template file;
    - write template file and register scenario.

## Safety Behavior

- Always show a preview before writing files.
- Do not overwrite existing files by default.
- Registration in `LoadScenarioConfig()` / `ListScenarios()` must be explicit.
- Warn that generated scenarios are code scaffolds, not validated scientific
  parameterizations.
- When a selected basin implies a default pathogen profile or canal Q source,
  display that default in the preview so the user can check it.
- If the user chooses registration, update only the minimum scenario registry
  entries needed for `LoadScenarioConfig()` and `ListScenarios()` to find the new
  scenario.

## Future Implementation Target

- Keep current non-interactive commands working:

```bash
Rscript scripts/create_scenario_template.R \
  --name MyScenario \
  --copy-from VoltaWetPathogenCrypto

Rscript scripts/create_scenario_template.R \
  --name MyBegaCrypto \
  --basin bega \
  --type pathogen \
  --target cryptosporidium
```

- Add a testable internal helper that accepts a list of answers, for example:
  `CreateScenarioTemplateFromAnswers(answers)`.
- Keep terminal prompts as a thin wrapper around the answer-list helper.
- Use temporary files in tests for any write/register behavior.
- Avoid adding new R package dependencies for prompting unless there is a clear
  benefit over `readLines(stdin(), n = 1)`.

## Validation Plan For Future Implementation

- Unit tests:
  - simulated answers create a valid scenario template;
  - pathogen choices are discovered from `inst/pathogen_input`;
  - chemical choices are discovered from the workbook when present;
  - output file overwrite protection works;
  - optional registration updates scenario registry text correctly in a temp
    copy;
  - generated registered scenarios can be loaded in a temp config environment.
- Manual checks:
  - `Rscript scripts/create_scenario_template.R --interactive`;
  - print-only flow;
  - write-template flow;
  - write-and-register flow.
- Standard validation after implementation:
  - `R CMD INSTALL Package`;
  - `Rscript scripts/smoke-test.R`;
  - `Rscript scripts/inspect_scenarios.R --scenario <new scenario>`.

## Assumptions

- The wizard is terminal-based, not a VS Code GUI.
- The existing `--copy-from` and explicit-flag modes remain supported.
- Scenario creation helps structure code, but does not replace scientific review.
