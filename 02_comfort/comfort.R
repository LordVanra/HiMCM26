# comfort.R
# Model 2 – Thermal comfort assessment
#
# Wraps the `comf` package's Standard Effective Temperature (SET) model to
# evaluate how each cooling option affects perceived thermal comfort.
# Produces per-zone SET values, discomfort loss (L), comfort benefit (B),
# efficiency (eta), person-hours, and comfort coverage summaries.


# set_value(T, Tr, v, RH, pressure, group)
# Calls comf::calcSET with the physiological parameters from `group` and the
# environmental conditions provided, returning a single SET value in °C.
#
# Arguments:
#   T        – zone dry-bulb temperature (°C)
#   Tr       – mean radiant temperature (°C)
#   v        – local air speed (m/s)
#   RH       – relative humidity (%)
#   pressure – atmospheric pressure (Pa)
#   group    – single-row data frame from the `groups` input table
set_value <- function(T, Tr, v, RH, pressure, group) {
  if (!requireNamespace("comf", quietly = TRUE))
    stop("comf package is not installed")

  stopifnot(
    nrow(group) == 1L,
    all(is.finite(c(T, Tr, v, RH, pressure))),
    v >= 0, RH >= 0, RH <= 100, pressure > 0
  )

  # Assemble the argument list for comf::calcSET
  # Note: pressure is converted from Pa to mmHg (pb) as required by the function
  args <- list(
    ta           = T,
    tr           = Tr,
    vel          = v,
    rh           = RH,
    clo          = group$clo,
    met          = group$met,
    wme          = group$wme,
    sa           = group$area_m2,
    pb           = pressure * 760 / 101325,   # Pa → mmHg
    ltime        = group$ltime,
    ht           = group$height,
    wt           = group$weight,
    tu           = group$tu,
    obj          = "set",
    csw          = group$csw,
    cdil         = group$cdil,
    cstr         = group$cstr,
    bodyPosition = group$posture
  )

  stopifnot(!any(vapply(args, anyNA, logical(1))))

  value <- do.call(comf::calcSET, args)
  stopifnot(length(value) == 1L, is.finite(value))

  as.numeric(value)
}


# comfort_totals(d, energy)
# Aggregates per-zone comfort metrics into a single-row summary for one
# (venue, scenario, option) combination.
#
# Returns a data frame with columns:
#   B, E, eta         – total benefit, energy, and benefit-per-kWh efficiency
#   L                 – total discomfort loss (person-°C-hours)
#   comfortable_person_hours, comfortable_person_hours_gained
#   person_hours      – total occupied person-hours
#   coverage          – fraction of person-hours that are comfortable
comfort_totals <- function(d, energy) {
  B <- sum(d$B)
  data.frame(
    B       = B,
    E       = energy,
    eta     = if (!is.na(energy) && energy > 0) B / energy else NA_real_,
    L       = sum(d$L),
    comfortable_person_hours        = sum(d$comfortable_person_hours),
    comfortable_person_hours_gained = sum(d$comfortable_person_hours_gained),
    person_hours = sum(d$person_hours),
    coverage = if (!anyNA(d$person_hours) && sum(d$person_hours) > 0)
      sum(d$comfortable_person_hours) / sum(d$person_hours) else NA_real_
  )
}


# run_comfort(cfg, tables, physics, log)
# Evaluates thermal comfort for every zone row produced by run_physics.
#
# For each zone × option × scenario:
#   1. Calls set_value() to get the Standard Effective Temperature.
#   2. Derives person-hours, discomfort loss (L), and coverage from SET thresholds.
#   3. Compares each option against the NONE baseline to compute benefit (B).
#   4. Summarises into one row per (venue, scenario, option).
#
# Returns a list:
#   detail  – the enriched per-zone data frame
#   summary – aggregated metrics per option
run_comfort <- function(cfg, tables, physics, log = skip_log()) {
  require_model_data(cfg, tables, through = 2L)

  d            <- physics$zones
  group_fields <- setdiff(input_columns()$groups, "source")

  # --- Validate the population (groups) table --------------------------------
  groups_ok <- complete_for(tables$groups, group_fields, "groups", log, 2, "SET", "all exposures")
  if (nrow(tables$groups) != 1L) {
    skip_output(log, 2, "SET", "groups (one population definition required)", "all exposures")
    groups_ok <- FALSE
  }

  # Comfort thresholds: NA means those derived columns will also be NA
  if (is.na(cfg$set_upper))
    skip_output(log, 2, "B/eta/L/comfort coverage", "cfg.set_upper")
  if (is.na(cfg$set_lower))
    skip_output(log, 2, "comfortable person-hours/coverage", "cfg.set_lower")

  # Check exposure fields needed for SET and occupancy-based comfort
  exposure_fields <- c(
    "zone", "v_local",
    if (cfg$comfort_basis == "occupied") "people",
    if (cfg$radiant_model == "measured") "Tr"
  )
  complete_for(tables$weather_occ, exposure_fields, "weather_occ", log, 2, "SET/comfort", "input table")

  # Initialise all comfort output columns to NA
  for (name in c("SET", "B", "L", "comfortable_person_hours",
                 "comfortable_person_hours_gained", "person_hours", "coverage",
                 "B_per_person", "L_per_person", "SET_drop",
                 "comfortable_hours_per_person", "comfortable_hours_gained_per_person"))
    d[[name]] <- rep(NA_real_, nrow(d))

  # ---- Pass 1: compute SET and loss per zone row ----------------------------
  for (i in seq_len(nrow(d))) {
    a       <- d[i, ]
    context <- paste(a$venue, a$scenario, a$hour, a$zone, a$option, sep = "/")

    # Attempt SET calculation if all required environmental inputs are present
    if (groups_ok &&
        complete_for(a, c("T", "Tr", "v_local", "RH", "pressure"),
                     "zone_conditions", log, 2, "SET", context))
      d$SET[i] <- attempt(set_value(a$T, a$Tr, a$v_local, a$RH, a$pressure, tables$groups),
                          log, 2, "SET", context)

    # Person-hours: occupancy × scenario duration
    if (!is.na(a$people) && a$people >= 0)
      d$person_hours[i] <- a$people * a$dt_hours
    else if (cfg$comfort_basis == "occupied")
      skip_output(log, 2, "occupied comfort", "weather_occ.people", context)

    # Discomfort loss per person: degree-hours above the upper SET threshold
    if (!is.na(d$SET[i]) && !is.na(cfg$set_upper)) {
      d$L_per_person[i] <- a$dt_hours * max(0, d$SET[i] - cfg$set_upper)
      d$L[i]            <- d$people[i] * d$L_per_person[i]
    }

    # Comfort coverage: fraction of time within the [set_lower, set_upper] band
    if (!is.na(d$SET[i]) && !anyNA(c(cfg$set_upper, cfg$set_lower))) {
      if (cfg$set_lower > cfg$set_upper) {
        skip_output(log, 2, "comfortable person-hours/coverage",
                    "invalid: cfg.set_lower > cfg.set_upper", context)
      } else {
        d$comfortable_hours_per_person[i] <- a$dt_hours *
          (d$SET[i] >= cfg$set_lower && d$SET[i] <= cfg$set_upper)
        d$comfortable_person_hours[i]     <- a$people * d$comfortable_hours_per_person[i]
        if (!is.na(d$person_hours[i]) && d$person_hours[i] > 0)
          d$coverage[i] <- d$comfortable_person_hours[i] / d$person_hours[i]
      }
    }
  }

  # ---- Pass 2: compute deltas vs. NONE baseline ----------------------------
  for (i in seq_len(nrow(d))) {
    a        <- d[i, ]
    baseline <- which(d$venue    == a$venue    &
                        d$scenario == a$scenario &
                        d$hour     == a$hour     &
                        d$zone     == a$zone     &
                        d$option   == "NONE")

    if (length(baseline) != 1L) {
      skip_output(log, 2, "B/eta/comfortable person-hours gained",
                  "matching NONE zone/hour result",
                  paste(a$venue, a$scenario, a$option))
      next
    }

    b <- d[baseline, ]
    if (!anyNA(c(b$people, a$people)) && b$people != a$people)
      stop("Occupancy must be identical across options")

    # Benefit = reduction in discomfort compared to no device
    d$B[i]           <- b$L - a$L
    d$B_per_person[i] <- b$L_per_person - a$L_per_person
    d$SET_drop[i]    <- b$SET - a$SET

    # Comfortable-hours gain from the NONE baseline
    d$comfortable_hours_gained_per_person[i] <- a$comfortable_hours_per_person - b$comfortable_hours_per_person
    d$comfortable_person_hours_gained[i]     <- a$comfortable_person_hours     - b$comfortable_person_hours
  }

  # ---- Pass 3: aggregate summaries per (venue, scenario, option) ------------
  summaries <- list()
  keys      <- unique(physics$resources[c("venue", "scenario", "option")])

  for (i in seq_len(nrow(keys))) {
    key     <- keys[i, ]
    context <- paste(key, collapse = "/")

    # Detail rows and resource totals for this key
    a  <- d[which(d$venue    == key$venue    &
                    d$scenario == key$scenario &
                    d$option   == key$option), , drop = FALSE]
    r  <- physics$resources[which(physics$resources$venue    == key$venue    &
                                    physics$resources$scenario == key$scenario &
                                    physics$resources$option   == key$option), , drop = FALSE]

    nz       <- length(which(tables$zones$venue == key$venue))
    obs      <- tables$weather_occ[which(tables$weather_occ$venue    == key$venue &
                                           tables$weather_occ$scenario == key$scenario), , drop = FALSE]
    expected <- nz * length(unique(obs$hour[!is.na(obs$hour)]))

    energy <- sum(r$kWh)
    water  <- sum(r$water_kg)
    total  <- comfort_totals(a, energy)

    # If the expected number of zone/hour rows is not met, suppress aggregated metrics
    if (expected == 0 || nrow(a) != expected || anyDuplicated(paste(a$hour, a$zone))) {
      for (field in setdiff(names(total), "E")) total[[field]] <- NA_real_
      skip_output(log, 2, "B/eta/L/comfort coverage",
                  "zone_conditions missing expected zones/hours", context)
    }

    # Flags for whether per-person metrics are computable
    single_complete <- nz == 1L && expected > 0 && nrow(a) == expected
    physical_valid  <- expected > 0 && nrow(a) == expected &&
      !anyDuplicated(paste(a$hour, a$zone)) &&
      all(is.finite(as.matrix(a[c("T", "w", "RH")]))) &&
      all(a$RH >= 0 & a$RH <= 100 + cfg$rtol)

    b_person   <- if (single_complete) sum(a$B_per_person) else NA_real_
    l_person   <- if (single_complete) sum(a$L_per_person) else NA_real_
    eta_person <- if (!is.na(energy) && energy > 0) b_person / energy else NA_real_

    summaries[[length(summaries) + 1L]] <- data.frame(
      key,
      total,
      B_per_person     = b_person,
      L_per_person     = l_person,
      eta_per_person   = eta_person,
      mean_SET         = if (single_complete) sum(a$SET * a$dt_hours) / sum(a$dt_hours) else NA_real_,
      mean_SET_drop    = if (single_complete) sum(a$SET_drop * a$dt_hours) / sum(a$dt_hours) else NA_real_,
      comfortable_hours_per_person        = if (single_complete) sum(a$comfortable_hours_per_person)        else NA_real_,
      comfortable_hours_gained_per_person = if (single_complete) sum(a$comfortable_hours_gained_per_person) else NA_real_,
      coverage_per_person  = if (single_complete) sum(a$comfortable_hours_per_person) / sum(a$dt_hours) else NA_real_,
      water_kg         = water,
      physical_valid   = physical_valid,
      valid_SET_rows   = sum(!is.na(a$SET)),
      expected_rows    = expected
    )
  }

  # Return detail rows and an empty-typed prototype for safe rbinding
  list(
    detail  = d,
    summary = bind_rows(summaries, data.frame(
      venue = character(), scenario = character(), option = character(),
      B = numeric(), E = numeric(), eta = numeric(), L = numeric(),
      physical_valid = logical(),
      comfortable_person_hours = numeric(), comfortable_person_hours_gained = numeric(),
      person_hours = numeric(), coverage = numeric(),
      B_per_person = numeric(), L_per_person = numeric(), eta_per_person = numeric(),
      mean_SET = numeric(), mean_SET_drop = numeric(),
      comfortable_hours_per_person = numeric(), comfortable_hours_gained_per_person = numeric(),
      coverage_per_person = numeric(), water_kg = numeric(),
      valid_SET_rows = integer(), expected_rows = integer()
    ))
  )
}


# plot_comfort_gallery(result, cfg, book)
# Populates the gallery book with Model-2 (comfort) charts covering SET,
# felt-temperature reduction, discomfort loss, efficiency, and coverage.
plot_comfort_gallery <- function(result, cfg, book) {
  a <- result$options

  # Mean SET by option — lower is not always more comfortable
  chart_metric(book, "C01", 2, a, "mean_SET",
               "What the conditions feel like: SET",
               "Standard effective temperature (degC)")

  # Heatmap: how much did each device reduce felt temperature?
  chart_heatmap(book, "C02", 2, a, "mean_SET_drop",
                "Change in felt temperature from no device", "SET reduction (degC)")

  # Lollipop: felt-temperature reduction ranked by option
  chart_metric(book, "C03", 2, a, "mean_SET_drop",
               "Felt-temperature reduction by option", "SET reduction (degC)", "lollipop")

  # Scatter: energy vs. SET reduction (physical comparison, not regret)
  d <- chart_data(a)
  d <- d[is.finite(d$mean_SET_drop), ]
  p <- ggplot2::ggplot(d, ggplot2::aes(E, mean_SET_drop, color = option)) +
    ggplot2::geom_point(size = 3.5) +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    chart_colors() + chart_theme() +
    ggplot2::labs(
      title   = "Electricity versus felt-temperature reduction",
      x = "Energy in modeled scenario (kWh)", y = "SET reduction (degC)",
      caption = chart_caption())
  chart_add(book, "C04", 2, "Electricity versus felt-temperature reduction", p, data = d)

  # Scatter: air temperature vs. SET (illustrates the gap between dry-bulb and felt temp)
  d <- chart_data(result$comfort_detail)
  d <- d[is.finite(d$T) & is.finite(d$SET), ]
  p <- ggplot2::ggplot(d, ggplot2::aes(T, SET, color = option)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, color = "grey65", linetype = 2) +
    ggplot2::geom_point(size = 3.5) +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    chart_colors() + chart_theme() +
    ggplot2::labs(
      title   = "Air temperature and felt temperature differ",
      x = "Air temperature (degC)", y = "SET (degC)", caption = chart_caption())
  chart_add(book, "C05", 2, "Air temperature and felt temperature differ", p, data = d)

  # Comfort efficiency (benefit per kWh) and residual discomfort
  chart_metric(book, "C06", 2, a, "decision_eta",
               "Comfort benefit per unit of electricity", "Comfort benefit / kWh")
  chart_metric(book, "C07", 2, a, "loss",
               "Residual discomfort after cooling", "Discomfort (see configured comfort basis)")

  # Comfort coverage heatmap: fraction of person-hours within the comfort band
  field <- if (cfg$comfort_basis == "per_person") "coverage_per_person" else "coverage"
  chart_heatmap(book, "C08", 2, a, field, "Comfort coverage by option", "Fraction comfortable")

  invisible(book)
}
