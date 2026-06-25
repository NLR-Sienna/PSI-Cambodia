# -*- coding: utf-8 -*-
# ---
# jupyter:
#   jupytext:
#     text_representation:
#       extension: .jl
#       format_name: percent
#       format_version: '1.3'
#       jupytext_version: 1.19.1
#   kernelspec:
#     display_name: Julia 1.11
#     language: julia
#     name: julia-1.11
# ---

# %%
using Pkg
Pkg.activate(".")
Pkg.status()


using PowerSystems
using CSV
using DataFrames
using Dates
using TimeSeries
using JSON

# %%

# %%
# Read in and clean data
pownet_data_dir = joinpath("PowNet", "Model_withdata", "input")     # data source
sienna_data_dir = mkpath("sienna_data")                             # formatted data target
re_config_dir   = "REDE_resource_data"                              # renewable config directory
re_data_dir     = joinpath("REDE_resource_data", "Output")          # renewable time series dir


# Read PowNet data files
branch = CSV.read(joinpath(pownet_data_dir, "data_camb_transparam.csv"), DataFrame)
gens   = CSV.read(joinpath(pownet_data_dir, "data_camb_genparams.csv"), DataFrame)
loads   = CSV.read(joinpath(pownet_data_dir, "data_camb_load_2016.csv"), DataFrame)

# %%
# Add missing required branch info
branch[!, :r] .= 0.0
branch[!, :b] .= 0.0
branch[!, :x] .= 0.01 ./ branch.linesus
branch[!, :name] = branch.source .* "_" .* branch.sink



# %%
# timeseries_pointers

# Internal helper: create time series pointer entries
function make_tsp(df, label, simulation, category, input_data_dir, ts_name)
    component_names = names(df)
    tsp_entries = Vector{Dict}(undef, length(component_names))

    for (i, comp) in enumerate(component_names)
        ## max of the column (skip missing just in case)
        norm = maximum(skipmissing(df[!, comp]))
        tsp_entries[i] = Dict(
            "simulation" => simulation,
            "resolution" => 3600,
            "category" => category,
            "component_name" => comp,
            "module" => "PowerSystems",
            "type" => "SingleTimeSeries",
            "name" => label,
            "scaling_factor_multiplier" => "get_max_active_power",
            "scaling_factor_multiplier_module" => "PowerSystems",
            "normalization_factor" => norm,
            #"data_file" => joinpath(sienna_data_dir, ts_name)
            "data_file" => joinpath(ts_name)
        )
    end

    return tsp_entries
end

# Process a time series file and create its metadata entries
function make_ts_and_tsp(ts_name, input_data_dir, sienna_data_dir, category, simulation, label)
    ts_path = joinpath(input_data_dir, ts_name)
    ts = CSV.read(ts_path, DataFrame)
    if occursin("load", ts_name) || occursin("hydro", ts_name)
        DataFrames.rename!(ts, Dict(:Hour => :Period))
        ts[!, :Year] .= 2017
    else
        ts ./= 1000  # kW → MW
        time_index = CSV.read(
            joinpath(sienna_data_dir, "data_camb_load_2016.csv"),
            DataFrame;
            select = ["Year", "Month", "Day", "Period"]
        )
        ts = hcat(time_index, ts)
    end

    CSV.write(joinpath(sienna_data_dir, ts_name), ts)

    component_cols = setdiff(names(ts), ["Year", "Month", "Day", "Period"])
    
    ## Force timeseries values to Float64 (this is the important fix)
    for c in component_cols
        ts[!, c] = Float64.(ts[!, c])
    end

    df_comp = ts[:, component_cols]

    @show eltype(ts[!, component_cols[1]])
    

    return make_tsp(df_comp, label, simulation, category, input_data_dir, ts_name)
end

# Collect metadata for all time series
loads_tsp = make_ts_and_tsp(
    "data_camb_load_2016.csv",
    pownet_data_dir,
    sienna_data_dir,
    #"ElectricLoad",
    "PowerLoad",
    "CambodiaSimulation",
    "max_active_power"
)

hydro_tsp = vcat(
    make_ts_and_tsp("data_camb_hydro_2016.csv",
        pownet_data_dir, sienna_data_dir,
        "Generator", "CambodiaSimulation", "max_active_power"),

    make_ts_and_tsp("data_camb_hydro_import_2016.csv",
        pownet_data_dir, sienna_data_dir,
        "Generator", "CambodiaSimulation", "max_active_power")
)

re_tsp = make_ts_and_tsp(
    "data_solar_wind_power_2016.csv",
    re_data_dir,
    sienna_data_dir,
    "Generator",
    "CambodiaSimulation",
    "max_active_power"
)

# Combine all time series metadata
all_tsp = vcat(loads_tsp, hydro_tsp, re_tsp)





# %%
gens

# %%
# # Collect generator metadata
# Helper function to add hydro, solar, and wind plants

# convert JSON files to Dataframe
hydro_tsp_df = DataFrame(hydro_tsp)
re_tsp_df = DataFrame(re_tsp)

# helper create gen function to add hydro and wind and solar info back to the gens metadata file 

function create_gen!(gen_df, gen, node, typ)
    gen_row = Dict{String, Any}(zip(names(gen_df), zeros(ncol(gen_df))))
    gen_row["name"] = gen.component_name
    gen_row["node"] = node
    gen_row["maxcap"] = gen.normalization_factor
    gen_row["ramp"] = gen.normalization_factor
    gen_row["typ"] = typ
    append!(gen_df, gen_row, promote = true)
end

# Create complete hydro info from hydro_ts
for hy in eachrow(hydro_tsp_df)
    create_gen!(gens, hy, hy.component_name, "hydro_HY")
end


# re_tsp_df.type → "SingleTimeSeries" which does not match with the re_config column ['type']
DataFrames.rename!(re_tsp_df, :type => :ts_type)

# Create complete wind and solar data
re_config = CSV.read(
    joinpath(re_config_dir, "RE_plant_config.csv"), DataFrame)

for re in eachrow(leftjoin(
            re_tsp_df, re_config; on = :component_name=>:name))
    create_gen!(gens, re, re["node"], re["type"])
end

# # Clean up -- add missing required generator info
gens[!, :fuel] = [t[1] for t in split.(gens.typ, "_")]
gens[!, :prime_mover] = [t[end] for t in split.(gens.typ, "_")]
gens[!, :zero_col] .= 0.0
gens[gens.fuel.=="imp", :prime_mover] .= "OT"
gens[gens.fuel.=="imp", :fuel] .= "OTHER"
gens = gens[gens.fuel.!="slack", :]
gens[gens.name.=="Salabam", :var_om] .= 48.0
gens[gens.name.=="impnode_viet", :var_om] .= 65.0
gens[gens.name.=="impnode_thai", :var_om] .= 66.0




# %%
# # Export supporting .csv files
# Create a bus/node table
loads = DataFrame(loads_tsp)

bus = DataFrame(Dict(:node => union(branch.source, branch.sink)))
bus[!, :type] .= "PV"
bus[!, :voltage] .= 100.0
bus[[b in names(loads) for b in bus.node], :type] .= "PQ"
bus[bus.node.==gens[gens.maxcap.==maximum(gens.maxcap), :node], :type] .= "REF"
bus[!, :id] = [1:nrow(bus)...]

bus

# %%
CSV.write(joinpath(sienna_data_dir, "timeseries_pointers.csv"), all_tsp)
CSV.write(joinpath(sienna_data_dir, "branch.csv"), branch)
CSV.write(joinpath(sienna_data_dir, "gen.csv"), gens)
CSV.write(joinpath(sienna_data_dir, "bus.csv"), bus)
CSV.write(joinpath(sienna_data_dir, "load.csv"), loads)
json_str = JSON.json(all_tsp)
open(joinpath(sienna_data_dir, "timeseries_pointers.json"), "w") do io
    write(io, json_str)
end

# %%
rawsys = PowerSystemTableData(
    sienna_data_dir,
    100.0,
    "user_descriptors.yaml";
    generator_mapping_file = "generator_mapping.yaml",
    timeseries_metadata_file = joinpath(sienna_data_dir,"timeseries_pointers.csv"),
)

sys = System(rawsys; time_series_in_memory = true,time_series_resolution=Hour(1))

transform_single_time_series!(sys, Hour(48), Hour(24), resolution = Dates.Hour(1))

# Disable renewables initially
for g in get_components(RenewableDispatch, sys)
    set_available!(g, false)
end

to_json(sys, "sys-cambodia.json", force = true)


# %%
for g in get_components(RenewableDispatch, sys)
    println(get_name(g)," pm=", get_prime_mover_type(g))
end

for g in get_components(ThermalStandard, sys)
    println(get_name(g), "  fuel=", get_fuel(g), "  pm=", get_prime_mover_type(g))
end

for g in get_components(ThermalMultiStart, sys)
    println(get_name(g), "  fuel=", get_fuel(g), "  pm=", get_prime_mover_type(g))
end

# %%
