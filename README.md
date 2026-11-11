# HiMCM26 cooling project

**ANALYSIS BLOCKED — no venue observations or project choices were supplied.**
The four source files parse in R 4.5.2. The blank-data run stops before physics,
SET, cost, regret, or sensitivity calculations. No numerical recommendations have
been generated. Blank CSV cells load as typed missing values. Only the supplied
A/B/C maxima and powers are recorded in `input_problem_ratings.csv`; this file is
a source reference, not a substitute for applicable operating specifications.

## Run from this directory

```r
source("01_physics/physics.R")
source("02_comfort/comfort.R")
source("03_decision/decision.R")
source("04_sensitivity/sensitivity.R")
config <- build_config()
run_project(config, run_sensitivity = TRUE, run_monte_carlo = FALSE)
```

Fill the `input_*.csv` files and edit `build_config()` before attempting analysis.
`write_input_templates(config)` creates absent templates without overwriting files.
Do not replace blanks with zero unless zero has a documented source. Replace the
single blank template row with actual records. Record every populated cell in
`01_physics/input_registry.csv` using `table.row.field` as its parameter ID.
The registry is separate from the collection templates. Derived values require
formulas and source IDs in notes. Registry uncertainty bounds may remain missing
unless that quantity participates in an enabled uncertainty analysis.

`01_physics/result_data_readiness.csv` and `missing_inputs.txt` enumerate the missing
fields, units, scopes, affected models, and entry locations. They are diagnostics,
not successful analysis results. A failed rerun does not delete prior result files;
check run IDs before interpreting any files from an earlier run.

## Contracts and decisions still required

The input contract is defined in `input_contract()` in physics.R. All temperatures
are degC, flow masses kg/s, moisture ratios kg water/kg dry air, pressures Pa,
power kW, surface heat rates W, water totals kg, and durations hours. IDs and
timestamps join cases, groups, equipment, and zones; use unique stable IDs.
`case_id` identifies a venue/scenario/option/model-variant combination. Each case
needs complete time coverage, including its matched NONE baseline. Supply explicit
zero counts for inactive equipment and zero-valued source terms only when known.
No equipment rows are needed for a NONE case once the equipment table is populated
with the active cases. `NONE` is a defined structural key, never an unknown value.

Occupancy sources are group totals, not per-person rates. A zone/time must have the
same local airspeed and mean radiant temperature for all groups; otherwise split
the exposure zones explicitly. Group clothing/activity is fixed over its group ID;
use distinct IDs if these change. Baseline comparison requires matching partitions,
weather, group population, duration, and baseline shade. Do not encode extra shade
as a cooling-device effect. Material capacitance must be separately justified within
the supplied total capacitance and not counted twice.

Before approval, read the following model limitations:

- The implemented balance uses supplied total/dry-air flow rates, constant supplied
  cp, well-mixed zones, prescribed surface temperatures, and no moisture buffering
  or condensation. Both flow mass bases must balance within supplied tolerances.
  The distinction between mass bases under evaporation requires an agreed
  approximation; an inconsistent dataset stops. Electrical heat must be included
  in the documented sensible sources where applicable, not inferred from power.
- Psychrometric equations use the ASHRAE liquid-water formulation as documented by
  PsychroLib, restricted to nonnegative wet bulbs and dry bulbs 0–200 degC. Direct
  evaporation uses constant moist-air enthalpy. These are proposed mathematical
  approximations awaiting `psychrometric_approval` and `balance_approval`, not
  accepted project assumptions. Unsupported or supersaturated states stop.
- Incoming evaporative supply is implemented for outdoor inlet air. Ordinary
  interzone recirculation is supported. Evaporative recirculation is explicitly
  unsupported and stops; it requires a nonlinear extension after the actual system
  is known. A uses measured local airspeed and never subtracts 3 degC from air.
- B/C need actual effectiveness and reference conditions. `outlet` checks measured
  reference reduction against effectiveness. `shelter` additionally requires a
  supplied audited `shelter_calibration(device, inputs, case, config)` function.
  The maxima cannot establish effectiveness without reference conditions.
- Dynamic forcing is piecewise constant in each supplied interval; occupancy
  benefit uses interval-start exposure. This quadrature and interval resolution
  require `time_approval` and a convergence study. Steady mode requires a response-
  time comparison with occupancy/weather changes in `steady_justification`.
- Only fixed NONE/A/B/C investments and operation are implemented. Additional
  adaptive policies require an explicit evaluator extension after information and
  policy rules are agreed. The `policy_description` and `information_rule` must
  state what is chosen before conditions are observed.
- SET needs every comf argument, the exact installed version, and a source audit
  of internal physiological constants/applicability. `set_audit` documents that
  review. Package signature checking does not by itself validate physiology.
- Safety uses externally documented case-level assessments, not SET-derived medical
  conclusions. Missing assessments block the pipeline. No safety pass is assumed.
- Annual costs require explicit representative annual weights and common currency.
  Demand and other charges must be documented, including known zero. Resource
  caps refer to the evaluated horizon; budgets refer to annual cost. Optional grid
  emissions are not implemented; do not imply an emissions result exists.
- Robust feasibility requires the selected option to pass every scenario.
  `comparator = "robust"` compares against robust-feasible actions; `"scenario"`
  compares against each scenario's feasible actions. All use the same resource
  limits. Near-tie tolerance is supplied by the user. Zero-energy efficiency is NA.
- Sensitivity requires supplied bounds, selected pairs, approved rating/partition
  alternatives, and an audited `sensitivity_recompute(config, inputs, spec, value)`
  adapter returning `list(config=..., inputs=...)`. It must recompute dependent
  quantities and provenance coherently. `approved_alternatives(config, inputs)`
  returns a list of `list(id=..., config=..., inputs=...)` for confirmed alternatives.
  These functions cannot be filled responsibly without the actual model choices.
- Optional Monte Carlo requires explicit authorization, joint sampler `mc_draw`,
  convergence function `mc_converged`, count, seed, quantile probabilities, and
  source documentation. The sampler returns a complete config/input pair; it must
  never fill missing observations. Monte Carlo is disabled initially.

## Verification status and remaining implementation limits

See `check_structural.txt` and each model's `check_verification.csv`. Structural
checks exercise the actual blank-input rejection through each public entry point.
Scientific checks are BLOCKED, not PASS: published psychrometric/SET reference
values, residual checks on real data, timestep convergence, independent validation,
regret behavior on real scenarios, calibration, and scaling need applicable inputs.
The check functions report those prerequisites; they are not a completed numerical
test suite. No fabricated fixtures have been used.

This is a guarded implementation with extension points, **not a verified completed
scientific workflow**. In particular, rail outputs currently list matched variant
results; automatic change/reason/impact and simpler-case recovery checks still need
an approved mapping between partitions. Influential venue characteristics require
the approved sensitivity transformations. Numerical briefs are evidence extracts,
not finished COO/blog prose. Sensitivity and decision analysis preserve
no_feasible_option; regret normalization is undefined for those cases.
Do not remove these limitations from reporting until they are implemented and tested.

No package was installed automatically. Required packages: comf for SET and deSolve
for dynamic ODEs. Record and audit their exact versions after manual installation.
There is no dependency lockfile because no scientific package environment has been
installed or verified. The existing R environment is recorded in check_session.txt.

## Reviewed documentation

- SET signature/units and references: https://search.r-project.org/CRAN/refmans/comf/html/calcSET.html
- deSolve ODE contract: https://search.r-project.org/CRAN/refmans/deSolve/html/ode.html
- Psychrometric equations: https://github.com/psychrometrics/psychrolib/blob/master/src/c/psychrolib.c

No graphs, images, demo datasets, or assumed venue values are included.
