# PSI-Cambodia

This repository contains an example of how to execute a power system scheduling simulation in [Sienna](https://github.com/Sienna-Platform/) using the [PowerSimulations.j](https://github.com/Sienna-Platform/PowerSimulations.jl) package, expanding on the data assembled for the [PowNet](https://github.com/kamal0013/PowNet) application for the power
grid in Cambodia. [![DOI](https://zenodo.org/badge/278169749.svg)](https://zenodo.org/badge/latestdoi/278169749)

![](https://github.com/kamal0013/PowNet/blob/master/fig2_Cambodia_grid.jpg)

This simulation is based on three open-source data and modeling tools from the [National Laboratory of the Rockies (NLR)](https://www.nlr.gov/) used to model power systems with renewable resources such as wind and solar:

1. The former RE Data Explorer has been deprecated. Wind and solar resource data are now accessed separately:
    - The [Wind Resource Database (WRDB)](https://wrdb.nlr.gov/data-viewer) can be used to investigate where to site wind plants, explore mean wind speeds, and download wind time-series resource files for selected latitude and longitudes.
    - The [National Solar Radiation Database (NSRDB)](https://nsrdb.nlr.gov/) can be used to investigate where to site solar plants and download solar irradiance time-series resource files for selected latitude and longitudes.

    - This repository already contains resource data files in the *REDE_resource_data/Input/* folder downloaded from the WRDB and NSRDB (historically via the RE Data Explorer) for 5 hypothetical wind and solar plants in Cambodia.

2. The [System Advisor Model (SAM)](https://sam.nlr.gov/) can be used to model the power output (MW) from a wind or solar power plant, using the hourly or subhourly resource data from the WRDB or NSRDB as inputs.

    - There are multiple ways for users to access SAM, including but not limited to:
        - A [downloadable GUI](https://sam.nlr.gov/download.html), which can be used for manual analysis of individual locations, i.e., power plants
        - A Python interface called [PySAM](https://nrel-pysam.readthedocs.io/en/main/index.html), which can be used to programmatically process multiple locations and/or plant configurations
        - The [Renewable Energy Potential (reV) tool](https://github.com/NatLabRockies/reV), which can be used for very large scenario analysis and batch runs
        
    - In the *REDE_resource_data* folder, there is a Python script that uses PySAM to process multiple solar and wind time-series resource files downloaded from the WRDB and NSRDB for locations in Cambodia. This notebook is based on a PySAM example notebook, available [here](https://github.com/NatLabRockies/pysam/blob/main/Examples/PySAMWorkshop.ipynb). 
    
    - This processing has already been complete for the 5 example plants, and the outputs are available in the *REDE_resource_data/Output/* folder. However, if users would like to add other wind and solar locations and process those, here are the required steps:
        1. Add wind resource files from the WRDB to *REDE_resource_data/Input/Wind/* and solar resource files from the NSRDB to *REDE_resource_data/Input/Solar/*
        
        2. Update the *REDE_resource_data/RE_plant_config.csv* file, which is a manually generated .csv file to make it easier to load the same plant metadata into both PySAM (to generate the plant-specific power profiles) and Sienna\Data (to attach the hypothetical solar and wind plants to the existing PowerSystem.jl model). It contains the following 4 pointers:
            - type (used by Sienna\Data): either "Solar_PV" or "Wind_WT" 
            - node (used by Sienna\Data): Acronym of the node in the PowNet system that the plant should connect to (for example, the closest node based on the latitude/longitude of the plant). 
            - resource_file (used by PySAM): Resource file from the WRDB (wind) or [NSRDB](https://nsrdb.nlr.gov/) (solar)
            - specification_file (used by PySAM): Plant configuration file, [exported from the SAM GUI](https://nrel-pysam.readthedocs.io/en/latest/inputs-from-sam.html). Example wind and solar plant specification files are already included in the *REDE_resource_data/Input* folders for the following configurations:
                 * Solar: (1) A 100 MWdc fixed (12 degree ~= Cambodia's latitute) tilt system or (2) a 100 MWdc one-axis tracking plant
                 * Wind: Models plant with Gamesa G114 2.0 MW turbines, which is selected to emulate the 'T200' representative turbine in the wind technical potential study (more info Table 12, page 23 [here](https://www.nlr.gov/docs/fy17osti/66861.pdf)); A review of Cambodia's mean wind speeds in the WRDB indicates that the T200 or perhaps T237 representative turbines are a good choice for Cambodia.
                 
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

The workflow is Julia-first: run the `.jl` scripts directly or generate notebooks with [Literate.jl](https://github.com/fredrikekre/Literate.jl).

1. Prepare the serialized system (regenerates `sys-cambodia.*` if needed):

   ```bash
   julia --project=. Cambodia-data-prep.jl
   ```

2. Run the unit-commitment example (uses [PlotlyLight](https://github.com/JuliaPlots/PlotlyLight.jl) for interactive dispatch plots):

   ```bash
   julia --project=. PSI-Cambodia.jl
   ```

3. Optionally generate Jupyter notebooks from the Literate-formatted scripts:

   ```julia
   include("literate.jl")
   ```

   This produces `Cambodia-data-prep.ipynb` (executed) and `PSI-Cambodia.ipynb` (not executed). Notebooks are gitignored; regenerate them locally with `literate.jl`.
