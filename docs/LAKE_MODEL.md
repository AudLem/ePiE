# Lake Modeling Approach in ePiE

## Overview

ePiE models lakes using a **single Completely Stirred Tank Reactor (CSTR)** approach per lake polygon. This is a screening-level model that treats each lake as one well-mixed volume with uniform concentration throughout.

## Single-CSTR Assumption

### Mathematical Formulation

For each lake, the outlet concentration is calculated using the first-order decay CSTR equation:

```
C_out = C_in × exp(-k × τ)
```

Where:
- `C_out` = concentration at lake outlet (µg/L or mg/L)
- `C_in` = concentration entering the lake (µg/L or mg/L)
- `k` = first-order decay rate constant (day⁻¹)
- `τ` = residence time = V/Q (days)
- `V` = lake volume (m³)
- `Q` = flow rate through the lake (m³/day)

### Residence Time Calculation

```
τ = V / Q
```

Where:
- `V` is obtained from HydroLAKES database (or calculated from area × mean depth)
- `Q` is estimated using Manning-Strickler equation based on hydraulic geometry

### Implementation in ePiE

1. **Lake Inlet/Outlet Nodes** (see `17_ConnectLakesToNetwork.R`)
   - Each lake polygon creates a pair of nodes: `LakeIn_<lake_id>` and `LakeOut_<lake_id>`
   - All upstream river segments and source nodes are rewired to point to `LakeIn`
   - `LakeIn` points to `LakeOut`
   - `LakeOut` points to the downstream river network

2. **Lake Emissions** (see `Set_local_parameters_custom_removal_fast3.R` lines 244-254)
   - Direct emissions from agglomerations and WWTPs inside the lake are summed into `HL$E_in`
   - **Important**: This does NOT include emissions from inlet nodes (which are upstream of the lake)
   - Only source nodes (agglomerations, WWTPs) physically located within the lake boundary contribute to `HL$E_in`

3. **Lake Concentration Calculation** (see `Compute_env_conformations_v4.R` Case 3)
   - Lake is treated as a single well-mixed reactor
   - All inflows converge at `LakeIn` and are mixed
   - The mixed concentration passes through the CSTR with residence time τ
   - Outflow concentration emerges at `LakeOut`

## Standards and Literature Compliance

This approach follows established modeling frameworks:

### SWAT Model (Arnold et al.)
- SWAT treats each lake/reservoir as a single well-mixed compartment
- All inflows are aggregated and assumed to mix instantaneously
- First-order decay is applied to the mixed volume
- Reference: Arnold, J.G., et al. (2012). "SWAT: Model Use, Calibration, and Validation." *Transactions of the ASABE*.

### WASP Model (Ambrose et al.)
- WASP (Water Quality Analysis Simulation Program) uses a segmented approach for large waterbodies
- For screening-level analysis, WASP can be configured as a single CSTR
- Reference: Ambrose, R.B., et al. (1993). "WASP, Version 5: A Hydrodynamic and Water Quality Model." *EPA*

### CSTR Fundamentals (Bolin & Rodhe, 1973)
- The exponential decay formula C_out = C_in × exp(-kτ) is derived from mass balance on a well-mixed reactor
- This is the fundamental equation for first-order removal in a CSTR
- Reference: Bolin, B. and Rodhe, H. (1973). "A note on the concepts of age distribution and transit time in natural reservoirs." *Tellus*.

## Limitations and Applicability

### When the Single-CSTR Assumption is Appropriate

The single-CSTR model is appropriate for:

- **Lakes < 100 km²**: Smaller lakes tend to be well-mixed
- **Residence time < 1 year**: Short residence times limit stratification development
- **Screening-level analysis**: When computational efficiency is prioritized over fine-scale spatial resolution
- **Conservative contaminants**: When the substance is not highly sensitive to spatial heterogeneity

### Known Limitations

The single-CSTR approach does NOT capture:

1. **Thermal Stratification**: Deep lakes (>30m) can develop distinct epilimnion, metalimnion, and hypolimnion layers with different mixing and decay rates
2. **Spatial Heterogeneity**: Large lakes may have concentration gradients from inlet to outlet
3. **Multiple Inlet Mixing**: While all inflows are aggregated, the actual mixing dynamics (e.g., density currents, wind-driven circulation) are not modeled
4. **Seasonal Turnover**: The model assumes constant mixing, but many temperate lakes experience seasonal stratification and mixing events
5. **Sediment-Water Exchange**: Sediment interactions are modeled at the lake scale, not spatially varying

### Future Enhancements

Potential improvements for future work (not currently implemented):

- **Stratification modifier**: For deep lakes (>30m), apply a depth-dependent decay rate or multi-layer CSTR
- **Hydrodynamic sub-model**: Couple with 2D/3D hydrodynamic model for large lakes
- **Spatially-varying decay**: Account for light attenuation (depth-dependent photolysis) and temperature gradients
- **Sediment focusing**: Model sediment deposition patterns in lake basins

## Comparison to Literature

| Aspect | Literature Standard | ePiE Implementation | Status |
|--------|-------------------|---------------------|--------|
| Single CSTR per lake | Standard for screening (Rueda 2006) | ✅ Implemented | Compliant |
| Multi-inlet aggregation | SWAT: single inflow | ✅ All inlets rewired to LakeIn | Compliant |
| Residence time calculation | V/Q (Bolin & Rodhe 1973) | ✅ Using Manning-Strickler Q | Compliant |
| First-order decay | C_out = C_in × exp(-kτ) | ✅ Implemented in Case 3 | Compliant |
| Stratification handling | Multi-layer models for deep lakes | ❌ Not implemented | Future work |
| Spatial heterogeneity | 2D/3D models for large lakes | ❌ Not implemented | Future work |

## References

1. **Arnold, J.G., et al.** (2012). "SWAT: Model Use, Calibration, and Validation." *Transactions of the ASABE*, 55(4), 1491-1508. DOI: 10.13031/2013.42256

2. **Ambrose, R.B., et al.** (1993). "WASP, Version 5: A Hydrodynamic and Water Quality Model - Model Theory, User's Manual, and Programmer's Guide." *EPA/600/R-93/139*

3. **Bolin, B. and Rodhe, H.** (1973). "A note on the concepts of age distribution and transit time in natural reservoirs." *Tellus*, 25(1), 58-62. DOI: 10.3402/tellusa.v25i1.9644

4. **Rueda, F., et al.** (2006). "Modelling the effect of size and configuration on the residence time of shallow lakes." *Ecological Modelling*, 193(3-4), 475-494. DOI: 10.1016/j.ecolmodel.2005.09.009

5. **Oldenkamp, R., et al.** (2019). "Mapping the concentrations of pharmaceuticals in European rivers." *Environmental Research Letters*, 14(7), 074037. DOI: 10.1088/1748-9326/ab1c5d

6. **Messager, M.L., et al.** (2016). "Global estimate of the number of lakes and ponds based on high-resolution imagery." *Nature Communications*, 7, 13603. DOI: 10.1038/ncomms13603 (HydroLAKES database)

## Related Code Files

- `Package/R/17_ConnectLakesToNetwork.R` - Creates LakeIn/LakeOut node pairs
- `Package/R/18_DetectLakeSegmentCrossings.R` - Detects river-lake boundary crossings
- `Package/R/Set_local_parameters_custom_removal_fast3.R` - Calculates lake emissions (lines 244-254)
- `Package/R/Compute_env_concentrations_v4.R` - Applies CSTR decay (Case 3, lines 165+)
- `Package/src/compenvcons_v4.cpp` - C++ implementation of CSTR calculation (lines 317-331)
