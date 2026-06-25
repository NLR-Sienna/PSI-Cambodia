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

# %% [markdown] name="A slide " slideshow={"slide_type": "slide"}
# # Sienna\Ops Production Cost Modeling Demo using the [PowerSimulations.jl](https://github.com/nrel-sienna/powersimulations.jl) package
# **Cambodia Example**: from [PowNet](https://github.com/kamal0013/PowNet)
#
# https://github.com/NREL-Sienna/PSI-Cambodia

# %% [markdown] name="A slide " slideshow={"slide_type": "slide"}
# ## Introduction
# This example shows how to run a PCM study using Powersimulations.jl. This example depends upon a
# dataset of the Cambodian grid assembled using the
# [Cambodia-data-prep.jl](./Cambodia-data-prep.jl) script and [PowerSystems.jl](https://github.com/nrel-sienna/powersystems.jl).

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Dependencies

# %% name="A slide " slideshow={"slide_type": "fragment"}
using PowerSystems
using PowerSimulations
using PowerAnalytics
using PowerGraphics
using HydroPowerSimulations
using Logging
using Dates
using CSV
using DataFrames
using HiGHS
solver  = optimizer_with_attributes(HiGHS.Optimizer)
plotlyjs()

# %% name="A slide " slideshow={"slide_type": "skip"}
logger = configure_logging(console_level = Logging.Info,
    file_level = Logging.Debug,
    filename = "log.txt")

sim_folder = mkpath(joinpath(pwd(), "Cambodia-sim"))

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Load the `System` from the serialized data.
# *Note that the underlying time-series data is from 2016; time-stamps list 2017 as a hack from Cambodia-data-prep.jl to accommodate the fact that 2016 is a leap year and we have no leap day information*

# %% name="A slide " slideshow={"slide_type": "fragment"}
sys = System("sys-cambodia.json")

# %% [markdown] name="A slide " slideshow={"slide_type": "slide"}
# ## Set up PCM

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Create a problem `template`
# Now we can create a `template` that specifies a standard unit commitment problem
# with a DCOPF network representation.
# Defining the duals allows us to retrieve the LMPs in the results
#
# PSY5's `template_unit_commitment()` no longer attaches a default device model for
# `HydroDispatch` (PSY3's default ran it as run-of-river). We add it back explicitly so
# the hydro fleet dispatches against its inflow time series and shows up in the results.

# %% name="A slide " slideshow={"slide_type": "fragment"}
template = template_unit_commitment(network = NetworkModel(DCPPowerModel, duals = [NodalBalanceActiveConstraint]))
set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Create a `model`
# Now we can apply the `template` to the data (`sys`) to create a `model`.
# *Note that you can define multiple models here to create multi-stage simulations*

# %% name="A slide " slideshow={"slide_type": "fragment"}
models = SimulationModels(
    decision_models=[
        DecisionModel(template, sys, optimizer=solver, name="UC"),
    ],
)

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Sequential Simulation
# In addition to defining the formulation template, sequential simulations require
# definitions for how information flows between problems.

# %% name="A slide " slideshow={"slide_type": "fragment"}
DA_sequence = SimulationSequence(
    models=models,
    ini_cond_chronology=InterProblemChronology(),
)

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Define and build a simulation
# This simulation is only 3 days (3 steps) for computation speed. In order to run a year-long (364 days due to the 24 hour lookahead) simulations, the following code is recommended instead:
#
# sim = Simulation(
#     name = "Cambodia-year-no_RE",
#     steps = 364,
#     models=models,
#     sequence=DA_sequence,
#     simulation_folder=sim_folder,
# )

# %% name="A slide " slideshow={"slide_type": "fragment"}
sim = Simulation(
    name = "Cambodia-no-RE",
    steps = 3,
    models=models,
    sequence=DA_sequence,
    simulation_folder=sim_folder,
)

build!(sim, console_level = Logging.Info, file_level = Logging.Debug,  recorders = [:simulation])

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Execute the simulation

# %% name="A slide " slideshow={"slide_type": "fragment"}
execute!(sim)

# %% [markdown] name="A slide " slideshow={"slide_type": "slide"}
# ## Explore Simulation Results

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Load simulation results

# %% name="A slide " slideshow={"slide_type": "fragment"}
results = SimulationResults(sim)
uc_results = get_decision_problem_results(results, "UC")

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Plot simulation results using [PowerGraphics.jl](https://github.com/nrel-sienna/PowerGrahpics.jl)

# %% name="A slide " slideshow={"slide_type": "fragment"}
plot_fuel(uc_results, generator_mapping_file = "fuel_mapping.yaml");

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ## Read in some summary information about the optimization process
# Each objective_value is for the full 48 hour optimization window, including the lookahead

# %% name="A slide " slideshow={"slide_type": "fragment"}
first(read_optimizer_stats(uc_results), 10)

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Now read in the *realized* cost for each timestep for each thermal generator
# In this model, wind, solar, and hydro have 0 operating cost and do not contribute to total cost

# %% name="A slide " slideshow={"slide_type": "fragment"}
costs = read_realized_expressions(uc_results, list_expression_names(uc_results))["ProductionCostExpression__ThermalStandard"]

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### We can sum over the set of generators and time-steps to get total production cost for this window

# %%
#sum(sum(eachcol(costs[!, 2:end])))
sum(sum, eachcol(costs[:, 3:end]))

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Look up a table of the Locational Marginal Prices (LMPs)
# LMPs represent the value of 1 additional MW of power at the given node
# LMPs are reversed in sign

# %% name="A slide " slideshow={"slide_type": "fragment"}
first(read_realized_duals(uc_results)["NodalBalanceActiveConstraint__ACBus"], 100)

# %% [markdown] name="A slide " slideshow={"slide_type": "slide"}
# # Now, let's connect the potential renewable generators

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Connect renewable generators

# %% name="A slide " slideshow={"slide_type": "fragment"}
for g in get_components(RenewableDispatch, sys)
    set_available!(g, true)
end

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Re-build and re-simulate
# If switching to a year-long simulation rather than 3-day snapshot, first re-run the simulation definition. This also saves the result to a separate folder than the "no RE" base case to allow for post-processing comparisons:
#
# sim = Simulation(
#     name = "Cambodia-year-RE",
#     steps = 364,
#     models=models,
#     sequence=DA_sequence,
#     simulation_folder=sim_folder,
# )

# %% name="A slide " slideshow={"slide_type": "fragment"}
sim = Simulation(
    name = "Cambodia-RE",
    steps = 3,
    models=models,
    sequence=DA_sequence,
    simulation_folder=sim_folder,
)


build!(sim, console_level = Logging.Info, file_level = Logging.Debug,  recorders = [:simulation]);
execute!(sim);
results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC");

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Plot dispatch stack with renewables

# %% name="A slide " slideshow={"slide_type": "fragment"}
plot_fuel(uc_results, generator_mapping_file = "fuel_mapping.yaml");

# %% [markdown] name="A slide " slideshow={"slide_type": "subslide"}
# ### Get total operating cost of system with renewables for comparison

# %% name="A slide " slideshow={"slide_type": "fragment"}
costs = read_realized_expressions(uc_results, list_expression_names(uc_results))["ProductionCostExpression__ThermalStandard"]
sum(sum, eachcol(costs[:, 3:end]))

# %% [markdown]
# ### Power Analytics Comparsion
#

# %%
# Load results folder 
results_dir = sim_folder
results_all = create_problem_results_dict(results_dir, "UC"; populate_system=true)
results_all = Dict(
    "Cambodia-no-RE" => results_all["Cambodia-no-RE"],
    "Cambodia-RE"    => results_all["Cambodia-RE"],
)

# Define selectors
thermal_selector_sys    = make_selector(ThermalStandard; groupby=:all)
renewable_selector_sys  = make_selector(RenewableDispatch; groupby=:all)
storage_selector_sys    = make_selector(EnergyReservoirStorage; groupby=:all)

#Define which time-series metrics to compute (same pattern as tutorial)
time_computations = [
    (PowerAnalytics.Metrics.calc_active_power,     thermal_selector_sys,   "Thermal Generation (MWh)"),
    (PowerAnalytics.Metrics.calc_curtailment,      renewable_selector_sys, "Renewables Curtailment (MWh)"),
    (PowerAnalytics.Metrics.calc_active_power_in,  storage_selector_sys,   "Storage Charging (MWh)"),
    (PowerAnalytics.Metrics.calc_active_power_out, storage_selector_sys,   "Storage Discharging (MWh)"),
    (PowerAnalytics.Metrics.calc_stored_energy,    storage_selector_sys,   "Storage SOC (MWh)"),
]

# define “Timeless” metrics (same as tutorial)
timeless_computations = [
    PowerAnalytics.Metrics.calc_sum_objective_value, 
    PowerAnalytics.Metrics.calc_sum_solve_time, 
    PowerAnalytics.Metrics.calc_sum_bytes_alloc]
timeless_names        = ["Objective Value", "Solve Time (s)", "Memory Allocated"]

# same as the tutorial too
function analyze_one(results)
    time_series_analytics = compute_all(results, time_computations...)
    aggregated_time       = aggregate_time(time_series_analytics)
    computed_all          = compute_all(results, timeless_computations, nothing, timeless_names)
    all_time_analytics    = hcat(aggregated_time, computed_all)
    return time_series_analytics, all_time_analytics
end

function save_one(results_dir, time_series_analytics, all_time_analytics)
    CSV.write(joinpath(results_dir, "summary_dataframe.csv"), time_series_analytics)
    CSV.write(joinpath(results_dir, "summary_stats.csv"), all_time_analytics)
end

function post_processing(all_results)
    summaries = DataFrame[]
    for (scenario_name, results) in pairs(all_results)
        println("Computing for scenario: ", scenario_name)
        (ts, alltime) = analyze_one(results)
        save_one(results.results_output_folder, ts, alltime)
        push!(summaries, hcat(DataFrame("Scenario" => scenario_name), alltime))
    end
    summaries_df = vcat(summaries...)
    CSV.write(joinpath(results_dir,"all_scenarios_summary.csv"), summaries_df)
    return summaries_df
end

df_summary = post_processing(results_all)
show(df_summary; allcols=true)


# %%
