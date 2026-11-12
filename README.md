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
save_chart_gallery(result, s, cfg, tables)
```

`Rscript test_pipeline.R` runs the checks. Synthetic data exist only in the test file. Monte Carlo stays off unless `run_monte_carlo(cfg, tables)` is called explicitly.

## Required data and unresolved decisions

`run_all()` checks the selected model's required data before computing anything. It stops with one list naming the table, field, row and venue for every missing required value. The individual model entry points also check their required data. Unknown fields used only by an inactive mode do not block the current run: for example, surface temperatures are not required by mixing-only physics, and annual tariffs are not required by purchase-cost comparison. Bounds are required only when sensitivity or Monte Carlo is requested. No Monte Carlo enable flag is required.

The user-selected comparison band is now `set_lower=23` and `set_upper=26` degC SET. It enables benefit, efficiency, discomfort, coverage and regret. This is a modeling policy, not an ASHRAE Standard 55 compliance test or a prediction that 80% of occupants are satisfied. ASHRAE comfort depends jointly on air and radiant temperature, humidity, airspeed, activity and clothing; its operative-temperature comfort zones are not a universal SET interval ([ASHRAE Handbook, Thermal Comfort](https://handbook.ashrae.org/handbooks/F25/SI/F25_Ch09/F25_Ch09_si.aspx)). The prior T-shirt/shorts input remains 0.36 clo; it was not silently replaced with 0.5 clo. Setting either threshold back to NA skips its dependent outputs. NA caps remain explicitly disabled as instructed.

`physical_valid` means all expected zone/hour temperature and moisture solutions exist within RH limits. `resource_feasible` means the configured caps pass. `feasible` requires both. It does not assess passenger safety. `decision_ready` additionally requires a discomfort loss and decision cost. Invalid fixed-drop coolers no longer appear feasible merely because caps are disabled. Regret is reported only for feasible options.

## Chart selection gallery

Open `graphs/index.html` to browse charts by model. Each chart has an ID, a PNG preview, an editable SVG and its plotted data as CSV. `graphs/chart_index.csv` lists ready and pending figures. Plot functions live in their respective model files; the gallery exporter is in sensitivity.R. Chart export requires ggplot2, dplyr and scales.

The chart style follows the supplied ggplot example: a minimal white background, light grid, blue A, green B, coral C and gray NONE. Physics charts show air conditions and resources. Comfort charts show SET and its change without inventing comfort thresholds. Sensitivity charts show ranked SET effects, response curves and resource swings within the supplied +/-5% bounds; they are not confidence intervals.

D02 compares cost, electricity and evaporated water on a radar chart. Each axis is divided by its largest displayed value across the complete profiles; smaller means lower resource use, not a better overall recommendation. D07 is the minimax decision radar (maximum regret, cost, electricity, water). Both are now calculable. Minimax selects by maximum regret, never by radar area. Cost, energy and water remain reported trade-offs with disabled caps; they are not silently combined into the regret objective.

These comparison layouts target the current one-hour, one-zone reference cases. Missing values are marked NA or explicitly omitted, never converted to zero. Existing model assumptions and incomplete cooler outputs still apply. Charts with no calculable values appear as pending cards instead of fabricated figures.

## Inputs now assigned

- Six named reference venues, one occupied waiting-area zone each. Names and links are in the zones.csv source column.
- Each venue now receives three simultaneous hot-weather hours from NASA POWER/MERRA-2: peak temperature, humid-hot and dry-hot. Each scenario lasts one hour. The original summer means are preserved in `sources/weather_occ_summer_mean.csv` but are no longer active decision scenarios.
- Each A/B/C candidate has one reference device. These are candidate designs, not claims about installed equipment.
- Reference purchase prices: A $1,499; B $4,159; C $4,939. These are product references, not quoted prices of the hypothetical contest devices. Tax/installation are excluded.
- B/C airflow: 9,000 / 13,350 CFM, converted to 4.2475269888 / 6.30049836672 m3/s. Dry-air mass flow is calculated at each outdoor inlet condition from the ASHRAE specific-volume equation; no fixed density is guessed.
- Fan reference exposure: 1.81356 m/s, from the AirEye contour annotation. This is an explicitly selected near-field reference case, not a certified passenger distance/setting or a shelter-wide coverage claim.
- Clothing: user-selected T-shirt/shorts, 0.36 clo. The remaining person settings are the sourced seated reference configuration: 1 met, 0 met external work, 171 cm, 70 kg, Mosteller body area, 60-minute exposure, 40% turbulence. This is not measured passenger demographics.
- Physiological coefficients are explicitly assigned from comf::calcSET's documented implementation: csw=170, cdil=120, cstr=0.5.
- Contest powers and 5/8 degC outlet cooling caps are retained. Actual outlet cooling is limited by the wet-bulb depression and the moisture balance.

## Simplifications applied at the user's request

The default is a reference comparison, not an exact site microclimate prediction:

1. `heat_model="mixing_only"`: outdoor/interzone exchange and device source terms are retained; surface heat exchange and internal heat/moisture generation are omitted. Their unknown input cells remain NA, not zero. Geometry, surface temperatures, convection coefficients and internal gains are not needed in this mode.
2. `radiant_model="air_reference"`: radiant temperature is held at the uncooled outdoor temperature for every option at a given zone/hour. Evaporative cooling therefore does not automatically cool the radiant surroundings. Actual MRT inputs remain NA. This is still an explicit neutral-radiation reference approximation, not a supported site-specific MRT prediction; use `radiant_model="measured"` and supplied `weather_occ.Tr` for that. Measured mode stops if Tr is missing.
3. `comfort_basis="per_person"`: decisions use the one-zone reference person's discomfort/benefit. Passenger counts remain NA. Actual passenger-total B, L and person-hours remain NA; they are never calculated using invented occupancy. Outputs distinguish `B_per_person`, `L_per_person`, `eta_per_person`, and the selected `loss`/`decision_eta` from the occupied-total columns.
4. `cost_basis="purchase"`: compare purchase cost and one-hour kWh/water. Annual maintenance, life, discount rate, annual weighting and tariffs are not required. Electricity cost is shown only if a tariff is supplied. A budget in this mode refers to purchase cost, not annual cost.

The full formulation remains available with heat_model="full", radiant_model="measured", comfort_basis="occupied", cost_basis="annual" and its required inputs. The arbitrary three-zone ceiling has been removed; a four-zone synthetic regression checks scaling. Per-person aggregation supports one occupied zone per venue; multi-zone population totals need actual occupancy. Tests demonstrate software behavior, not measured performance at larger venues.

`weather_occ.dt_hours` is the operating interval in hours, identical across zones in the same case. Its current value of 1 records the previously selected one-hour comparison. Energy, evaporated water and discomfort totals all multiply by this duration. Setting it to 8 models eight hours of those same conditions, not eight observed weather hours. `groups.ltime` separately controls the reference person's SET exposure in minutes; an eight-hour operating schedule does not imply every passenger waits eight hours.

`devices.v_occupied` optionally supplies the passenger-position airspeed for any technology. This takes priority over the existing fan reference speed or baseline speed. Missing values retain the explicitly labeled reference assumptions: A uses v_fan, while B/C use baseline v_local. Flow through a cooler is not automatically converted into a passenger airspeed or coverage area. A spatial coverage claim still needs supported exposure data.

Annual-cost mode now requires a water price for B/C as well as capital, maintenance, life, discount rate, electricity price and annual scenario weight. An explicit zero water price can represent a supported zero charge; NA no longer silently removes an applicable annual water expense. Purchase-cost mode remains the selected reference comparison.

## Physical inputs assigned

Both default-mode physical inputs are populated for all six waiting areas: balanced outdoor kg dry air/s in exchanges.csv and baseline passenger m/s in weather_occ.csv. These are authorized scenario estimates, not site measurements. DATA_README.md contains the six results, every assumption, calculation chain and complete source/BibTeX catalog.

The selected settings are `set_lower=23`, `set_upper=26` and `cooler_limit="saturation_limit"`. Upper is used for hot-discomfort benefit/efficiency/regret; lower is used for two-sided comfort coverage. The loss function remains hot discomfort, so a result below 23 degC SET affects coverage but is not assigned a new cold-discomfort penalty.
Passenger heat safety is unassessed. Optional budget/kWh/water caps remain inactive while NA. No extra physical inputs are required for the default simplified reference comparison. Actual-population totals and annual ownership costs are intentionally not part of that mode.

## Evaporative cooling limit

`saturation_limit` is now the default. Outlet cooling is capped at `min(dT_max, T_out - Twb_out)`. Humidity ratio follows the existing constant-enthalpy balance; if numerical/model differences would produce RH above 100%, the outlet is additionally limited at the constant-enthalpy saturation boundary. This preserves both the wet-bulb temperature limit and the moisture check. No device calibration values are invented. It is an ideal upper-limit model, not a measured product performance curve. The supersaturation conflict is resolved for the default run; the explicitly selected `fixed` mode still rejects impossible states.

A calibrated branch remains available as `cooler_limit="effectiveness"`. It requires `devices.T_ref` (degC), `RH_ref` (%) and `pressure_ref` (Pa), with reference conditions applying to the stated outlet drop. Those fields remain NA and are not required by the selected saturation-limit mode. The device caps describe outlet air in this model; waiting-area cooling is calculated by mixing, not assumed equal to 5/8 degC.

## Sensitivity and outputs

bounds.csv contains the user-authorized +/-5% around populated numerical inputs; hour IDs are not swept. Bounds are in each stored field's units (including degC for temperatures). Missing data remain NA. Rebuild/add the corresponding bounds row when a new physical input is supplied; the naming is table.row.column. Monte Carlo uses independent uniform draws within these bounds and labels its results conditional on them. Paired inlet/outlet rows are one flow parameter: they are changed together and sampled once. Disagreeing bounds for a pair are reported and skipped. Monte Carlo remains off for the project run.

These are exploratory perturbations, not evidence-based uncertainty intervals. In particular, +/-5% of a stored Celsius number depends on that scale's zero; it is not a thermodynamic relative-temperature uncertainty. Independent uniform weather draws do not preserve weather correlations and must not be presented as observed weather frequencies or confidence intervals.

Results are saved as CSVs in the four model folders. `result_options.csv` includes purchase cost, one-hour energy/water, per-person and occupied-total columns, selected loss/cost bases and the explicit model basis. No reference result should be presented as observed installation performance. The switching/benchmark/regret workflow retains all scenarios and does not drop missing competitors. The Pareto and break-even plots are saved when their required outputs are available; stale generated plots are removed if a later run cannot produce them. SET and SET reduction are calculated without a comfort threshold and are included in sensitivity results. Per-reference-person comfortable hours, hours gained and coverage are provided when the comfort range is set. These never substitute for passenger-total person-hours.

Each venue has three hot-weather scenarios, so minimax evaluates the same four alternatives across multiple conditions. The +/-5% sweeps remain separate exploratory sensitivity cases, not additional weather observations. `result_switching.csv` reports each scenario's best option(s) beside the robust choice. An empty sensitivity-switching table means no recommendation change was found within the sampled bounds; it does not mean the weather scenarios were omitted.

Recommendations include `scenario_count` and `decision_scope`. The new weather scenarios use simultaneous hourly temperature, humidity and pressure from NASA POWER/MERRA-2; they are gridded data, not shelter observations. Selection and provenance are in `sources/nasa_hourly_2025/README.md`. The bus/rail comparison retains the approved ventilation and baseline-airflow estimates; it does not establish actual rail-site prediction accuracy. Missing occupancy, surface heat inputs and measured device coverage are not invented.

The regression suite covers default saturation-limited cooling, conservation of outlet enthalpy, the wet-bulb limit, threshold-free SET differences, per-person coverage with unknown occupancy, paired Monte Carlo flow sampling, multi-scenario regret, sensitivity recomputation and stale plot removal.

Scientific references: the repository research CSV and bibliography; comf calcSET documentation at https://search.r-project.org/CRAN/refmans/comf/html/calcSET.html; ASHRAE psychrometric formulation documented by https://github.com/psychrometrics/psychrolib.
