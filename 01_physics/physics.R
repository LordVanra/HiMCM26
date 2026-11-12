# physics.R
# Model 1 – Physical environment and thermodynamics
#
# Provides:
#   - Psychrometric helpers (saturation pressure, humidity ratio, wet-bulb,
#     relative humidity)
#   - Evaporative-cooler outlet state (evap_state)
#   - Multi-zone steady-state air temperature and humidity solver (run_physics)
#   - Input validation, skip-log infrastructure, and CSV loader
#   - Configuration builder (build_config) and input-column schema
#   - ggplot2 chart helpers shared by all gallery modules


# Shared chart palette — one fixed colour per cooling option so every plot is
# visually consistent across modules.
chart_palette <- c(NONE = "#A0AEC0", A = "#4299E1", B = "#48BB78", C = "#F56565")


# chart_theme()
# Returns a minimal ggplot2 theme with consistent typography and grid style
# used by every chart produced in the gallery.
chart_theme <- function() {
  ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(
    plot.title    = ggplot2::element_text(face = "bold", size = 17, margin = ggplot2::margin(b = 6)),
    plot.subtitle = ggplot2::element_text(color = "grey40", size = 10, margin = ggplot2::margin(b = 12)),
    plot.caption  = ggplot2::element_text(color = "grey40", hjust = 0, size = 9),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(color = "grey92"),
    strip.text       = ggplot2::element_text(face = "bold"),
    legend.position  = "bottom",
    legend.title     = ggplot2::element_blank(),
    plot.margin      = ggplot2::margin(16, 20, 16, 16))
}


# chart_data(d)
# Enriches a data frame with display-friendly venue labels, ordered option
# factor levels, and a combined site/scenario panel label for faceting.
chart_data <- function(d) {
  # Human-readable labels for the six analysis venues
  labels <- c(
    DAL_BUS  = "Dallas / bus",  DAL_RAIL = "Dallas / rail",
    BOS_BUS  = "Boston / bus",  BOS_RAIL = "Boston / rail",
    PHX_BUS  = "Phoenix / bus", PHX_RAIL = "Phoenix / rail"
  )

  # Translate venue codes to readable site names when the column is present
  if ("venue" %in% names(d)) {
    d$site <- ifelse(d$venue %in% names(labels), labels[d$venue], d$venue)
    d$site <- factor(d$site, levels = unique(c(unname(labels), d$site)))
  }

  # Order cooling options consistently (NONE, A, B, C) for all charts
  if ("option" %in% names(d))
    d$option <- factor(d$option, levels = names(chart_palette))

  # Build a combined panel label used for ggplot2 facet_wrap
  if (all(c("site", "scenario") %in% names(d))) {
    d$panel <- paste(d$site, d$scenario, sep = "\n")
    d$panel <- factor(d$panel, levels = unique(d$panel[order(d$site, d$scenario)]))
  }

  d
}


# chart_colors(fill)
# Returns a list of ggplot2 scale objects that apply the shared palette to
# the colour aesthetic, and optionally the fill aesthetic.
chart_colors <- function(fill = FALSE) {
  c(
    list(ggplot2::scale_color_manual(values = chart_palette, drop = FALSE)),
    if (fill) list(ggplot2::scale_fill_manual(values = chart_palette, drop = FALSE))
  )
}


# chart_caption()
# Standard footnote appended to every chart explaining key modelling caveats.
chart_caption <- function() {
  "Reference model; estimated ventilation and passenger airspeed. Scenario duration is explicit in the input tables."
}


# chart_add(book, id, model, title, plot, reason, data)
# Stores a chart entry (plot object + metadata) in the gallery environment
# so that save_chart_gallery() can render everything in one pass.
chart_add <- function(book, id, model, title, plot = NULL, reason = "", data = data.frame()) {
  book$items[[id]] <- list(
    id     = id,
    model  = model,
    title  = title,
    plot   = plot,
    reason = reason,
    data   = data
  )
  invisible(book)
}


# chart_metric(book, id, model, d, field, title, units, kind)
# Adds a bar or lollipop chart for a single numeric metric across options
# and venue/scenario panels.
chart_metric <- function(book, id, model, d, field, title, units, kind = "bar", subtitle = NULL) {
  d <- chart_data(d)
  d$value <- d[[field]]

  # If no finite values exist at all, record the chart as unavailable
  if (!any(is.finite(d$value))) {
    chart_add(book, id, model, title,
              reason = paste(field, "unavailable; see pipeline skipped outputs"))
    return(invisible(NULL))
  }

  g <- d[is.finite(d$value), , drop = FALSE]

  # Base aesthetic mapping shared by both chart kinds
  p <- ggplot2::ggplot(g, ggplot2::aes(x = option, y = value, fill = option, color = option))

  if (kind == "bar") {
    # Vertical bars with numeric labels above each column
    p <- p +
      ggplot2::geom_col(width = .58, alpha = .85) +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", value)),
                         vjust = -.55, color = "#2D3748", size = 3.2)
  } else {
    # Lollipop: vertical segment from zero to value, with a dot at the tip
    p <- p +
      ggplot2::geom_segment(ggplot2::aes(xend = option, y = 0, yend = value), linewidth = 1.2) +
      ggplot2::geom_point(size = 3)
  }

  p <- p +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    chart_colors(fill = kind == "bar") +
    chart_theme() +
    ggplot2::scale_x_discrete(drop = FALSE) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(.08, .18))) +
    ggplot2::labs(title = title,
                  x = NULL, y = units, caption = chart_caption())

  chart_add(book, id, model, title, p, data = d)
}


# chart_heatmap(book, id, model, d, field, title, units)
# Adds a tile heatmap of a single metric with options on the x-axis and
# venue/scenario panels on the y-axis.  NA cells are shown explicitly.
chart_heatmap <- function(book, id, model, d, field, title, units) {
  d <- chart_data(d)
  d$value <- d[[field]]

  if (!any(is.finite(d$value))) {
    chart_add(book, id, model, title, reason = paste(field, "unavailable"))
    return(invisible(NULL))
  }

  # Format numeric labels; show "NA" for missing cells so readers are not misled
  d$label <- ifelse(is.finite(d$value), sprintf("%.2f", d$value), "NA")

  p <- ggplot2::ggplot(d, ggplot2::aes(option, panel, fill = value)) +
    ggplot2::geom_tile(color = "white", linewidth = 1.5) +
    ggplot2::geom_text(ggplot2::aes(label = label), size = 4) +
    ggplot2::scale_fill_gradient(low = "#EBF8FF", high = "#63B3ED",
                                 na.value = "#EDF2F7", name = units) +
    chart_theme() +
    ggplot2::labs(title = title,
                  x = NULL, y = NULL, caption = chart_caption()) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), legend.position = "right")

  chart_add(book, id, model, title, p, data = d)
}


# plot_physics_gallery(result, tables, book)
# Populates the gallery book with the nine Model-1 (physics) charts covering
# zone temperature, humidity, air movement, and resource consumption.
plot_physics_gallery <- function(result, tables, book) {
  z <- result$zone_conditions

  # Attach baseline (NONE option) temperature and humidity for delta calculations
  baseline <- z[z$option == "NONE", c("venue", "scenario", "hour", "zone", "T", "RH")]
  names(baseline)[5:6] <- c("baseline_T", "baseline_RH")
  z <- merge(z, baseline, by = c("venue", "scenario", "hour", "zone"), all.x = TRUE, sort = FALSE)

  # Derived columns for delta charts
  z$cooling      <- z$baseline_T - z$T          # temperature reduction vs. no device
  z$humidity_gain <- z$RH - z$baseline_RH       # RH increase from evaporative cooling
  z$w_g_kg       <- z$w * 1000                  # humidity ratio in g/kg for readability

  # --- Individual metric charts ---
  chart_metric(book, "P01", 1, z, "T",
               "Air temperature in the waiting area", "Air temperature (degC)")
  chart_heatmap(book, "P02", 1, z, "cooling",
                "How much does each device cool the air?", "degC reduction")
  chart_metric(book, "P03", 1, z, "RH",
               "Relative humidity after cooling", "Relative humidity (%)")
  chart_metric(book, "P04", 1, z, "humidity_gain",
               "Humidity added by evaporative cooling", "Change in RH (percentage points)", "lollipop")
  chart_metric(book, "P05", 1, z, "w_g_kg",
               "Moisture carried by the air", "Humidity ratio (g water / kg dry air)")
  chart_metric(book, "P06", 1, z, "v_local",
               "Air movement at the passenger", "Local airspeed (m/s)")

  # Scatter: temperature vs. relative humidity coloured by option
  d <- chart_data(z)
  d <- d[is.finite(d$T) & is.finite(d$RH), ]
  p <- ggplot2::ggplot(d, ggplot2::aes(T, RH, color = option)) +
    ggplot2::geom_point(size = 4) +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    chart_colors() + chart_theme() +
    ggplot2::labs(
      title   = "The temperature-humidity trade-off",
      x = "Air temperature (degC)", y = "Relative humidity (%)", caption = chart_caption())
  chart_add(book, "P07", 1, "The temperature-humidity trade-off", p, data = d)

  # Resource charts: water evaporated and electricity consumed
  chart_metric(book, "P08", 1, result$hourly_resources, "water_kg",
               "Evaporated water required", "Evaporated water (kg / modeled interval)")
  chart_metric(book, "P09", 1, result$hourly_resources, "kWh",
               "Electricity used during the modeled interval", "Energy (kWh)")

  invisible(book)
}


# Configuration and input schema

# build_config()
# Returns the default analysis configuration list.  Every field can be
# overridden by the caller before passing the config to run_physics /
# run_comfort / run_decision / run_sensitivity / run_monte_carlo.
build_config <- function() {
  list(
    solver        = "steady",    # Only "steady" (mass-balanced) is implemented
    rtol          = 1e-8,        # Residual tolerance for mass balance and root-finding
    tie_tol       = 1e-6,        # Tolerance for declaring two options equally good
    seed          = 1L,          # RNG seed for reproducible Monte Carlo draws
    mc_n          = 1000L,       # Number of Monte Carlo draws
    sweep_levels  = 5L,          # Points per parameter in the sensitivity sweep
    set_upper     = NA_real_,    # Upper SET comfort threshold (°C); NA disables loss/regret
    set_lower     = NA_real_,    # Lower SET comfort threshold (°C); NA disables coverage
    budget        = NA_real_,    # Maximum allowed decision cost; NA means no cap
    kwh_cap       = NA_real_,    # Maximum kWh per scenario; NA means no cap
    water_cap     = NA_real_,    # Maximum water (kg) per scenario; NA means no cap
    heat_model    = "mixing_only",   # "mixing_only" or "full" (adds surface/internal loads)
    radiant_model = "air_reference", # "air_reference" or "measured" (uses Tr column)
    comfort_basis = "per_person",    # "per_person" or "occupied" (scales by occupancy)
    cost_basis    = "purchase",      # "purchase" or "annual" (annualised life-cycle cost)
    cooler_limit  = "fixed"          # "fixed", "saturation_limit", or "effectiveness"
  )
}


# input_columns()
# Returns a named list giving the expected column names for each input table.
# Used by empty_input(), load_tables(), and require_model_data() to validate
# that all required fields are present before running the pipeline.
input_columns <- function() {
  list(
    zones      = c("venue", "zone", "volume_m3", "area_m2", "h", "Tsurf",
                   "sensible_W", "moisture_kg_s", "source"),
    exchanges  = c("venue", "from", "to", "mass_kg_s", "source"),
    weather_occ = c("venue", "scenario", "hour", "dt_hours", "zone", "T", "RH",
                    "pressure", "people", "v_local", "Tr", "annual_weight", "source"),
    devices    = c("venue", "option", "type", "zone", "power_kW", "v_fan",
                   "v_occupied", "m_dot", "airflow_m3_s", "dT_max",
                   "T_ref", "RH_ref", "pressure_ref",
                   "capital", "maintenance", "life_years", "discount_rate",
                   "electricity_price", "water_price", "source"),
    groups     = c("clo", "met", "wme", "height", "weight", "area_m2",
                   "posture", "ltime", "tu", "csw", "cdil", "cstr", "source"),
    bounds     = c("parameter", "lower", "upper", "source")
  )
}


# Input validation helpers

# require_model_data(cfg, tables, through, bounds_required)
# Checks that every field needed to run up to pipeline stage `through` is
# present and non-missing.  Stops with a detailed diagnostic message listing
# all missing fields so the user can fix them in one go.
#
# through = 1L  physics only
# through = 2L  physics + comfort
# through = 3L  physics + comfort + decision (default)
require_model_data <- function(cfg, tables, through = 3L, bounds_required = FALSE) {
  missing <- character()

  # Inner helper: adds descriptive entries to `missing` for every bad cell
  need <- function(name, fields, rows = NULL) {
    d <- tables[[name]]
    if (is.null(d) || !nrow(d)) {
      missing <<- c(missing, paste0(name, ": no rows"))
      return(invisible(NULL))
    }
    if (is.null(rows)) rows <- seq_len(nrow(d))

    for (field in fields) {
      # A cell is bad if the column is absent, NA, non-finite (numeric), or blank (character)
      bad <- if (!field %in% names(d)) rows else rows[
        is.na(d[[field]][rows]) |
          (if (is.numeric(d[[field]]))
            !is.finite(d[[field]][rows])
           else
            !nzchar(trimws(as.character(d[[field]][rows]))))
      ]

      for (i in bad) {
        # Include key-column values in the message to help locate the row
        keys    <- intersect(c("venue", "scenario", "zone", "option"), names(d))
        context <- paste(as.character(unlist(d[i, keys, drop = FALSE])), collapse = "/")
        missing <<- c(missing, sprintf("%s.%s [row %d%s]",
                                       name, field, i,
                                       if (nzchar(context)) paste0("; ", context) else ""))
      }
    }
  }

  # --- Stage 1: Physics inputs ---
  need("zones",      c("venue", "zone",
                        if (cfg$heat_model == "full") c("area_m2", "h", "Tsurf", "sensible_W", "moisture_kg_s")))
  need("exchanges",  c("venue", "from", "to", "mass_kg_s"))
  need("weather_occ", c("venue", "scenario", "hour", "zone", "T", "RH", "pressure", "dt_hours"))
  need("devices",    c("venue", "option", "type", "zone", "power_kW"))

  dd <- tables$devices
  ww <- tables$weather_occ
  zz <- tables$zones

  if (!is.null(dd) && nrow(dd)) {
    cool <- which(dd$type %in% c("B", "C"))

    # Evaporative coolers need a maximum cooling drop
    need("devices", "dT_max", cool)

    # At least one of m_dot or airflow_m3_s must be provided for each B/C device
    mass <- if ("m_dot"        %in% names(dd)) dd$m_dot        else rep(NA_real_, nrow(dd))
    flow <- if ("airflow_m3_s" %in% names(dd)) dd$airflow_m3_s else rep(NA_real_, nrow(dd))
    for (i in cool[!is.finite(mass[cool]) & !is.finite(flow[cool])])
      missing <- c(missing, sprintf("devices.m_dot OR devices.airflow_m3_s [row %d; %s/%s]",
                                    i, dd$venue[i], dd$option[i]))

    # Effectiveness model requires reference-condition calibration columns
    if (cfg$cooler_limit == "effectiveness")
      need("devices", c("T_ref", "RH_ref", "pressure_ref"), cool)

    occupied_speed <- if ("v_occupied" %in% names(dd)) dd$v_occupied else rep(NA_real_, nrow(dd))

    # Stage 2: fan airspeed needed for fan-only devices (unless v_occupied is given)
    if (through >= 2L)
      need("devices", "v_fan", which(dd$type == "A" & !is.finite(occupied_speed)))

    # Stage 3: cost inputs
    if (through >= 3L) {
      need("devices", "capital")
      if (cfg$cost_basis == "annual") {
        need("devices", c("maintenance", "life_years", "discount_rate", "electricity_price"))
        need("devices", "water_price", cool)
        need("weather_occ", "annual_weight")
      }
    }
  }

  # --- Stage 2: Comfort inputs ---
  if (through >= 2L) {
    need("groups", setdiff(input_columns()$groups, "source"))
    need("weather_occ", c("v_local",
                           if (cfg$radiant_model == "measured")  "Tr",
                           if (cfg$comfort_basis == "occupied")   "people"))
  }

  # Cross-table consistency: every zone must appear in weather_occ for each scenario/hour
  if (!is.null(ww) && nrow(ww) && !is.null(zz) && nrow(zz)) {
    cases <- unique(ww[c("venue", "scenario", "hour")])
    for (i in seq_len(nrow(cases))) {
      k        <- cases[i, ]
      expected <- zz$zone[which(zz$venue == k$venue)]
      actual   <- ww$zone[which(ww$venue == k$venue &
                                  ww$scenario == k$scenario &
                                  ww$hour     == k$hour)]

      for (zone in setdiff(expected, actual))
        missing <- c(missing, paste("weather_occ: missing zone", zone,
                                    "for", paste(k, collapse = "/")))
      if (!length(expected))
        missing <- c(missing, paste("zones: no zones for", k$venue))
      if (!any(tables$exchanges$venue %in% k$venue))
        missing <- c(missing, paste("exchanges: no rows for", k$venue))

      # Every standard cooling option must be represented in devices
      for (op in c("A", "B", "C"))
        if (!any(dd$venue %in% k$venue & dd$option %in% op))
          missing <- c(missing, paste("devices: missing option", op, "for", k$venue))
    }
  }

  if (bounds_required)
    need("bounds", c("parameter", "lower", "upper"))

  # Fail fast with a complete list of all problems found
  if (length(missing))
    stop(paste(c("Analysis not started: required data are missing:",
                 paste0("- ", unique(missing))), collapse = "\n"), call. = FALSE)

  invisible(TRUE)
}


# empty_input(name)
# Creates a zero-row data frame with the correct column types for the named
# input table.  Used as a safe placeholder when a CSV is absent.
empty_input <- function(name) {
  chars <- c("venue", "zone", "from", "to", "scenario", "option",
             "type", "posture", "parameter", "source")
  as.data.frame(setNames(
    lapply(input_columns()[[name]], function(k)
      if (k %in% chars) character() else numeric()),
    input_columns()[[name]]
  ))
}


# load_tables(root)
# Reads all input CSV files from `root`, returning a named list matching
# input_columns().  Missing files become empty-typed data frames so the
# pipeline can report a tidy "no rows" error rather than crashing on NULL.
load_tables <- function(root = ".") {
  setNames(lapply(names(input_columns()), function(n) {
    path <- file.path(root, paste0(n, ".csv"))
    if (!file.exists(path)) return(empty_input(n))

    d <- read.csv(path, na.strings = c("", "NA"), stringsAsFactors = FALSE,
                  check.names = FALSE, strip.white = TRUE)

    # Add any schema columns not present in the file (e.g. optional columns)
    for (k in setdiff(input_columns()[[n]], names(d)))
      d[[k]] <- rep(NA, nrow(d))

    d
  }), names(input_columns()))
}


# Skip-log infrastructure
# The skip log collects non-fatal data-quality issues encountered during the
# pipeline run so they can be reported as a tidy table rather than stopping
# execution.  Each skipped output is tagged with which model stage flagged it.

# skip_log()
# Creates a fresh, empty skip-log environment.
skip_log <- function() {
  e       <- new.env(parent = emptyenv())
  e$rows  <- list()
  e
}


# skip_output(log, model, output, inputs, context)
# Appends one entry to the skip log recording that `output` could not be
# computed because `inputs` were unavailable or invalid.
skip_output <- function(log, model, output, inputs, context = "all") {
  if (!length(inputs)) return(invisible(NULL))
  log$rows[[length(log$rows) + 1L]] <- data.frame(
    model   = model,
    output  = output,
    context = context,
    inputs  = paste(unique(inputs), collapse = ", "),
    stringsAsFactors = FALSE
  )
  invisible(NULL)
}


# skipped_table(log)
# Collapses the skip log into a deduplicated data frame suitable for
# including in the pipeline result list.
skipped_table <- function(log) {
  if (!length(log$rows))
    return(data.frame(model = character(), output = character(),
                      context = character(), inputs = character()))
  unique(do.call(rbind, log$rows))
}


# Field-completeness helpers

# missing_fields(d, fields, table)
# Returns a character vector of "table.field" strings for every field that is
# absent from d or contains at least one NA.
missing_fields <- function(d, fields, table) {
  bad <- fields[vapply(fields, function(k)
    !k %in% names(d) || !nrow(d) || anyNA(d[[k]]), logical(1))]
  if (length(bad)) paste0(table, ".", bad) else character()
}


# complete_for(d, fields, table, log, model, output, context)
# Checks whether all `fields` in data frame `d` are present and complete.
# Records any deficiency in the skip log and returns TRUE/FALSE.
complete_for <- function(d, fields, table, log, model, output, context) {
  missing <- missing_fields(d, fields, table)
  skip_output(log, model, output, missing, context)
  !length(missing)
}


# attempt(expr, log, model, output, context)
# Evaluates `expr` and returns the result.  If an error is thrown, logs it
# as a skip entry and returns NA_real_ so the pipeline can continue.
attempt <- function(expr, log, model, output, context) {
  tryCatch(expr, error = function(e) {
    skip_output(log, model, output,
                paste0("invalid: ", conditionMessage(e)), context)
    NA_real_
  })
}


# bind_rows(rows, prototype)
# Safely rbinds a list of data frames.  Returns `prototype` (an empty typed
# data frame) when `rows` is empty, ensuring consistent column types.
bind_rows <- function(rows, prototype) {
  if (!length(rows)) prototype else do.call(rbind, rows)
}


# Psychrometric functions
# All temperature arguments are in °C; pressure in Pa; humidity ratio in
# kg water / kg dry air.

# sat_pressure(T)
# Saturation vapour pressure (Pa) at dry-bulb temperature T (°C).
# Uses the ASHRAE Handbook of Fundamentals (2017) correlation:
#   - Ice-point branch for T ≤ 0.01 °C
#   - Liquid-water branch for T > 0.01 °C
sat_pressure <- function(T) {
  stopifnot(length(T) == 1L, is.finite(T), T >= -100, T <= 200)
  K <- T + 273.15  # Convert to Kelvin

  if (T <= 0.01) {
    # Ice-surface correlation (ASHRAE eq. 5)
    exp(-5674.5359/K + 6.3925247 - 0.009677843*K +
          0.00000062215701*K^2 + 2.0747825e-9*K^3 - 9.484024e-13*K^4 + 4.1635019*log(K))
  } else {
    # Liquid-water correlation (ASHRAE eq. 6)
    exp(-5800.2206/K + 1.3914993 - 0.048640239*K +
          0.000041764768*K^2 - 1.4452093e-8*K^3 + 6.5459673*log(K))
  }
}


# humidity_ratio(T, RH, pressure)
# Humidity ratio w (kg water / kg dry air) from temperature T (°C),
# relative humidity RH (%), and total pressure (Pa).
humidity_ratio <- function(T, RH, pressure) {
  stopifnot(is.finite(RH), RH >= 0, RH <= 100, is.finite(pressure), pressure > 0)
  pv <- RH/100 * sat_pressure(T)   # Partial vapour pressure (Pa)
  stopifnot(pv < pressure)          # Guard against supersaturation
  0.621945 * pv / (pressure - pv)  # ASHRAE ratio of molecular weights
}


# relative_humidity(T, w, pressure)
# Relative humidity (%) from temperature T (°C), humidity ratio w, and
# total pressure (Pa).  Inverse of humidity_ratio().
relative_humidity <- function(T, w, pressure) {
  stopifnot(is.finite(w), w >= 0, is.finite(pressure), pressure > 0)
  100 * pressure * w / (0.621945 + w) / sat_pressure(T)
}


# wet_bulb(T, w, pressure, tol)
# Thermodynamic wet-bulb temperature (°C) found by root-solving the ASHRAE
# psychrometric equation.  Separate formulas apply above and below 0 °C.
wet_bulb <- function(T, w, pressure, tol = 1e-8) {
  stopifnot(w >= 0, relative_humidity(T, w, pressure) <= 100 + tol)

  # Residual: difference between target w and the value predicted by wet-bulb tw
  f <- function(tw) {
    ws <- humidity_ratio(tw, 100, pressure)   # Saturation humidity at wet-bulb
    if (tw >= 0)
      ((2501 - 2.326*tw)*ws - 1.006*(T - tw)) / (2501 + 1.86*T - 4.186*tw) - w
    else
      ((2830 - 0.24*tw)*ws  - 1.006*(T - tw)) / (2830 + 1.86*T - 2.1*tw)   - w
  }

  uniroot(f, c(-100, T), tol = tol)$root
}


# Evaporative cooler physics

# evap_state(device, weather, cfg)
# Computes the temperature T (°C), humidity ratio w, and water evaporated
# (kg) at the outlet of an evaporative cooler.
#
# Three cooler-limit modes are supported (cfg$cooler_limit):
#   "fixed"            – the cooler always delivers exactly dT_max of cooling
#   "effectiveness"    – cooling limited by the device's wet-bulb effectiveness
#                        relative to reference-condition calibration data
#   "saturation_limit" – when dT_max would supersaturate the supply air, the
#                        cooling is reduced to stay at 100 % RH
#
# Returns a named numeric vector: c(T, w, water_kg).
evap_state <- function(device, weather, cfg) {
  stopifnot(device$m_dot >= 0, device$dT_max >= 0)

  wo   <- humidity_ratio(weather$T, weather$RH, weather$pressure)
  drop <- device$dT_max   # Default cooling drop (°C); may be revised below

  # --- Effectiveness mode ---
  # Scale the rated dT_max by the ratio of local to rated wet-bulb depression
  if (cfg$cooler_limit == "effectiveness") {
    wr         <- humidity_ratio(device$T_ref, device$RH_ref, device$pressure_ref)
    depression <- device$T_ref - wet_bulb(device$T_ref, wr, device$pressure_ref, cfg$rtol)
    stopifnot(depression > 0)

    eps  <- device$dT_max / depression   # Saturation effectiveness (dimensionless)
    stopifnot(eps >= 0, eps <= 1)

    drop <- min(device$dT_max,
                eps * (weather$T - wet_bulb(weather$T, wo, weather$pressure, cfg$rtol)))
  }

  # dT_max describes the outlet in this device model, not the mixed waiting-area air.
  Ts   <- weather$T - drop
  hout <- 1.006*weather$T + wo*(2501 + 1.86*weather$T)   # Specific enthalpy (kJ/kg) at inlet
  ws   <- (hout - 1.006*Ts) / (2501 + 1.86*Ts)           # Outlet humidity ratio (const-enthalpy)
  stopifnot(ws >= wo - cfg$rtol)

  # --- Saturation-limit mode ---
  # If the constant-enthalpy process crosses 100 % RH, find the saturation
  # boundary temperature by root-solving and clamp the outlet there.
  if (relative_humidity(Ts, ws, weather$pressure) > 100 + cfg$rtol) {
    if (cfg$cooler_limit != "saturation_limit")
      stop("fixed outlet reduction requires supersaturation under the direct-evaporation moisture model")

    # This explicitly selected alternative reduces cooling at the saturation boundary.
    residual <- function(t) {
      w <- (hout - 1.006*t) / (2501 + 1.86*t)
      relative_humidity(t, w, weather$pressure) - 100
    }
    Ts <- min(weather$T,
              uniroot(residual, c(Ts, weather$T), tol = cfg$rtol/100)$root + cfg$rtol)
    ws <- if (Ts == weather$T) wo else (hout - 1.006*Ts) / (2501 + 1.86*Ts)
  }

  # Water evaporated over the full scenario duration (kg)
  c(T = Ts, w = ws, water_kg = device$m_dot * (ws - wo) * 3600 * weather$dt_hours)
}


# Zone network helpers

# mass_residual(zones, exchanges)
# Returns the net mass flow imbalance (kg/s) for each zone.
# A balanced zone network has all residuals within cfg$rtol of zero.
mass_residual <- function(zones, exchanges) {
  vapply(zones, function(z)
    sum(exchanges$mass_kg_s[exchanges$to   == z]) -
      sum(exchanges$mass_kg_s[exchanges$from == z]),
    numeric(1))
}


# zone_components(zones, flows)
# Partitions the zone network into connected components using the exchange
# flows as undirected edges.  Returns a list of character vectors, each
# holding the names of zones that belong to the same connected component.
# This is used so the linear solver handles each isolated sub-network
# independently.
zone_components <- function(zones, flows) {
  remaining <- zones
  out       <- list()

  while (length(remaining)) {
    component <- remaining[1]

    # Grow the component until no new linked zones are found
    repeat {
      linked <- unique(c(
        component,
        flows$to[flows$from   %in% component],
        flows$from[flows$to   %in% component]
      ))
      linked <- intersect(linked, zones)
      if (setequal(component, linked)) break
      component <- linked
    }

    out[[length(out) + 1L]] <- component
    remaining <- setdiff(remaining, component)
  }

  out
}


# Physics pipeline entry point

# run_physics(cfg, tables, log)
# Solves the steady-state zone temperature and humidity for every combination
# of (venue, scenario, hour, option) in the input tables.
#
# Algorithm summary:
#   1. Compute outdoor psychrometrics (w, Twb) from weather_occ inputs.
#   2. For each scenario/hour and each cooling option:
#      a. Validate mass balance of the exchange network.
#      b. Compute evaporative-cooler outlet states (evap_state) for B/C devices.
#      c. Solve the linear mass-balance system for zone T and w, treating
#         evaporative supply as a modified boundary condition.
#      d. Derive zone RH and assign local airspeed (v_local).
#   3. Collect per-interval resource totals (kWh, water_kg).
#
# Returns a list:
#   outdoor      – psychrometric state of outdoor air
#   zones        – zone-level T, w, RH, v_local, etc. for each option
#   resources    – per-interval energy and water totals
#   mass_balance – residual and balance flag for each zone/option
run_physics <- function(cfg, tables, log = skip_log()) {
  require_model_data(cfg, tables, through = 1L)

  # ---- Step 1: Outdoor psychrometrics ----------------------------------------
  outdoor <- tables$weather_occ
  complete_for(outdoor, c("T", "RH", "pressure"), "weather_occ", log, 1, "outdoor", "input table")

  outdoor$w   <- outdoor$Twb <- rep(NA_real_, nrow(outdoor))

  for (i in seq_len(nrow(outdoor))) {
    a       <- outdoor[i, , drop = FALSE]
    context <- paste(a$venue, a$scenario, a$hour, sep = "/")

    if (complete_for(a, c("T", "RH", "pressure"), "weather_occ", log, 1, "outdoor", context)) {
      outdoor$w[i] <- attempt(humidity_ratio(a$T, a$RH, a$pressure),
                              log, 1, "outdoor.w", context)
      if (!is.na(outdoor$w[i]))
        outdoor$Twb[i] <- attempt(wet_bulb(a$T, outdoor$w[i], a$pressure, cfg$rtol),
                                  log, 1, "outdoor.Twb", context)
    }
  }

  # ---- Step 2: Structural checks (zone & exchange tables) --------------------
  zone_fields <- c("venue", "zone",
                   if (cfg$heat_model == "full")
                     c("area_m2", "h", "Tsurf", "sensible_W", "moisture_kg_s"))

  complete_for(tables$zones,     zone_fields,                       "zones",       log, 1, "zone_conditions",         "input table")
  complete_for(tables$exchanges, c("venue", "from", "to", "mass_kg_s"), "exchanges",   log, 1, "zone_conditions",         "input table")
  complete_for(outdoor,          c("venue", "scenario", "hour", "zone"), "weather_occ", log, 1, "zone_conditions/energy/water", "input table")
  complete_for(tables$devices,   c("venue", "option", "type", "zone"),   "devices",     log, 1, "device_assignment",       "input table")

  # Warn early if evaporative devices are entirely missing flow data
  evaporative <- tables$devices[which(tables$devices$type %in% c("B", "C")), , drop = FALSE]
  if (nrow(evaporative) &&
      all(is.na(evaporative$m_dot)) &&
      (!"airflow_m3_s" %in% names(evaporative) || all(is.na(evaporative$airflow_m3_s))))
    skip_output(log, 1, "evaporative_supply/water", "devices.m_dot or devices.airflow_m3_s", "B/C inputs")

  # Fan devices without an explicit v_occupied need v_fan for SET computation
  fans <- tables$devices[which(tables$devices$type == "A"), , drop = FALSE]
  if ("v_occupied" %in% names(fans))
    fans <- fans[!is.finite(fans$v_occupied), , drop = FALSE]
  if (nrow(fans))
    complete_for(fans, "v_fan", "devices", log, 2, "fan SET", "A inputs")

  # ---- Step 3: Scenario × option loop ----------------------------------------
  cases <- unique(outdoor[
    complete.cases(outdoor[c("venue", "scenario", "hour")]),
    c("venue", "scenario", "hour"), drop = FALSE
  ])

  zone_rows <- resource_rows <- checks <- list()

  for (ci in seq_len(nrow(cases))) {
    key     <- cases[ci, ]
    context <- paste(key, collapse = "/")

    # Subset tables to this venue/scenario/hour
    obs <- outdoor[which(outdoor$venue    == key$venue &
                           outdoor$scenario == key$scenario &
                           outdoor$hour     == key$hour), , drop = FALSE]
    z   <- tables$zones[which(tables$zones$venue       == key$venue), , drop = FALSE]
    f   <- tables$exchanges[which(tables$exchanges$venue == key$venue), , drop = FALSE]
    dev <- tables$devices[which(tables$devices$venue    == key$venue), , drop = FALSE]

    options  <- unique(c("NONE", "A", "B", "C", dev$option[!is.na(dev$option)]))
    duration <- unique(obs$dt_hours)

    # Scenario duration must be unique and positive
    if (length(duration) != 1L || !is.finite(duration) || duration <= 0)
      stop(paste("Invalid or inconsistent weather_occ.dt_hours:", context), call. = FALSE)

    # Structural validity flags reused across the option loop
    flow_ok <- complete_for(f, c("from", "to", "mass_kg_s"), "exchanges", log, 1, "zone_conditions", context)
    zone_ok <- complete_for(z, "zone",                        "zones",     log, 1, "zone_conditions", context)

    if (zone_ok && anyDuplicated(z$zone)) {
      skip_output(log, 1, "zone_conditions", "invalid: require distinct zone names", context)
      zone_ok <- FALSE
    }

    if (zone_ok && flow_ok) {
      # Exchanges must reference valid zone names and have non-negative flows
      flow_ok <- all(c(f$from, f$to) %in% c(z$zone, "OUTSIDE")) && all(f$mass_kg_s >= 0)
      if (!flow_ok)
        skip_output(log, 1, "zone_conditions", "invalid: exchange endpoint or negative flow", context)
    }

    # --- Per-option computation ---
    for (op in options) {
      dd    <- dev[which(dev$option == op), , drop = FALSE]
      label <- paste(context, op, sep = "/")

      # NONE baseline has zero power and water by definition
      power <- if (op == "NONE") 0 else NA_real_
      water <- if (op == "NONE") 0 else NA_real_

      device_ok <- op == "NONE" ||
        complete_for(dd, c("type", "zone"), "devices", log, 1, "zone_conditions", label)

      # Electrical energy from rated power draw
      if (op != "NONE" && complete_for(dd, "power_kW", "devices", log, 1, "energy", label)) {
        if (all(dd$power_kW >= 0))
          power <- sum(dd$power_kW)
        else
          skip_output(log, 1, "energy", "invalid: negative power_kW", label)
      }

      # --- Evaporative supply state for each B/C device ----------------------
      supplies    <- vector("list", nrow(dd))
      water_each  <- rep(NA_real_, nrow(dd))

      if (device_ok && op != "NONE") {
        for (di in seq_len(nrow(dd))) {
          d  <- dd[di, ]
          dc <- paste(label, d$zone, sep = "/")

          if (d$type == "A") { water_each[di] <- 0; next }
          if (!d$type %in% c("B", "C")) {
            skip_output(log, 1, "zone_conditions/water", "invalid: device type", dc)
            next
          }

          # Convert volumetric airflow to mass flow using ASHRAE moist-air specific volume
          # (287.042 * T_K * (1 + 1.607858*w) / p)  per kg dry air
          if (is.na(d$m_dot) &&
              "airflow_m3_s" %in% names(d) && !is.na(d$airflow_m3_s) &&
              all(is.finite(c(obs$T[1], obs$pressure[1], obs$w[1])))) {
            # ASHRAE moist-air specific volume per kg dry air; not a guessed density.
            specific_volume <- 287.042 * (obs$T[1] + 273.15) *
              (1 + 1.607858 * obs$w[1]) / obs$pressure[1]
            d$m_dot     <- d$airflow_m3_s / specific_volume
            dd$m_dot[di] <- d$m_dot
          }

          okd <- complete_for(d,   c("m_dot", "dT_max"),          "devices",     log, 1, "evaporative_supply/water", dc)
          okw <- complete_for(obs, c("T", "RH", "pressure"),       "weather_occ", log, 1, "evaporative_supply/water", dc)

          if (okd && okw) {
            # All zones in this scenario must share the same outdoor conditions
            same <- nrow(unique(obs[c("T", "RH", "pressure")])) == 1
            if (!same) {
              skip_output(log, 1, "evaporative_supply/water",
                          "invalid: outdoor weather differs across zones", dc)
              next
            }
            val <- attempt(evap_state(d, obs[1, ], cfg), log, 1, "evaporative_supply/water", dc)
            if (length(val) == 3 && !anyNA(val)) {
              supplies[[di]]  <- val
              water_each[di] <- val["water_kg"]
            }
          }
        }
      }

      # Aggregate water consumption across all devices in this option
      if (op != "NONE" && nrow(dd) && !anyNA(water_each))
        water <- sum(water_each)

      # Record energy and water totals for this scenario/option interval
      resource_rows[[length(resource_rows) + 1L]] <- data.frame(
        key, option = op, dt_hours = duration,
        kWh = power * duration, water_kg = water
      )

      # Skip zone solving if any structural prerequisite failed
      if (!zone_ok || !flow_ok || !device_ok) next
      if (nrow(dd) && any(!dd$zone %in% z$zone)) {
        skip_output(log, 1, "zone_conditions", "invalid: device zone", label)
        next
      }

      # --- Mass-balance check -------------------------------------------------
      balance <- mass_residual(z$zone, f)
      for (i in seq_len(nrow(z)))
        checks[[length(checks) + 1L]] <- data.frame(
          key, option = op, zone = z$zone[i],
          mass_residual_kg_s = balance[i],
          balanced = abs(balance[i]) <= cfg$rtol
        )

      # --- Linear zone solver (temperature and humidity) ----------------------
      for (component in zone_components(z$zone, f)) {
        zz <- z[match(component, z$zone), , drop = FALSE]
        n  <- nrow(zz)
        T  <- w <- RH <- rep(NA_real_, n)

        if (any(abs(balance[component]) > cfg$rtol)) {
          skip_output(log, 1, "zone_conditions", "invalid: mass imbalance",
                      paste(label, paste(component, collapse = "+")))
        } else {
          # Build the zone-to-zone mass-flow matrix and outdoor-inflow vector
          matrix_flow <- matrix(0, n, n)
          outflow     <- numeric(n)

          for (i in seq_len(n)) {
            incoming         <- f[f$to == zz$zone[i], , drop = FALSE]
            matrix_flow[i, i] <- -sum(incoming$mass_kg_s)
            outflow[i]        <- sum(incoming$mass_kg_s[incoming$from == "OUTSIDE"])

            for (j in seq_len(nrow(incoming))) {
              k <- match(incoming$from[j], zz$zone)
              if (!is.na(k))
                matrix_flow[i, k] <- matrix_flow[i, k] + incoming$mass_kg_s[j]
            }
          }

          # Solve for temperature (T) then humidity ratio (w) using the same
          # matrix structure but different RHS terms
          for (quantity in c("T", "w")) {
            zfields <- if (cfg$heat_model == "mixing_only") character() else
              if (quantity == "T") c("area_m2", "h", "Tsurf", "sensible_W") else "moisture_kg_s"
            wfields <- if (quantity == "T") "T" else c("T", "RH", "pressure", "w")

            okz <- complete_for(zz,  zfields, "zones",       log, 1, paste0("zone_", quantity), label)
            okw <- complete_for(obs, wfields, "weather_occ", log, 1, paste0("zone_", quantity), label)
            if (!okz || !okw) next

            if (nrow(unique(obs[wfields])) != 1L) {
              skip_output(log, 1, paste0("zone_", quantity),
                          "invalid: inconsistent outdoor boundary", label)
              next
            }

            A <- matrix_flow
            b <- outflow * obs[[quantity]][1]

            if (quantity == "T") {
              # cp = 1006 J/(kg dry air K), the dry-air term in the ASHRAE enthalpy model.
              A <- A * 1006
              b <- b * 1006
              if (cfg$heat_model == "full") {
                # Add surface convection heat transfer: h * A_surf * (T_surf - T_zone)
                diag(A) <- diag(A) - zz$h * zz$area_m2
                b       <- b + zz$h * zz$area_m2 * zz$Tsurf + zz$sensible_W
              }
            } else if (cfg$heat_model == "full") {
              # Add moisture source term for humidity equation
              b <- b + zz$moisture_kg_s
            }

            # Inject evaporative cooler supply as an additional zone source/sink
            usable <- TRUE
            for (di in seq_len(nrow(dd))) {
              d <- dd[di, ]
              i <- match(d$zone, zz$zone)
              if (is.na(i) || d$type == "A") next
              if (is.null(supplies[[di]])) { usable <- FALSE; next }
              mass    <- d$m_dot * if (quantity == "T") 1006 else 1
              A[i, i] <- A[i, i] - mass
              b[i]    <- b[i]    + mass * supplies[[di]][quantity]
            }

            if (!usable) {
              skip_output(log, 1, paste0("zone_", quantity),
                          "evaporative_supply unavailable (see its missing inputs)", label)
              next
            }

            solution <- attempt(as.vector(solve(A, -b, tol = cfg$rtol)),
                                log, 1, paste0("zone_", quantity), label)
            if (length(solution) == n && all(is.finite(solution))) {
              if (quantity == "T") T <- solution else w <- solution
            }
          }
        }

        # --- Zone exposure: airspeed and RH for each zone in the component ----
        for (i in seq_len(n)) {
          oo <- obs[which(obs$zone == zz$zone[i]), , drop = FALSE]
          if (nrow(oo) != 1) {
            skip_output(log, 1, "zone_exposure",
                        "weather_occ.zone (one record per zone/hour required)", label)
            oo <- obs[NA_integer_, , drop = FALSE]
          }

          # Default airspeed: use the weather_occ baseline
          v <- oo$v_local

          # Fan devices override the zone airspeed
          fans <- dd[which(dd$zone == zz$zone[i] & dd$type == "A"), , drop = FALSE]
          if (nrow(fans))
            v <- if (nrow(fans) == 1) fans$v_fan else NA_real_

          # v_occupied (device-level exposure field) takes precedence over v_fan
          exposure <- dd[which(dd$zone == zz$zone[i]), , drop = FALSE]
          if ("v_occupied" %in% names(exposure) && nrow(exposure) &&
              any(is.finite(exposure$v_occupied))) {
            speeds <- unique(exposure$v_occupied[is.finite(exposure$v_occupied)])
            v      <- if (length(speeds) == 1L) speeds else NA_real_
          }

          if (anyNA(v))
            skip_output(log, 2, "SET",
                        "one defined passenger airspeed per zone (v_occupied, v_fan or v_local)", label)

          # Derive zone RH from solved T and w; flag physically impossible values
          if (all(is.finite(c(T[i], w[i], oo$pressure)))) {
            RH[i] <- attempt(relative_humidity(T[i], w[i], oo$pressure),
                             log, 1, "zone_RH", label)
            if (!is.na(RH[i]) && (RH[i] < 0 || RH[i] > 100 + cfg$rtol)) {
              skip_output(log, 1, "zone_RH/SET", "invalid: RH exceeds 100% or is negative", label)
              RH[i] <- NA_real_
            }
          }

          # Assemble one result row per zone
          zone_rows[[length(zone_rows) + 1L]] <- data.frame(
            key,
            option   = op,
            zone     = zz$zone[i],
            T        = T[i],
            w        = w[i],
            RH       = RH[i],
            pressure = oo$pressure,
            people   = oo$people,
            v_local  = v,
            Tr       = if (cfg$radiant_model == "air_reference") oo$T else oo$Tr,
            dt_hours = duration
          )
        }
      }
    }
  }

  # ---- Return collated results -----------------------------------------------
  list(
    outdoor = outdoor,
    zones = bind_rows(zone_rows, data.frame(
      venue = character(), scenario = character(), hour = numeric(),
      option = character(), zone = character(),
      T = numeric(), w = numeric(), RH = numeric(),
      pressure = numeric(), people = numeric(),
      v_local = numeric(), Tr = numeric(), dt_hours = numeric()
    )),
    resources = bind_rows(resource_rows, data.frame(
      venue = character(), scenario = character(), hour = numeric(),
      option = character(), dt_hours = numeric(),
      kWh = numeric(), water_kg = numeric()
    )),
    mass_balance = bind_rows(checks, data.frame(
      venue = character(), scenario = character(), hour = numeric(),
      option = character(), zone = character(),
      mass_residual_kg_s = numeric(), balanced = logical()
    ))
  )
}
