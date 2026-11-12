source("01_physics/physics.R")
source("02_comfort/comfort.R")
source("03_decision/decision.R")
source("04_sensitivity/sensitivity.R")

fixture <- function() {
  tables <- setNames(lapply(names(input_columns()), empty_input), names(input_columns()))
  tables$zones <- data.frame(venue = "test", zone = "z1", volume_m3 = 100,
    area_m2 = 20, h = 4, Tsurf = 35, sensible_W = 100, moisture_kg_s = 0, source = "synthetic test only")
  tables$exchanges <- data.frame(venue = "test", from = c("OUTSIDE", "z1"), to = c("z1", "OUTSIDE"), mass_kg_s = .5, source = "synthetic test only")
  tables$weather_occ <- data.frame(venue = "test", scenario = "hot", hour = 1,
    zone = "z1", T = 35, RH = 30, pressure = 101325, people = 10,
    v_local = .1, Tr = 35, annual_weight = 100, source = "synthetic test only")
  tables$devices <- data.frame(venue = "test", option = c("A", "B", "C"), type = c("A", "B", "C"),
    zone = "z1", power_kW = c(.25, 1.2, 2.5), v_fan = c(1.5, NA, NA),
    m_dot = c(NA, .5, 1), dT_max = c(3, 5, 8),
    capital = c(100, 200, 300), maintenance = 10, life_years = 10,
    discount_rate = 0, electricity_price = .1, water_price = NA_real_, source = "synthetic test only")
  tables$groups <- data.frame(clo = .5, met = 1.2, wme = 0, height = 171, weight = 70,
    area_m2 = 1.8258, posture = "standing", ltime = 60, tu = 40, csw = 170, cdil = 120, cstr = .5, source = "reference-test parameters only")
  tables
}

empty_tables <- setNames(lapply(names(input_columns()), empty_input), names(input_columns()))
empty_run <- run_all(build_config(), empty_tables, quiet = TRUE)
stopifnot(nrow(empty_run$outdoor) == 0, nrow(empty_run$options) == 0, nrow(empty_run$skipped) > 0)

cfg <- build_config()
cfg$heat_model <- "full"; cfg$radiant_model <- "measured"
cfg$comfort_basis <- "occupied"; cfg$cost_basis <- "annual"
cfg$set_upper <- 26; cfg$set_lower <- 20
tables <- fixture()
r <- run_all(cfg, tables, quiet = TRUE)
stopifnot(nrow(r$zone_conditions) == 4, all(r$mass_balance$balanced),
  all(abs(r$mass_balance$mass_residual_kg_s) <= cfg$rtol),
  all(r$zone_conditions$RH <= 100), all(r$zone_conditions$RH >= 0),
  all(is.finite(r$comfort_detail$SET)), all(is.finite(r$options$L)),
  any(r$recommendations$chosen), !nrow(r$skipped))
stopifnot(annualized_capital(100, 10, 0) == 10)

# Published SET example: pythermalcomfort documentation, Standard Effective Temperature:
# https://pythermalcomfort.readthedocs.io/en/stable/documentation/models.html
# T=Tr=25 C, v=.1 m/s, RH=50%, met=1.2, clo=.5 gives 24.3 C rounded to 0.1 C.
reference <- set_value(25, 25, .1, 50, 101325, tables$groups)
stopifnot(abs(reference - 24.3) <= .05)

z <- r$zone_conditions
stopifnot(abs(z$T[z$option == "A"] - z$T[z$option == "NONE"]) < 1e-10)
for (op in c("B", "C")) {
  dev <- tables$devices[tables$devices$option == op, ]
  state <- evap_state(dev, tables$weather_occ, cfg)
  stopifnot(abs(state["T"] - (35 - dev$dT_max)) < 1e-12,
    state["w"] > humidity_ratio(35, 30, 101325))
  expected <- dev$m_dot*(state["w"] - humidity_ratio(35, 30, 101325))*3600
  stopifnot(abs(r$options$water_kg[r$options$option == op] - expected) < 1e-8)
}

bad <- tables; bad$exchanges$mass_kg_s[2] <- .4
bad_result <- run_all(cfg, bad, quiet = TRUE)
stopifnot(any(!bad_result$mass_balance$balanced), all(is.na(bad_result$zone_conditions$T)),
  all(is.finite(bad_result$options$E)))

wet <- tables; wet$zones$moisture_kg_s <- 1
wet_result <- run_all(cfg, wet, quiet = TRUE)
stopifnot(all(is.na(wet_result$zone_conditions$RH)),
  any(grepl("RH exceeds", wet_result$skipped$inputs)))

double <- tables
zz <- tables$zones; zz$zone <- "z2"
double$zones <- rbind(tables$zones, zz)
ff <- tables$exchanges; ff$from[ff$from == "z1"] <- "z2"; ff$to[ff$to == "z1"] <- "z2"
double$exchanges <- rbind(tables$exchanges, ff)
ww <- tables$weather_occ; ww$zone <- "z2"
double$weather_occ <- rbind(tables$weather_occ, ww)
dd <- tables$devices; dd$zone <- "z2"
double$devices <- rbind(tables$devices, dd)
r2 <- run_all(cfg, double, quiet = TRUE)
for (op in c("A", "B", "C")) {
  one <- r$options[r$options$option == op, ]; two <- r2$options[r2$options$option == op, ]
  stopifnot(abs(two$B - 2*one$B) < 1e-8, abs(two$E - 2*one$E) < 1e-8,
    abs(two$eta - one$eta) < 1e-8)
}

partial <- tables; partial$devices$m_dot[partial$devices$type == "B"] <- NA
pr <- run_all(cfg, partial, quiet = TRUE)
stopifnot(all(is.finite(pr$zone_conditions$T[pr$zone_conditions$option %in% c("NONE", "A", "C")])),
  is.na(pr$options$L[pr$options$option == "B"]), is.finite(pr$options$E[pr$options$option == "B"]))

dry_only <- tables; dry_only$weather_occ$RH <- NA_real_
dry_result <- run_all(cfg, dry_only, quiet = TRUE)
stopifnot(all(is.finite(dry_result$zone_conditions$T[dry_result$zone_conditions$option %in% c("NONE", "A")])),
  all(is.na(dry_result$zone_conditions$RH)))

independent <- double; independent$zones$sensible_W[1] <- NA_real_
independent_result <- run_all(cfg, independent, quiet = TRUE)
stopifnot(all(is.finite(independent_result$zone_conditions$T[independent_result$zone_conditions$zone == "z2"])),
  all(is.na(independent_result$options$L)))

unset <- cfg; unset$set_upper <- unset$set_lower <- NA_real_
u <- run_all(unset, tables, quiet = TRUE)
stopifnot(all(is.finite(u$comfort_detail$SET)), all(is.na(u$options$L)), all(u$options$feasible))
missing_cost <- tables; missing_cost$devices$capital <- NA
mc <- run_all(cfg, missing_cost, quiet = TRUE)
stopifnot(all(mc$options$feasible), all(is.finite(mc$options$L)),
  all(is.na(mc$options$annual_cost[mc$options$option != "NONE"])))
limit <- cfg; limit$budget <- 1
lim <- run_all(limit, tables, quiet = TRUE)
stopifnot(all(!lim$options$feasible[lim$options$option != "NONE"]))
matrix_case <- data.frame(venue = "test", scenario = rep(c("s1", "s2"), each = 4),
  option = rep(c("NONE", "A", "B", "C"), 2), L = c(10, 3, 5, 9, 10, 8, 6, 1),
  annual_cost = rep(c(0, 1, 2, 3), 2), eta = rep(c(NA, 1, 2, 3), 2), feasible = TRUE)
regret <- minimax_regret(matrix_case, cfg)
stopifnot(identical(regret$recommendations$option[regret$recommendations$chosen], "B"))
stopifnot(all(regret$options$R == c(7, 0, 2, 6, 9, 7, 5, 0)))

tables$bounds <- data.frame(parameter = "cfg.set_upper", lower = 25, upper = 28, source = "synthetic test bounds only")
sweep <- run_sensitivity(cfg, tables, quiet = TRUE)
stopifnot(nrow(sweep$detail) == cfg$sweep_levels*4, all(is.finite(sweep$detail$L)))
unset_threshold <- cfg; unset_threshold$set_upper <- NA_real_
with_bounds <- run_sensitivity(unset_threshold, tables, quiet = TRUE)
stopifnot(all(is.finite(with_bounds$detail$L)), all(is.na(with_bounds$detail$delta_L)))
mc_cfg <- cfg; mc_cfg$mc_n <- 5L
simulation <- run_monte_carlo(mc_cfg, tables, quiet = TRUE)
stopifnot(abs(sum(simulation$frequencies$frequency) - 1) < 1e-12,
  all(simulation$frequencies$draws == 5),
  identical(simulation, run_monte_carlo(mc_cfg, tables, quiet = TRUE)))

simple_cfg <- build_config()
simple_cfg$set_upper <- 26; simple_cfg$set_lower <- 20
simple <- fixture()
simple$weather_occ$people <- NA_real_; simple$weather_occ$Tr <- NA_real_
for (field in c("area_m2", "h", "Tsurf", "sensible_W", "moisture_kg_s")) simple$zones[[field]] <- NA_real_
for (field in c("maintenance", "life_years", "discount_rate", "electricity_price")) simple$devices[[field]] <- NA_real_
simple$devices$airflow_m3_s <- c(NA, .5, 1)
simple$devices$m_dot <- NA_real_
simple_result <- run_all(simple_cfg, simple, quiet = TRUE)
stopifnot(all(is.finite(simple_result$comfort_detail$SET)),
  all(is.na(simple_result$options$L)), all(is.finite(simple_result$options$loss)),
  all(is.finite(simple_result$options$purchase_cost)),
  all(simple_result$options$decision_cost == simple_result$options$purchase_cost),
  any(simple_result$recommendations$chosen), !nrow(simple_result$skipped))
stopifnot(all(simple_result$zone_conditions$Tr == simple_result$zone_conditions$T),
  is.na(simple$weather_occ$people), is.na(simple$weather_occ$Tr),
  is.na(simple$zones$Tsurf), all(is.na(simple$devices$m_dot)))

stopifnot(all(is.finite(u$options$mean_SET)), all(is.finite(u$options$mean_SET_drop)),
  all(is.na(u$options$loss)), all(is.na(u$options$coverage_per_person)))
stopifnot(all(is.finite(simple_result$options$coverage_per_person)),
  all(simple_result$options$coverage_per_person >= 0 & simple_result$options$coverage_per_person <= 1),
  all(is.na(simple_result$options$person_hours)))

stopifnot(all(simple_result$options$safety_status == "unassessed"))

humid <- fixture(); humid$weather_occ$RH <- 85
limited_cfg <- cfg; limited_cfg$cooler_limit <- "saturation_limit"
fixed <- run_all(cfg, humid, quiet = TRUE)
limited <- run_all(limited_cfg, humid, quiet = TRUE)
stopifnot(all(is.na(fixed$zone_conditions$T[fixed$zone_conditions$option %in% c("B", "C")])),
  all(is.finite(limited$zone_conditions$T)), all(limited$zone_conditions$RH <= 100 + cfg$rtol))
for (op in c("B", "C")) {
  dev <- humid$devices[humid$devices$option == op, ]; w <- humid$weather_occ
  supply <- evap_state(dev, w, limited_cfg)
  original_w <- humidity_ratio(w$T, w$RH, w$pressure)
  original_h <- 1.006*w$T + original_w*(2501 + 1.86*w$T)
  new_h <- 1.006*supply["T"] + supply["w"]*(2501 + 1.86*supply["T"])
  stopifnot(abs(original_h - new_h) < 1e-8,
    supply["T"] > w$T - dev$dT_max,
    relative_humidity(supply["T"], supply["w"], w$pressure) <= 100 + cfg$rtol)
}

saturated_weather <- humid$weather_occ; saturated_weather$RH <- 100
saturated_supply <- evap_state(humid$devices[2, ], saturated_weather, limited_cfg)
stopifnot(saturated_supply["T"] <= saturated_weather$T, saturated_supply["water_kg"] >= 0)

paired <- fixture()
paired$bounds <- data.frame(parameter = c("exchanges.1.mass_kg_s", "exchanges.2.mass_kg_s"),
  lower = .475, upper = .525, source = "synthetic test bounds only")
stopifnot(nrow(usable_bounds(cfg, paired, skip_log(), every_numeric = FALSE)) == 1)
changed <- set_parameter("exchanges.1.mass_kg_s", .52, cfg, paired)
stopifnot(all(mass_residual(changed$tables$zones$zone, changed$tables$exchanges) == 0))
paired_mc <- run_monte_carlo(mc_cfg, paired, quiet = TRUE)
stopifnot(abs(sum(paired_mc$frequencies$frequency) - 1) < 1e-12)

scratch <- file.path(tempdir(), "himcm_plot_checks")
dir.create(scratch, showWarnings = FALSE)
stopifnot(pareto_plot(r$options, file.path(scratch, "pareto.png")),
  break_even_plot(sweep$detail, file.path(scratch, "break_even.png")))
stopifnot(file.info(file.path(scratch, c("pareto.png", "break_even.png")))$size > 0)
for (folder in c("01_physics", "02_comfort", "03_decision", "04_sensitivity"))
  dir.create(file.path(scratch, folder), showWarnings = FALSE)
invisible(capture.output(save_results(simple_result, scratch)))
stopifnot(file.exists(file.path(scratch, "03_decision", "result_pareto.png")))
invisible(capture.output(save_results(u, scratch)))
stopifnot(!file.exists(file.path(scratch, "03_decision", "result_pareto.png")))

cat("PASS: physics, RH, SET reference, zero discount, scaling, missing-data isolation, constraints, regret, sensitivity, Monte Carlo and plot checks.\n")
