# Project Structure

This document describes the organization of the ePiE repository and R package.

## Root Directory
- `docs/`: Comprehensive documentation (Getting Started, Usage, Debugging).
- `.vscode/`: Configuration for VS Code (R debugging, C++ attachment).
- `Package/`: The core R package source code.
- `Builds/`: Compiled `.zip`, `.tar.gz`, and `.tgz` versions of the package.
- `Inputs/`: Historical scripts and raw data fragments (legacy).
- `Plots/`: Generated visual examples from the model.

## R Package (`Package/`)
- `DESCRIPTION`: Package metadata and dependencies.
- `NAMESPACE`: Exported/Imported functions.
- `R/`: R source code (functions).
    - `00_utils.R`: Common utility functions.
    - `01_...`: Data loading and selection.
    - `02_...`: Concentration engines (Chemical and Pathogen).
    - `10_` to `1A_`: Network building pipeline.
    - `20_` to `23_`: Simulation state and visualization.
    - `30_` to `32_`: Scenario configuration and pipeline orchestrators.
- `src/`: C++ source code for performance-critical calculations.
- `inst/config/`: Configuration files.
    - `basins/`: Spatial file paths for specific river basins.
    - `scenarios/`: Simulation parameters for specific runs.
- `inst/pathogen_input/`: Pathogen-specific parameters (e.g., `cryptosporidium.R`).
- `tests/`: Automated test suite (`testthat`).
- `man/`: Auto-generated function documentation (`.Rd`).
- `data/`: Built-in datasets (`basins`, `flow_index`, etc.).
