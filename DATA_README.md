# Data README: active inputs, assumptions and source audit

Updated 12 November 2026. The summer comparison includes four venues in each study area: a bus stop, a rail platform, a campus courtyard, and a covered outdoor airport terminal area. Ventilation and baseline airspeed use documented scenario estimates.

The technical correction holds reference radiant temperature at uncooled outdoor temperature across device options. It does not establish actual MRT. `weather_occ.dt_hours=1` now explicitly records the already selected operating interval. New optional `devices.v_occupied`, `T_ref`, `RH_ref` and `pressure_ref` fields remain NA; no passenger exposure or calibration conditions have been invented. The default fixed cooling comparison, per-person basis and purchase-cost basis remain as previously selected. Required missing data now stop the requested analysis; inputs used only by inactive modes do not. Current code behavior and the remaining limits are described in README.md.

## Active airflow estimates

| Waiting area | Baseline passenger airspeed (m/s) | Ventilation (m³/s) | Ventilation (kg dry air/s) |
|---|---:|---:|---:|
| DAL_BUS | 0.931468 | 1.956083 | 2.179867 |
| DAL_RAIL | 1.397202 | 5.216221 | 5.812979 |
| BOS_BUS | 0.453536 | 0.952425 | 1.112528 |
| BOS_RAIL | 0.680304 | 2.539801 | 2.966742 |
| PHX_BUS | 0.690180 | 1.449379 | 1.550364 |
| PHX_RAIL | 1.035271 | 3.865010 | 4.134305 |

CSV inputs retain full calculation precision. Each mass flow is written to BOTH the outdoor inlet and outlet rows; this describes one balanced throughflow, not twice the ventilation rate. The density conversion uses each city’s temperature, RH and pressure and the model’s dry-air basis.

## Location references

| ID | Selected real location | Identity source |
|---|---|---|
| DAL_BUS | Rosa Parks Plaza, northbound shelter at bays N/O, 901 Elm St | `dart_rosa` |
| DAL_RAIL | West End Station, covered platform waiting area, 800 Pacific Ave | `dart_west` |
| BOS_BUS | Grove Hall Route 28 clear-roof control shelter shown in B-COOL Images 9-10 | `boston_shade` |
| BOS_RAIL | Mattapan Station, outdoor trolley-platform waiting area near Mattapan Square | `bwa_mattapan` |
| PHX_BUS | Central Avenue/Camelback Transit Center, bus passenger shelter | `valley_bus` |
| PHX_RAIL | Central Avenue/Camelback light-rail station, canopy-covered waiting area | `valley_rail` |

Boston bus means the clear-roof Grove Hall control shelter shown in the B-COOL report; the report does not identify its exact stop number. Mattapan means the outdoor trolley waiting zone, not the enclosed building. Phoenix bus and rail are separate waiting zones at Central/Camelback. Dallas bus is Rosa Parks Plaza and rail is West End. None of these identity sources supplies measured ventilation or passenger wind.

## Additional venue case studies

| Study area | Campus courtyard | Covered outdoor airport terminal area |
|---|---|---|
| Dallas | `DAL_QUAD` · [Dallas College Mountain View Student Courtyard](https://www.dallascollege.edu/about/legal/speech-expression-assembly/) | `DAL_PAV` · [Dallas Love Field baggage-claim curbside canopy](https://dallas.gov/government/Council%20Meeting%20Documents/2015/B-Dallas-LoveField_021815.pdf) |
| Boston | `BOS_QUAD` · [Boston University George Sherman Union Courtyard](https://www.bu.edu/reservations/around-campus/outdoor-locations/) | `BOS_PAV` · [Boston Logan Terminal C departures canopy](https://www.skanska.com/us/en/construction/transportation-infrastructure/airports/massport-terminal-c-canopy) |
| Phoenix | `PHX_QUAD` · [ASU Delph Courtyard, West Valley campus](https://tours.asu.edu/west/delph-courtyard) | `PHX_PAV` · [Phoenix Sky Harbor Terminal 3 curbside canopy](https://www.gftinc.com/project/phoenix-sky-harbor-international-airport-terminal-3-modernization-phase-1/) |

The airport cases represent outdoor passenger areas beneath terminal canopies. Each site is modeled as one occupied zone with the same seated reference person and one device per candidate. The reference exposure is a standardized one-hour comparison; actual dwell times and occupancy are unknown.

| Study area | Summer air temperature (°C) | Relative humidity (%) | Pressure (kPa) | Baseline airspeed (m/s), both sites | Courtyard exchange (kg dry air/s) | Canopy exchange (kg dry air/s) |
|---|---:|---:|---:|---:|---:|---:|
| Dallas | 29.2 | 62.0 | 99.230 | 1.397 | 11.626 | 17.439 |
| Boston | 21.1 | 75.9 | 100.560 | 0.680 | 5.933 | 8.900 |
| Phoenix | 33.0 | 26.8 | 95.350 | 1.035 | 8.269 | 12.403 |

Each city uses the same 2001–2025 NASA POWER June–August climate reference as its bus and rail cases. Both venue types use the rail exposure factor of 0.75 and opening effectiveness of 0.35. Equivalent openings of 16 m² for courtyards and 24 m² for canopies are scenario assumptions that let the model compare larger outdoor exchange rates. Within each city, the modeled canopy has 1.5 times the courtyard exchange by construction. The calculation chain below converts those openings into airflow estimates. Site measurements of openings, airflow, radiant temperature, and equipment coverage would be needed to validate the comparison.

## Explicit scenario assumptions for the transit stops

| Input | Bus waiting zone | Rail waiting zone | Basis |
|---|---:|---:|---|
| Equivalent opening area | 3 m² | 8 m² | Analyst-selected 1.5×2 m and 4×2 m equivalent apertures; NOT as-built measurements |
| Opening effectiveness Cw | 0.35 | 0.35 | Selected from published oblique-wind range; actual wind direction unknown |
| Opening fraction | 1 | 1 | Entire assumed aperture active |
| Wind reference height | 1.1 m | 1.1 m | Chosen passenger-zone reference height, matching Phoenix study measurement height |
| Height-profile exponent | 0.33 | 0.33 | Published towns/cities exponent, applied as a simplified same-profile assumption |
| Passenger sheltering factor S | 0.50 | 0.75 | Analyst choices distinguishing a more sheltered bus zone from an open platform zone; NOT published calibration coefficients |
| Stack-driven ventilation | Omitted | Omitted | Wind-only approximation; not evidence that real stack exchange is zero |

The common type assumptions keep comparisons consistent across cities. They do not claim to reproduce individual canopies, nearby-building turbulence, wind direction, gusts or train/bus-induced flow. Source key `airflow_scenario_2026` explicitly documents these choices rather than attributing them to a manufacturer or transit agency.

## Calculation chain

1. NASA POWER WS10M: U10=(30×June+31×July+31×August)/92. Use the same 2001–2025 grid queries already used for each city’s climate.
2. Approach wind U=U10×(1.1/10)^0.33. The power-law form/exponent are supported by `energyplus_242_surface`, Local Wind Speed Calculation. Treating the gridded 10 m wind as an equivalent same-profile reference is our additional assumption; this is not the full weather-station-to-site terrain correction. Extrapolation into an urban canopy is approximate.
3. Baseline passenger speed v_local=S×U, independent of fan A. S is a scenario factor, not inferred from cooler CFM.
4. Ventilation Q=Cw×A_open×U, opening fraction 1, using the wind-driven term in `energyplus_wind_ventilation`. This is an approximation adapted to the generic waiting-zone control volume.
5. pv=(RH/100)×p_sat(T); w=0.621945×pv/(P−pv); specific volume=287.042×(T+273.15)×(1+1.607858w)/P; m_dry=Q/specific_volume. See `psychrolib_volume` and the existing physics.R saturation-pressure equation.

| City | June/July/August U10 (m/s) | Weighted U10 | Approach U (m/s) | Specific volume (m³/kg dry air) |
|---|---|---:|---:|---:|
| Dallas | 4.21 / 3.79 / 3.59 | 3.859565217 | 1.862936149 | 0.897340387 |
| Boston | 1.95 / 1.84 / 1.85 | 1.879239130 | 0.907071733 | 0.856090777 |
| Phoenix | 3.19 / 2.87 / 2.53 | 2.859782609 | 1.380360766 | 0.934863435 |

## Other active numerical inputs and their bases

| Input group | Values/basis | Source keys |
|---|---|---|
| City summer climate | Dallas 29.2°C, 62.0%, 99230 Pa; Boston 21.1°C, 75.9%, 100560 Pa; Phoenix 33.0°C, 26.8%, 95350 Pa | `nasa_2026_dallas_summer`, `nasa_2026_boston_summer`, `nasa_2026_phoenix_summer` |
| Climate aggregation | June–August full-day means, weights 30/31/31; pressure kPa×1000; grid anchors are airport coordinates, not on-site observations | NASA query records in research CSV |
| Contest A/B/C | 0.25/1.2/2.5 kW; up-to 3°C perceived / 5°C air / 8°C air reductions; fixed outlet drops in current reference model are a separate user-selected simplification | `comap_2026_options`, `comap_2026_problem_b` |
| A reference | AirEye 20-inch 120 V Midnight Black pedestal/low rider F-AE1-2001A750C716L10S34; $1499 opened listing price | `aireye_20_price` |
| A fan exposure | 357 ft/min×0.3048/60=1.81356 m/s; user-selected contour reference; no certified distance/setting or whole-shelter coverage | `aireye_2021_specs` |
| B reference | Portacool APEX 2000 PACA20001A1; 9000 CFM; $4159 MSRP | `portacool_2000` |
| C reference | Portacool APEX 4000 PACA40001A1; 13350 CFM; $4939 MSRP | `portacool_4000` |
| Cooler airflow conversion | CFM×0.028316846592/60: B 4.2475269888 and C 6.30049836672 m³/s; mass uses inlet specific volume | Exact foot-to-metre conversion and `psychrolib_volume` |
| Occupant clothing | User-selected T-shirt/shorts represented by ASHRAE shorts/short-sleeve ensemble, 0.36 clo; an ensemble proxy rather than measured passenger dress | `ashrae_2021_comfort` |
| Reference person | 1 met, 0 met external work, 171 cm, 70 kg, sitting, 60 minutes, 40% turbulence; area sqrt(171×70/3600)=1.823458252881047 m² | `comf_0112_set`; documented reference defaults, not demographics |
| Physiology | csw=170, cdil=120, cstr=0.5 | `comf_0112_set`, calcSET Usage |
| Scenario/model | One zone per venue, one reference hour, one device per candidate; mixing-only, MRT=modeled air temperature, per-person comfort, purchase-cost comparison | Existing user-selected configuration; project README.md |
| Sensitivity | Existing ±5% around active numeric inputs; now includes the two added inputs | User-selected convention, NOT confidence intervals |

The current A datasheet (2021 revision) lists 386 W whereas the retailer lists 363 W. Neither is the contest power. Older B literature lists 6700 CFM; the selected current manufacturer page lists 9000 CFM. These differences are recorded, not silently reconciled. Prices are observed references, exclude installation/tax, and can change. No actual utility account rate is assigned.

## Historical/reference-only numerical material

The research CSV retains unselected reference measurements, methods, old device specifications and costs. Its `record_role`, `status`, `applicability`, `calculation`, `source_locator` and `related_record_ids` distinguish these from active inputs. The following catalog lists EVERY research quantity and its provenance; it is not an assertion that every row is an active model input.

| Record | Quantity / location or device | Value or reference | Status | Citation key |
|---|---|---|---|---|
| cd001 | Average summer temperature; Dallas; not_applicable | 29.2 degC | verified_derived | nasa_2026_dallas_summer |
| cd002 | Average summer temperature; Boston; not_applicable | 21.1 degC | verified_derived | nasa_2026_boston_summer |
| cd003 | Average summer temperature; Phoenix; not_applicable | 33.0 degC | verified_derived | nasa_2026_phoenix_summer |
| cd004 | Average summer relative humidity; Dallas; not_applicable | 62.0 %RH | verified_derived | nasa_2026_dallas_summer |
| cd005 | Average summer relative humidity; Boston; not_applicable | 75.9 %RH | verified_derived | nasa_2026_boston_summer |
| cd006 | Average summer relative humidity; Phoenix; not_applicable | 26.8 %RH | verified_derived | nasa_2026_phoenix_summer |
| cd007 | Atmospheric pressure; Dallas; not_applicable | 9.923E+4 Pa | verified_derived | nasa_2026_dallas_summer |
| cd008 | Atmospheric pressure; Boston; not_applicable | 1.0056E+5 Pa | verified_derived | nasa_2026_boston_summer |
| cd009 | Atmospheric pressure; Phoenix; not_applicable | 9.535E+4 Pa | verified_derived | nasa_2026_phoenix_summer |
| cd019_bus | Dimensioned shelter/station layout; DAL_BUS; not_applicable | Roofed, open-front shelter; ambient air exchange not_applicable | generic_representation | dart_rosa |
| cd019_rail | Dimensioned shelter/station layout; DAL_RAIL; not_applicable | Roofed platform waiting zone, open to outdoor air not_applicable | generic_representation | dart_west |
| cd020_bus | Dimensioned shelter/station layout; BOS_BUS; not_applicable | Roofed, open-front shelter; ambient air exchange not_applicable | generic_representation | boston_shade |
| cd020_rail | Dimensioned shelter/station layout; BOS_RAIL; not_applicable | Roofed platform waiting zone, open to outdoor air not_applicable | generic_representation | bwa_mattapan |
| cd021_bus | Dimensioned shelter/station layout; PHX_BUS; not_applicable | Roofed, open-front shelter; ambient air exchange not_applicable | generic_representation | valley_bus |
| cd021_rail | Dimensioned shelter/station layout; PHX_RAIL; not_applicable | Roofed platform waiting zone, open to outdoor air not_applicable | generic_representation | valley_rail |
| cd022_bus | Ventilation or measured airflow through location; DAL_BUS; not_applicable | 1.9560829564140139 m3/s | scenario_estimate | airflow_scenario_2026 |
| cd022_rail | Ventilation or measured airflow through location; DAL_RAIL; not_applicable | 5.216221217104038 m3/s | scenario_estimate | airflow_scenario_2026 |
| cd023_bus | Ventilation or measured airflow through location; BOS_BUS; not_applicable | 0.9524253191799562 m3/s | scenario_estimate | airflow_scenario_2026 |
| cd023_rail | Ventilation or measured airflow through location; BOS_RAIL; not_applicable | 2.53980085114655 m3/s | scenario_estimate | airflow_scenario_2026 |
| cd024_bus | Ventilation or measured airflow through location; PHX_BUS; not_applicable | 1.4493788043047402 m3/s | scenario_estimate | airflow_scenario_2026 |
| cd024_rail | Ventilation or measured airflow through location; PHX_RAIL; not_applicable | 3.865010144812641 m3/s | scenario_estimate | airflow_scenario_2026 |
| cd037_bus | Airspeed where people stand or sit; DAL_BUS; not_applicable | 0.931468074482864 m/s | scenario_estimate | airflow_scenario_2026 |
| cd037_rail | Airspeed where people stand or sit; DAL_RAIL; not_applicable | 1.3972021117242959 m/s | scenario_estimate | airflow_scenario_2026 |
| cd038_bus | Airspeed where people stand or sit; BOS_BUS; not_applicable | 0.4535358662761697 m/s | scenario_estimate | airflow_scenario_2026 |
| cd038_rail | Airspeed where people stand or sit; BOS_RAIL; not_applicable | 0.6803037994142546 m/s | scenario_estimate | airflow_scenario_2026 |
| cd039_bus | Airspeed where people stand or sit; PHX_BUS; not_applicable | 0.6901803830022574 m/s | scenario_estimate | airflow_scenario_2026 |
| cd039_rail | Airspeed where people stand or sit; PHX_RAIL; not_applicable | 1.035270574503386 m/s | scenario_estimate | airflow_scenario_2026 |
| cd041 | Evaporative cooler airflow; not_applicable; B | 9000 CFM | proxy_estimate | portacool_2000 |
| cd042 | Evaporative cooler airflow; not_applicable; C | 13350 CFM | proxy_estimate | portacool_4000 |
| cd047 | Equipment purchase price; not_applicable; A | 1499.00 USD | proxy_estimate | aireye_20_price |
| cd048 | Equipment purchase price; not_applicable; B | 4159 USD | proxy_estimate | portacool_2000 |
| cd049 | Equipment purchase price; not_applicable; C | 4939 USD | proxy_estimate | portacool_4000 |
| cd062 | DWU non-residential water volume rate; Dallas; not_applicable | 5.32 USD/1000_US_gal | verified_reference_not_selected | dallas_2025_water_rates |
| cd063 | DWU non-residential water volume rate; Dallas; not_applicable | 5.88 USD/1000_US_gal | verified_reference_not_selected | dallas_2025_water_rates |
| cd064 | DWU non-residential water volume rate; Dallas; not_applicable | 8.59 USD/1000_US_gal | verified_reference_not_selected | dallas_2025_water_rates |
| cd065 | BWSC tiered water volume rate; Boston; not_applicable | 9.384 USD/1000_US_gal | verified_reference_not_selected | bwsc_2026_rates |
| cd066 | BWSC tiered water volume rate; Boston; not_applicable | 10.022 USD/1000_US_gal | verified_reference_not_selected | bwsc_2026_rates |
| cd067 | BWSC tiered water volume rate; Boston; not_applicable | 10.93 USD/1000_US_gal | verified_reference_not_selected | bwsc_2026_rates |
| cd068 | BWSC tiered water volume rate; Boston; not_applicable | 11.649 USD/1000_US_gal | verified_reference_not_selected | bwsc_2026_rates |
| cd069 | BWSC tiered water volume rate; Boston; not_applicable | 12.261 USD/1000_US_gal | verified_reference_not_selected | bwsc_2026_rates |
| cd070 | BWSC tiered water volume rate; Boston; not_applicable | 12.764 USD/1000_US_gal | verified_reference_not_selected | bwsc_2026_rates |
| cd071 | Phoenix high-season water volume charge; Phoenix; not_applicable | 6.13 USD/748_US_gal | verified_reference_not_selected | phoenix_2025_water_rates |
| cd072 | Phoenix water environmental charge; Phoenix; not_applicable | 0.62 USD/748_US_gal | verified_reference_not_selected | phoenix_2025_water_rates |
| cd073 | Oncor distribution energy component; Dallas; not_applicable | 0.031236 USD/kWh | verified_reference_not_selected | oncor_2026_delivery |
| cd074 | Eversource G-1 non-demand variable delivery total; Boston; not_applicable | 0.14804 USD/kWh | verified_reference_not_selected | eversource_2026_boston |
| cd075 | APS E-32 XS summer base bundled energy rate; Phoenix; not_applicable | 0.15055 USD/kWh | verified_reference_not_selected | aps_2024_e32xs |
| cd076 | APS E-32 XS summer base bundled energy rate; Phoenix; not_applicable | 0.08327 USD/kWh | verified_reference_not_selected | aps_2024_e32xs |
| sel001 | selected study location; DAL_BUS;  | Rosa Parks Plaza, northbound shelter at bays N/O, 901 Elm St text | selected_reference | dart_rosa |
| sel002 | selected study location; DAL_RAIL;  | West End Station, covered platform waiting area, 800 Pacific Ave text | selected_reference | dart_west |
| sel003 | selected study location; BOS_BUS;  | Grove Hall Route 28 clear-roof control shelter shown in B-COOL Images 9-10 text | selected_reference | boston_shade |
| sel004 | selected study location; BOS_RAIL;  | Mattapan Station, outdoor trolley-platform waiting area near Mattapan Square text | selected_reference | bwa_mattapan |
| sel005 | selected study location; PHX_BUS;  | Central Avenue/Camelback Transit Center, bus passenger shelter text | selected_reference | valley_bus |
| sel006 | selected study location; PHX_RAIL;  | Central Avenue/Camelback light-rail station, canopy-covered waiting area text | selected_reference | valley_rail |
| sel007 | selected equipment model; ; A | Big Ass Fans AirEye 20-inch 120 V Midnight Black pedestal/low rider; F-AE1-2001A750C716L10S34 text | selected_reference | aireye_20_price |
| sel008 | contest electrical power; ; A | 0.25 kW | problem_given | comap_2026_options |
| sel009 | contest maximum cooling; ; A | 3 degC perceived | problem_given | comap_2026_options |
| sel010 | selected equipment model; ; B | Portacool APEX 2000 (PACA20001A1) text | selected_reference | portacool_2000 |
| sel011 | contest electrical power; ; B | 1.2 kW | problem_given | comap_2026_options |
| sel012 | contest maximum cooling; ; B | 5 degC air-temperature reduction | problem_given | comap_2026_options |
| sel013 | selected equipment model; ; C | Portacool APEX 4000 (PACA40001A1) text | selected_reference | portacool_4000 |
| sel014 | contest electrical power; ; C | 2.5 kW | problem_given | comap_2026_options |
| sel015 | contest maximum cooling; ; C | 8 degC air-temperature reduction | problem_given | comap_2026_options |
| sel016 | manufacturer airflow; ; A | 2100 m3/h | superseded_reference | tttiger_ff10d |
| sel017 | manufacturer voltage; ; A | 220 V | superseded_reference | tttiger_ff10d |
| sel018 | manufacturer rated power; ; A | 0.25 kW | superseded_reference | tttiger_ff10d |
| sel019 | manufacturer airflow; ; B | 9000 CFM | selected_reference | portacool_2000 |
| sel020 | manufacturer voltage; ; B | 120 V | selected_reference | portacool_2000 |
| sel021 | manufacturer current; ; B | 8 A | selected_reference | portacool_2000 |
| sel022 | manufacturer airflow; ; C | 13350 CFM | selected_reference | portacool_4000 |
| sel023 | manufacturer voltage; ; C | 120 V | selected_reference | portacool_4000 |
| sel024 | manufacturer current; ; C | 9 A | selected_reference | portacool_4000 |
| res001 | fan reference maximum input power; ; A | 386 W | published_reference_not_site_input | aireye_2021_specs |
| res002 | fan reference maximum rotation; ; A | 1220 rpm | published_reference_not_site_input | aireye_2021_specs |
| res003 | fan reference airflow diagram annotation; ; A | 1.81356 m/s | published_reference_not_site_input | aireye_2021_specs |
| res004 | fan inspection frequency; ; A | 1 per year | published_reference_not_site_input | aireye_maintenance |
| res005 | replacement media set price; ; B | 406.99 USD | published_reference_not_site_input | portacool_media_prices |
| res006 | media life lower bound; ; B | 5 years | published_reference_not_site_input | portacool_buying_guide |
| res007 | annualized media only allowance; ; B | 81.40 USD/year | conditional_derived_reference | portacool_media_prices |
| res008 | minimum reservoir drain frequency; ; B | 1 per operating week | published_reference_not_site_input | portacool_apex_maintenance |
| res009 | media drying fan run time; ; B | 15 minutes per shutdown | published_reference_not_site_input | portacool_buying_guide |
| res010 | replacement media set price; ; C | 685.99 USD | published_reference_not_site_input | portacool_media_prices |
| res011 | media life lower bound; ; C | 5 years | published_reference_not_site_input | portacool_buying_guide |
| res012 | annualized media only allowance; ; C | 137.20 USD/year | conditional_derived_reference | portacool_media_prices |
| res013 | minimum reservoir drain frequency; ; C | 1 per operating week | published_reference_not_site_input | portacool_apex_maintenance |
| res014 | media drying fan run time; ; C | 15 minutes per shutdown | published_reference_not_site_input | portacool_buying_guide |
| res015 | set default clothing insulation; ;  | 0.5 clo | published_model_default | comf_0112_set |
| res016 | set default activity; ;  | 1 met | published_model_default | comf_0112_set |
| res017 | set default external work; ;  | 0 met | published_model_default | comf_0112_set |
| res018 | set default height; ;  | 171 cm | published_model_default | comf_0112_set |
| res019 | set default body mass; ;  | 70 kg | published_model_default | comf_0112_set |
| res020 | set default posture; ;  | sitting text | published_model_default | comf_0112_set |
| res021 | set default exposure duration; ;  | 60 minutes | published_model_default | comf_0112_set |
| res022 | set default turbulence intensity; ;  | 40 % | published_model_default | comf_0112_set |
| res023 | set default body surface area; ;  | 1.823458 m2 | derived_model_default | comf_0112_set |
| res024 | quiet seated activity; ;  | 1 met | published_reference_not_site_input | ashrae_2021_comfort |
| res025 | relaxed standing activity; ;  | 1.2 met | published_reference_not_site_input | ashrae_2021_comfort |
| res026 | shorts short sleeved shirt insulation; ;  | 0.36 clo | published_reference_not_site_input | ashrae_2021_comfort |
| res027 | trousers short sleeved shirt insulation; ;  | 0.57 clo | published_reference_not_site_input | ashrae_2021_comfort |
| res028 | seated reference sensible heat; ;  | 65 W/person | published_reference_not_site_input | idae_occupant_heat |
| res029 | seated reference latent heat; ;  | 35 W/person | published_reference_not_site_input | idae_occupant_heat |
| res030 | phoenix shade morning air temperature; Phoenix;  | 33.6 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res031 | phoenix shade morning globe temperature; Phoenix;  | 35.1 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res032 | phoenix shade morning passenger height wind; Phoenix;  | 0.7 m/s | published_reference_not_site_input | phoenix_2018_microclimate |
| res033 | phoenix shade morning relative humidity; Phoenix;  | 26 % | published_reference_not_site_input | phoenix_2018_microclimate |
| res034 | phoenix shade morning shaded metal bench temperature; Phoenix;  | 33 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res035 | phoenix shade morning shaded concrete temperature; Phoenix;  | 32.9 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res036 | phoenix shade afternoon air temperature; Phoenix;  | 41.2 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res037 | phoenix shade afternoon globe temperature; Phoenix;  | 44.3 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res038 | phoenix shade afternoon passenger height wind; Phoenix;  | 1 m/s | published_reference_not_site_input | phoenix_2018_microclimate |
| res039 | phoenix shade afternoon relative humidity; Phoenix;  | 13.7 % | published_reference_not_site_input | phoenix_2018_microclimate |
| res040 | phoenix shade afternoon shaded metal bench temperature; Phoenix;  | 40.4 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res041 | phoenix shade afternoon shaded concrete temperature; Phoenix;  | 41.3 degC | published_reference_not_site_input | phoenix_2018_microclimate |
| res042 | mattapan walk audit air temperature; Boston;  | 26.67 degC | published_reference_not_site_input | mattapan_walk_audit |
| res043 | mattapan walk audit bus stop bench surface; Boston;  | 40.56 degC | published_reference_not_site_input | mattapan_walk_audit |
| res044 | mattapan walk audit unshaded sidewalk surface; Boston;  | 46.67 degC | published_reference_not_site_input | mattapan_walk_audit |
| res045 | mattapan walk audit tree shaded sidewalk surface; Boston;  | 33.33 degC | published_reference_not_site_input | mattapan_walk_audit |
| res046 | boston standard shelter width; Boston;  | 1.524 m | published_reference_not_site_input | boston_shelter_standard |
| res047 | surface convection correlation; ;  | h_c = 5.7 + 3.8 * V_z W/(m2 K) | published_method | energyplus_242_surface |
| res048 | cooler advertising dry climate rh upper context; ;  | 30 % | published_reference_not_site_input | portacool_cooling_faq |
| air001 | summer reference wind 10m; DAL_BUS;  | 3.859565217391304 m/s | verified_derived | nasa_2026_dallas_summer |
| air002 | reference height; DAL_BUS;  | 1.1 m | explicit_assumption | airflow_scenario_2026 |
| air003 | urban wind exponent; DAL_BUS;  | 0.33 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air004 | assumed opening area; DAL_BUS;  | 3.0 m2 | explicit_assumption | airflow_scenario_2026 |
| air005 | opening effectiveness; DAL_BUS;  | 0.35 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air006 | passenger sheltering factor; DAL_BUS;  | 0.5 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air007 | local approach wind estimate; DAL_BUS;  | 1.862936148965728 m/s | scenario_estimate | airflow_scenario_2026 |
| air008 | inlet specific volume; DAL_BUS;  | 0.8973403874957414 m3/kg dry air | derived_reference | psychrolib_volume |
| air009 | ventilation dry air mass flow; DAL_BUS;  | 2.1798672874548366 kg dry air/s | scenario_estimate | airflow_scenario_2026 |
| air010 | summer reference wind 10m; DAL_RAIL;  | 3.859565217391304 m/s | verified_derived | nasa_2026_dallas_summer |
| air011 | reference height; DAL_RAIL;  | 1.1 m | explicit_assumption | airflow_scenario_2026 |
| air012 | urban wind exponent; DAL_RAIL;  | 0.33 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air013 | assumed opening area; DAL_RAIL;  | 8.0 m2 | explicit_assumption | airflow_scenario_2026 |
| air014 | opening effectiveness; DAL_RAIL;  | 0.35 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air015 | passenger sheltering factor; DAL_RAIL;  | 0.75 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air016 | local approach wind estimate; DAL_RAIL;  | 1.862936148965728 m/s | scenario_estimate | airflow_scenario_2026 |
| air017 | inlet specific volume; DAL_RAIL;  | 0.8973403874957414 m3/kg dry air | derived_reference | psychrolib_volume |
| air018 | ventilation dry air mass flow; DAL_RAIL;  | 5.812979433212899 kg dry air/s | scenario_estimate | airflow_scenario_2026 |
| air019 | summer reference wind 10m; BOS_BUS;  | 1.8792391304347824 m/s | verified_derived | nasa_2026_boston_summer |
| air020 | reference height; BOS_BUS;  | 1.1 m | explicit_assumption | airflow_scenario_2026 |
| air021 | urban wind exponent; BOS_BUS;  | 0.33 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air022 | assumed opening area; BOS_BUS;  | 3.0 m2 | explicit_assumption | airflow_scenario_2026 |
| air023 | opening effectiveness; BOS_BUS;  | 0.35 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air024 | passenger sheltering factor; BOS_BUS;  | 0.5 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air025 | local approach wind estimate; BOS_BUS;  | 0.9070717325523394 m/s | scenario_estimate | airflow_scenario_2026 |
| air026 | inlet specific volume; BOS_BUS;  | 0.8560907772557396 m3/kg dry air | derived_reference | psychrolib_volume |
| air027 | ventilation dry air mass flow; BOS_BUS;  | 1.1125284192793479 kg dry air/s | scenario_estimate | airflow_scenario_2026 |
| air028 | summer reference wind 10m; BOS_RAIL;  | 1.8792391304347824 m/s | verified_derived | nasa_2026_boston_summer |
| air029 | reference height; BOS_RAIL;  | 1.1 m | explicit_assumption | airflow_scenario_2026 |
| air030 | urban wind exponent; BOS_RAIL;  | 0.33 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air031 | assumed opening area; BOS_RAIL;  | 8.0 m2 | explicit_assumption | airflow_scenario_2026 |
| air032 | opening effectiveness; BOS_RAIL;  | 0.35 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air033 | passenger sheltering factor; BOS_RAIL;  | 0.75 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air034 | local approach wind estimate; BOS_RAIL;  | 0.9070717325523394 m/s | scenario_estimate | airflow_scenario_2026 |
| air035 | inlet specific volume; BOS_RAIL;  | 0.8560907772557396 m3/kg dry air | derived_reference | psychrolib_volume |
| air036 | ventilation dry air mass flow; BOS_RAIL;  | 2.9667424514115948 kg dry air/s | scenario_estimate | airflow_scenario_2026 |
| air037 | summer reference wind 10m; PHX_BUS;  | 2.8597826086956526 m/s | verified_derived | nasa_2026_phoenix_summer |
| air038 | reference height; PHX_BUS;  | 1.1 m | explicit_assumption | airflow_scenario_2026 |
| air039 | urban wind exponent; PHX_BUS;  | 0.33 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air040 | assumed opening area; PHX_BUS;  | 3.0 m2 | explicit_assumption | airflow_scenario_2026 |
| air041 | opening effectiveness; PHX_BUS;  | 0.35 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air042 | passenger sheltering factor; PHX_BUS;  | 0.5 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air043 | local approach wind estimate; PHX_BUS;  | 1.3803607660045147 m/s | scenario_estimate | airflow_scenario_2026 |
| air044 | inlet specific volume; PHX_BUS;  | 0.9348634351020028 m3/kg dry air | derived_reference | psychrolib_volume |
| air045 | ventilation dry air mass flow; PHX_BUS;  | 1.5503642028170657 kg dry air/s | scenario_estimate | airflow_scenario_2026 |
| air046 | summer reference wind 10m; PHX_RAIL;  | 2.8597826086956526 m/s | verified_derived | nasa_2026_phoenix_summer |
| air047 | reference height; PHX_RAIL;  | 1.1 m | explicit_assumption | airflow_scenario_2026 |
| air048 | urban wind exponent; PHX_RAIL;  | 0.33 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air049 | assumed opening area; PHX_RAIL;  | 8.0 m2 | explicit_assumption | airflow_scenario_2026 |
| air050 | opening effectiveness; PHX_RAIL;  | 0.35 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air051 | passenger sheltering factor; PHX_RAIL;  | 0.75 dimensionless | explicit_assumption | airflow_scenario_2026 |
| air052 | local approach wind estimate; PHX_RAIL;  | 1.3803607660045147 m/s | scenario_estimate | airflow_scenario_2026 |
| air053 | inlet specific volume; PHX_RAIL;  | 0.9348634351020028 m3/kg dry air | derived_reference | psychrolib_volume |
| air054 | ventilation dry air mass flow; PHX_RAIL;  | 4.134304540845509 kg dry air/s | scenario_estimate | airflow_scenario_2026 |

## Limits and audit notes

Physical inputs for the default simplified case are assigned. Full-model surface/occupancy/annual-cost fields remain unfilled because that mode is not selected. Policy thresholds/caps are separate choices. Boston B/C and Dallas C retain the previously documented supersaturation conflict under fixed drops; these airflow estimates do not resolve it.

The ±5% bounds are narrow scenario perturbations, not evidence that airflow estimates are accurate to 5%. Inflow and outflow are a coupled pair and must be changed together in a mass-balanced sensitivity run. The sensitivity setter now couples the two reverse-direction rows for each one-zone outdoor exchange. Varying either row updates both, preserving mass balance. The two corresponding bounds entries produce equivalent paired sweeps. No sensitivity run or simulation results were generated during this data update.

## Complete source catalog and BibTeX audit

Every CSV source key and every citation below has one standalone BibTeX entry. URL fields preserve query strings/percent encoding. Unknown publication years are left absent rather than invented; access dates use 2026-11-11. Titles protect proper capitalization, corporate authors are braced, and the journal article retains its DOI, volume and pages. The BibTeX file is parsed and round-trip checked for duplicate/missing keys.

| Key | Source | Locator / revision |
|---|---|---|
| `aireye_2021_specs` | [AirEye Technical Specifications](https://www.webstaurantstore.com/documents/specsheets/baf_aireye_spec_sheet.pdf) | PDF p. 2 electrical table; p. 5 airflow graphic, 20-inch fan |
| `aireye_20_price` | [Big Ass Fans AirEye 20 inch Midnight Black Pedestal / Low Rider Fan](https://www.webstaurantstore.com/big-ass-fans-aireye-20-midnight-black-pedestal-low-rider-fan-120v/657AEPMB20.html) | Item 657AEPMB20, manufacturer F-AE1-2001A750C716L10S34, displayed price |
| `aireye_maintenance` | [AirEye Maintenance](https://bigassfans.com/docs/aireye/aireye-maintenance.pdf) | Page 1, annual preventive maintenance checklist |
| `airflow_scenario_2026` | Authorized airflow reference scenario for six HiMCM waiting areas | DATA_README.md: Active airflow estimates and Explicit scenario assumptions |
| `aps_2024_e32xs` | [Rate Schedule E-32 XS: Extra Small General Service](https://www.aps.com/-/media/APS/APSCOM-PDFs/Utility/Regulatory-and-Legal/Regulatory-Plan-Details-Tariffs/Business/Business-NonResidential-Plans/e32_ExtraSmall.pdf) | See related tariff_reference records for exact page/section and rate conditions. |
| `ashrae_2021_comfort` | [2021 ASHRAE Handbook Fundamentals, Chapter 9 Thermal Comfort](https://handbook.ashrae.org/handbooks/F21/SI/f21_ch09/F21_Ch09_si.aspx) | Table 4 Metabolic Rates; Table 7 clothing ensembles |
| `boston_shade` | [The Shade Effect](https://www.abettercity.org/docs-new/the%20shade%20effect%20final%20report%20march%202026.pdf) | March 2026; pp. 9-10, clear-roof control bus shelter in Grove Hall, Images 9 and 10 |
| `boston_shelter_standard` | [Boston Complete Streets Guidelines: Sidewalks](https://www.boston.gov/sites/default/files/file/2020/09/02%20CHAPTER%202%20-%20SIDEWALKS.pdf) | Printed p. 86, Transit Stops / Bus Shelters |
| `bwa_mattapan` | [Mattapan Station Building](https://www.bwaboston.com/mattapan-station-building) | Project description: Boston, bus and trolley terminus; completed 2009 |
| `bwsc_2026_rates` | [2026 Rate Document](https://www.bwsc.org/sites/default/files/2025-12/2026%20Final%20RATE%20DOC.pdf) | See related tariff_reference records for exact page/section and rate conditions. |
| `comap_2026_options` | [2026 HiMCM Problem B](https://www.contest.comap.org/highschool/contests/himcm/2026_Problems/2026_HiMCM_Problem_B.pdf) | Page 2, Requirement 2a cooling-system table; also supplied explicitly by user |
| `comap_2026_problem_b` | [2026 HiMCM Problem B: Air Conditioning the Environment: Modeling Energy Waste in Public Cooling](https://www.contest.comap.org/highschool/contests/himcm/2026_Problems/2026_HiMCM_Problem_B.pdf) | p. 2, Requirement 2a, Cooling System / Effect on Shelter / Energy Use table |
| `comf_0112_set` | [comf: Models and Equations for Human Comfort Research](https://cran.r-project.org/web/packages/comf/comf.pdf) | pp. 62-63, calcSET Usage and Arguments |
| `dallas_2025_water_rates` | [City of Dallas utility fees effective October 1, 2025](https://dallas.gov/departments/waterutilities/Documents/COD%20Rates%20Insert_Digital.pdf) | See related tariff_reference records for exact page/section and rate conditions. |
| `dart_rosa` | [Rosa Parks Plaza](https://www.dart.org/guide/transit-and-use/rail/rail-station-detail/rosa-parks-plaza) | Station Information: address and northbound bays N and O |
| `dart_rosa_shelters` | [DART dedicates Rosa Parks Plaza](https://www.dart.org/about/news-and-events/newsreleases/newsrelease-detail/dart-dedicates-rosa-parks-plaza-864) | Plaza will be unique: four passenger shelters and two bus bays |
| `dart_west` | [West End Station](https://www.dart.org/guide/transit-and-use/rail/rail-station-detail/west-end-station) | Station Information: Pacific Avenue between Market and Lamar; 800 Pacific Avenue |
| `energyplus_242_surface` | [EnergyPlus Engineering Reference: Outside Surface Heat Balance](https://raw.githubusercontent.com/NREL/EnergyPlus/v24.2.0/doc/engineering-reference/src/surface-heat-balance-manager-processes/outside-surface-heat-balance.tex) | McAdams subsection; convection and radiative heat-balance equations |
| `energyplus_wind_ventilation` | [EnergyPlus Engineering Reference: Infiltration/Ventilation](https://energyplus.readthedocs.io/en/stable/guides/engineering-reference/8.3-infiltrationventilation.html) | Ventilation by Wind and Stack with Open Area, wind-driven equation Qw=Cw*A*F*V |
| `eversource_2026_boston` | [2026 Summary of Eastern Massachusetts Electric Rates for Greater Boston Service Area](https://www.eversource.com/docs/default-source/rates-tariffs/ema-greater-boston-rates.pdf?sfvrsn=875c1c95_19) | See related tariff_reference records for exact page/section and rate conditions. |
| `idae_occupant_heat` | [Thermal wellbeing in a climate controlled environment](https://www.idae.es/en/news/thermal-wellbeing-climate-controlled-environment) | Metabolic activity table; sitting without working row; sensible heat definition |
| `mattapan_walk_audit` | [Mattapan Square Engagement Report](https://www.boston.gov/sites/default/files/file/2023/11/Consult%20Lela%20_Mattapan%20Square%20Engagement%20Report%20sm.pdf) | Printed pp. 19-20, Youth Engagement Committee Walk Audit; PDF page 11 |
| `nasa_2026_boston_summer` | [NASA POWER climatology at Boston reference coordinates](https://power.larc.nasa.gov/api/temporal/climatology/point?parameters=T2M%2CT2M_MAX%2CT2M_MIN%2CRH2M%2CPS%2CWS10M%2CALLSKY_SFC_SW_DWN&community=RE&longitude=-71.01056&latitude=42.36056&format=JSON) | JSON properties.parameter.T2M.JUN/JUL/AUG; parameters.T2M.units; header.range; geometry.coordinates |
| `nasa_2026_dallas_summer` | [NASA POWER climatology at Dallas reference coordinates](https://power.larc.nasa.gov/api/temporal/climatology/point?parameters=T2M%2CT2M_MAX%2CT2M_MIN%2CRH2M%2CPS%2CWS10M%2CALLSKY_SFC_SW_DWN&community=RE&longitude=-97.02196&latitude=32.89743&format=JSON) | JSON properties.parameter.T2M.JUN/JUL/AUG; parameters.T2M.units; header.range; geometry.coordinates |
| `nasa_2026_phoenix_summer` | [NASA POWER climatology at Phoenix reference coordinates](https://power.larc.nasa.gov/api/temporal/climatology/point?parameters=T2M%2CT2M_MAX%2CT2M_MIN%2CRH2M%2CPS%2CWS10M%2CALLSKY_SFC_SW_DWN&community=RE&longitude=-112.003465&latitude=33.427799&format=JSON) | JSON properties.parameter.T2M.JUN/JUL/AUG; parameters.T2M.units; header.range; geometry.coordinates |
| `oncor_2026_delivery` | [Tariff for Retail Delivery Service](https://www.oncor.com/content/dam/oncorwww/documents/about-us/regulatory/tariff-and-rate-schedules/Tariff%20for%20Retail%20Delivery%20Service.pdf) | See related tariff_reference records for exact page/section and rate conditions. |
| `phoenix_2018_microclimate` | [Public transit infrastructure and heat perceptions in hot and dry climates](https://doi.org/10.1007/s00484-021-02074-4) | Tables 2 and 3; printed pp. 349-350; measurement methods pp. 347-348 |
| `phoenix_2025_water_rates` | [Water Rate Schedule Effective March 1, 2025](https://www.phoenix.gov/content/dam/phoenix/waterservicessite/documents/rates_effective_march_2025.pdf) | p. 1; User and Other Charges / High Season / Inside City; Environmental Charge / Inside City; notes 1-5 |
| `portacool_2000` | [APEX 2000 Portable Evaporative Coolers](https://www.portacool.com/products/apex-series/apex-2000-portable-evaporative-coolers/) | Product Information table and MSRP beside product title; current page accessed 2026-11-11 |
| `portacool_4000` | [APEX 4000 Portable Evaporative Coolers](https://www.portacool.com/products/apex-series/apex-4000-portable-evaporative-coolers/) | Product Information table and MSRP beside product title; current page accessed 2026-11-11 |
| `portacool_apex_maintenance` | [APEX Series Maintenance and Care](https://www.portacool.com/resources/maintenance-care/apex-series/) | Regular Maintenance; applies to APEX 2000 and APEX 4000 |
| `portacool_buying_guide` | [Portacool Buying Guide](https://www.portacool.com/resources/buying-guide/) | FAQs: media life and daily/weekly maintenance |
| `portacool_cooling_faq` | [Portacool FAQs](https://www.portacool.com/support/faq/) | Replacement Media: Just tell me already, how much will it lower my temperature? |
| `portacool_media_prices` | [Replacement Evaporative Cooler Media](https://www.portacool.com/products/parts-accessories/media/) | PACHT2000K and PACHT4000K product cards |
| `psychrolib_volume` | [PsychroLib API Documentation](https://psychrometrics.github.io/psychrolib/api_docs.html) | GetHumRatioFromRelHum, GetSatVapPres and GetMoistAirVolume; ASHRAE 2017 ch. 1 equation 26 |
| `tttiger_ff10d` | [FF10D 10-Inch AC Portable Axial Flow Fan](https://tttigerfan.com/products/industrial-ventilation-fans/ff-10-d/) | Specifications: rated power, airflow, voltage and frequency |
| `valley_bus` | [FY 2012-2016 Short Range Transit Plan](https://d1rbsgppyrdqq4.cloudfront.net/prism/s3fs-public/c16/109292/2012-2016_Short_Range_Transit_Program.pdf?VersionId=3KqWFiKrvML2W.sBQeetilxKVkKusYuc) | Transit facility inventory: Central Ave / Camelback Transit Center; historical facility reference |
| `valley_rail` | [Station Platforms](https://vulcan-production.nyc3.cdn.digitaloceanspaces.com/pages/downloads/about/agency/fact-sheets-brochures/fact-sheets/lrt2274_station_platforms_-_october_2016_update_4.pdf) | Page 1: Station design and map showing Central Ave/Camelback in Phoenix |


## Final validation

All twelve passenger-speed inputs and all twenty-four balanced inlet/outlet mass-flow rows are populated. Paired ventilation sensitivity changes preserve mass balance.

All 38 bibliography entries parse successfully with unique citation keys, and every key appears in this README. Biber also parses and writes the bibliography successfully. Its strict data-model check reports 23 missing-publication-date warnings for undated references; these are intentionally retained with access dates rather than fabricated publication years. These warnings are not BibTeX syntax errors.
