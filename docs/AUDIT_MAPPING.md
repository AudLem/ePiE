# Architecture and Logic Mapping: ePiE (Extended Pharmaceutical Iterative Engine)

This document maps the legacy `./SHoeks/` (baseline) logic to the refactored `./AudLem/` (fork) architecture, interpreting the hydrological mass-balance model through the requested ptychographic lens.

## 1. Core ePiE Pipeline Mapping

The ePiE algorithm is a spatially explicit, steady-state mass balance model for substances (APIs/Pathogens) in river catchments.

| Ptychographic Component | Hydrological Reality | Legacy (SHoeks) | Refactored (AudLem) |
| :--- | :--- | :--- | :--- |
| **Object (O)** | **Basin/Network Topology** | `LoadEuropeanBasins()` in `01_LoadBasins.R` | Modularized in `16_BuildNetworkTopology.R` |
| **Probe (P)** | **Substance Emission ($E_{in}$)** | `LoadExampleConsumption()` in `01_ExampleData.R` | `02_PathogenModel.R` / `22_CalculateEmissions.R` |
| **Propagation** | **Downstream Transport ($e^{-kd/v}$)** | `compenvcons_v4.cpp` (Line 233) | `compenvcons_v4.cpp` (Line 235) |
| **Update Equation** | **Mass Balance ($C = E / Q$)** | `compenvcons_v4.cpp` (Line 222) | `compenvcons_v4.cpp` (Line 185) |
| **FFT / iFFT** | **Unit/Domain Shift** | Implicit scaling ($10^6$) | Explicit scaling logic in `02_ComputeEnvConcentrations.R` |

## 2. Refactoring Summary

### IO and Preprocessing
- **Legacy:** Rigid, monolithic R scripts that pass large vectors to C++. Pre-processing was limited to simple river/lake subsets.
- **Refactored:** A multi-stage pipeline (`10_*.R` to `19_*.R`) that builds a robust topology, handles complex lake-river connectivity, and allows for scenario normalization (`20_NormalizeScenarioState.R`).

### Substance Abstraction
- **Legacy:** Hardcoded for chemical (API) calculations.
- **Refactored:** Introduces `00_substance_abstraction.R`, allowing the same transport engine to handle chemicals (Ibuprofen) and pathogens (Cryptosporidium, Rotavirus) by abstracting emission and decay parameters.

## 3. Mathematical Alignment

The "Update" step in both repositories relies on the steady-state assumption:
$$C_{node} = \frac{\sum E_{upstream} + E_{local}}{Q_{out}}$$
where $Q_{out}$ is the discharge at the node. In `./AudLem/`, this is enhanced with a **CSTR (Completely Stirred Tank Reactor)** model for lakes:
$$C_{lake} = \frac{E_{total}}{Q + k \cdot V}$$
where $V$ is the lake volume.
