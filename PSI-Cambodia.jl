# # Sienna\Ops Production Cost Modeling Demo using the [PowerSimulations.jl](https://github.com/Sienna-Platform/powersimulations.jl) package
# **Cambodia Example**: from [PowNet](https://github.com/kamal0013/PowNet)
#
# https://github.com/NLR-Sienna/PSI-Cambodia

#-
# ## Introduction
# This example shows how to run a PCM study using Powersimulations.jl. This example depends upon a
# dataset of the Cambodian grid assembled using the
# [Cambodia-data-prep.jl](./Cambodia-data-prep.jl) script and [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl).

#-
# ### Dependencies

#-
using PowerSystems
using PowerSimulations
using PowerAnalytics
using PlotlyLight
using PowerGraphics
using HydroPowerSimulations
using Logging
using Dates
using CSV
using DataFrames
using HiGHS
solver  = optimizer_with_attributes(HiGHS.Optimizer)

#-
logger = configure_logging(console_level = Logging.Info,
    file_level = Logging.Debug,
    filename = "log.txt")

sim_folder = mkpath(joinpath(pwd(), "Cambodia-sim"))

#-
# ### Load the `System` from the serialized data.
# *Note that the underlying time-series data is from 2016; time-stamps list 2017 as a hack from Cambodia-data-prep.jl to accommodate the fact that 2016 is a leap year and we have no leap day information*

#-
sys = System("sys-cambodia.json")

#-
# ## Set up PCM

#-
# ### Create a problem `template`
# Now we can create a `template` that specifies a standard unit commitment problem
# with a DCOPF network representation.
# Defining the duals allows us to retrieve the LMPs in the results
#
# PSY5's `template_unit_commitment()` no longer attaches a default device model for
# `HydroDispatch` (PSY3's default ran it as run-of-river). We add it back explicitly so
# the hydro fleet dispatches against its inflow time series and shows up in the results.

#-
template = template_unit_commitment(network = NetworkModel(DCPPowerModel, duals = [NodalBalanceActiveConstraint]))
set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)

#-
# ### Create a `model`
# Now we can apply the `template` to the data (`sys`) to create a `model`.
# *Note that you can define multiple models here to create multi-stage simulations*

#-
models = SimulationModels(
    decision_models=[
        DecisionModel(template, sys, optimizer=solver, name="UC"),
    ],
)

#-
# ### Sequential Simulation
# In addition to defining the formulation template, sequential simulations require
# definitions for how information flows between problems.

#-
DA_sequence = SimulationSequence(
    models=models,
    ini_cond_chronology=InterProblemChronology(),
)

#-
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

#-
sim = Simulation(
    name = "Cambodia-no-RE",
    steps = 3,
    models=models,
    sequence=DA_sequence,
    simulation_folder=sim_folder,
)

build!(sim, console_level = Logging.Info, file_level = Logging.Debug,  recorders = [:simulation])

#-
# ### Execute the simulation

#-
execute!(sim)

#-
# ## Explore Simulation Results

#-
# ### Load simulation results

#-
results = SimulationResults(sim)
uc_results = get_decision_problem_results(results, "UC")

#-
# ### Plot simulation results using [PowerGraphics.jl](https://github.com/Sienna-Platform/PowerGraphics.jl)

#-
plot_fuel_plotly(uc_results, generator_mapping_file = "fuel_mapping.yaml");

#-
# ## Read in some summary information about the optimization process
# Each objective_value is for the full 48 hour optimization window, including the lookahead

#-
first(read_optimizer_stats(uc_results), 10)

#-
# ### Now read in the *realized* cost for each timestep for each thermal generator
# In this model, wind, solar, and hydro have 0 operating cost and do not contribute to total cost

#-
costs = read_realized_expressions(uc_results, list_expression_names(uc_results))["ProductionCostExpression__ThermalStandard"]

#-
# ### We can sum over the set of generators and time-steps to get total production cost for this window

#-
sum(sum, eachcol(costs[:, 3:end]))

#-
# ### Look up a table of the Locational Marginal Prices (LMPs)
# LMPs represent the value of 1 additional MW of power at the given node
# LMPs are reversed in sign

#-
first(read_realized_duals(uc_results)["NodalBalanceActiveConstraint__ACBus"], 100)

#-
# # Now, let's connect the potential renewable generators

#-
# ### Connect renewable generators

#-
for g in get_components(RenewableDispatch, sys)
    set_available!(g, true)
end

## Rebuild decision models so unavailable renewables from the no-RE build are included.
models = SimulationModels(
    decision_models=[
        DecisionModel(template, sys, optimizer=solver, name="UC"),
    ],
)
DA_sequence = SimulationSequence(
    models=models,
    ini_cond_chronology=InterProblemChronology(),
)

#-
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

#-
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

#-
# ### Plot dispatch stack with renewables

#-
plot_fuel_plotly(uc_results, generator_mapping_file = "fuel_mapping.yaml");

#-
# ### Get total operating cost of system with renewables for comparison

#-
costs = read_realized_expressions(uc_results, list_expression_names(uc_results))["ProductionCostExpression__ThermalStandard"]
sum(sum, eachcol(costs[:, 3:end]))

#-
# ### Power Analytics Comparison
#

#-
## Load results folder
results_dir = sim_folder
results_all = create_problem_results_dict(results_dir, "UC"; populate_system=true)
results_all = Dict(
    "Cambodia-no-RE" => results_all["Cambodia-no-RE"],
    "Cambodia-RE"    => results_all["Cambodia-RE"],
)

## Define selectors
thermal_selector_sys    = make_selector(ThermalStandard; groupby=:all)
renewable_selector_sys  = make_selector(RenewableDispatch; groupby=:all)

## Define which time-series metrics to compute (same pattern as tutorial)
thermal_metrics = [
    (PowerAnalytics.Metrics.calc_active_power, thermal_selector_sys, "Thermal Generation (MWh)"),
]
renewable_metrics = [
    (PowerAnalytics.Metrics.calc_curtailment, renewable_selector_sys, "Renewables Curtailment (MWh)"),
]

function time_computations_for(scenario_name)
    if scenario_name == "Cambodia-RE"
        return vcat(thermal_metrics, renewable_metrics)
    else
        return thermal_metrics
    end
end

## define “Timeless” metrics (same as tutorial)
timeless_computations = [
    PowerAnalytics.Metrics.calc_sum_objective_value, 
    PowerAnalytics.Metrics.calc_sum_solve_time, 
    PowerAnalytics.Metrics.calc_sum_bytes_alloc]
timeless_names        = ["Objective Value", "Solve Time (s)", "Memory Allocated"]

## same as the tutorial too
function analyze_one(results, scenario_name)
    time_series_analytics = compute_all(results, time_computations_for(scenario_name)...)
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
        (ts, alltime) = analyze_one(results, scenario_name)
        save_one(results.results_output_folder, ts, alltime)
        push!(summaries, hcat(DataFrame("Scenario" => scenario_name), alltime))
    end
    summaries_df = vcat(summaries...; cols=:union)
    CSV.write(joinpath(results_dir,"all_scenarios_summary.csv"), summaries_df)
    return summaries_df
end

df_summary = post_processing(results_all)
show(df_summary; allcols=true)
