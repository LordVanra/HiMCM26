# test_pipeline.R
# End-to-end regression tests for the full HiMCM analysis pipeline.
#
# Run this file with Rscript from the project root.  It prints "PASS: ..."
# at the end if every assertion succeeds, or stops with an error on the
# first failure.
#
# Tests cover:
#   - Missing-data detection (require_model_data)
#   - Standard Effective Temperature against a published reference value
#   - Full physics + comfort + decision run on a synthetic single-zone fixture
#   - Mass-balance failure propagation
#   - High-humidity saturation behaviour (RH > 100 % guard)
#   - Two-zone scaling (benefits and energy scale linearly with zones)
#   - Four-zone network, parameter setting, and usable_bounds de-duplication
#   - Partial device data stopping rules
#   - Budget and cap feasibility flags
#   - Minimax-regret correctness on a hand-crafted matrix
#   - Sensitivity sweep and Monte Carlo runs (with Monte Carlo reproducibility)
#   - Simplified (optional-field-free) mode
#   - SET-threshold-independent metrics (mean_SET, mean_SET_drop)
#   - Duration scaling (all energy/water/benefit metrics scale with dt_hours)
#   - Multiple missing-field stopping (all fields reported in one error)
#   - Calibrated effectiveness cooling model
#   - Saturation-limit cooling mode
#   - Saturated outdoor conditions
#   - Paired symmetric exchange bounds
#   - Pareto and break-even plot file generation
#   - save_results() output including optional plot removal
#   - Decision gallery radar chart (D07) using ggplot2 / dplyr / scales

source("01_physics/physics.R")
source("02_comfort/comfort.R")
source("03_decision/decision.R")
source("04_sensitivity/sensitivity.R")


# Shared fixture builder
# Creates a minimal but complete set of input tables for a single zone ("z1")
# at a single venue ("test") with one hot scenario and three device options.
fixture <- function() {
  tables <- setNames(lapply(names(input_columns()), empty_input), names(input_columns()))

  # Single zone: 100 m³ volume, 20 m² floor, 4 m ceiling, 35 °C surface temp
  tables$zones <- data.frame(
    venue = "test", zone = "z1", volume_m3 = 100,
    area_m2 = 20, h = 4, Tsurf = 35, sensible_W = 100, moisture_kg_s = 0,
    source = "synthetic test only"
  )

  # Exchange network: 0.5 kg/s outdoor supply and return
  tables$exchanges <- data.frame(
    venue = "test",
    from  = c("OUTSIDE", "z1"),
    to    = c("z1", "OUTSIDE"),
    mass_kg_s = .5,
    source    = "synthetic test only"
  )

  # One weather/occupancy row: hot (35 °C, 30 % RH), 10 people, 1-hour scenario
  tables$weather_occ <- data.frame(
    venue = "test", scenario = "hot", hour = 1,
    zone = "z1", dt_hours = 1, T = 35, RH = 30, pressure = 101325, people = 10,
    v_local = .1, Tr = 35, annual_weight = 100, source = "synthetic test only"
  )

  # Three cooling options:
  #   A – fan only  (1.5 m/s, 0.25 kW)
  #   B – evaporative mist (0.5 kg/s, max 5 °C drop)
  #   C – evaporative cooler (1 kg/s, max 8 °C drop)
  tables$devices <- data.frame(
    venue    = "test",
    option   = c("A", "B", "C"),
    type     = c("A", "B", "C"),
    zone     = "z1",
    power_kW = c(.25, 1.2, 2.5),
    v_fan    = c(1.5, NA, NA),
    m_dot    = c(NA, .5, 1),
    dT_max   = c(3, 5, 8),
    capital  = c(100, 200, 300),
    maintenance    = 10,
    life_years     = 10,
    discount_rate  = 0,
    electricity_price = .1,
    water_price    = 0,
    source         = "synthetic test only"
  )

  # Reference population: lightly-dressed standing adult
  tables$groups <- data.frame(
    clo = .5, met = 1.2, wme = 0, height = 171, weight = 70,
    area_m2 = 1.8258, posture = "standing", ltime = 60, tu = 40,
    csw = 170, cdil = 120, cstr = .5, source = "reference-test parameters only"
  )

  tables
}


# Helper: assert that a call stops with a specific "Analysis not started" error
# that mentions every field listed in `fields`.
empty_tables <- setNames(lapply(names(input_columns()), empty_input), names(input_columns()))

expect_missing <- function(expr, fields) {
  message <- tryCatch({ force(expr); "NO ERROR" }, error = conditionMessage)
  stopifnot(
    startsWith(message, "Analysis not started:"),
    all(vapply(fields, grepl, logical(1), x = message, fixed = TRUE))
  )
}


# Test 1 – Missing-data guard fires for all required tables at once
expect_missing(
  run_all(build_config(), empty_tables, quiet = TRUE),
  c("zones", "devices", "weather_occ", "groups")
)


# Test 2 – Full pipeline run on the standard fixture
cfg <- build_config()
stopifnot(cfg$set_lower == 23, cfg$set_upper == 26, cfg$cooler_limit == "saturation_limit")
cfg$cooler_limit <- "fixed"
cfg$heat_model    <- "full"
cfg$radiant_model <- "measured"
cfg$comfort_basis <- "occupied"
cfg$cost_basis    <- "annual"
cfg$set_upper     <- 26
cfg$set_lower     <- 20

tables <- fixture()
r      <- run_all(cfg, tables, quiet = TRUE)

# Basic structural checks
stopifnot(
  nrow(r$zone_conditions) == 4,                              # NONE + 3 options
  all(r$mass_balance$balanced),                              # Network is balanced
  all(abs(r$mass_balance$mass_residual_kg_s) <= cfg$rtol),
  all(r$zone_conditions$RH <= 100),
  all(r$zone_conditions$RH >= 0),
  all(is.finite(r$comfort_detail$SET)),
  all(is.finite(r$options$L)),
  any(r$recommendations$chosen),                             # At least one option recommended
  !nrow(r$skipped)                                           # No skipped outputs
)

# Annualised capital at zero discount rate is simply capital / life_years
stopifnot(annualized_capital(100, 10, 0) == 10)


# Test 3 – SET reference value from pythermalcomfort documentation
# Published SET example: pythermalcomfort documentation, Standard Effective Temperature:
# https://pythermalcomfort.readthedocs.io/en/stable/documentation/models.html
# T = Tr = 25 °C, v = 0.1 m/s, RH = 50 %, met = 1.2, clo = 0.5 → 24.3 °C (± 0.05)
reference <- set_value(25, 25, .1, 50, 101325, tables$groups)
stopifnot(abs(reference - 24.3) <= .05)


# Test 4 – Fan (option A) must leave zone temperature unchanged vs. NONE
#          Evaporative coolers (B, C) must achieve exactly dT_max cooling and
#          add moisture above the ambient humidity ratio
z <- r$zone_conditions
stopifnot(abs(z$T[z$option == "A"] - z$T[z$option == "NONE"]) < 1e-10)

for (op in c("B", "C")) {
  dev   <- tables$devices[tables$devices$option == op, ]
  state <- evap_state(dev, tables$weather_occ, cfg)

  stopifnot(
    abs(state["T"] - (35 - dev$dT_max)) < 1e-12,              # Outlet temperature
    state["w"] > humidity_ratio(35, 30, 101325)                # Outlet is more humid
  )

  # Water consumption should match direct calculation from humidity change
  expected <- dev$m_dot * (state["w"] - humidity_ratio(35, 30, 101325)) * 3600
  stopifnot(abs(r$options$water_kg[r$options$option == op] - expected) < 1e-8)
}


# Test 5 – Unbalanced mass flows: zone temperatures become NA but energy
#          values are still computed
bad <- tables
bad$exchanges$mass_kg_s[2] <- .4   # Break mass balance

bad_result <- run_all(cfg, bad, quiet = TRUE)
stopifnot(
  any(!bad_result$mass_balance$balanced),
  all(is.na(bad_result$zone_conditions$T)),
  all(is.finite(bad_result$options$E))
)


# Test 6 – Excessive moisture source: RH goes impossible → zones skipped
wet <- tables
wet$zones$moisture_kg_s <- 1   # 1 kg/s moisture source drives RH > 100 %

wet_result <- run_all(cfg, wet, quiet = TRUE)
stopifnot(
  all(is.na(wet_result$zone_conditions$RH)),
  any(grepl("RH exceeds", wet_result$skipped$inputs))
)


# Test 7 – Two-zone network: benefit and energy scale linearly with zone count
double <- tables
zz <- tables$zones;    zz$zone <- "z2"
ff <- tables$exchanges; ff$from[ff$from == "z1"] <- "z2"; ff$to[ff$to == "z1"] <- "z2"
ww <- tables$weather_occ; ww$zone <- "z2"
dd <- tables$devices;    dd$zone <- "z2"

double$zones       <- rbind(tables$zones,       zz)
double$exchanges   <- rbind(tables$exchanges,   ff)
double$weather_occ <- rbind(tables$weather_occ, ww)
double$devices     <- rbind(tables$devices,     dd)

r2 <- run_all(cfg, double, quiet = TRUE)

for (op in c("A", "B", "C")) {
  one <- r$options[r$options$option  == op, ]
  two <- r2$options[r2$options$option == op, ]
  stopifnot(
    abs(two$B - 2*one$B) < 1e-8,
    abs(two$E - 2*one$E) < 1e-8,
    abs(two$eta - one$eta) < 1e-8   # Efficiency is per-kWh so it should not change
  )
}


# Test 8 – Partial device data: missing m_dot on a B/C device must be caught
partial <- tables
partial$devices$m_dot[partial$devices$type == "B"] <- NA

expect_missing(run_all(cfg, partial, quiet = TRUE), "devices.m_dot OR devices.airflow_m3_s")


# Test 9 – Missing RH in weather must be caught before running
dry_only <- tables
dry_only$weather_occ$RH <- NA_real_

expect_missing(run_all(cfg, dry_only, quiet = TRUE), "weather_occ.RH")


# Test 10 – Missing sensible_W in a two-zone config is correctly identified
independent <- double
independent$zones$sensible_W[1] <- NA_real_

expect_missing(run_all(cfg, independent, quiet = TRUE), "zones.sensible_W")


# Test 11 – No SET threshold: L is NA but SET is still computed
unset <- cfg
unset$set_upper <- unset$set_lower <- NA_real_

u <- run_all(unset, tables, quiet = TRUE)
stopifnot(
  all(is.finite(u$comfort_detail$SET)),
  all(is.na(u$options$L)),
  all(u$options$feasible)
)


# Test 12 – Missing capital: cost computation is blocked
missing_cost <- tables
missing_cost$devices$capital <- NA

expect_missing(run_all(cfg, missing_cost, quiet = TRUE), "devices.capital")


# Test 13 – Budget cap: all paid options become infeasible when budget is \$1
limit     <- cfg
limit$budget <- 1

lim <- run_all(limit, tables, quiet = TRUE)
stopifnot(all(!lim$options$feasible[lim$options$option != "NONE"]))


# Test 14 – Minimax regret on a hand-crafted 2-scenario × 4-option matrix
#
# Loss matrix (lower = better):
#   scenario s1: NONE=10, A=3,  B=5,  C=9
#   scenario s2: NONE=10, A=8,  B=6,  C=1
#
# Scenario-best: s1 → A(3), s2 → C(1)
# Regret:
#   s1: NONE=7, A=0, B=2, C=6
#   s2: NONE=9, A=7, B=5, C=0
# Max regret: NONE=9, A=7, B=5, C=6  → minimax chooses B
# Expected R values: c(7,0,2,6, 9,7,5,0)
matrix_case <- data.frame(
  venue       = "test",
  scenario    = rep(c("s1", "s2"), each = 4),
  option      = rep(c("NONE", "A", "B", "C"), 2),
  L           = c(10, 3, 5, 9, 10, 8, 6, 1),
  annual_cost = rep(c(0, 1, 2, 3), 2),
  eta         = rep(c(NA, 1, 2, 3), 2),
  feasible    = TRUE
)

regret <- minimax_regret(matrix_case, cfg)
stopifnot(
  identical(regret$recommendations$option[regret$recommendations$chosen], "B"),
  all(regret$options$R == c(7, 0, 2, 6, 9, 7, 5, 0))
)


# Test 15 – Sensitivity sweep: correct number of rows and finite L values
tables$bounds <- data.frame(
  parameter = "cfg.set_upper", lower = 25, upper = 28,
  source    = "synthetic test bounds only"
)

sweep <- run_sensitivity(cfg, tables, quiet = TRUE)
stopifnot(
  nrow(sweep$detail) == cfg$sweep_levels * 4,   # sweep_levels × 4 options
  all(is.finite(sweep$detail$L))
)


# When set_upper is NA the sweep still runs but delta_L should be NA
unset_threshold        <- cfg
unset_threshold$set_upper <- NA_real_
with_bounds <- run_sensitivity(unset_threshold, tables, quiet = TRUE)
stopifnot(
  all(is.finite(with_bounds$detail$L)),
  all(is.na(with_bounds$detail$delta_L))
)


# Test 16 – Monte Carlo: frequencies sum to 1, draw count is correct,
#           and results are bit-identical on a repeated call (seed is fixed)
mc_cfg      <- cfg
mc_cfg$mc_n <- 5L

simulation <- run_monte_carlo(mc_cfg, tables, quiet = TRUE)
stopifnot(
  abs(sum(simulation$frequencies$frequency) - 1) < 1e-12,
  all(simulation$frequencies$draws == 5),
  identical(simulation, run_monte_carlo(mc_cfg, tables, quiet = TRUE))
)


# Test 17 – Simplified (optional-field-free) mode
# Many fields are set to NA to exercise the "simple" fallback paths where
# comfort is computed without occupancy and costs are purchase-only.
simple_cfg           <- build_config()
simple_cfg$set_upper <- 26
simple_cfg$set_lower <- 20

simple <- fixture()
simple$weather_occ$people  <- NA_real_
simple$weather_occ$Tr      <- NA_real_

for (field in c("area_m2", "h", "Tsurf", "sensible_W", "moisture_kg_s"))
  simple$zones[[field]] <- NA_real_
for (field in c("maintenance", "life_years", "discount_rate", "electricity_price"))
  simple$devices[[field]] <- NA_real_

# Use volumetric airflow instead of mass flow for B/C
simple$devices$airflow_m3_s <- c(NA, .5, 1)
simple$devices$m_dot        <- NA_real_

simple_result <- run_all(simple_cfg, simple, quiet = TRUE)

stopifnot(
  all(is.finite(simple_result$comfort_detail$SET)),
  all(is.na(simple_result$options$L)),                          # No threshold → no loss
  all(is.finite(simple_result$options$loss)),
  all(is.finite(simple_result$options$purchase_cost)),
  all(simple_result$options$decision_cost == simple_result$options$purchase_cost),
  any(simple_result$recommendations$chosen),
  !nrow(simple_result$skipped)
)

# Optional fields must remain unmodified in the input tables (no side effects)
stopifnot(
  all(simple_result$zone_conditions$Tr == simple$weather_occ$T),
  is.na(simple$weather_occ$people),
  is.na(simple$weather_occ$Tr),
  is.na(simple$zones$Tsurf),
  all(is.na(simple$devices$m_dot))
)

# Evaporative coolers should raise Tr above T (evaporation adds humidity, not cooling to Tr)
stopifnot(all(
  simple_result$zone_conditions$Tr[simple_result$zone_conditions$option %in% c("B", "C")] >
    simple_result$zone_conditions$T[simple_result$zone_conditions$option  %in% c("B", "C")]
))


# Test 18 – No-threshold metrics: mean_SET and mean_SET_drop are still finite;
#            coverage_per_person is NA when no threshold is set
stopifnot(
  all(is.finite(u$options$mean_SET)),
  all(is.finite(u$options$mean_SET_drop)),
  all(is.na(u$options$loss)),
  all(is.na(u$options$coverage_per_person))
)

# In simplified mode (no occupancy), coverage_per_person should be [0, 1]
# but person_hours should be NA
stopifnot(
  all(is.finite(simple_result$options$coverage_per_person)),
  all(simple_result$options$coverage_per_person >= 0 &
        simple_result$options$coverage_per_person <= 1),
  all(is.na(simple_result$options$person_hours))
)


# Test 19 – Safety status is always "unassessed" (not in scope for this model)
stopifnot(all(simple_result$options$safety_status == "unassessed"))


# Test 20 – Duration scaling: doubling dt_hours doubles E, water, B, and L;
#           SET and eta are time-intensive and must NOT change
long_run <- fixture()
long_run$weather_occ$dt_hours <- 8

eight <- run_all(cfg, long_run, quiet = TRUE)

stopifnot(
  all(abs(eight$options$E        - 8*r$options$E)        < 1e-8),
  all(abs(eight$options$water_kg - 8*r$options$water_kg) < 1e-8),
  all(abs(eight$options$B        - 8*r$options$B)        < 1e-8),
  all(abs(eight$options$L        - 8*r$options$L)        < 1e-8),
  all(abs(eight$options$eta[-1]  - r$options$eta[-1])    < 1e-8),
  all(abs(eight$comfort_detail$SET - r$comfort_detail$SET) < 1e-8)
)


# Test 21 – Multiple missing fields: all reported in one error message
missing_many <- fixture()
missing_many$weather_occ$RH    <- NA
missing_many$devices$capital[1] <- NA
expect_missing(run_all(cfg, missing_many, quiet = TRUE), c("weather_occ.RH", "devices.capital"))


# Test 22 – Missing water_price when cost_basis = "annual": blocked
#            but purchase-only mode should succeed even without water_price
no_water_price <- fixture()
no_water_price$devices$water_price <- NA_real_

expect_missing(run_all(cfg, no_water_price, quiet = TRUE), "devices.water_price")
stopifnot(nrow(run_all(simple_cfg, no_water_price, quiet = TRUE)$options) == 4)


# Test 23 – Optional cfg flags: mc_n = NA and run_monte_carlo = NA should
#           still produce the standard 4 option rows
no_optional                <- cfg
no_optional$mc_n           <- NA_integer_
no_optional$run_monte_carlo <- NA

stopifnot(nrow(run_all(no_optional, fixture(), quiet = TRUE)$options) == 4)


# Test 24 – v_occupied device field overrides v_fan for SET calculation
exposure <- fixture()
exposure$devices$v_occupied <- c(1.2, .8, 1.1)
exposure$devices$v_fan      <- NA_real_

exposure_result <- run_all(cfg, exposure, quiet = TRUE)

stopifnot(all(
  exposure_result$zone_conditions$v_local[exposure_result$zone_conditions$option != "NONE"]
  == exposure$devices$v_occupied
))


# Test 25 – run_monte_carlo and run_sensitivity require a bounds table
expect_missing(run_monte_carlo(cfg, fixture(), quiet = TRUE), "bounds")
expect_missing(run_sensitivity(cfg, fixture(), quiet = TRUE), "bounds")


# Test 26 – Four-zone network
# Builds a 4-zone venue by replicating the fixture zone 4 times.
# Benefits and energy should scale 4× relative to the single-zone baseline.
four <- fixture()
for (name in c("zones", "exchanges", "weather_occ", "devices")) {
  four[[name]] <- do.call(rbind, lapply(1:4, function(i) {
    x <- fixture()[[name]]
    # Rename zone references so each copy targets its own zone (z1, z2, z3, z4)
    for (field in intersect(c("zone", "from", "to"), names(x)))
      x[[field]][x[[field]] == "z1"] <- paste0("z", i)
    x
  }))
}

four_result <- run_all(cfg, four, quiet = TRUE)

stopifnot(
  nrow(four_result$zone_conditions) == 16,       # 4 zones × 4 options
  all(four_result$mass_balance$balanced),
  all(abs(four_result$options$B - 4*r$options$B) < 1e-8),
  all(abs(four_result$options$E - 4*r$options$E) < 1e-8)
)

# set_parameter must update all linked rows simultaneously
changed_duration <- set_parameter("weather_occ.1.dt_hours", 8, cfg, four)
changed_weather  <- set_parameter("weather_occ.1.T",        36, cfg, four)
stopifnot(
  all(changed_duration$tables$weather_occ$dt_hours == 8),
  all(changed_weather$tables$weather_occ$T         == 36)
)

# Bounds table: only one of the four dt_hours rows qualifies as a unique boundary
four$bounds <- data.frame(
  parameter = paste0("weather_occ.", 1:4, ".dt_hours"),
  lower = .95, upper = 1.05, source = "synthetic test only"
)
stopifnot(nrow(usable_bounds(cfg, four, skip_log(), every_numeric = FALSE)) == 1)

# Sensitivity sweep over the four-zone network
four_sweep <- run_sensitivity(cfg, four, quiet = TRUE)
stopifnot(
  nrow(four_sweep$detail) == 4 * cfg$sweep_levels,
  all(is.finite(four_sweep$detail$L))
)


# Test 27 – Calibrated effectiveness cooling model
# When cooler_limit = "effectiveness", RH must stay ≤ 100 % and the outlet T
# must be above (T - dT_max) when humidity limits the achievable cooling.
calibrated <- fixture()
calibrated$devices$T_ref        <- 35
calibrated$devices$RH_ref       <- 30
calibrated$devices$pressure_ref <- 101325

cal_cfg              <- cfg
cal_cfg$cooler_limit <- "effectiveness"

# Increase ambient RH to 60 % to test saturation behaviour
calibrated$weather_occ$RH <- 60

cal_result <- run_all(cal_cfg, calibrated, quiet = TRUE)
stopifnot(all(cal_result$options$physical_valid))

# Verify outlet conditions for device C individually
cs <- evap_state(calibrated$devices[3, ], calibrated$weather_occ, cal_cfg)
stopifnot(
  cs["T"] > calibrated$weather_occ$T - calibrated$devices$dT_max[3],
  relative_humidity(cs["T"], cs["w"], calibrated$weather_occ$pressure) <= 100
)

# Without calibration columns the effectiveness model should stop
expect_missing(
  run_all(cal_cfg, fixture(), quiet = TRUE),
  c("devices.T_ref", "devices.RH_ref", "devices.pressure_ref")
)


# Test 28 – Saturation-limit cooling mode
# At high ambient humidity (85 %) the fixed-drop model produces supersaturation;
# saturation_limit mode should clamp T/RH to physically feasible values.
humid <- fixture()
humid$weather_occ$RH <- 85

limited_cfg              <- cfg
limited_cfg$cooler_limit <- "saturation_limit"

fixed   <- run_all(cfg,         humid, quiet = TRUE)   # fixed mode: should give NA
limited <- run_all(limited_cfg, humid, quiet = TRUE)   # limit mode: should succeed

# Fixed mode: evaporative zones are physically invalid (supersaturation)
stopifnot(
  all(is.na(fixed$zone_conditions$T[fixed$zone_conditions$option %in% c("B", "C")])),
  all(is.finite(limited$zone_conditions$T)),
  all(limited$zone_conditions$RH <= 100 + cfg$rtol)
)

stopifnot(
  all(!fixed$options$feasible[fixed$options$option %in% c("B", "C")]),
  all(fixed$options$resource_feasible),
  all(!fixed$options$physical_valid[fixed$options$option %in% c("B", "C")]),
  all(is.na(fixed$options$R[fixed$options$option %in% c("B", "C")]))
)

# Saturation-limit mode: enthalpy is conserved along the constant-enthalpy line
for (op in c("B", "C")) {
  dev    <- humid$devices[humid$devices$option == op, ]
  w      <- humid$weather_occ
  supply <- evap_state(dev, w, limited_cfg)

  original_w <- humidity_ratio(w$T, w$RH, w$pressure)
  original_h <- 1.006*w$T + original_w*(2501 + 1.86*w$T)       # Specific enthalpy (kJ/kg)
  new_h      <- 1.006*supply["T"] + supply["w"]*(2501 + 1.86*supply["T"])

  stopifnot(
    abs(original_h - new_h) < 1e-8,                                   # Enthalpy conservation
    supply["T"] > w$T - dev$dT_max,                                    # Less cooling than rated
    relative_humidity(supply["T"], supply["w"], w$pressure) <= 100 + cfg$rtol
  )
}


# Test 29 – Saturated outdoor conditions (RH = 100 %)
# evap_state must not add water and outlet T must not exceed ambient T.
saturated_weather        <- humid$weather_occ
saturated_weather$RH     <- 100

saturated_supply <- evap_state(humid$devices[2, ], saturated_weather, limited_cfg)
stopifnot(
  saturated_supply["T"]        <= saturated_weather$T,
  saturated_supply["water_kg"] >= 0
)


# Test 30 – Paired symmetric exchange bounds: linked rows collapse to one sweep
#           parameter, and setting one also updates its pair
paired <- fixture()
paired$bounds <- data.frame(
  parameter = c("exchanges.1.mass_kg_s", "exchanges.2.mass_kg_s"),
  lower     = .475, upper = .525, source = "synthetic test bounds only"
)

stopifnot(nrow(usable_bounds(cfg, paired, skip_log(), every_numeric = FALSE)) == 1)

changed <- set_parameter("exchanges.1.mass_kg_s", .52, cfg, paired)
stopifnot(all(mass_residual(changed$tables$zones$zone, changed$tables$exchanges) == 0))

paired_mc <- run_monte_carlo(mc_cfg, paired, quiet = TRUE)
stopifnot(abs(sum(paired_mc$frequencies$frequency) - 1) < 1e-12)


# Test 31 – Plot file generation
# Verifies that pareto_plot() and break_even_plot() return TRUE and write
# non-empty PNG files to a temporary directory.
scratch <- file.path(tempdir(), "himcm_plot_checks")
dir.create(scratch, showWarnings = FALSE)

stopifnot(
  pareto_plot(r$options,        file.path(scratch, "pareto.png")),
  break_even_plot(sweep$detail, file.path(scratch, "break_even.png"))
)
stopifnot(file.info(file.path(scratch, c("pareto.png", "break_even.png")))$size > 0)


# Test 32 – save_results() writes CSVs and conditionally writes/removes the
#           Pareto PNG
for (folder in c("01_physics", "02_comfort", "03_decision", "04_sensitivity"))
  dir.create(file.path(scratch, folder), showWarnings = FALSE)

invisible(capture.output(save_results(simple_result, scratch)))
stopifnot(file.exists(file.path(scratch, "03_decision", "result_pareto.png")))

# When L is all NA (no threshold set), the Pareto plot is skipped and the
# PNG from the previous call must be removed
invisible(capture.output(save_results(u, scratch)))
stopifnot(!file.exists(file.path(scratch, "03_decision", "result_pareto.png")))


# Test 33 – Decision gallery radar chart (D07) requires ggplot2, dplyr, scales
if (requireNamespace("ggplot2", quietly = TRUE) &&
    requireNamespace("dplyr",   quietly = TRUE) &&
    requireNamespace("scales",  quietly = TRUE)) {

  gallery        <- new.env(parent = emptyenv())
  gallery$items  <- list()
  plot_decision_gallery(r, cfg, gallery)

  radar <- gallery$items$D07
  stopifnot(
    !is.null(radar$plot),
    all(is.finite(radar$data$scaled)),
    all(radar$data$scaled >= 0 & radar$data$scaled <= 1),
    all(radar$data$raw[radar$data$metric == "Maximum\nregret"] ==
          radar$data$max_regret[radar$data$metric == "Maximum\nregret"])
  )
  invisible(ggplot2::ggplot_build(radar$plot))

  # Without a SET threshold the minimax radar (D07) should be a pending entry
  absent        <- new.env(parent = emptyenv())
  absent$items  <- list()
  plot_decision_gallery(u, build_config(), absent)
  stopifnot(
    is.null(absent$items$D07$plot),
    nzchar(absent$items$D07$reason)
  )
}


<<<<<<< HEAD
# Test 34 – The study inputs cover all four venue types in each city.
study_venues <- as.vector(outer(c("DAL", "BOS", "PHX"),
                               c("BUS", "RAIL", "QUAD", "PAV"), paste, sep = "_"))
study <- run_all(build_config(), load_tables(), quiet = TRUE)
study_options <- table(study$options$venue, study$options$option)
stopifnot(
  setequal(rownames(study_options), study_venues),
  setequal(colnames(study_options), c("NONE", "A", "B", "C")),
  all(study_options == 1L),
  setequal(study$outdoor$venue, study_venues),
  setequal(study$comfort_detail$venue, study_venues)
)
=======
two_venues <- fixture()
for (name in c("zones", "exchanges", "weather_occ", "devices")) {
  extra <- two_venues[[name]]; extra$venue <- "second"
  two_venues[[name]] <- rbind(two_venues[[name]], extra)
}
base_two <- run_all(cfg, two_venues, quiet = TRUE)
changed_two <- set_parameter("weather_occ.1.T", 36, cfg, two_venues)
cached_two <- rerun_sensitivity_case("weather_occ.1.T", changed_two, base_two)
full_two <- run_all(changed_two$cfg, changed_two$tables, quiet = TRUE)
ordered <- function(x) {
  x <- x[order(x$venue, x$scenario, x$option), ]; rownames(x) <- NULL; x
}
stopifnot(isTRUE(all.equal(ordered(cached_two$options), ordered(full_two$options))),
  isTRUE(all.equal(ordered(cached_two$recommendations), ordered(full_two$recommendations))))

cap_cfg <- build_config()
for (rh in c(0, 30, 70, 99, 100)) {
  w <- fixture()$weather_occ; w$RH <- rh
  dev <- fixture()$devices[3, ]
  supply <- evap_state(dev, w, cap_cfg)
  twb <- wet_bulb(w$T, humidity_ratio(w$T, w$RH, w$pressure), w$pressure)
  stopifnot(supply["T"] >= twb - cap_cfg$rtol, supply["T"] >= w$T-dev$dT_max-cap_cfg$rtol,
    relative_humidity(supply["T"], supply["w"], w$pressure) <= 100 + cap_cfg$rtol, supply["water_kg"] >= 0)
}
>>>>>>> 4c50923b122c8eb260ffc36a994fea0edbfbb56c

# All tests passed
cat("PASS: physics, RH, SET reference, duration scaling, fixed radiation, four zones,",
    "required-data stopping, optional Monte Carlo, calibrated cooling, costs,",
    "feasibility, regret, sensitivity, graphs and all 12 study venues.\n")
