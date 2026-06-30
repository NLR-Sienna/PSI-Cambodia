#nb # %% A slide [markdown] {"slideshow": {"slide_type": "slide"}}
# # Sienna\Ops Production Cost Modeling Demo using the [PowerSimulations.jl](https://github.com/Sienna-Platform/PowerSimulations.jl) package
# **Cambodia Example**: from [PowNet](https://github.com/kamal0013/PowNet)
#
# https://github.com/NLR-Sienna/PSI-Cambodia

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "slide"}}
# ## Introduction
# This example shows how to run a PCM study using Powersimulations.jl. This example depends upon a
# dataset of the Cambodian grid assembled using the
# [Cambodia-data-prep.jl](./Cambodia-data-prep.jl) script and [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl).

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Dependencies

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
using PowerSystems
using PowerSimulations
using PowerAnalytics
using PowerGraphics
using Logging
using Dates
using CSV
using DataFrames
using HiGHS
solver  = optimizer_with_attributes(HiGHS.Optimizer)
plotlyjs()

#-
#nb %% A slide [code] {"slideshow": {"slide_type": "skip"}}
logger = configure_logging(console_level = Logging.Info,
    file_level = Logging.Debug,
    filename = "log.txt")

sim_folder = mkpath(joinpath(pwd(), "Cambodia-sim"))

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Load the `System` from the serialized data.
# *Note that the underlying time-series data is from 2016; time-stamps list 2017 as a hack from Cambodia-data-prep.jl to accommodate the fact that 2016 is a leap year and we have no leap day information*

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
sys = System("sys-cambodia.json")

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "slide"}}
# ## Set up PCM

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Create a problem `template`
# Now we can create a `template` that specifies a standard unit commitment problem
# with a DCOPF network representation.
# Defining the duals allows us to retrieve the LMPs in the results

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
template = template_unit_commitment(network = NetworkModel(DCPPowerModel, duals = [NodalBalanceActiveConstraint]))

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Create a `model`
# Now we can apply the `template` to the data (`sys`) to create a `model`.
# *Note that you can define multiple models here to create multi-stage simulations*

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
models = SimulationModels(
    decision_models=[
        DecisionModel(template, sys, optimizer=solver, name="UC"),
    ],
)

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Sequential Simulation
# In addition to defining the formulation template, sequential simulations require
# definitions for how information flows between problems.

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
DA_sequence = SimulationSequence(
    models=models,
    ini_cond_chronology=InterProblemChronology(),
)

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
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

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
sim = Simulation(
    name = "Cambodia-test",
    steps = 3,
    models=models,
    sequence=DA_sequence,
    simulation_folder=mktempdir(cleanup=true),
)

build!(sim, console_level = Logging.Info, file_level = Logging.Debug,  recorders = [:simulation])

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Execute the simulation

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
execute!(sim)

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "slide"}}
# ## Explore Simulation Results

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Load simulation results

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
results = SimulationResults(sim)
uc_results = get_decision_problem_results(results, "UC")

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Plot simulation results using [PowerGraphics.jl](https://github.com/Sienna-Platform/PowerGraphics.jl)

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
plot_fuel(uc_results, generator_mapping_file = "fuel_mapping.yaml");

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ## Read in some summary information about the optimization process
# Each objective_value is for the full 48 hour optimization window, including the lookahead

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
first(read_optimizer_stats(uc_results), 10)

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Now read in the *realized* cost for each timestep for each thermal generator
# In this model, wind, solar, and hydro have 0 operating cost and do not contribute to total cost

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
costs = read_realized_expressions(uc_results, list_expression_names(uc_results))["ProductionCostExpression__ThermalStandard"]

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### We can sum over the set of generators and time-steps to get total production cost for this window
sum(sum(eachcol(costs[!, 2:end])))

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Look up a table of the Locational Marginal Prices (LMPs)
# LMPs represent the value of 1 additional MW of power at the given node
# LMPs are reversed in sign

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
first(read_realized_duals(uc_results)["NodalBalanceActiveConstraint__Bus"], 10)

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "slide"}}
# # Now, let's connect the potential renewable generators

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Connect renewable generators

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
for g in get_components(RenewableDispatch, sys)
    set_available!(g, true)
end

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
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

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
build!(sim, console_level = Logging.Info, file_level = Logging.Debug,  recorders = [:simulation]);
execute!(sim);
results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC");

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Plot dispatch stack with renewables

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
plot_fuel(uc_results, generator_mapping_file = "fuel_mapping.yaml");

#nb # %% A slide [markdown] {"slideshow": {"slide_type": "subslide"}}
# ### Get total operating cost of system with renewables for comparison

#nb %% A slide [code] {"slideshow": {"slide_type": "fragment"}}
costs = read_realized_expressions(uc_results, list_expression_names(uc_results))["ProductionCostExpression__ThermalStandard"]
sum(sum(eachcol(costs[!, 2:end])))
