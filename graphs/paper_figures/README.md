# Figures for the paper and COO memorandum

All figures are exported as 300 dpi PNG, editable vector SVG, and vector PDF. Each has a matching plotted-data CSV. Regenerate from the repository root with `python analysis/make_paper_figures.py`. Existing gallery files and model results are not overwritten.

## Suggested placement

For a two-page memorandum, use F1 at page width and a compact cost/resource table; add F4 only if space permits. Keep F2, F3 and F5 in the main paper or appendix. The memorandum text is in `analysis/COO_memorandum.md`. Its actual page count depends on font, margins, spacing and figure placement; approximately 580 words plus F1 is intended for a two-page layout.

## Ready-to-use captions

**F1. Cooling needs at the Boston bus shelter depend on weather conditions.** Predicted Standard Effective Temperature (SET) for a reference passenger under three selected one-hour scenarios. The shaded 23–26°C band is the chosen comparison target, not a safety threshold. The fan reaches the band in the hot-humid case; no active device reaches it at peak temperature; no device is needed to reach the band in the hot-dry case. Source: `03_decision/result_options.csv`.

**F2. Total cooling benefit and electricity efficiency favor different options.** In the Boston peak-temperature case, C provides the greatest reduction in hot discomfort, while A provides the greatest reduction per kilowatt-hour. Benefit is the avoided SET degree-hours above 26°C relative to no device, for one reference person over one hour. Source: `03_decision/result_options.csv`.

**F3. None of the modeled systems achieves the comparison target during the selected peak-temperature hours.** C gives the lowest SET at all six venues, but residual discomfort remains. Weather hours differ by city; bus and rail in the same city share weather inputs but use different airflow assumptions. Source: `03_decision/result_options.csv`.

**F4. Stronger peak-hour relief carries greater resource requirements.** Electricity use, evaporated water and reference purchase cost for the Boston peak-temperature case. The three panels use separate units and scales. Water excludes flushing and cleaning; purchase prices exclude tax, installation and maintenance. Source: `03_decision/result_options.csv`.

**F5. Outdoor temperature changes predicted comfort in the Boston hot-humid scenario.** Five temperature settings within the exploratory ±5% sweep, with relative humidity and other input fields held fixed. The dashed line marks the baseline outdoor temperature of 30.39°C; the shaded band marks the chosen comfort comparison target. Lines connect tested settings and are not confidence intervals. Source: `04_sensitivity/result_sensitivity_detail.csv`, filtered to `weather_occ.8.T`, `BOS_BUS`, `hot_humid`.

## Evidence and interpretation

The saved data represent modeled reference cases, not observed device performance. Airflow, passenger exposure, radiant conditions, and evaporative-performance assumptions are described in the repository README. Scenarios are selected stress cases, not weather probabilities; do not average their coverage and call it a percentage of summer hours. Comfort is calculated for a reference person, not an observed passenger population.

The memo's recommendation to pilot A is an operational interpretation of comfort and resource results, not the minimax selection. The existing unconstrained minimax rule selects C. The rule penalizes hot discomfort only; cold discomfort and resource limits would need explicit treatment to change that objective.

External support for operating recommendations:

- Massachusetts Emergency Management Agency, [Preparing for Extreme Heat](https://www.mass.gov/info-details/preparing-for-extreme-heat): access to air-conditioned cooling locations during extreme heat.
- PNNL Building America Solution Center, [Evaporative Cooling Systems](https://basc.pnnl.gov/resource-guides/evaporative-cooling-systems): maintenance of reservoirs and media, mineral buildup and flushing.

The primary model evidence is retained in the repository: `sources/nasa_hourly_2025/README.md`, `03_decision/result_options.csv`, `03_decision/result_recommendations.csv`, and `04_sensitivity/result_sensitivity_detail.csv`.
