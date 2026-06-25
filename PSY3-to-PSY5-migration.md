# Migrating PSI-Cambodia from Sienna PSY3 to PSY5

This guide documents how the PSI-Cambodia example was updated from the older
Sienna (PowerSystems.jl v2/PSY3-era) API to the current PSY5 stack. It is meant
as a practical checklist: every change below was applied to the files in this
repository, so you can follow the same steps to migrate your own scripts.

> **Terminology.** "PSY3" / "PSY5" refer to the Sienna / PowerSystems.jl
> generations. The exact resolved package versions before and after the update
> are listed in the table below.

## 1. Package versions

The environment was rebuilt against the current Sienna registry. Key version
jumps (see `Project.toml` / `Manifest.toml`):

| Package                       | Before (PSY3) | After (PSY5) |
| ----------------------------- | ------------- | ------------ |
| PowerSystems                  | 2.3.0         | 5.3.0        |
| PowerSimulations              | 0.20.2        | 0.32.4       |
| PowerAnalytics                | 0.3.3         | 1.1.0        |
| PowerGraphics                 | 0.14.0        | 0.21.0       |
| InfrastructureSystems         | 1.21.1        | 3.1.1        |
| StorageSystemsSimulations     | — (new)       | 0.14.1       |
| HydroPowerSimulations         | — (new)       | 0.13.1       |

Julia was also bumped to **1.11** (see the kernel header in the `.jl` files).

### `Project.toml` dependency changes

Added: `HydroPowerSimulations`, `StorageSystemsSimulations`, `PowerFlows`,
`PowerNetworkMatrices`, `PowerSystemCaseBuilder`, `InfrastructureSystems`,
`JSON`, `TimeSeries`.

Removed: `Literate`, `Logging` (`Logging` is still `using`-ed but it ships with
Julia's standard library, so it does not need to be an explicit dependency).

### How to rebuild the environment

```julia
] activate .
] rm PowerSystems PowerSimulations PowerAnalytics PowerGraphics   # drop old pins
] add PowerSystems PowerSimulations PowerAnalytics PowerGraphics
] add HydroPowerSimulations StorageSystemsSimulations PowerFlows PowerNetworkMatrices PowerSystemCaseBuilder InfrastructureSystems JSON TimeSeries
] instantiate
```

Then regenerate the serialized system by re-running `Cambodia-data-prep.jl`
(see §4) — a PSY3 `sys-cambodia.json` will **not** deserialize under PSY5.

## 2. Data-model / type renames

These renames affect both the scripts and the YAML mapping files.

| PSY3                                   | PSY5                                        | Where |
| -------------------------------------- | ------------------------------------------- | ----- |
| `Bus`                                  | `ACBus`                                      | results keys, e.g. `NodalBalanceActiveConstraint__Bus` → `...__ACBus` |
| `RenewableFix`                         | `RenewableNonDispatch`                       | `generator_mapping.yaml` |
| Battery / storage selectors           | `EnergyReservoirStorage`                     | `PSI-Cambodia.jl` PowerAnalytics selectors |

## 3. `PSI-Cambodia.jl` (the simulation) changes

1. **LMP / dual key rename** — `Bus` became `ACBus`:
   ```julia
   # PSY3
   read_realized_duals(uc_results)["NodalBalanceActiveConstraint__Bus"]
   # PSY5
   read_realized_duals(uc_results)["NodalBalanceActiveConstraint__ACBus"]
   ```

2. **Realized-expression column layout changed.** PSY5 results tables carry an
   extra leading column, so the numeric data now starts at column 3 and the sum
   uses the two-argument `sum`:
   ```julia
   # PSY3
   sum(sum(eachcol(costs[!, 2:end])))
   # PSY5
   sum(sum, eachcol(costs[:, 3:end]))
   ```

3. **PowerAnalytics 1.x API.** The old metric helpers were replaced by the
   selector + `compute_all` workflow. The script now uses:
   - `create_problem_results_dict(results_dir, "UC"; populate_system=true)`
   - `make_selector(ThermalStandard; groupby=:all)` (and likewise for
     `RenewableDispatch`, `EnergyReservoirStorage`)
   - `PowerAnalytics.Metrics.calc_active_power`, `calc_curtailment`,
     `calc_active_power_in/out`, `calc_stored_energy`,
     `calc_sum_objective_value`, `calc_sum_solve_time`, `calc_sum_bytes_alloc`
   - `compute_all(...)` + `aggregate_time(...)` to build the summary DataFrames.

4. **PowerGraphics** `plot_fuel`. PowerAnalytics 1.x's `make_fuel_dictionary`
   iterates over **all** `StaticInjection` components (which now includes
   `PowerLoad`), and a load has no fuel/prime-mover entry in `fuel_mapping.yaml`,
   so the category lookup returns `nothing` and the plot dies with
   `KeyError: key "nothing" not found`.

   A first attempt fixed this by passing `filter_func = x -> !isa(x, ElectricLoad)`
   to drop the loads. **That filter breaks the plot a different way:** `plot_fuel`
   also draws a demand line (`load = true` by default), and it forwards the *same*
   `filter_func` into `plot_demand!` → `get_load_data`. With every load filtered
   out, the demand series is empty and `combine_categories` reduces a
   `Matrix{Union{}}`, dying with
   `MethodError: promote_operation(::typeof(+), ::Type{Union{}}, ::Type{Union{}})`.

   The robust fix is to give `fuel_mapping.yaml` a catch-all category so loads
   resolve to a valid (but data-less) category instead of `nothing`, and call
   `plot_fuel` **without** `filter_func` so the demand line keeps its data.
   Loads carry no generation variable, so `categorize_data` drops them from the
   dispatch stack automatically:
   ```yaml
   # fuel_mapping.yaml — catch-all so PowerLoad never maps to `nothing`
   Other:
     - {primemover: null, fuel: null}
   ```
   ```julia
   # PSY3 (PowerAnalytics 0.x)
   plot_fuel(uc_results, generator_mapping_file = "fuel_mapping.yaml")
   # PSY5 (PowerAnalytics 1.x) — no filter_func; keeps the demand overlay
   plot_fuel(uc_results, generator_mapping_file = "fuel_mapping.yaml")
   ```

5. **Hydro dropped from the default UC template (regression — fixed).** PSY3's
   `template_unit_commitment()` attached a default `HydroDispatch` device model
   (run-of-river), so the 7 hydro units dispatched against their inflow series.
   PSY5's `_default_devices_uc()` no longer includes any hydro model, so
   `HydroDispatch` got no `ActivePowerVariable`, contributed ~0 MW, and was
   **absent from the dispatch stack** — and because Cambodia is hydro-heavy, the
   results badly over-dispatched thermal (no-RE thermal production cost 287,574
   vs. 107,719 with hydro). The fix re-attaches a run-of-river model explicitly:
   ```julia
   using HydroPowerSimulations   # provides HydroDispatchRunOfRiver
   template = template_unit_commitment(network = NetworkModel(DCPPowerModel, duals = [NodalBalanceActiveConstraint]))
   set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
   ```
   After re-running, hydro dispatches ~16,600 MWh over the 3-day window and
   appears as the `Hydropower` series in `plot_fuel`. `HydroPowerSimulations`
   was already added to `Project.toml` during the migration; it just needed to
   be loaded and wired into the template.

6. **Notebook generation uses jupytext, not Literate.** `PSI-Cambodia.jl` is a
   jupytext "percent"-format slideshow deck (it carries RISE
   `slideshow={...}` cell metadata in its `# %%` markers). Literate cannot parse
   jupytext's `name=... slideshow={...}` cell metadata and fails with
   `type Nothing has no field captures` in `parse_nbmeta`. `literate.jl` therefore
   builds this notebook with `jupytext --to notebook` (which preserves the slide
   metadata) and only uses `Literate.notebook(...)` for the true Literate-format
   `Cambodia-data-prep.jl`. Requires `jupytext` on `PATH` (ships with the Anaconda
   Python used here).

## 4. `Cambodia-data-prep.jl` (system construction) changes

1. **`transform_single_time_series!` signature.** The horizon is now a `Period`
   and a `resolution` keyword is required:
   ```julia
   # PSY3
   transform_single_time_series!(sys, 48, Hour(24))
   # PSY5
   transform_single_time_series!(sys, Hour(48), Hour(24), resolution = Dates.Hour(1))
   ```

2. **`System` constructor keywords.**
   ```julia
   # PSY3
   sys = System(rawsys, time_series_resolution = Dates.Hour(1))
   # PSY5
   sys = System(rawsys; time_series_in_memory = true, time_series_resolution = Hour(1))
   ```

3. **`PowerSystemTableData` now takes an explicit `timeseries_metadata_file`:**
   ```julia
   rawsys = PowerSystemTableData(
       sienna_data_dir, 100.0, "user_descriptors.yaml";
       generator_mapping_file = "generator_mapping.yaml",
       timeseries_metadata_file = joinpath(sienna_data_dir, "timeseries_pointers.csv"),
   )
   ```

4. **Time-series pointer format.** PSY5 requires each pointer to declare its
   time-series `type` and `module`. The `make_tsp` helper was rewritten to emit
   a list of dictionaries with `"type" => "SingleTimeSeries"` and
   `"module" => "PowerSystems"` (and the table is also written out as
   `timeseries_pointers.json` in addition to the CSV).

5. **Strict numeric typing.** PSY5 is stricter about time-series value types, so
   every component column is now explicitly coerced to `Float64` before building
   the system:
   ```julia
   for c in component_cols
       ts[!, c] = Float64.(ts[!, c])
   end
   ```

6. **Imports.** `using PowerGraphics` was dropped from the data-prep script;
   `using TimeSeries` and `using JSON` were added.

7. **In-code comments must use `##` (Literate gotcha).** `Cambodia-data-prep.jl`
   is run through `Literate.notebook(...)`. Literate treats *any* line whose first
   non-whitespace is `# ` (hash + space) as a **markdown** line — even when it is
   indented inside a function — which splits the surrounding code into separate
   notebook cells and produces a `ParseError: premature end of input`. Comments
   that must stay inside a code block (e.g. inside `make_tsp`/`make_ts_and_tsp`)
   were changed to `##`; Literate rewrites `##` back to `#` in the generated code.
   (`#"..."` with no space after `#` is already treated as code, so it was left
   as-is.)

## 5. Configuration / mapping file changes

- **`generator_mapping.yaml`** — `RenewableFix` → `RenewableNonDispatch`.
- **`user_descriptors.yaml`** — the cost-curve column mapping changed. PSY5's
  table parser requires at least one `output_point_*` column **paired with**
  either a `heat_rate_*` or a `cost_point_*` column; if it finds `output_point`
  columns but no `heat_rate`/`cost_point` partner it throws
  `DataFormatError("Configuration for cost terms not recognized")`. Map the real
  `heat_rate` column to `heat_rate_a1` (a linear heat-rate coefficient) and keep
  one zero `output_point_0`. With `fuel_price = 0` the effective marginal cost
  remains `var_om`, matching the PSY3 behavior:
  ```yaml
  # PSY3
  - {custom_name: zero_col, name: cost_point_0}
  - {custom_name: zero_col, name: output_point_0}
  # PSY5
  - {custom_name: heat_rate, name: heat_rate_a1}
  - {custom_name: zero_col, name: output_point_0}
  ```
  > Note: a bare `cost_point_0`/`output_point_0` pair of zeros is **not** a valid
  > PSY5 fix — a single `(0, 0)` point makes `create_pwl_cost` evaluate `0/0` and
  > yields a `NaN` cost. Use the `heat_rate_a1` mapping above instead.
- **`fuel_mapping.yaml`** — PSY5 matches fuel/prime-mover combinations more
  strictly, so explicit `{primemover, fuel}` entries were added for the prime
  movers present in this system (e.g. `{primemover: IC, fuel: DISTILLATE_FUEL_OIL}`,
  `{primemover: ST, fuel: COAL}`, `{primemover: OT, fuel: OTHER}`) alongside the
  existing generic fallbacks.

## 6. Serialized system files

Because the PSY3 serialization is not forward-compatible, the system was
regenerated under PSY5. The following committed artifacts were refreshed by
re-running `Cambodia-data-prep.jl`:

- `sys-cambodia.json` (regenerated)
- `sys-cambodia_time_series_storage.h5` (regenerated)
- `sys-cambodia_metadata.json` (**new** — PSY5 writes a metadata sidecar
  alongside the JSON)
- `sys-cambodia_validation_descriptors.json` (unchanged)

## 7. Migration checklist

1. Bump Julia to 1.11 and rebuild the environment (§1).
2. Apply the type renames `Bus → ACBus` and `RenewableFix → RenewableNonDispatch`
   (§2).
3. Update `PSI-Cambodia.jl` results/PowerAnalytics calls (§3).
4. Update `Cambodia-data-prep.jl` system-construction calls and the
   time-series pointer format (§4).
5. Update `generator_mapping.yaml`, `user_descriptors.yaml`, and
   `fuel_mapping.yaml` (§5).
6. Re-run `Cambodia-data-prep.jl` to regenerate `sys-cambodia.json` and its
   companion files (§6), then run `PSI-Cambodia.jl` to confirm the simulation
   executes end-to-end.
