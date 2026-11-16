# Figures for the paper and COO memorandum

All figures are exported as 300 dpi PNG, editable vector SVG, and vector PDF. Each has a matching plotted-data CSV. Regenerate from the repository root with `python analysis/make_paper_figures.py`. Existing gallery files and model results are not overwritten.

## Suggested placement

### Results 1 · Cooling efficiency

1. **F6 · Cooling efficiency across 36 cases.** Compare SET reduction per kWh and per $1,000 of equipment price.
2. **F12 · Fan efficiency advantage.** Compare the fan with the more efficient evaporative cooler in each case.
3. **F9 · Purchase-price efficiency winners.** Identify which device leads in each venue and weather scenario.
4. **F10 · Peak-hour cooling and electricity.** Compare total delivered cooling and electricity use at peak heat.
5. **F11 · Ventilation and efficiency.** Show how outdoor exchange changes efficiency in the separate summer-mean scaling exercise.

### Results 2 · Minimax choice

1. **F7 · Maximum regret by venue.** Show each option’s worst regret and highlight the recommendation at all 12 venues.
2. **F8 · Boston bus shelter radar.** Use the single-venue redraw of generated radar D07 to compare regret, purchase price, electricity, and water on the original gallery scales.
3. **F13 · Purchase price and regret.** Show the cost–regret frontier at the three bus shelters.
4. **F3 · Peak-hour thermal comfort.** Show absolute SET for all options and venues relative to the comfort target.
5. **F14 · Minimax sensitivity switches.** Show the five tested intervals in which a Boston venue’s recommendation changes between the fan and larger cooler.

Regenerate F6–F14 from the repository root with `python analysis/make_results_figures.py` after running the R pipeline and `Rscript 03_decision/venue_scaling.R`.

For a two-page memorandum, use F1 at page width and a compact cost/resource table; add F4 only if space permits. Keep F2, F3 and F5 in the main paper or appendix. The memorandum text is in `analysis/COO_memorandum.md`. Its actual page count depends on font, margins, spacing and figure placement; approximately 580 words plus F1 is intended for a two-page layout.

## Ready-to-use captions

**F1. Cooling needs at the Boston bus shelter depend on weather conditions.** Predicted Standard Effective Temperature (SET) for a reference passenger under three selected one-hour scenarios. The shaded 23–26°C band is the chosen comparison target, not a safety threshold. The fan reaches the band in the hot-humid case; no active device reaches it at peak temperature; no device is needed to reach the band in the hot-dry case. Source: `03_decision/result_options.csv`.

**F2. Total cooling benefit and electricity efficiency favor different options.** In the Boston peak-temperature case, C provides the greatest reduction in hot discomfort, while A provides the greatest reduction per kilowatt-hour. Benefit is the avoided SET degree-hours above 26°C relative to no device, for one reference person over one hour. Source: `03_decision/result_options.csv`.

**F3. Peak-hour thermal comfort across 12 venues.** The figure compares all four cooling options at each bus stop, rail platform, courtyard, and airport canopy. Venues within a city share weather inputs and use venue-specific airflow assumptions. Source `03_decision/result_options.csv`.

**F4. Stronger peak-hour relief carries greater resource requirements.** Electricity use, evaporated water and reference purchase cost for the Boston peak-temperature case. The three panels use separate units and scales. Water excludes flushing and cleaning; purchase prices exclude tax, installation and maintenance. Source: `03_decision/result_options.csv`.

**F5. Outdoor temperature changes predicted comfort in the Boston hot-humid scenario.** Five temperature settings within the exploratory ±5% sweep, with relative humidity and other input fields held fixed. The dashed line marks the baseline outdoor temperature of 30.39°C; the shaded band marks the chosen comfort comparison target. Lines connect tested settings and are not confidence intervals. Source: `04_sensitivity/result_sensitivity_detail.csv`, filtered to `weather_occ.8.T`, `BOS_BUS`, `hot_humid`.

## Evidence and interpretation

The saved data represent modeled reference cases, not observed device performance. Airflow, passenger exposure, radiant conditions, and evaporative-performance assumptions are described in the repository README. Scenarios are selected stress cases, not weather probabilities; do not average their coverage and call it a percentage of summer hours. Comfort is calculated for a reference person, not an observed passenger population.

The memo's recommendation to pilot A is an operational interpretation of comfort and resource results, not the minimax selection. The existing unconstrained minimax rule selects C. The rule penalizes hot discomfort only; cold discomfort and resource limits would need explicit treatment to change that objective.

External support for operating recommendations:

- Massachusetts Emergency Management Agency, [Preparing for Extreme Heat](https://www.mass.gov/info-details/preparing-for-extreme-heat): access to air-conditioned cooling locations during extreme heat.
- PNNL Building America Solution Center, [Evaporative Cooling Systems](https://basc.pnnl.gov/resource-guides/evaporative-cooling-systems): maintenance of reservoirs and media, mineral buildup and flushing.

The primary model evidence is retained in the repository: `sources/nasa_hourly_2025/README.md`, `03_decision/result_options.csv`, `03_decision/result_recommendations.csv`, and `04_sensitivity/result_sensitivity_detail.csv`.
