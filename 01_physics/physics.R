build_config <- function() {
  list(solver = "steady", rtol = 1e-8, tie_tol = 1e-6, seed = 1L,
       mc_n = 1000L, sweep_levels = 5L, set_upper = NA_real_,
       set_lower = NA_real_, budget = NA_real_, kwh_cap = NA_real_,
       water_cap = NA_real_, heat_model = "mixing_only",
       radiant_model = "air_reference", comfort_basis = "per_person", cost_basis = "purchase", cooler_limit = "fixed")
}

input_columns <- function() {
  list(
    zones = c("venue", "zone", "volume_m3", "area_m2", "h", "Tsurf", "sensible_W", "moisture_kg_s", "source"),
    exchanges = c("venue", "from", "to", "mass_kg_s", "source"),
    weather_occ = c("venue", "scenario", "hour", "zone", "T", "RH", "pressure", "people", "v_local", "Tr", "annual_weight", "source"),
    devices = c("venue", "option", "type", "zone", "power_kW", "v_fan", "m_dot", "airflow_m3_s", "dT_max", "capital", "maintenance", "life_years", "discount_rate", "electricity_price", "water_price", "source"),
    groups = c("clo", "met", "wme", "height", "weight", "area_m2", "posture", "ltime", "tu", "csw", "cdil", "cstr", "source"),
    bounds = c("parameter", "lower", "upper", "source")
  )
}

empty_input <- function(name) {
  chars <- c("venue", "zone", "from", "to", "scenario", "option", "type", "posture", "parameter", "source")
  as.data.frame(setNames(lapply(input_columns()[[name]], function(k)
    if (k %in% chars) character() else numeric()), input_columns()[[name]]))
}

load_tables <- function(root = ".") {
  setNames(lapply(names(input_columns()), function(n) {
    path <- file.path(root, paste0(n, ".csv"))
    if (!file.exists(path)) return(empty_input(n))
    d <- read.csv(path, na.strings = c("", "NA"), stringsAsFactors = FALSE,
                  check.names = FALSE, strip.white = TRUE)
    for (k in setdiff(input_columns()[[n]], names(d))) d[[k]] <- rep(NA, nrow(d))
    d
  }), names(input_columns()))
}

skip_log <- function() {
  e <- new.env(parent = emptyenv())
  e$rows <- list()
  e
}

skip_output <- function(log, model, output, inputs, context = "all") {
  if (!length(inputs)) return(invisible(NULL))
  log$rows[[length(log$rows) + 1L]] <- data.frame(model = model, output = output,
    context = context, inputs = paste(unique(inputs), collapse = ", "), stringsAsFactors = FALSE)
  invisible(NULL)
}

skipped_table <- function(log) {
  if (!length(log$rows)) return(data.frame(model = character(), output = character(), context = character(), inputs = character()))
  unique(do.call(rbind, log$rows))
}

missing_fields <- function(d, fields, table) {
  bad <- fields[vapply(fields, function(k) !k %in% names(d) || !nrow(d) || anyNA(d[[k]]), logical(1))]
  if (length(bad)) paste0(table, ".", bad) else character()
}

complete_for <- function(d, fields, table, log, model, output, context) {
  missing <- missing_fields(d, fields, table)
  skip_output(log, model, output, missing, context)
  !length(missing)
}

attempt <- function(expr, log, model, output, context) {
  tryCatch(expr, error = function(e) {
    skip_output(log, model, output, paste0("invalid: ", conditionMessage(e)), context)
    NA_real_
  })
}

bind_rows <- function(rows, prototype) {
  if (!length(rows)) prototype else do.call(rbind, rows)
}

sat_pressure <- function(T) {
  stopifnot(length(T) == 1L, is.finite(T), T >= -100, T <= 200)
  K <- T + 273.15
  if (T <= 0.01) exp(-5674.5359/K + 6.3925247 - 0.009677843*K +
    0.00000062215701*K^2 + 2.0747825e-9*K^3 - 9.484024e-13*K^4 + 4.1635019*log(K))
  else exp(-5800.2206/K + 1.3914993 - 0.048640239*K +
    0.000041764768*K^2 - 1.4452093e-8*K^3 + 6.5459673*log(K))
}

humidity_ratio <- function(T, RH, pressure) {
  stopifnot(is.finite(RH), RH >= 0, RH <= 100, is.finite(pressure), pressure > 0)
  pv <- RH/100 * sat_pressure(T)
  stopifnot(pv < pressure)
  0.621945 * pv/(pressure - pv)
}

relative_humidity <- function(T, w, pressure) {
  stopifnot(is.finite(w), w >= 0, is.finite(pressure), pressure > 0)
  100 * pressure * w/(0.621945 + w)/sat_pressure(T)
}

wet_bulb <- function(T, w, pressure, tol = 1e-8) {
  stopifnot(w >= 0, relative_humidity(T, w, pressure) <= 100 + tol)
  f <- function(tw) {
    ws <- humidity_ratio(tw, 100, pressure)
    if (tw >= 0) ((2501 - 2.326*tw)*ws - 1.006*(T - tw))/(2501 + 1.86*T - 4.186*tw) - w
    else ((2830 - 0.24*tw)*ws - 1.006*(T - tw))/(2830 + 1.86*T - 2.1*tw) - w
  }
  uniroot(f, c(-100, T), tol = tol)$root
}

evap_state <- function(device, weather, cfg) {
  stopifnot(device$m_dot >= 0, device$dT_max >= 0)
  wo <- humidity_ratio(weather$T, weather$RH, weather$pressure)
  # User-specified fixed outlet drop; zone cooling is determined by mixing and heat gains.
  Ts <- weather$T - device$dT_max
  hout <- 1.006*weather$T + wo*(2501 + 1.86*weather$T)
  ws <- (hout - 1.006*Ts)/(2501 + 1.86*Ts)
  stopifnot(ws >= wo - cfg$rtol)
  if (relative_humidity(Ts, ws, weather$pressure) > 100 + cfg$rtol) {
    if (cfg$cooler_limit != "saturation_limit")
      stop("fixed outlet reduction requires supersaturation under the direct-evaporation moisture model")
    # This explicitly selected alternative reduces cooling at the saturation boundary.
    residual <- function(t) {
      w <- (hout - 1.006*t)/(2501 + 1.86*t)
      relative_humidity(t, w, weather$pressure) - 100
    }
    Ts <- min(weather$T, uniroot(residual, c(Ts, weather$T), tol = cfg$rtol/100)$root + cfg$rtol)
    ws <- if (Ts == weather$T) wo else (hout - 1.006*Ts)/(2501 + 1.86*Ts)
  }
  c(T = Ts, w = ws, water_kg = device$m_dot*(ws - wo)*3600)
}

mass_residual <- function(zones, exchanges) {
  vapply(zones, function(z) sum(exchanges$mass_kg_s[exchanges$to == z]) -
    sum(exchanges$mass_kg_s[exchanges$from == z]), numeric(1))
}

zone_components <- function(zones, flows) {
  remaining <- zones; out <- list()
  while (length(remaining)) {
    component <- remaining[1]
    repeat {
      linked <- unique(c(component, flows$to[flows$from %in% component], flows$from[flows$to %in% component]))
      linked <- intersect(linked, zones)
      if (setequal(component, linked)) break
      component <- linked
    }
    out[[length(out) + 1L]] <- component
    remaining <- setdiff(remaining, component)
  }
  out
}

run_physics <- function(cfg, tables, log = skip_log()) {
  outdoor <- tables$weather_occ
  complete_for(outdoor, c("T", "RH", "pressure"), "weather_occ", log, 1, "outdoor", "input table")
  outdoor$w <- outdoor$Twb <- rep(NA_real_, nrow(outdoor))
  for (i in seq_len(nrow(outdoor))) {
    a <- outdoor[i, , drop = FALSE]; context <- paste(a$venue, a$scenario, a$hour, sep = "/")
    if (complete_for(a, c("T", "RH", "pressure"), "weather_occ", log, 1, "outdoor", context)) {
      outdoor$w[i] <- attempt(humidity_ratio(a$T, a$RH, a$pressure), log, 1, "outdoor.w", context)
      if (!is.na(outdoor$w[i])) outdoor$Twb[i] <- attempt(wet_bulb(a$T, outdoor$w[i], a$pressure, cfg$rtol), log, 1, "outdoor.Twb", context)
    }
  }
  zone_fields <- c("venue", "zone", if (cfg$heat_model == "full") c("area_m2", "h", "Tsurf", "sensible_W", "moisture_kg_s"))
  complete_for(tables$zones, zone_fields, "zones", log, 1, "zone_conditions", "input table")
  complete_for(tables$exchanges, c("venue", "from", "to", "mass_kg_s"), "exchanges", log, 1, "zone_conditions", "input table")
  complete_for(outdoor, c("venue", "scenario", "hour", "zone"), "weather_occ", log, 1, "zone_conditions/energy/water", "input table")
  complete_for(tables$devices, c("venue", "option", "type", "zone"), "devices", log, 1, "device_assignment", "input table")
  evaporative <- tables$devices[which(tables$devices$type %in% c("B", "C")), , drop = FALSE]
  if (nrow(evaporative) && all(is.na(evaporative$m_dot)) && (!"airflow_m3_s" %in% names(evaporative) || all(is.na(evaporative$airflow_m3_s))))
    skip_output(log, 1, "evaporative_supply/water", "devices.m_dot or devices.airflow_m3_s", "B/C inputs")
  fans <- tables$devices[which(tables$devices$type == "A"), , drop = FALSE]
  if (nrow(fans)) complete_for(fans, "v_fan", "devices", log, 2, "fan SET", "A inputs")
  cases <- unique(outdoor[complete.cases(outdoor[c("venue", "scenario", "hour")]), c("venue", "scenario", "hour"), drop = FALSE])
  zone_rows <- resource_rows <- checks <- list()
  for (ci in seq_len(nrow(cases))) {
    key <- cases[ci, ]; context <- paste(key, collapse = "/")
    obs <- outdoor[which(outdoor$venue == key$venue & outdoor$scenario == key$scenario & outdoor$hour == key$hour), , drop = FALSE]
    z <- tables$zones[which(tables$zones$venue == key$venue), , drop = FALSE]
    f <- tables$exchanges[which(tables$exchanges$venue == key$venue), , drop = FALSE]
    dev <- tables$devices[which(tables$devices$venue == key$venue), , drop = FALSE]
    options <- unique(c("NONE", "A", "B", "C", dev$option[!is.na(dev$option)]))
    flow_ok <- complete_for(f, c("from", "to", "mass_kg_s"), "exchanges", log, 1, "zone_conditions", context)
    zone_ok <- complete_for(z, "zone", "zones", log, 1, "zone_conditions", context)
    if (zone_ok && (nrow(z) > 3 || anyDuplicated(z$zone))) {
      skip_output(log, 1, "zone_conditions", "invalid: require 1 to 3 distinct zones", context); zone_ok <- FALSE
    }
    if (zone_ok && flow_ok) {
      flow_ok <- all(c(f$from, f$to) %in% c(z$zone, "OUTSIDE")) && all(f$mass_kg_s >= 0)
      if (!flow_ok) skip_output(log, 1, "zone_conditions", "invalid: exchange endpoint or negative flow", context)
    }
    for (op in options) {
      dd <- dev[which(dev$option == op), , drop = FALSE]
      label <- paste(context, op, sep = "/")
      power <- if (op == "NONE") 0 else NA_real_
      water <- if (op == "NONE") 0 else NA_real_
      device_ok <- op == "NONE" || complete_for(dd, c("type", "zone"), "devices", log, 1, "zone_conditions", label)
      if (op != "NONE" && complete_for(dd, "power_kW", "devices", log, 1, "energy", label)) {
        if (all(dd$power_kW >= 0)) power <- sum(dd$power_kW)
        else skip_output(log, 1, "energy", "invalid: negative power_kW", label)
      }
      supplies <- vector("list", nrow(dd)); water_each <- rep(NA_real_, nrow(dd))
      if (device_ok && op != "NONE") for (di in seq_len(nrow(dd))) {
        d <- dd[di, ]; dc <- paste(label, d$zone, sep = "/")
        if (d$type == "A") { water_each[di] <- 0; next }
        if (!d$type %in% c("B", "C")) { skip_output(log, 1, "zone_conditions/water", "invalid: device type", dc); next }
        if (is.na(d$m_dot) && "airflow_m3_s" %in% names(d) && !is.na(d$airflow_m3_s) &&
            all(is.finite(c(obs$T[1], obs$pressure[1], obs$w[1])))) {
          # ASHRAE moist-air specific volume per kg dry air; not a guessed density.
          specific_volume <- 287.042 * (obs$T[1] + 273.15) * (1 + 1.607858 * obs$w[1])/obs$pressure[1]
          d$m_dot <- d$airflow_m3_s/specific_volume
          dd$m_dot[di] <- d$m_dot
        }
        okd <- complete_for(d, c("m_dot", "dT_max"), "devices", log, 1, "evaporative_supply/water", dc)
        okw <- complete_for(obs, c("T", "RH", "pressure"), "weather_occ", log, 1, "evaporative_supply/water", dc)
        if (okd && okw) {
          same <- nrow(unique(obs[c("T", "RH", "pressure")])) == 1
          if (!same) { skip_output(log, 1, "evaporative_supply/water", "invalid: outdoor weather differs across zones", dc); next }
          val <- attempt(evap_state(d, obs[1, ], cfg), log, 1, "evaporative_supply/water", dc)
          if (length(val) == 3 && !anyNA(val)) { supplies[[di]] <- val; water_each[di] <- val["water_kg"] }
        }
      }
      if (op != "NONE" && nrow(dd) && !anyNA(water_each)) water <- sum(water_each)
      resource_rows[[length(resource_rows) + 1L]] <- data.frame(key, option = op, kWh = power, water_kg = water)
      if (!zone_ok || !flow_ok || !device_ok) next
      if (nrow(dd) && any(!dd$zone %in% z$zone)) { skip_output(log, 1, "zone_conditions", "invalid: device zone", label); next }
      balance <- mass_residual(z$zone, f)
      for (i in seq_len(nrow(z))) checks[[length(checks) + 1L]] <- data.frame(key, option = op, zone = z$zone[i], mass_residual_kg_s = balance[i], balanced = abs(balance[i]) <= cfg$rtol)
      for (component in zone_components(z$zone, f)) {
        zz <- z[match(component, z$zone), , drop = FALSE]; n <- nrow(zz)
        T <- w <- RH <- rep(NA_real_, n)
        if (any(abs(balance[component]) > cfg$rtol)) {
          skip_output(log, 1, "zone_conditions", "invalid: mass imbalance", paste(label, paste(component, collapse = "+")))
        } else {
          matrix_flow <- matrix(0, n, n); outflow <- numeric(n)
          for (i in seq_len(n)) {
            incoming <- f[f$to == zz$zone[i], , drop = FALSE]
            matrix_flow[i, i] <- -sum(incoming$mass_kg_s)
            outflow[i] <- sum(incoming$mass_kg_s[incoming$from == "OUTSIDE"])
            for (j in seq_len(nrow(incoming))) {
              k <- match(incoming$from[j], zz$zone)
              if (!is.na(k)) matrix_flow[i, k] <- matrix_flow[i, k] + incoming$mass_kg_s[j]
            }
          }
          for (quantity in c("T", "w")) {
            zfields <- if (cfg$heat_model == "mixing_only") character() else if (quantity == "T") c("area_m2", "h", "Tsurf", "sensible_W") else "moisture_kg_s"
            wfields <- if (quantity == "T") "T" else c("T", "RH", "pressure", "w")
            okz <- complete_for(zz, zfields, "zones", log, 1, paste0("zone_", quantity), label)
            okw <- complete_for(obs, wfields, "weather_occ", log, 1, paste0("zone_", quantity), label)
            if (!okz || !okw) next
            if (nrow(unique(obs[wfields])) != 1L) { skip_output(log, 1, paste0("zone_", quantity), "invalid: inconsistent outdoor boundary", label); next }
            A <- matrix_flow; b <- outflow * obs[[quantity]][1]
            if (quantity == "T") {
              # cp = 1006 J/(kg dry air K), the dry-air term in the ASHRAE enthalpy model.
              A <- A * 1006; b <- b * 1006
              if (cfg$heat_model == "full") {
                diag(A) <- diag(A) - zz$h * zz$area_m2
                b <- b + zz$h * zz$area_m2 * zz$Tsurf + zz$sensible_W
              }
            } else if (cfg$heat_model == "full") b <- b + zz$moisture_kg_s
            usable <- TRUE
            for (di in seq_len(nrow(dd))) {
              d <- dd[di, ]; i <- match(d$zone, zz$zone)
              if (is.na(i) || d$type == "A") next
              if (is.null(supplies[[di]])) { usable <- FALSE; next }
              mass <- d$m_dot * if (quantity == "T") 1006 else 1
              A[i, i] <- A[i, i] - mass; b[i] <- b[i] + mass * supplies[[di]][quantity]
            }
            if (!usable) { skip_output(log, 1, paste0("zone_", quantity), "evaporative_supply unavailable (see its missing inputs)", label); next }
            solution <- attempt(as.vector(solve(A, -b, tol = cfg$rtol)), log, 1, paste0("zone_", quantity), label)
            if (length(solution) == n && all(is.finite(solution))) {
              if (quantity == "T") T <- solution else w <- solution
            }
          }
        }
        for (i in seq_len(n)) {
          oo <- obs[which(obs$zone == zz$zone[i]), , drop = FALSE]
          if (nrow(oo) != 1) {
            skip_output(log, 1, "zone_exposure", "weather_occ.zone (one record per zone/hour required)", label)
            oo <- obs[NA_integer_, , drop = FALSE]
          }
          v <- oo$v_local
          fans <- dd[which(dd$zone == zz$zone[i] & dd$type == "A"), , drop = FALSE]
          if (nrow(fans)) {
            if (nrow(fans) == 1) v <- fans$v_fan else v <- NA_real_
            if (anyNA(v)) skip_output(log, 2, "SET", "devices.v_fan (one defined local fan speed per zone)", label)
          }
          if (all(is.finite(c(T[i], w[i], oo$pressure)))) {
            RH[i] <- attempt(relative_humidity(T[i], w[i], oo$pressure), log, 1, "zone_RH", label)
            if (!is.na(RH[i]) && (RH[i] < 0 || RH[i] > 100 + cfg$rtol)) {
              skip_output(log, 1, "zone_RH/SET", "invalid: RH exceeds 100% or is negative", label)
              RH[i] <- NA_real_
            }
          }
          zone_rows[[length(zone_rows) + 1L]] <- data.frame(key, option = op, zone = zz$zone[i],
            T = T[i], w = w[i], RH = RH[i], pressure = oo$pressure, people = oo$people,
            v_local = v, Tr = if (cfg$radiant_model == "air_reference") T[i] else oo$Tr, dt_hours = 1)
        }
      }
    }
  }
  list(outdoor = outdoor,
    zones = bind_rows(zone_rows, data.frame(venue = character(), scenario = character(), hour = numeric(), option = character(), zone = character(), T = numeric(), w = numeric(), RH = numeric(), pressure = numeric(), people = numeric(), v_local = numeric(), Tr = numeric(), dt_hours = numeric())),
    resources = bind_rows(resource_rows, data.frame(venue = character(), scenario = character(), hour = numeric(), option = character(), kWh = numeric(), water_kg = numeric())),
    mass_balance = bind_rows(checks, data.frame(venue = character(), scenario = character(), hour = numeric(), option = character(), zone = character(), mass_residual_kg_s = numeric(), balanced = logical())))
}
