# Debugging ePiE

This document explains how to set up your environment to debug the ePiE R package, including its C++ core.

## 1. RStudio Debugging

RStudio is the easiest way to debug the R portions of the model.

- **Breakpoints**: Open any `.R` file in the `Package/R/` directory and click to the left of the line number to set a breakpoint.
- **Source the package**: Run `devtools::load_all("Package")` or press `Ctrl+Shift+L`.
- **Run the simulation**: Call your function (e.g., `RunSimulationPipeline(cfg)`). RStudio will stop at your breakpoint.
- **Browser**: You can also insert `browser()` into the code where you want to pause execution.

## 2. VS Code Debugging

VS Code provides a powerful environment for both R and C++ debugging.

### Prerequisites
- Install the **R** and **R Debugger** extensions in VS Code.
- Install the **C/C++** extension for native debugging.

### Configuring the R Debugger
The repository includes a `.vscode/launch.json` file to help you start.

1.  Open the **Run and Debug** view (`Ctrl+Shift+D`).
2.  Select **"Debug R Script"** or **"Debug R Simulation"**.
3.  Set your breakpoints in any `.R` file.
4.  Press **F5** to start.

### Debugging C++ Code
The concentration engine is written in C++ (`Package/src/compenvcons_v4.cpp`). To debug it:

1.  Rebuild the package with debug symbols:
    ```bash
    R CMD INSTALL Package --preclean --with-keep.source
    ```
2.  Use a debugger like `gdb` or `lldb` attached to the R process, or use the **"Attach to R (C++)"** configuration in VS Code.

## 3. Common Issues

### "Cannot find file..."
Ensure your `data_root` and `output_root` paths are absolute and the directory structure matches [GETTING_STARTED.md](./GETTING_STARTED.md).

### "Rcpp symbol not found"
If you've modified the C++ code, you must recompile. Run `Rcpp::compileAttributes("Package")` and then `devtools::load_all("Package")`.

### Memory Errors
C++ memory errors (segfaults) are best diagnosed using `valgrind`:
```bash
R -d valgrind -e 'library(ePiE); RunSimulationPipeline(cfg)'
```
