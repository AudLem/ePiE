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

## 1. VS Code Debugging (Recommended)

The repository includes a `.vscode/launch.json` with pre-configured launch targets for every scenario.

### Prerequisites
- Install the **R** and **R Debugger** extensions in VS Code.
- Install the **C/C++** extension for native debugging.

### Running a Scenario

1. Open the **Run and Debug** view (`Cmd+Shift+D` on Mac).
2. Select a scenario from the dropdown:
   - **Full batch**: `Run All Scenarios`
   - **Network builds**: `Network: Volta Wet (HydroSHEDS)`, `Network: Volta (GeoGLOWS v2)`, etc.
   - **Simulations**: `Sim: Volta Wet Ibuprofen (GeoGLOWS)`, `Sim: Volta Dry Crypto (HydroSHEDS)`, etc.
   - **Tests**: `Run All Regression Tests`
   - **Smoke test**: `Run Smoke Test`
   - **Install**: `Install ePiE Package`
3. Set breakpoints in any `.R` file under `Package/R/`.
4. Press **F5** to start.

### Available Launch Configurations

| Config | Purpose |
|---|---|
| `Debug Current R File` | Run whatever R file is open |
| `Install ePiE Package` | Reinstall from source |
| `Run Smoke Test` | Verify package/data setup with `scripts/smoke-test.R` |
| `Run All Scenarios` | Run `scripts/run_all_scenarios.R` from the workspace root |
| `Run All Regression Tests` | Run the 16 Ouse/Ibuprofen golden-master tests |
| `Network: Volta Wet/Dry (HydroSHEDS)` | Build HydroSHEDS network |
| `Network: Bega (HydroSHEDS)` | Build Bega network |
| `Network: Volta (GeoGLOWS v2)` | Build GeoGLOWS network |
| `Sim: Volta Wet/Dry Ibuprofen/Crypto (HydroSHEDS)` | HydroSHEDS simulation |
| `Sim: Volta Wet/Dry Ibuprofen/Crypto (GeoGLOWS)` | GeoGLOWS simulation |
| `Sim: Bega Ibuprofen/Crypto (HydroSHEDS)` | Bega simulation |
| `Attach to R (C++)` | Attach gdb to running R process |

`Run All Scenarios` is the reliable full-batch launch target. It uses `scripts/run_all_scenarios.R`, which loads local source with `pkgload::load_all()` when available and constructs simulation state from the prebuilt network outputs. The individual simulation launch targets are useful for quick debugging, but should eventually call the same `run_single_scenario()` helper instead of calling `RunSimulationPipeline(cfg)` directly.

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
2. Use the **"Attach to R (C++)"** configuration in VS Code, or attach `gdb`/`lldb` manually.

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
