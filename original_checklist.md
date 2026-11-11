# Cooling project: what information to collect

This guide can be used without reading any program files. It tells you what to measure, request, or look up to compare a fan, two evaporative coolers, and no active cooling at passenger waiting areas.

**No venue measurements have been supplied. Leave unavailable information marked “unknown.” Do not replace it with zero or a typical value.** The tables describe information to collect; they do not contain assumed measurements.

## What is already known

These values come from the supplied problem statement and do not need to be rediscovered.

| Option | What it is | Stated maximum effect | Electrical power stated in the problem | What remains unknown |
|---|---|---|---|---|
| A | Fan | Up to 3°C perceived cooling; this does not mean the air becomes 3°C colder | 0.25 kW | Airspeed at people, area served, operating conditions, placement and costs |
| B | Evaporative cooler | Up to 5°C air-temperature reduction | 1.2 kW | Where the reduction is measured, reference weather, airflow, humidity increase, water use, area served and costs |
| C | Large evaporative cooler | Up to 8°C air-temperature reduction | 2.5 kW | Where the reduction is measured, reference weather, airflow, humidity increase, water use, area served and costs |
| No active cooling | The comparison baseline | No active-device cooling | No active-device electricity, by definition; other facility loads are separate | The same venue's weather, shade, ventilation and occupancy without the proposed device |

## How to collect and label information

A **venue** is a specific shelter or station. A **zone** is a part of it where conditions can reasonably be treated as similar, such as a shaded seating area or an exposed queue. A **time interval** is the period represented by a measurement. A **scenario** is a documented combination of weather and passenger demand. An **option** is the equipment arrangement being compared.

For every observation, keep the venue name, precise location or zone, date, local time and timezone, observation duration, equipment operating state, unit, and source. Record sensor accuracy or uncertainty if available. For documents, keep the title, issuer, date, page/table, and link or copy. An equipment specification must identify the actual make/model and operating setting to which it applies.

Do not choose an observation frequency arbitrarily. Record the native measurement times and durations; the analyst must establish whether they resolve the weather, passenger and equipment changes that matter. Preserve raw measurements as well as any averages or conversions.

**Start with Sections 1–4.** They establish which places and devices are being studied and what conditions people experience. Then obtain occupant, cost and policy information. The final section lists work for the analyst/programmer, so it is not mistaken for data you need to measure.

## 1. Which places and periods are being studied?

| Information to collect | Exactly what to record | Units or format | Where to obtain it / useful evidence |
|---|---|---|---|
| Identity of each venue | Official name, address or coordinates, and whether it is the bus shelter, railway station, or one of the two real-venue applications. Identify two named real venues with different climates or systems. State explicitly if a venue serves more than one role. | Names, location and role | Transport operator, site records, official maps |
| Existing cooling systems | Which systems are actually installed, their make/model, location, quantity and current use. Clearly distinguish them from equipment proposed only for comparison. | Equipment inventory and annotated plan | Operator records, site inspection, equipment labels |
| Study dates and hours | Dates, daily start/end times, timezone, and whether the study covers a particular hot period, season or operating schedule. | Dates, clock times, timezone, hours | Project brief, operating timetable, available observation records |
| Venue layout | Dimensioned plan showing covered/uncovered waiting areas, seats, queues, walls, roof, entrances, exits, openings, equipment and nearby obstructions. | Metres and a labelled drawing | Survey, architectural drawings, site measurements |
| Zones used for comparison | Boundaries of areas with different exposure, shading, ventilation or passenger use. Explain why they should be distinguished. | Labelled plan and description | Site inspection plus measured spatial differences |
| Air volume in each zone | Length, width and effective height of the air region being modeled. For irregular or open areas, provide the geometry and boundary definition rather than guessing a volume. | m; calculated volume in m³ | Drawings or measured dimensions; analyst documents calculation |
| Shade and sun exposure | Which zones are shaded, by what structure, and how the shade changes during the study hours. Record any changes to the shade arrangement between comparisons. | Labelled plan, timestamps, descriptive observations | Site survey, time-stamped observations, building geometry |
| Climate evidence for real venues | Weather observations or documented local climate information relevant to the study period, with station location and applicability to the venue. | Source, location, dates and measured climate variables | Applicable weather station or local observations |
| Station model revisions | A drawing and explanation of features added in the more detailed station model: extra zones, entrances, surfaces, sources or circulation paths. Supply the same station and conditions for the simpler and more detailed comparisons. | Before/after plans and list of physical changes | Station drawings, site records, agreed modeling plan |

## 2. Weather, ventilation and heat entering the space

Collect time-varying information for each relevant venue and interval. Outdoor weather, zone air conditions and surface temperatures are different measurements; one cannot silently substitute for another.

| Information to collect | Exactly what to record | Units or format | Where to obtain it / useful evidence |
|---|---|---|---|
| Outdoor air temperature | Dry-bulb air temperature near the venue, measurement location, height and time. Record instrument exposure so direct solar heating of the sensor is not confused with air temperature. | °C | Suitable local temperature sensor or applicable weather record |
| Outdoor relative humidity | Relative humidity measured at the same place/time as outdoor temperature. | % RH, not a decimal fraction | Humidity sensor or applicable weather record |
| Atmospheric pressure | Air pressure applicable to the venue and observation time. Identify whether a weather source reports station pressure or sea-level-adjusted pressure; retain that distinction for the analyst. | Pa, or original unit with its label | Barometer or documented weather source |
| Air temperature inside each zone | Initial temperature at the beginning of the study and time-stamped temperatures during the study. Preserve sensor location. | °C | Zone temperature sensors |
| Humidity inside each zone | Initial and time-stamped relative humidity, paired with temperature and pressure. The analyst can calculate water content per kilogram of dry air from these measurements. | % RH; matching °C and Pa | Zone humidity sensors and paired weather records |
| Every incoming/outgoing airflow path | Where air comes from and goes to: outdoors, another zone, or a device; include supply, return and exhaust paths. Identify recirculated air separately from fresh outdoor air. | Labelled path diagram and direction | Ventilation drawings, equipment inspection, airflow survey |
| Airflow along each path | Flow rate and direction at each operating condition/time, including changes when equipment is switched on. If only velocity is measured, also record the opening area and measurement positions needed for a defensible flow calculation. | Prefer original m³/s or m³/h; retain any measured kg/s | Airflow measurements, applicable fan/duct performance records |
| Conditions of the flowing air | Temperature, humidity and pressure associated with measured volumetric airflow, so the analyst can convert it to total-air and dry-air mass flow. | °C, % RH, Pa | Measurements at the relevant inlet, outlet or path |
| Opening geometry and state | Dimensions of doors/openings, whether they are open or closed, and changes during the observation period. Geometry alone is not a measured airflow rate. | m or m²; time-stamped open/closed state | Drawings and site observation |
| Surfaces exchanging heat with each zone | Identify each relevant roof, wall, floor or other surface and the area exposed to the zone air. | Labelled surface and m² | Drawings or measurements |
| Surface temperature | Temperature of each relevant surface over the study intervals, not just outdoor or zone air temperature. | °C | Applicable contact or infrared measurements with method recorded |
| Surface-to-air heat transfer | Applicable convective heat-transfer coefficient for each modeled surface, or the geometry, airflow and evidence an analyst needs to select an applicable engineering relation. Do not invent a coefficient. | W/(m²·K), if established; otherwise supporting measurements | Applicable engineering source or documented calculation |
| Other sensible heat sources | Heat entering zone air from lighting, motors, electronics, other equipment or processes. Record location, timing and whether stated power is heat released into this zone or merely electrical input. | W and operating times | Metering, equipment specifications, documented heat accounting |
| Other moisture sources | Water vapor added inside each zone by sources other than the evaporative supply stream; identify source and timing. Avoid counting the cooler's supply moisture twice. | kg of water/s, or observations allowing a documented conversion | Process measurements, applicable source records |
| Heat stored by materials | If walls, roof, floor or furnishings are to store heat in the model: material identity, amount/mass, specific heat, relevant initial temperature and evidence that the material participates over the study period. | kg, J/(kg·K), °C; or documented effective J/K | Construction records and applicable material data; analyst determines applicability |

Air mass inside a zone, air heat capacity, humidity ratio and effective thermal capacitance are **derived or source-supported quantities**. Collect geometry, air conditions and applicable material evidence first; the analyst must retain the formulas and sources used to calculate them.

## 3. Equipment performance and water use

Use one equipment record per installation and operating setting. Measurements should identify inlet/outlet locations, time, and which units were operating.

| Information to collect | Exactly what to record | Units or format | Where to obtain it / useful evidence |
|---|---|---|---|
| Device identity and quantity | A/B/C classification, manufacturer/model if a real product is used, number installed and number running in each interval. | Names and integer counts | Equipment labels, operator inventory, operating log |
| Device location and orientation | Position, discharge direction, distance to waiting passengers and any obstructions. | Labelled plan; distances in m | Site survey or proposed installation plan |
| Operating schedule and setting | On/off periods, speed or mode, and the rule determining when those settings are used. | Timestamps, named settings, written rule | Operator records or explicitly proposed operating plan |
| Electrical consumption | Applicable power at each setting and, if measured, energy over an interval. Preserve the problem-stated powers separately from product-specific measurements. | kW and/or kWh with duration | Power meter, applicable product specification, supplied problem statement |
| Fan airspeed experienced by people | Airspeed at the actual occupied positions and relevant body heights, for fan off and each proposed fan setting. Record the locations and the area actually reached. | m/s with position and height in m | Local airspeed measurements or verified applicable performance measurements |
| Evaporative-cooler airflow | Supply flow for each operating setting and where that supply enters the occupied space. | m³/s or m³/h, plus air conditions | Applicable product performance data or measured outlet flow |
| Evaporative-cooler inlet conditions | Temperature, relative humidity and pressure at the inlet, matched to the outlet measurements and operating setting. | °C, % RH, Pa | Paired inlet measurements or an applicable performance test |
| Evaporative-cooler outlet conditions | Temperature and humidity at the outlet, measured at the same time/setting as the inlet. | °C and % RH | Paired outlet measurements or an applicable performance test |
| Meaning of the advertised maximum reduction | Evidence stating whether 5°C/8°C refers to inlet-to-outlet air reduction or a reduction in the shelter, and exactly where/how it was measured. | Manufacturer/test statement with measurement locations | Original specification, test report or clarification from the problem source |
| Conditions behind the advertised rating | Inlet temperature, humidity and pressure; airflow, operating setting, and relevant test geometry at which the stated reduction was achieved. | °C, % RH, Pa, flow units, geometry and mode | The same reference test that supports the rating |
| Evaporative effectiveness | Verified fraction of the available dry-bulb-to-wet-bulb cooling achieved, or the paired inlet/outlet data needed to calculate it. This is not the electrical efficiency. | Dimensionless fraction, with test conditions | Applicable performance test; analyst derives from documented measurements |
| Evaporation water consumption | Water actually evaporated over an operating period, if separately measured; otherwise provide matched airflow and inlet/outlet humidity for calculation. | kg or litres with duration; retain temperature if converting volume to mass | Water balance measurements or paired air measurements |
| Bleed, drift and other water losses | Water discharged to control mineral buildup, droplets carried away, or other non-evaporative losses. Identify whether the available water reading includes these losses. | kg or litres per measured duration | Water-meter logs, operating manual, maintenance records |
| Occupied area served | Which zones or passenger positions receive the device's effect at each setting, with supporting local airspeed/temperature/humidity measurements. | Labelled area in m² and exposure measurements | Spatial measurement survey, applicable performance study |

For A, the “3°C perceived cooling” value does not replace local airspeed measurements. For B/C, a maximum temperature drop alone does not establish performance under a different humidity or geometry. If a loss is truly zero or a device uses no water, record why rather than treating a blank as zero.

## 4. Passenger numbers and conditions at their positions

| Information to collect | Exactly what to record | Units or format | Where to obtain it / useful evidence |
|---|---|---|---|
| People present in each zone | Number of people physically present during each interval, separated into groups only where exposure, clothing or activity differs. Counts of arrivals alone are not occupancy. | Persons, time and zone | Direct counts, suitable occupancy records |
| Waiting duration and turnover | Arrival/departure or dwell-time evidence sufficient to determine how long people are exposed. Distinguish repeated observations from unique people. | Minutes; time-stamped records | Passenger survey or applicable operator observations |
| Movement between zones | If movement is modeled, record when/how people move between zones. Do not change occupancy across options simply to make one device look better. | Zone-to-zone counts and times | Observations or explicitly documented behavior model |
| Activity | What passengers are doing—sitting, standing, walking, carrying loads—and the duration of each activity. The analyst must source an applicable metabolic rate. | Activity description and duration; metabolic rate in met if justified | Observations and applicable physiological reference |
| Clothing | Clothing ensembles and relevant differences between groups or periods. The analyst must source an applicable insulation value. | Garment descriptions; clo if justified | Observations/survey and applicable clothing reference |
| Posture | Whether the representative exposure is seated or standing. | Sitting/standing and time | Observation |
| Body-level airspeed | Airspeed at occupied positions for each option, including no active cooling; do not substitute total ventilation flow. | m/s with location/height/time | Local airspeed measurements |
| Mean radiant temperature | The effective radiant temperature seen by a person at each position. Provide a suitable radiant measurement or the raw globe/surface/geometry measurements and method needed to calculate it. Air temperature alone is insufficient. | °C; retain raw measurements and method | Radiant/globe measurements with supporting airspeed and instrument details, or documented radiation calculation |
| Air turbulence | Fluctuation of local air velocity around its mean, or a time-resolved measurement record from which an analyst can determine the turbulence intensity. | % if calculated; otherwise time-stamped m/s | Suitable airspeed measurement record |
| Heat and moisture released by occupants | Applicable sensible heat and water-vapor generation for the observed activity/group, identifying whether values are per person or totals. | W/person and kg/s/person, or clearly labelled totals | Applicable source data or measurements, with activity and conditions documented |
| Population represented | Description of the population to which the comfort calculation is meant to apply, including any relevant limitations for vulnerable groups. | Description and applicability evidence | Study scope, operator information, appropriate population evidence |
| Representative body dimensions, if supported | Height and mass appropriate to the explicitly selected population representation, or an approved model-reference population. Do not silently adopt package defaults or seek identifiable personal records unnecessarily. | cm and kg; surface area in m² if documented/derived | Approved population/model reference or appropriate study data |
| External mechanical work | Whether the represented activity performs external mechanical work, with an applicable value or a supported zero. | met if established, otherwise activity evidence | Applicable activity/physiology reference |

## 5. Costs, practical limits and criteria for a satisfactory result

The first part of this table contains prices and operating facts. The second part contains **decisions for the project owner**; those decisions cannot be inferred from weather measurements.

| Information or decision | Exactly what to provide | Units or format | Who/source to ask |
|---|---|---|---|
| Purchase cost | Total equipment purchase cost for each venue/option, with quantity and quote date. | Currency; specify currency code | Supplier quotation, procurement records |
| Installation cost | Electrical work, plumbing, mounting, site preparation and other installation charges, identifying what is included. | Currency | Installer quotation, operator project records |
| Annual maintenance | Servicing, cleaning, replacement pads/filters, labor and other recurring maintenance, without double counting. | Currency/year | Maintenance contract, service records |
| Useful economic life | Supported replacement/service-life period used for annual cost comparison. | Years | Asset policy, applicable supplier evidence |
| Discount rate | Rate the owner wants used to annualize capital costs; specify whether it is zero and the price/inflation basis. | Annual fraction or clearly labelled % | Project owner or finance policy |
| Electricity tariff | Energy price, dates of applicability and any relevant time-of-use structure. | Currency/kWh; tariff schedule | Applicable utility bill or tariff |
| Demand charges | Whether billed peak demand affects the option; applicable tariff and demand evidence or a justified annual total. State explicitly if not applicable. | Currency/kW and billing period, or justified currency/year | Utility tariff and metering/billing records |
| Water tariff | Applicable water price and billing unit, including any relevant associated charges. | Currency per litre, m³ or kg; identify unit | Applicable water bill or tariff |
| Other charges | Any other supported annual cost, with description; explicit evidence if none apply. | Currency/year | Operator/finance records |
| Annual operating exposure | Evidence for how often the studied operating conditions occur during a year. A few observed hot hours cannot automatically represent a whole year. | Hours/year, days/year or justified repetitions/year | Timetables, annual weather/occupancy records, documented weighting plan |
| Budget limit — owner decision | Maximum acceptable annualized total cost, and whether separate upfront spending limits also apply. | Currency/year; any separate capital cap labelled | Project owner |
| Electricity limit — owner decision | Maximum electricity use allowed, with the exact time horizon it covers. | kWh per stated period | Project owner/operator |
| Water limit — owner decision | Maximum water consumption allowed, with the exact time horizon it covers. | kg, litres or m³ per stated period | Project owner/operator |
| Comfort target — owner/research decision | Upper SET comfort threshold and lower bound for overcooling, supported for the represented population. SET is a calculated comfort index, not simply measured air temperature. | °C SET for both bounds, plus justification | Agreed project criteria and applicable comfort reference |
| Minimum acceptable comfort coverage — owner decision | Required fraction of all occupied time within the agreed comfort bounds. This is a fraction of person-hours, not necessarily the fraction of unique passengers. | Fraction or % of occupied person-hours | Project owner |
| Safety rule — qualified assessment | Appropriate heat-stress screening method, thresholds, exposure duration, population applicability and whether passing is mandatory. Do not infer safety from SET alone. | Named method, criteria, units and applicability | Appropriate qualified assessor and applicable guidance |
| Safety result for each case | Documented assessment of the specified conditions under that rule, including pass/fail, supporting evidence and limitations. If unknown, leave unknown. | Assessment record and pass/fail | Qualified assessment using actual case conditions |
| Allowed operating decisions — owner decision | What is installed in advance; what can be switched or adjusted later; which measurements are available when making those decisions. | Written operating rules | Project owner/operator |
| Failure contingencies — owner decision | What to do if no device meets comfort/resource/safety requirements or observed conditions lie outside those evaluated; identify whether contingency performance is known. | Condition/action plan and supporting evidence | Operator and relevant responsible staff |
| Primary venue for the COO memo | Which venue the management recommendation should focus on and the intended decision period. | Venue name and period | Project owner |

## 6. Alternative conditions and uncertainty

Do not invent a percentage range or a probability distribution. Use observed variation, measurement uncertainty, applicable performance evidence or explicitly approved planning scenarios.

| Information to collect or decide | Exactly what to provide | Units or format | Evidence / scope |
|---|---|---|---|
| Weather scenarios | Actual or explicitly authorized combinations of temperature, humidity and pressure, with timing. Keep combinations physically and empirically supported. | °C, % RH, Pa and times | Venue-relevant observations or documented scenario basis |
| Passenger-demand scenarios | Passenger counts by zone and time, waiting duration and group composition for each proposed demand case. | Persons and minutes | Observed demand records or explicit planning scenarios |
| Range for each tested quantity | Lower/upper supported values for comfort thresholds, airflow, local airspeed, area/population served, weather, occupancy and budget/resource limits. Identify the quantity and where/when it applies. | Original unit of each quantity | Measurements, uncertainty estimates, applicable evidence or explicit owner choices |
| Relationships between quantities | Which values must change together: for example airflow and fan setting, or occupancy and occupant heat/moisture. Provide the relationship and evidence, not an assumption of independence. | Paired records, performance curves or documented equations | Same system and applicable operating conditions |
| Selected combined changes | Which two quantities should be varied jointly and which combinations are meaningful. | Named quantities and permitted combinations | Research/owner decision informed by evidence |
| Alternative rating interpretations | Only interpretations of the advertised cooling reductions that have been confirmed as meaningful; supporting reference conditions for each. | Explanation and applicable test evidence | Problem clarification, manufacturer/test report |
| Alternative zone layouts | Approved ways to divide the same venue, with how people, surfaces, airflow and equipment map between the layouts. | Labelled plans and allocation rules | Site evidence and agreed model design |
| Monte Carlo uncertainty model — only if requested | Evidence-based distributions and dependencies, data supporting them, and a clear distinction between uncertain measurements and missing observations. | Joint statistical model and source data | Qualified statistical/engineering analysis of applicable evidence |

Monte Carlo is currently disabled. Random sampling cannot be used to manufacture missing observations.

## 7. Evidence needed to check whether the model is trustworthy

| Evidence to obtain | Exactly what to retain | Units / detail | Purpose |
|---|---|---|---|
| Measured device-on/device-off comparisons | Matching weather, occupancy, shade, device setting, zone temperature/humidity, local airspeed, radiant conditions, electricity and water records. Note unavoidable differences rather than hiding them. | Raw time-stamped records with units and locations | Check predicted changes against actual observations |
| Independent validation observations | Measurements not already used to calibrate the same model; identify any reuse explicitly. | Separate dataset and collection conditions | Avoid claiming a fit to calibration data is independent validation |
| Sensor and measurement uncertainty | Instrument model, calibration/accuracy information, measurement procedure and known limitations. | Accuracy in each measured unit; calibration record | Interpret prediction errors and set supported uncertainty ranges |
| Published reference cases | Inputs, expected outputs, implementation version and source for psychrometric and two-node SET calculations. These are verification cases, not venue observations. | Complete published case and units | Check the scientific calculation implementation |
| Repeatability/spatial detail | Enough repeated or spatial observations to establish whether zone averages and reported differences are meaningful; retain the available sample count. | Individual observations, positions and times | Assess variability and model limitations |

## 8. Analyst/programmer responsibilities — not field data to search for

These items appeared alongside missing data in the earlier table. They should be handled by the person implementing and reviewing the analysis.

| Responsibility | What must be resolved |
|---|---|
| Calculate derived physical quantities | Calculate humidity ratio, wet-bulb temperature, dry-air mass, airflow mass conversions, heat capacitance and evaporative water use from sourced inputs; preserve formulas and provenance. |
| Choose and justify the physical model | Confirm the well-mixed-zone, heat-capacity, surface, evaporation and moisture-buffering assumptions. Compare response times with weather/occupancy changes before choosing steady or dynamic calculation. |
| Audit the human comfort model | Select an applicable two-node implementation and document all physiological settings, including sweating, vasodilation and vasoconstriction coefficients, exposure duration and represented body surface area. Do not silently inherit defaults. |
| Select numerical settings | Set and test numerical tolerances, integration method, time resolution and convergence criteria. Use dimensionally appropriate tolerances; the current shared-tolerance implementation needs review. |
| Define the decision convention | State whether regret comparators must be feasible across every scenario or only within the scenario, and justify how near-ties are reported. Apply the same information/resource rules to all options. |
| Implement sensitivity changes coherently | Specify grid resolution and combinations; update dependent physical quantities, provenance and alternative zone mappings consistently. |
| Configure optional Monte Carlo | Obtain explicit authorization; implement the supported joint model; choose/document sample count, seed, output quantiles and convergence tests. |
| Set up and verify software | Install and audit the required R packages, record versions, test known reference cases and keep separate records of verification, calibration and independent validation. |
| Complete unsupported extensions if needed | Add and verify adaptive operating policies, evaporative recirculation or other actual-system features before using them. Complete matched station-revision impact/recovery checks. |
| Label and trace all records | Assign consistent venue/zone/equipment/group/scenario labels and retain sources, formulas, units and applicability. Internal code identifiers can be assigned after the information is collected. |

## What a usable handover looks like

Provide a labelled site plan, the raw measurement/operating logs, applicable equipment documents, occupancy observations, cost quotations/tariffs, and a written list of the owner's limits and decisions. Each item should say which venue, location, device setting and period it applies to. Unknowns should remain explicitly unknown. No program knowledge or internal field names are needed to assemble this material.

