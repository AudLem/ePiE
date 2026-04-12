## ePiE
ePiE is a spatially explicit model that estimates concentrations of active pharmaceutical ingredients (APIs) in surface waters across Europe. This repository contains the R package of the ePiE model alongside all the required input parameters, such as the parameterized European river catchment and discharge data. 

## ePiE: Installation

Run the code below to make sure all dependencies are installed (because ePiE is not yet in CRAN, this needs to be done manually).

``` r
# install dependencies
if(!require("Rcpp")) install.packages("Rcpp") # for source code in C++
if(!require("terra")) install.packages("terra") # for flow rasters
if(!require("sf")) install.packages("sf") # for rivers and lakes
if(!require("mapview")) install.packages("mapview") # for interactive map
```

Next, the ePiE package can be directly installed from R using the regular `install.packages()` function, see the code below.

``` r
# Install the R package on Windows
install.packages("https://github.com/SHoeks/ePiE/raw/refs/heads/main/Builds/ePiE_1.25.zip", 
                 repos=NULL, 
                 method="libcurl")

# Install the R package on MacOS
install.packages("https://github.com/SHoeks/ePiE/raw/refs/heads/main/Builds/ePiE_1.25.tgz",
                 repos=NULL, 
                 method="libcurl")

# Install the R package on Linux
install.packages("https://github.com/SHoeks/ePiE/raw/refs/heads/main/Builds/ePiE_1.25.tar.gz", 
                 repos=NULL, 
                 method="libcurl")
```

## ePiE: Getting Started & Documentation

For detailed instructions on setting up, running, and debugging the model, please refer to the documentation in the `docs/` directory:

- [**Getting Started**](./docs/GETTING_STARTED.md): Prerequisites and Directory Setup.
- [**Usage & Examples**](./docs/USAGE.md): Simple chemical and pathogen simulation runs.
- [**Debugging Guide**](./docs/DEBUGGING.md): How to use RStudio and VS Code debuggers.

---

## ePiE: Development Status
ePiE is currently being extended to support pathogen modelling as part of WP2. Current focus is on Cryptosporidium, with support for Rotavirus, Giardia, and Campylobacter planned.

