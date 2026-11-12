set_value <- function(T, Tr, v, RH, pressure, group) {
  if (!requireNamespace("comf", quietly = TRUE)) stop("comf package is not installed")
  stopifnot(nrow(group) == 1L, all(is.finite(c(T, Tr, v, RH, pressure))),
    v >= 0, RH >= 0, RH <= 100, pressure > 0)
  args <- list(ta = T, tr = Tr, vel = v, rh = RH, clo = group$clo,
    met = group$met, wme = group$wme, sa = group$area_m2,
    pb = pressure * 760/101325, ltime = group$ltime, ht = group$height,
    wt = group$weight, tu = group$tu, obj = "set", csw = group$csw,
    cdil = group$cdil, cstr = group$cstr, bodyPosition = group$posture)
  stopifnot(!any(vapply(args, anyNA, logical(1))))
  value <- do.call(comf::calcSET, args)
  stopifnot(length(value) == 1L, is.finite(value))
  as.numeric(value)
}

comfort_totals <- function(d, energy) {
  B <- sum(d$B)
  data.frame(B = B, E = energy, eta = if (!is.na(energy) && energy > 0) B/energy else NA_real_,
    L = sum(d$L), comfortable_person_hours = sum(d$comfortable_person_hours),
    comfortable_person_hours_gained = sum(d$comfortable_person_hours_gained),
    person_hours = sum(d$person_hours),
    coverage = if (!anyNA(d$person_hours) && sum(d$person_hours) > 0)
      sum(d$comfortable_person_hours)/sum(d$person_hours) else NA_real_)
}

run_comfort <- function(cfg, tables, physics, log = skip_log()) {
  d <- physics$zones
  group_fields <- setdiff(input_columns()$groups, "source")
  groups_ok <- complete_for(tables$groups, group_fields, "groups", log, 2, "SET", "all exposures")
  if (nrow(tables$groups) != 1L) {
    skip_output(log, 2, "SET", "groups (one population definition required)", "all exposures")
    groups_ok <- FALSE
  }
  if (is.na(cfg$set_upper)) skip_output(log, 2, "B/eta/L/comfort coverage", "cfg.set_upper")
  if (is.na(cfg$set_lower)) skip_output(log, 2, "comfortable person-hours/coverage", "cfg.set_lower")
  exposure_fields <- c("zone", "v_local", if (cfg$comfort_basis == "occupied") "people", if (cfg$radiant_model == "measured") "Tr")
  complete_for(tables$weather_occ, exposure_fields, "weather_occ", log, 2, "SET/comfort", "input table")
  for (name in c("SET", "B", "L", "comfortable_person_hours", "comfortable_person_hours_gained", "person_hours", "coverage", "B_per_person", "L_per_person", "SET_drop", "comfortable_hours_per_person", "comfortable_hours_gained_per_person")) d[[name]] <- rep(NA_real_, nrow(d))
  for (i in seq_len(nrow(d))) {
    a <- d[i, ]; context <- paste(a$venue, a$scenario, a$hour, a$zone, a$option, sep = "/")
    if (groups_ok && complete_for(a, c("T", "Tr", "v_local", "RH", "pressure"), "zone_conditions", log, 2, "SET", context))
      d$SET[i] <- attempt(set_value(a$T, a$Tr, a$v_local, a$RH, a$pressure, tables$groups), log, 2, "SET", context)
    if (!is.na(a$people) && a$people >= 0) d$person_hours[i] <- a$people * a$dt_hours
    else if (cfg$comfort_basis == "occupied") skip_output(log, 2, "occupied comfort", "weather_occ.people", context)
    if (!is.na(d$SET[i]) && !is.na(cfg$set_upper)) {
      d$L_per_person[i] <- a$dt_hours * max(0, d$SET[i] - cfg$set_upper)
      d$L[i] <- d$people[i] * d$L_per_person[i]
    }
    if (!is.na(d$SET[i]) && !anyNA(c(cfg$set_upper, cfg$set_lower))) {
      if (cfg$set_lower > cfg$set_upper) skip_output(log, 2, "comfortable person-hours/coverage", "invalid: cfg.set_lower > cfg.set_upper", context)
      else {
        d$comfortable_hours_per_person[i] <- a$dt_hours * (d$SET[i] >= cfg$set_lower && d$SET[i] <= cfg$set_upper)
        d$comfortable_person_hours[i] <- a$people * d$comfortable_hours_per_person[i]
        if (!is.na(d$person_hours[i]) && d$person_hours[i] > 0) d$coverage[i] <- d$comfortable_person_hours[i]/d$person_hours[i]
      }
    }
  }
  for (i in seq_len(nrow(d))) {
    a <- d[i, ]; baseline <- which(d$venue == a$venue & d$scenario == a$scenario & d$hour == a$hour & d$zone == a$zone & d$option == "NONE")
    if (length(baseline) != 1L) { skip_output(log, 2, "B/eta/comfortable person-hours gained", "matching NONE zone/hour result", paste(a$venue, a$scenario, a$option)); next }
    b <- d[baseline, ]
    if (!anyNA(c(b$people, a$people)) && b$people != a$people) stop("Occupancy must be identical across options")
    d$B[i] <- b$L - a$L
    d$B_per_person[i] <- b$L_per_person - a$L_per_person
    d$SET_drop[i] <- b$SET - a$SET
    d$comfortable_hours_gained_per_person[i] <- a$comfortable_hours_per_person - b$comfortable_hours_per_person
    d$comfortable_person_hours_gained[i] <- a$comfortable_person_hours - b$comfortable_person_hours
  }
  summaries <- list()
  keys <- unique(physics$resources[c("venue", "scenario", "option")])
  for (i in seq_len(nrow(keys))) {
    key <- keys[i, ]; context <- paste(key, collapse = "/")
    a <- d[which(d$venue == key$venue & d$scenario == key$scenario & d$option == key$option), , drop = FALSE]
    r <- physics$resources[which(physics$resources$venue == key$venue & physics$resources$scenario == key$scenario & physics$resources$option == key$option), , drop = FALSE]
    nz <- length(which(tables$zones$venue == key$venue))
    obs <- tables$weather_occ[which(tables$weather_occ$venue == key$venue & tables$weather_occ$scenario == key$scenario), , drop = FALSE]
    expected <- nz * length(unique(obs$hour[!is.na(obs$hour)]))
    energy <- sum(r$kWh); water <- sum(r$water_kg)
    total <- comfort_totals(a, energy)
    if (expected == 0 || nrow(a) != expected || anyDuplicated(paste(a$hour, a$zone))) {
      for (field in setdiff(names(total), "E")) total[[field]] <- NA_real_
      skip_output(log, 2, "B/eta/L/comfort coverage", "zone_conditions missing expected zones/hours", context)
    }
    single_complete <- nz == 1L && expected > 0 && nrow(a) == expected
    b_person <- if (single_complete) sum(a$B_per_person) else NA_real_
    l_person <- if (single_complete) sum(a$L_per_person) else NA_real_
    eta_person <- if (!is.na(energy) && energy > 0) b_person/energy else NA_real_
    summaries[[length(summaries) + 1L]] <- data.frame(key, total, B_per_person = b_person,
      L_per_person = l_person, eta_per_person = eta_person,
      mean_SET = if (single_complete) sum(a$SET*a$dt_hours)/sum(a$dt_hours) else NA_real_,
      mean_SET_drop = if (single_complete) sum(a$SET_drop*a$dt_hours)/sum(a$dt_hours) else NA_real_,
      comfortable_hours_per_person = if (single_complete) sum(a$comfortable_hours_per_person) else NA_real_,
      comfortable_hours_gained_per_person = if (single_complete) sum(a$comfortable_hours_gained_per_person) else NA_real_,
      coverage_per_person = if (single_complete) sum(a$comfortable_hours_per_person)/sum(a$dt_hours) else NA_real_,
      water_kg = water,
      valid_SET_rows = sum(!is.na(a$SET)), expected_rows = expected)
  }
  list(detail = d, summary = bind_rows(summaries, data.frame(venue = character(), scenario = character(), option = character(),
    B = numeric(), E = numeric(), eta = numeric(), L = numeric(), comfortable_person_hours = numeric(),
    comfortable_person_hours_gained = numeric(), person_hours = numeric(), coverage = numeric(), B_per_person = numeric(), L_per_person = numeric(), eta_per_person = numeric(), mean_SET = numeric(), mean_SET_drop = numeric(), comfortable_hours_per_person = numeric(), comfortable_hours_gained_per_person = numeric(), coverage_per_person = numeric(), water_kg = numeric(), valid_SET_rows = integer(), expected_rows = integer())))
}
