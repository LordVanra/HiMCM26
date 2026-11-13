# Hot-weather scenario sources

NASA POWER/MERRA-2 hourly gridded temperature (T2M), relative humidity (RH2M) and surface pressure (PS), June-August 2025, at the existing city reference coordinates. These are hourly mean reanalysis values, not measurements at the waiting areas. Each city response contains 2,208 complete hours. PS is supplied in kPa and converted to Pa. UTC timestamps are retained.

Three distinct hours are selected deterministically for each city, before looking at cooling outcomes:

1. Highest dry-bulb temperature in the summer.
2. Highest humidity ratio among the hottest 10% of hourly records, excluding the peak hour.
3. Lowest humidity ratio among the same hot subset, excluding the earlier choices.

The hottest 10% means ceil(0.10 * 2208) = 221 records, ordered by temperature descending and UTC timestamp ascending for ties. Humidity ratio uses the same ASHRAE saturation-pressure equation as physics.R. The humid/dry labels are relative to that city's hot subset; Phoenix's humid-hot scenario is not humid on a Boston scale. The 10% selection rule defines stress scenarios, not probabilities. There is no assertion that these scenarios span every plausible summer condition.

All variables for each scenario come from the same timestamp. Bus and rail in a city use the same three weather records. The previously approved venue ventilation and passenger airspeed estimates are held fixed across weather scenarios; hourly wind/exposure changes are not claimed to have been measured.

| City | Scenario | UTC hour (YYYYMMDDHH) | T (degC) | RH (%) | Pressure (Pa) |
|---|---|---|---:|---:|---:|
| DAL | hot_peak | 2025073120 | 42.64 | 16.13 | 99210.0 |
| DAL | hot_humid | 2025080717 | 36.51 | 41.02 | 99710.0 |
| DAL | hot_dry | 2025082523 | 36.54 | 18.01 | 99170.0 |
| BOS | hot_peak | 2025072918 | 36.79 | 28.99 | 100390.0 |
| BOS | hot_humid | 2025062322 | 30.39 | 71.92 | 100660.0 |
| BOS | hot_dry | 2025080819 | 29.18 | 28.17 | 101400.0 |
| PHX | hot_peak | 2025080721 | 47.92 | 6.03 | 95280.0 |
| PHX | hot_humid | 2025082220 | 42.64 | 20.46 | 95240.0 |
| PHX | hot_dry | 2025061621 | 45.26 | 2.99 | 95130.0 |

Raw API responses are DAL.json, BOS.json and PHX.json. Exact requests are in the corresponding *_request.txt files. selected_scenarios.csv contains the selection rule and source URL for each row. fetch_hot_weather.py downloads the source responses; prepare_hot_scenarios.py reproduces the active weather table and its authorized +/-5% bounds. The prior summer means are preserved one directory above.

[NASA hourly API documentation](https://power.larc.nasa.gov/docs/services/api/temporal/hourly/). The response headers identify MERRA2/POWER sources, hourly UTC, API v2.10.4, and -999 as the fill value. No selected record contains a fill value.

The user-selected 23-26 degC SET comparison band is a policy choice, not an ASHRAE Standard 55 compliance claim or a computed 80% satisfaction rate. See [ASHRAE Thermal Comfort](https://handbook.ashrae.org/handbooks/F25/SI/F25_Ch09/F25_Ch09_si.aspx). Clothing remains the previously chosen T-shirt/shorts reference (0.36 clo).
