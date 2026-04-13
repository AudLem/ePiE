# Project Structure

This document describes the organization of the ePiE repository and R package.

## Root Directory

- `docs/`: Documentation (Getting Started, Usage, Debugging, Bugfix Plan).
- `scripts/`: Setup and verification scripts (`setup-data.sh`, `smoke-test.R`).
- `.vscode/`: Configuration for VS Code (R debugging, C++ attachment).
- `Package/`: The core R package source code.
- `data_manifest.json`: SHA-256 checksums for data archives downloaded from GitHub Releases.
- `Inputs/`: Basin shapefiles and user data (gitignored — download via `setup-data.sh`).
- `Outputs/`: Pre-built networks and simulation results (gitignored).

## R Package (`Package/`)
- `DESCRIPTION`: Package metadata and dependencies.
- `NAMESPACE`: Exported/Imported functions.
- `R/`: R source code (functions).
    - `00_...`: Utility and abstraction layers.
    - `01_...`: Data loading, selection, and hydrology.
    - `02_...`: Concentration engines (Chemical and Pathogen), SimpleTreat 4.0.
    - `10_` to `1A_`: Network building pipeline (10 steps).
    - `20_` to `23_`: Simulation state, emissions, and visualization.
    - `30_` to `32_`: Scenario configuration and pipeline orchestrators.
- `src/`: C++ source code for performance-critical calculations.
- `inst/config/`: Configuration files.
    - `basins/`: Spatial file paths for specific river basins (Volta, Bega).
    - `scenarios/`: Simulation parameters for specific runs.
- `inst/pathogen_input/`: Pathogen-specific parameters (Cryptosporidium, Giardia, Rotavirus, Campylobacter).
- `tests/`: Automated test suite (`testthat`).
- `man/`: Auto-generated function documentation (`.Rd`).
