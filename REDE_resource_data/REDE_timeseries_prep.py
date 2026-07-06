#!/usr/bin/env python
# coding: utf-8

# This code takes time-series wind resource profiles from the WRDB and solar resource profiles from the NSRDB
# (formerly accessed via the deprecated RE Data Explorer) and processes them into power profiles for
# time-series simulations in PowerSimulations.jl.  

import PySAM.Pvwattsv8
import PySAM.Windpower
import os
import glob
import json
import pandas as pd
import numpy as np

# ### Define helper functions
# - Load a .json of SAM specifications, generated from the GUI: https://nrel-pysam.readthedocs.io/en/main/inputs-from-sam.html

def load_pysam_json(pysam_model, json_file):
    with open(json_file, 'r') as file:
        data = json.load(file)
        # loop through each key-value pair
        for k, v in data.items():
            if k != "number_inputs":
                pysam_model.value(k, v)

# ### Load in solar and wind configuration file
config = pd.read_csv("RE_plant_config.csv")

solar_dir = os.path.join(os.getcwd(), "Input", "Solar")
wind_dir = os.path.join(os.getcwd(), "Input", "Wind")

# ### Calculate AC power output profiles 
# Each hypothetical solar and wind plant is modeled with the resource data from its unique latitude/longitude

power_df = pd.DataFrame(0.0, index =np.arange(8760), columns = config['name'])

for index, row in config.iterrows():
    if row['type'].split("_")[0].upper() == "SOLAR":
        pv = PySAM.Pvwattsv8.new()
        solar_json = os.path.join(solar_dir, row['specification_file'])
        load_pysam_json(pv, solar_json)
        pv.SolarResource.solar_resource_file = os.path.join(
            solar_dir, row['resource_file'])
        pv.execute(0)
        power_df[row['name']] = pv.Outputs.gen
    elif row['type'].split("_")[0].upper() == "WIND":
        wind = PySAM.Windpower.default("WindPowerNone")
        wind_json = os.path.join(wind_dir, row['specification_file'])
        load_pysam_json(wind, wind_json)
        wind.Resource.wind_resource_filename = os.path.join(
            wind_dir, row['resource_file'])
        wind.execute(0)
        power_df[row['name']] = wind.Outputs.gen
    else: 
       raise Exception("Plant type must be 'solar' or 'wind'")     


# Export to .csv for use by Sienna\Ops

power_df.to_csv(os.path.join(os.getcwd(), "Output", "data_solar_wind_power_2016.csv"), index = False)