# PSI-Cambodia

This repository contains an example of how to execute a power system scheduling simulation in [Sienna](https://github.com/Sienna-Platform/) using the [PowerSimulations.j](https://github.com/Sienna-Platform/PowerSimulations.jl) package, expanding on the data assembled for the [PowNet](https://github.com/kamal0013/PowNet) application for the power
grid in Cambodia. [![DOI](https://zenodo.org/badge/278169749.svg)](https://zenodo.org/badge/latestdoi/278169749)

> **Note:** This example has been updated to the current Sienna PSY5 stack. If you are coming from the older PSY3-era API, see [PSY3-to-PSY5-migration.md](PSY3-to-PSY5-migration.md) for a step-by-step guide to the changes.

![](https://github.com/kamal0013/PowNet/blob/master/fig2_Cambodia_grid.jpg)

This simulation is based on three open-source data and modeling tools used to model power systems with renewable resources such as wind and solar:

1. The [RE-Data Explorer](re-explorer.org/) can be used to investigate where to site wind and solar plants and to download wind and solar time-series resource files for selected latitude & longitudes where the plants will be located.

    - This repository already contains resource data files in the *REDE_resource_data/Input/* folder from the RE-Data Explorer for 5 hypothetical wind and solar plants in Cambodia.

2. The [System Advisor Model (SAM)](https://sam.nrel.gov/) can be used to model the power output (MW) from a wind or solar power plant, using the hourly or subhourly resource data from the RE-Data Explorer as inputs.

    - There are multiple ways for users to access SAM, including but not limited to:
        - A [downloadable GUI](https://sam.nrel.gov/download.html), which can be used for manual analysis of individual locations, i.e., power plants
        - A Python interface called [PySAM](https://nrel-pysam.readthedocs.io/en/main/index.html), which can be used to programmatically process multiple locations and/or plant configurations
        - The [Renewable Energy Potential (reV) tool](https://github.com/NREL/reV), which can be used for very large scenario analysis and batch runs
        
    - In the *REDE_resource_data* folder, there is a Python script that uses PySAM to process multiple solar and wind time-series resource files downloaded from the RE-Data Explorer for locations in Cambodia. This notebook is based on a PySAM example notebook, available [here](https://github.com/NREL/pysam/blob/main/Examples/PySAMWorkshop.ipynb). 
    
    - This processing has already been complete for the 5 example plants, and the outputs are available in the *REDE_resource_data/Output/* folder. However, if users would like to add other wind and solar locations and process those, here are the required steps:
        1. Add wind or solar resource files from the RE-Data Explorer to the *REDE_resource_data/Input/* folders
        
        2. Update the *REDE_resource_data/RE_plant_config.csv* file, which is a manually generated .csv file to make it easier to load the same plant metadata into both PySAM (to generate the plant-specific power profiles) and Sienna\Data (to attach the hypothetical solar and wind plants to the existing PowerSystem.jl model). It contains the following 4 pointers:
            - type (used by Sienna\Data): either "Solar_PV" or "Wind_WT" 
            - node (used by Sienna\Data): Acronym of the node in the PowNet system that the plant should connect to (for example, the closest node based on the latitude/longitude of the plant). 
            - resource_file (used by PySAM): Resource file (from RE-Data Explorer or the [National Solar Radiation Database (NSRDB)](https://nsrdb.nrel.gov/)) 
            - specification_file (used by PySAM): Plant configuration file, [exported from the SAM GUI](https://nrel-pysam.readthedocs.io/en/latest/inputs-from-sam.html). Example wind and solar plant specification files are already included in the *REDE_resource_data/Input* folders for the following configurations:
                 * Solar: (1) A 100 MWdc fixed (12 degree ~= Cambodia's latitute) tilt system or (2) a 100 MWdc one-axis tracking plant
                 * Wind: Models plant with Gamesa G114 2.0 MW turbines, which is selected to emulate the 'T200' representative turbine in the RE-Data Explorer's wind technical potential study (more info Table 12, page 23 [here](https://www.nrel.gov/docs/fy17osti/66861.pdf)); A review of Cambodia's mean wind speeds in the RE-Data Explorer indicates that the T200 or perhaps T237 representative turbines are a good choice for Cambodia.
                 
        3. Then, run the `REDE_timeseries_prep.py` script by navigating to the *REDE_resource_data* folder in a terminal with [conda](https://docs.conda.io/projects/continuumio-conda/en/latest/user-guide/install/index.html) installed, and running:
            ```
                conda env create --name pysam_env --file=environment.yml
                conda activate pysam_env
                python REDE_timeseries_prep.py
            ```
            This will install PySAM and run process the plant data. (Note: There are two ways to install PySAM: `pip` and `conda`. If you decide to install PySAM on your own rather than using the `environment.yml` file, it is recommended to use `pip` due to delays updating the `conda` version of PySAM: `pip install nrel-pysam`.)

3. Finally, [Sienna](https://github.com/Sienna-Platform/) can be used to run simulations of the Cambodia system, including the new renewable resources. 

This example includes two pieces of code:
 - Data preparation using Sienna's [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl) package and
 construction of a `System`. This includes pulling in the wind and solar power profiles. 
 - Example `Simulation` of a day-ahead unit-commitment scheduling sequence using Sienna's [PowerSimulations.j](https://github.com/Sienna-Platform/PowerSimulations.jl) package.

## Setup

Requires [Julia](https://julialang.org/downloads/) 1.11 or newer.

```bash
git submodule update --init PowNet
```

From a Julia REPL at the repository root:

```julia
] activate .
] instantiate
```

## Running the example

Examples are provided as `.jl` scripts. To autogenerate Jupyter notebooks:

```julia
include("literate.jl")
```

This produces `Cambodia-data-prep.ipynb` and `PSI-Cambodia.ipynb` (not committed; see `.gitignore`).
