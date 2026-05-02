# Debugging ePiE

This document explains how to set up your environment to debug the ePiE R package, including its C++ core.

## IMPORTANT: Always Use Full Diagnostics

**Before any debugging session, always run with `diagnostics = "full"`**. This generates comprehensive diagnostic maps and logs that are essential for understanding what went wrong.

```r
# For network builds
cfg   <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")
state <- BuildNetworkPipeline(cfg, diagnostics = "full")

# For simulations
cfg     <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs")
results <- RunSimulationPipeline(state, substance = "cryptosporidium")
```

Diagnostic outputs are saved to:
- `<output_dir>/plots/diagnostics/` — intermediate network maps at each processing step
- Console output — detailed progress and validation messages

These diagnostic maps help you:
- Verify canal connectivity (are canals connected to rivers or dead ends?)
- Check lake integration
- Validate population and WWTP distributions
- Identify where the pipeline fails

See [CONFIGURATION.md](./CONFIGURATION.md#diagnostics) for diagnostic level details.

## 1. VS Code Tasks

The repository uses VS Code tasks for normal R work. It does not use R launch targets for scenarios.

### Prerequisites
- Install the **R** extension if you want R language support in VS Code.
- Install the **C/C++** extension only if you need to attach a native debugger to the C++ code.
- Make sure R is installed at `/Library/Frameworks/R.framework/Resources/bin/R`.

### Run a Task

1. Open the command palette with `Cmd+Shift+P`.
2. Select **Tasks: Run Task**.
3. Choose one of the `R:` tasks.

You can also use **Terminal > Run Task** from the VS Code menu.

### Available R Tasks

| Task | Purpose |
|---|---|
| `R: Run Current File` | Run the open R file with `Rscript` |
| `R: Install Package` | Install the local package from `Package/` |
| `R: Smoke Test` | Run `scripts/smoke-test.R` |
| `R: Test Pathogen Profiles` | Run the pathogen profile tests |
| `R: Test Pathogen Formulas` | Run the pathogen formula tests |
| `R: Validate Profile Scenario Defaults` | Check default pathogen profile settings for Bega and Volta |
| `R: Bega Crypto Profile Simulation` | Run a focused Bega cryptosporidium profile simulation in a temporary output folder |
| `R: Volta Wet Crypto Profile Simulation` | Run a focused Volta wet cryptosporidium profile simulation in a temporary output folder |
| `R: Run All Scenarios` | Run `scripts/run_all_scenarios.R` from the workspace root |

The tasks are defined in `.vscode/tasks.json`. They run from the repository root.

### R Breakpoints

The current VS Code setup does not define R debugger launch configurations. For line-by-line R debugging, use one of these options:
- insert `browser()` in the R code and run a task;
- use RStudio breakpoints;
- add a dedicated VS Code R debugger configuration later, if needed.

### Native C++ Attach Debugging

`.vscode/launch.json` contains one launch configuration:

| Config | Purpose |
|---|---|
| `Attach to R (C++ / lldb)` | Attach lldb to a running R process for C++ debugging |

Use this only when debugging native code in `Package/src/`.

## 2. RStudio Debugging

- **Breakpoints**: Open any `.R` file and click to the left of the line number.
- **Load local source**: Open `ePiE.Rproj`, restart R, then run:
  ```r
  project_root <- rstudioapi::getActiveProject()
  if (!dir.exists(file.path(project_root, "Package"))) {
    project_root <- dirname(project_root)
  }
  setwd(project_root)
  stopifnot(dir.exists("Package"))
  pkgload::load_all("Package")
  ```
- **Fallback without rstudioapi**:
  ```r
  setwd("/path/to/ePiE")
  stopifnot(dir.exists("Package"))
  pkgload::load_all("Package")
  ```
- **Debug network input CRS and Step 01 map in RStudio**:
  ```r
  cfg <- LoadScenarioConfig("VoltaWetNetwork", "Inputs", "Outputs")
  state <- BuildNetworkPipeline(
    cfg,
    checkpoint_dir = "checkpoints/volta_wet",
    stop_after_step = "01_load_inputs",
    diagnostics = "maps",
    interactive_diagnostics = TRUE
  )
  ```
  This prints a CRS report in the Console, shows the basin/rivers/canals/lakes/flow-direction map in the Plots pane, saves `Outputs/volta_wet/plots/diagnostics/step_01_crs_report.csv`, saves `Outputs/volta_wet/plots/diagnostics/step_01_loaded_inputs_map.png`, and waits for Enter before continuing in an interactive R session.
  
  Use a network scenario such as `VoltaWetNetwork` for `BuildNetworkPipeline()`. Do not pass a simulation/pathogen scenario such as `VoltaWetPathogenCampylobacter` to `BuildNetworkPipeline()`, because simulation configs use prebuilt network outputs and do not contain `basin_shp_path`.
- **Run all scenarios**:
  ```r
  source("scripts/run_all_scenarios.R")
  ```
- **Run one scenario via the batch helper**:
  ```r
  lines <- readLines("scripts/run_all_scenarios.R")
  cutoff <- which(grepl("# Scenario list", lines))[1] - 1
  eval(parse(text = lines[1:cutoff]), envir = .GlobalEnv)
  run_single_scenario(list(
    name = "volta_wet_crypto",
    type = "pathogen",
    config_name = "VoltaWetPathogenCrypto",
    network_dir = "volta_wet"
  ))
  ```
- **Installed-package testing**: Use `R CMD INSTALL Package` only when validating the installed package rather than the active source tree.
- **Browser**: Insert `browser()` into the code where you want to pause execution.

## 3. Debugging C++ Code

The concentration engine is written in C++ (`Package/src/compenvcons_v4.cpp`).

1. Rebuild with debug symbols:
   ```bash
   R CMD INSTALL Package --preclean --with-keep.source
   ```
2. Use the **"Attach to R (C++ / lldb)"** configuration in VS Code, or attach `lldb` manually.

## 4. Common Issues

### "Cannot find file..."
Ensure `data_root` and `output_root` paths are absolute and match the directory structure in [GETTING_STARTED.md](./GETTING_STARTED.md).

### "Rcpp symbol not found"
After modifying C++ code, recompile:
```bash
Rscript -e 'Rcpp::compileAttributes("Package")'
R CMD INSTALL Package
```

### "Prediction not possible due to insufficient flow/slope data"
The Q and slope propagation loops fill missing values from neighbours. If nodes remain unfilled after propagation, the pipeline now applies a median fallback. Check that your network has enough nodes with valid flow data.

### "numbers of columns of arguments do not match"
This occurs during `rbind` when GeoGLOWS and canal data have mismatched columns. The pipeline handles this automatically — if you see this error, ensure you've installed the latest version (`R CMD INSTALL Package`).

### GeoGLOWS simulation hangs or is very slow
GeoGLOWS geometries can have thousands of vertices per segment. The pipeline simplifies them in UTM (100m tolerance). If the network still has too many nodes, reduce the tolerance in `12_ProcessRiverGeometry.R`.

### Memory Errors
C++ memory errors (segfaults) are best diagnosed using `valgrind`:
```bash
R -d valgrind -e 'library(ePiE); cfg <- LoadScenarioConfig("VoltaWetPathogenCrypto", "Inputs", "Outputs"); state <- BuildNetworkPipeline(cfg); RunSimulationPipeline(state, substance = "cryptosporidium")'
```
