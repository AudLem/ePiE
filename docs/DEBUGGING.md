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
   - **Network builds**: `Network: Volta Wet (HydroSHEDS)`, `Network: Volta (GeoGLOWS v2)`, etc.
   - **Simulations**: `Sim: Volta Wet Ibuprofen (GeoGLOWS)`, `Sim: Volta Dry Crypto (HydroSHEDS)`, etc.
   - **Tests**: `Run All Regression Tests`
   - **Install**: `Install ePiE Package`
3. Set breakpoints in any `.R` file under `Package/R/`.
4. Press **F5** to start.

### Available Launch Configurations

| Config | Purpose |
|---|---|
| `Debug Current R File` | Run whatever R file is open |
| `Install ePiE Package` | Reinstall from source |
| `Run All Regression Tests` | Run the 16 Ouse/Ibuprofen golden-master tests |
| `Network: Volta Wet/Dry (HydroSHEDS)` | Build HydroSHEDS network |
| `Network: Bega (HydroSHEDS)` | Build Bega network |
| `Network: Volta (GeoGLOWS v2)` | Build GeoGLOWS network |
| `Sim: Volta Wet/Dry Ibuprofen/Crypto (HydroSHEDS)` | HydroSHEDS simulation |
| `Sim: Volta Wet/Dry Ibuprofen/Crypto (GeoGLOWS)` | GeoGLOWS simulation |
| `Sim: Bega Ibuprofen/Crypto (HydroSHEDS)` | Bega simulation |
| `Attach to R (C++)` | Attach gdb to running R process |

## 2. RStudio Debugging

- **Breakpoints**: Open any `.R` file and click to the left of the line number.
- **Source the package**: Run `source("Package/R/zzz.R")` then call functions directly.
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
