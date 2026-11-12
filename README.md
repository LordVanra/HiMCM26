# HiMCM cooling comparison

Run from this folder:

```r
source("01_physics/physics.R")
source("02_comfort/comfort.R")
source("03_decision/decision.R")
source("04_sensitivity/sensitivity.R")
cfg <- build_config()
tables <- load_tables()
result <- run_all(cfg, tables)
save_results(result)
s <- run_sensitivity(cfg, tables)
save_sensitivity(s)
```

`Rscript test_pipeline.R` runs the checks. Synthetic data exist only in the test file. Monte Carlo stays off unless `run_monte_carlo(cfg, tables)` is called explicitly.

## Inputs now assigned

- Six named reference venues, one occupied waiting-area zone each. Names and links are in the zones.csv source column.
- Each venue receives its city's sourced summer temperature, humidity and pressure for the user-selected one-hour scenario.
- Each A/B/C candidate has one reference device. These are candidate designs, not claims about installed equipment.
- Reference purchase prices: A $1,499; B $4,159; C $4,939. These are product references, not quoted prices of the hypothetical contest devices. Tax/installation are excluded.
- B/C airflow: 9,000 / 13,350 CFM, converted to 4.2475269888 / 6.30049836672 m3/s. Dry-air mass flow is calculated at each outdoor inlet condition from the ASHRAE specific-volume equation; no fixed density is guessed.
- Fan reference exposure: 1.81356 m/s, from the AirEye contour annotation. This is an explicitly selected near-field reference case, not a certified passenger distance/setting or a shelter-wide coverage claim.
- Clothing: user-selected T-shirt/shorts, 0.36 clo. The remaining person settings are the sourced seated reference configuration: 1 met, 0 met external work, 171 cm, 70 kg, Mosteller body area, 60-minute exposure, 40% turbulence. This is not measured passenger demographics.
- Physiological coefficients are explicitly assigned from comf::calcSET's documented implementation: csw=170, cdil=120, cstr=0.5.
- Contest powers and user-requested fixed outlet reductions are retained. Full source explanations remain beside the CSV values and in cooling_data_sources.csv.

## Simplifications applied at the user's request

The default is a reference comparison, not an exact site microclimate prediction:

1. `heat_model="mixing_only"`: outdoor/interzone exchange and device source terms are retained; surface heat exchange and internal heat/moisture generation are omitted. Their unknown input cells remain NA, not zero. Geometry, surface temperatures, convection coefficients and internal gains are not needed in this mode.
2. `radiant_model="air_reference"`: SET is evaluated with radiant temperature equal to modeled air temperature. Actual MRT inputs remain NA. This removes the MRT measurement requirement but cannot quantify solar/shade radiation effects.
3. `comfort_basis="per_person"`: decisions use the one-zone reference person's discomfort/benefit. Passenger counts remain NA. Actual passenger-total B, L and person-hours remain NA; they are never calculated using invented occupancy. Outputs distinguish `B_per_person`, `L_per_person`, `eta_per_person`, and the selected `loss`/`decision_eta` from the occupied-total columns.
4. `cost_basis="purchase"`: compare purchase cost and one-hour kWh/water. Annual maintenance, life, discount rate, annual weighting and tariffs are not required. Electricity cost is shown only if a tariff is supplied. A budget in this mode refers to purchase cost, not annual cost.

The full formulation remains available with heat_model="full", radiant_model="measured", comfort_basis="occupied", cost_basis="annual" and its required inputs. Per-person aggregation supports one occupied zone per venue; multi-zone population totals need actual occupancy.

## Physical inputs assigned

Both default-mode physical inputs are populated for all six waiting areas: balanced outdoor kg dry air/s in exchanges.csv and baseline passenger m/s in weather_occ.csv. These are authorized scenario estimates, not site measurements. DATA_README.md contains the six results, every assumption, calculation chain and complete source/BibTeX catalog.

The remaining choices are:
- cfg.set_upper and cfg.set_lower: your acceptable SET comfort range in degC. Upper is needed for hot-discomfort benefit/efficiency/regret; lower is needed only for two-sided comfort coverage.
- cfg.cooler_limit: keep "fixed" (your present instruction, invalid wet cases stay unavailable) or explicitly select "saturation_limit" to reduce the outlet drop when humidity prevents the full 5/8 degC reduction.
Passenger heat safety is unassessed. Optional budget/kWh/water caps remain inactive while NA. No extra physical inputs are required for the default simplified reference comparison. Actual-population totals and annual ownership costs are intentionally not part of that mode.

## One remaining model conflict

Fixed B/C drops plus a constant-enthalpy direct-evaporation moisture balance require supersaturation for B/C under the Boston mean, and C under the Dallas mean. Those water/moisture-dependent results are flagged, not clamped or fabricated. This is a conflict between requested model conditions, not another missing research value. Electrical energy and purchase cost still calculate. The implemented alternative cfg.cooler_limit="saturation_limit" solves the saturated outlet state at the same moist-air enthalpy, taking the smaller of the requested reduction and this physical maximum. It needs no invented effectiveness. This is an ideal upper-limit direct-evaporation model, not a measured cooler rating. The alternative is tested but not enabled automatically.

## Sensitivity and outputs

bounds.csv contains the user-authorized +/-5% around populated numerical inputs; hour IDs are not swept. Bounds are in each stored field's units (including degC for temperatures). Missing data remain NA. Rebuild/add the corresponding bounds row when a new physical input is supplied; the naming is table.row.column. Monte Carlo uses independent uniform draws within these bounds and labels its results conditional on them. Paired inlet/outlet rows are one flow parameter: they are changed together and sampled once. Disagreeing bounds for a pair are reported and skipped. Monte Carlo remains off for the project run.

Results are saved as CSVs in the four model folders. `result_options.csv` includes purchase cost, one-hour energy/water, per-person and occupied-total columns, selected loss/cost bases and the explicit model basis. No reference result should be presented as observed installation performance. The switching/benchmark/regret workflow retains all scenarios and does not drop missing competitors. The Pareto and break-even plots are saved when their required outputs are available; stale generated plots are removed if a later run cannot produce them. SET and SET reduction are calculated without a comfort threshold and are included in sensitivity results. Per-reference-person comfortable hours, hours gained and coverage are provided when the comfort range is set. These never substitute for passenger-total person-hours.

Each venue currently has one summer-mean scenario. Minimax regret is implemented and tested over multiple scenarios, but with one scenario it reduces to a constrained single-scenario choice. The +/-5% sweeps are sensitivity cases, not additional observed weather days.

The regression suite also covers the opt-in saturation-limited branch, conservation of outlet enthalpy, threshold-free SET differences, per-person coverage with unknown occupancy, paired Monte Carlo flow sampling, and stale plot removal.

Scientific references: the repository research CSV and bibliography; comf calcSET documentation at https://search.r-project.org/CRAN/refmans/comf/html/calcSET.html; ASHRAE psychrometric formulation documented by https://github.com/psychrometrics/psychrolib.
