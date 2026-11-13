# sensitivity.R
# Model 4 – Parameter sensitivity sweep and Monte Carlo analysis
#
# Provides:
#   - numeric_parameters()   – discovers every finite numeric input value
#   - parameter_value()      – reads one parameter from cfg or a table cell
#   - linked_parameter_rows()– finds rows that must move together (e.g.
#                              symmetric exchange flows)
#   - set_parameter()        – applies a single parameter change to cfg/tables
#   - usable_bounds()        – filters the bounds table to sweep-ready entries
#   - run_sensitivity()      – deterministic sweep across parameter ranges
#   - run_monte_carlo()      – uniform-random Monte Carlo draws
#   - break_even_plot()      – base-R PNG of efficiency/discomfort vs. input
#   - save_sensitivity()     – writes CSVs and the break-even PNG
#   - save_monte_carlo()     – writes Monte Carlo CSVs
#   - chart_parameter_label()– human-readable parameter name for charts
#   - plot_sensitivity_gallery() – ggplot2 gallery of sensitivity charts
#   - save_chart_gallery()   – renders and saves all gallery charts as PNG/SVG


# Parameter discovery and manipulation

# numeric_parameters(cfg, tables)
# Returns a character vector of every finite numeric parameter in the form
# "table.row.field" (for table cells) or "cfg.name" (for config scalars).
# Used to seed the bounds table when every_numeric = TRUE in usable_bounds().
numeric_parameters <- function(cfg, tables) {
  parameters <- character()

  # Scan all table cells (excluding the "hour" index column)
  for (name in setdiff(names(tables), "bounds")) {
    for (field in names(tables[[name]])) {
      if (field == "hour") next
      x <- tables[[name]][[field]]
      if (is.numeric(x))
        for (row in which(is.finite(x)))
          parameters <- c(parameters, paste(name, row, field, sep = "."))
    }
  }

  # Scan relevant config scalars (thresholds and caps only)
  for (name in c("set_upper", "set_lower", "budget", "kwh_cap", "water_cap"))
    if (is.numeric(cfg[[name]]) && !is.na(cfg[[name]]))
      parameters <- c(parameters, paste0("cfg.", name))

  parameters
}


# parameter_value(parameter, cfg, tables)
# Retrieves the current value of a parameter string of the form:
#   "cfg.<name>"           – a config scalar
#   "<table>.<row>.<field>"– a single table cell
# Returns NA_real_ if the parameter string is malformed or out of range.
parameter_value <- function(parameter, cfg, tables) {
  parts <- strsplit(parameter, ".", fixed = TRUE)[[1]]

  # Config scalar
  if (length(parts) == 2 && parts[1] == "cfg")
    return(cfg[[parts[2]]])

  # Table cell
  if (length(parts) == 3 &&
      parts[1] %in% names(tables) &&
      parts[3] %in% names(tables[[parts[1]]])) {
    row <- suppressWarnings(as.integer(parts[2]))
    if (!is.na(row) && row >= 1 && row <= nrow(tables[[parts[1]]]))
      return(tables[[parts[1]]][[parts[3]]][row])
  }

  NA_real_
}


# linked_parameter_rows(parameter, tables)
# Returns the row indices that must be perturbed together when `parameter`
# is changed.  Two cases are handled:
#
#   weather_occ.T / RH / pressure / dt_hours / annual_weight:
#     All rows that share the same (venue, scenario) — and "hour" too unless
#     the field is annual_weight, which is scenario-level.
#
#   exchanges.mass_kg_s:
#     Symmetric inflow/outflow pairs (zone ↔ OUTSIDE) must have equal flows
#     to maintain mass balance, so both rows move together.
#
# Returns just the original row for all other parameters.
linked_parameter_rows <- function(parameter, tables) {
  parts <- strsplit(parameter, ".", fixed = TRUE)[[1]]
  if (length(parts) != 3L) return(integer())

  row <- as.integer(parts[2])
  d   <- tables[[parts[1]]]

  # Weather observations: group by scenario (and hour unless it's annual_weight)
  if (parts[1] == "weather_occ" &&
      parts[3] %in% c("T", "RH", "pressure", "dt_hours", "annual_weight")) {
    key <- c("venue", "scenario", if (parts[3] != "annual_weight") "hour")
    return(which(Reduce(`&`, lapply(key, function(k) d[[k]] == d[[k]][row]))))
  }

  # Exchange flows: pair inflow and outflow for symmetric zone ↔ OUTSIDE connections
  if (parts[1] == "exchanges" && parts[3] == "mass_kg_s") {
    pair <- which(d$venue == d$venue[row])
    if (length(pair) == 2L &&
        d$from[pair[1]] == d$to[pair[2]] &&
        d$to[pair[1]]   == d$from[pair[2]] &&
        "OUTSIDE" %in% d$from[pair])
      return(pair)
  }

  row
}


# set_parameter(parameter, value, cfg, tables)
# Returns a list(cfg, tables) with the named parameter set to `value`.
# Linked rows (see linked_parameter_rows) are updated simultaneously.
set_parameter <- function(parameter, value, cfg, tables) {
  parts <- strsplit(parameter, ".", fixed = TRUE)[[1]]

  if (parts[1] == "cfg") {
    cfg[[parts[2]]] <- value
  } else {
    rows <- linked_parameter_rows(parameter, tables)
    tables[[parts[1]]][[parts[3]]][rows] <- value
  }

  list(cfg = cfg, tables = tables)
}


# Bounds filtering

# usable_bounds(cfg, tables, log, every_numeric)
# Filters the bounds table to entries that are valid for use in a sweep:
#   - Parameter string resolves to a finite numeric value (or is a cfg policy)
#   - Lower and upper bounds are both finite and lower <= upper
#   - Linked rows must have identical bounds
#   - Duplicate linked-row entries are collapsed to one representative entry
#
# Returns a data frame with the same schema as tables$bounds.
usable_bounds <- function(cfg, tables, log, every_numeric = TRUE) {
  b          <- tables$bounds
  parameters <- if (every_numeric)
    unique(c(numeric_parameters(cfg, tables), b$parameter[!is.na(b$parameter)]))
  else
    unique(b$parameter[!is.na(b$parameter)])

  rows <- list()

  if (!length(parameters))
    skip_output(log, 4, "sensitivity/Monte Carlo", "bounds.parameter/lower/upper")

  for (parameter in parameters) {
    x <- b[which(b$parameter == parameter), , drop = FALSE]

    # Must have exactly one bounds row per parameter
    if (nrow(x) != 1L) {
      skip_output(log, 4, "sweep",
                  paste0("bounds.lower/upper for ", parameter), parameter)
      next
    }

    # Bounds must be non-NA
    if (anyNA(x[c("lower", "upper")])) {
      skip_output(log, 4, "sweep", missing_fields(x, c("lower", "upper"), "bounds"), parameter)
      next
    }

    value  <- parameter_value(parameter, cfg, tables)
    policy <- parameter %in% paste0("cfg.", c("set_upper", "set_lower", "budget", "kwh_cap", "water_cap"))

    # Non-policy parameters must currently have a finite numeric baseline value
    if (!policy && (length(value) != 1 || !is.numeric(value) || !is.finite(value))) {
      skip_output(log, 4, "sweep",
                  paste0(parameter, " is NA or nonnumeric; bounds cannot fill missing data"),
                  parameter)
      next
    }

    # Bounds must be ordered correctly
    if (!all(is.finite(c(x$lower, x$upper))) || x$lower > x$upper) {
      skip_output(log, 4, "sweep", "invalid lower/upper bounds", parameter)
      next
    }

    # Only cfg threshold/cap scalars are allowed as cfg sweep parameters
    if (startsWith(parameter, "cfg.") &&
        !sub("cfg.", "", parameter, fixed = TRUE) %in%
        c("set_upper", "set_lower", "budget", "kwh_cap", "water_cap")) {
      skip_output(log, 4, "sweep", "only cfg thresholds/caps are sweep parameters", parameter)
      next
    }

    rows[[length(rows) + 1L]] <- x
  }

  result <- bind_rows(rows, empty_input("bounds"))

  # Repeated records of one boundary condition must be perturbed together.
  # Remove duplicate linked-row entries, keeping only the first representative.
  drop <- integer()
  for (i in seq_len(nrow(result))) {
    parts  <- strsplit(result$parameter[i], ".", fixed = TRUE)[[1]]
    if (length(parts) != 3) next

    linked <- linked_parameter_rows(result$parameter[i], tables)
    other  <- match(paste(parts[1], setdiff(linked, as.integer(parts[2])), parts[3], sep = "."),
                    result$parameter)
    other  <- other[!is.na(other) & other > i]
    if (!length(other)) next

    # Linked entries must agree on bounds; otherwise both are dropped
    if (any(result$lower[i] != result$lower[other] | result$upper[i] != result$upper[other])) {
      skip_output(log, 4, "sweep", "linked boundary-condition bounds disagree", result$parameter[i])
      drop <- c(drop, i, other)
    } else {
      drop <- c(drop, other)
    }
  }

  if (length(drop))
    result <- result[-unique(drop), , drop = FALSE]

  result
}


# Sensitivity sweep helpers

# choice_for(result, venue)
# Extracts the minimax-chosen option string for a given venue from a
# run_all result.  Returns NA if no recommendation is available, or
# "no feasible option" if the status indicates infeasibility.
choice_for <- function(result, venue) {
  r    <- result$recommendations[result$recommendations$venue == venue, , drop = FALSE]
  if (!nrow(r)) return(NA_character_)

  good <- r$option[r$chosen %in% TRUE]
  if (length(good))
    paste(sort(good), collapse = ";")
  else if (any(grepl("no .*feasible option", r$status)))
    "no feasible option"
  else
    NA_character_
}


# Sensitivity sweep (deterministic)

# run_sensitivity(cfg, tables, quiet)
# Sweeps each bounded parameter from lower to upper across sweep_levels
# evenly-spaced values, running the full pipeline at each point.
#
# Returns a list:
#   detail    – one row per (parameter, value, venue, scenario, option)
#   switching – intervals where the chosen option changes
#   skipped   – skip-log entries
run_sensitivity <- function(cfg, tables, quiet = FALSE) {
  require_model_data(cfg, tables, bounds_required = TRUE)

  log    <- skip_log()
  bounds <- usable_bounds(cfg, tables, log)
  base   <- run_all(cfg, tables, quiet = TRUE)   # Baseline for delta computation
  rows   <- list()

  for (i in seq_len(nrow(bounds))) {
    b <- bounds[i, ]

    # Sweep this parameter through sweep_levels evenly-spaced values
    for (value in seq(b$lower, b$upper, length.out = cfg$sweep_levels)) {
      changed <- set_parameter(b$parameter, value, cfg, tables)
      result  <- run_all(changed$cfg, changed$tables, quiet = TRUE)
      a       <- result$options

      # Log if the pipeline produced results but key metrics are all missing
      if (nrow(a) && (!any(is.finite(a$decision_eta)) ||
                       !any(is.finite(a$loss))         ||
                       all(is.na(result$recommendations$chosen))))
        skip_output(log, 4, "eta/L/chosen option", unique(result$skipped$inputs), b$parameter)

      if (!nrow(a)) {
        skip_output(log, 4, "sweep outcomes",
                    "Models 1-3 have no complete case keys; see run_all skipped summary",
                    b$parameter)
        next
      }

      # Build one output row per option, including deltas vs. baseline
      for (j in seq_len(nrow(a))) {
        old     <- base$options[which(base$options$venue    == a$venue[j]    &
                                        base$options$scenario == a$scenario[j] &
                                        base$options$option   == a$option[j]), , drop = FALSE]
        old_eta <- old_L <- NA_real_
        if (nrow(old) == 1) { old_eta <- old$decision_eta; old_L <- old$loss }

        rows[[length(rows) + 1L]] <- data.frame(
          parameter     = b$parameter,
          value         = value,
          venue         = a$venue[j],
          scenario      = a$scenario[j],
          option        = a$option[j],
          mean_SET      = a$mean_SET[j],
          mean_SET_drop = a$mean_SET_drop[j],
          kWh           = a$E[j],
          water_kg      = a$water_kg[j],
          purchase_cost = a$purchase_cost[j],
          eta           = a$decision_eta[j],
          L             = a$loss[j],
          comfort_basis = a$comfort_basis[j],
          delta_eta     = a$decision_eta[j] - old_eta,
          delta_L       = a$loss[j]         - old_L,
          chosen_option   = choice_for(result, a$venue[j]),
          baseline_choice = choice_for(base,   a$venue[j])
        )
      }
    }
  }

  detail <- bind_rows(rows, data.frame(
    parameter = character(), value = numeric(), venue = character(),
    scenario = character(), option = character(),
    mean_SET = numeric(), mean_SET_drop = numeric(),
    kWh = numeric(), water_kg = numeric(), purchase_cost = numeric(),
    eta = numeric(), L = numeric(), comfort_basis = character(),
    delta_eta = numeric(), delta_L = numeric(),
    chosen_option = character(), baseline_choice = character()
  ))

  # --- Switching intervals: adjacent sweep points where the chosen option changes
  switching <- list()
  for (key in unique(paste(detail$parameter, detail$venue))) {
    d <- unique(detail[paste(detail$parameter, detail$venue) == key,
                       c("parameter", "venue", "value", "chosen_option")])
    d <- d[order(d$value), , drop = FALSE]
    if (nrow(d) < 2) next

    for (i in seq_len(nrow(d) - 1L))
      if (!anyNA(d$chosen_option[c(i, i + 1L)]) &&
          d$chosen_option[i] != d$chosen_option[i + 1L])
        switching[[length(switching) + 1L]] <- data.frame(
          parameter    = d$parameter[i],
          venue        = d$venue[i],
          lower        = d$value[i],
          upper        = d$value[i + 1L],
          choice_below = d$chosen_option[i],
          choice_above = d$chosen_option[i + 1L]
        )
  }

  result <- list(
    detail = detail,
    switching = bind_rows(switching, data.frame(
      parameter = character(), venue = character(),
      lower = numeric(), upper = numeric(),
      choice_below = character(), choice_above = character()
    )),
    skipped = skipped_table(log)
  )

  if (!quiet)
    cat("Sensitivity: ", nrow(detail), " outcome rows; skipped: ",
        if (nrow(result$skipped))
          paste(unique(paste(result$skipped$context, result$skipped$inputs, sep = ": ")),
                collapse = " | ")
        else "none",
        "\n", sep = "")

  result
}


# Break-even plot (base-R)

# break_even_plot(d, path)
# Writes a two-panel base-R PNG showing efficiency (eta) and residual
# discomfort (L) as functions of a swept input parameter for the first
# venue/scenario/parameter combination found in `d`.
# Returns TRUE on success, FALSE if no plottable data exist.
break_even_plot <- function(d, path) {
  useful <- d[is.finite(d$value) & (is.finite(d$eta) | is.finite(d$L)), , drop = FALSE]
  if (!nrow(useful)) return(FALSE)

  # Focus on the first parameter/venue/scenario combination
  first <- useful[1, ]
  a     <- useful[useful$parameter == first$parameter &
                    useful$venue     == first$venue    &
                    useful$scenario  == first$scenario, , drop = FALSE]

  grDevices::png(path, width = 1400, height = 700, res = 120)
  on.exit(grDevices::dev.off())

  par(mfrow = c(1, 2), mar = c(6, 4, 4, 1))
  colors <- setNames(seq_along(unique(a$option)), unique(a$option))

  for (metric in c("eta", "L")) {
    good <- a[is.finite(a[[metric]]), , drop = FALSE]

    if (!nrow(good)) {
      plot.new()
      title(paste(metric, "unavailable"))
      next
    }

    plot(range(good$value), range(good[[metric]]), type = "n",
         xlab = first$parameter,
         ylab = if (metric == "eta")
           "Efficiency (see comfort_basis in CSV)"
         else
           "Residual discomfort (see comfort_basis in CSV)",
         main = paste(first$venue, first$scenario, sep = " / "))

    for (op in unique(good$option)) {
      x <- good[good$option == op, ]
      x <- x[order(x$value), ]
      lines(x$value, x[[metric]], type = "b", pch = 19, col = colors[op])
    }
    legend("topright", legend = names(colors), col = colors, lty = 1, bty = "n")
  }

  TRUE
}


# save_sensitivity(result, root)
# Writes sensitivity CSVs and the break-even PNG to the 04_sensitivity folder.
# Removes the PNG if no plottable data exist.
save_sensitivity <- function(result, root = ".") {
  for (name in names(result))
    write.csv(result[[name]],
              file.path(root, "04_sensitivity", paste0("result_sensitivity_", name, ".csv")),
              row.names = FALSE, na = "NA")

  if (!break_even_plot(result$detail, file.path(root, "04_sensitivity", "result_break_even.png"))) {
    path <- file.path(root, "04_sensitivity", "result_break_even.png")
    if (file.exists(path)) unlink(path)
    cat("Skipped: break-even plot [complete bounded sweep with eta or L]\n")
  }

  invisible(result)
}


# Monte Carlo simulation

# run_monte_carlo(cfg, tables, quiet)
# Draws cfg$mc_n uniform random samples from the bounds table (bounds-only;
# numeric_parameters are not auto-added) and runs the full pipeline for each
# draw.  Results are summarised as choice frequencies and outcome quantiles.
#
# Returns a list:
#   frequencies – choice probability per venue/option
#   quantiles   – 5th / 50th / 95th percentile of eta, loss, decision_cost
#   skipped     – skip-log entries
run_monte_carlo <- function(cfg, tables, quiet = FALSE) {
  require_model_data(cfg, tables, bounds_required = TRUE)

  log    <- skip_log()
  bounds <- usable_bounds(cfg, tables, log, every_numeric = FALSE)
  rows   <- choices <- list()

  if (nrow(bounds)) {
    set.seed(cfg$seed)   # Ensure reproducibility across identical cfg$seed values

    for (draw in seq_len(cfg$mc_n)) {
      # Apply all parameter draws simultaneously before running the pipeline
      changed <- list(cfg = cfg, tables = tables)
      for (i in seq_len(nrow(bounds))) {
        b       <- bounds[i, ]
        value   <- runif(1, b$lower, b$upper)
        changed <- set_parameter(b$parameter, value, changed$cfg, changed$tables)
      }

      r <- run_all(changed$cfg, changed$tables, quiet = TRUE)

      # Collect option-level results for quantile computation
      if (nrow(r$options)) {
        a       <- r$options
        a$draw  <- draw
        rows[[length(rows) + 1L]] <- a
      }

      # Record the chosen option for each venue in this draw
      for (venue in unique(r$options$venue))
        choices[[length(choices) + 1L]] <- data.frame(
          draw   = draw,
          venue  = venue,
          choice = choice_for(r, venue)
        )
    }
  }

  draws      <- bind_rows(rows, data.frame())
  selections <- bind_rows(choices, data.frame(draw = integer(), venue = character(), choice = character()))

  frequencies <- quantiles <- list()
  label <- "Conditional on independent uniform draws within supplied bounds; not confidence intervals"

  # --- Frequency table: how often was each option chosen? --------------------
  for (venue in unique(selections$venue)) {
    s     <- selections[selections$venue == venue, ]
    known <- !is.na(s$choice)

    for (choice in unique(c(s$choice[known], if (any(!known)) "unresolved"))) {
      count <- if (choice == "unresolved") sum(!known) else sum(s$choice[known] == choice)
      frequencies[[length(frequencies) + 1L]] <- data.frame(
        venue          = venue,
        choice         = choice,
        count          = count,
        draws          = cfg$mc_n,
        frequency      = count / cfg$mc_n,
        interpretation = label
      )
    }
  }

  # --- Quantile table: distribution of key metrics per option ----------------
  if (nrow(draws)) {
    for (key in unique(paste(draws$venue, draws$scenario, draws$option))) {
      d <- draws[paste(draws$venue, draws$scenario, draws$option) == key, ]

      for (metric in c("decision_eta", "loss", "decision_cost")) {
        complete <- nrow(d) == cfg$mc_n && all(is.finite(d[[metric]]))
        q        <- if (complete) quantile(d[[metric]], c(.05, .5, .95), names = FALSE) else rep(NA_real_, 3)

        if (!complete)
          skip_output(log, 4, "Monte Carlo quantiles",
                      paste(metric, "incomplete across draws"), key)

        quantiles[[length(quantiles) + 1L]] <- data.frame(
          venue          = d$venue[1],
          scenario       = d$scenario[1],
          option         = d$option[1],
          metric         = metric,
          probability    = c(.05, .5, .95),
          value          = q,
          complete_draws = sum(is.finite(d[[metric]])),
          interpretation = label
        )
      }
    }
  }

  if (!length(rows))
    skip_output(log, 4, "Monte Carlo", "no usable bounds or no complete scenario keys")

  result <- list(
    frequencies = bind_rows(frequencies, data.frame(
      venue = character(), choice = character(),
      count = integer(), draws = integer(),
      frequency = numeric(), interpretation = character()
    )),
    quantiles = bind_rows(quantiles, data.frame(
      venue = character(), scenario = character(), option = character(),
      metric = character(), probability = numeric(), value = numeric(),
      complete_draws = integer(), interpretation = character()
    )),
    skipped = skipped_table(log)
  )

  if (!quiet)
    cat("Monte Carlo: ", nrow(result$frequencies), " frequency rows; ", label,
        ". Skipped: ",
        if (nrow(result$skipped)) paste(unique(result$skipped$inputs), collapse = " | ") else "none",
        "\n", sep = "")

  result
}


# save_monte_carlo(result, root)
# Writes Monte Carlo frequency and quantile tables as CSVs.
save_monte_carlo <- function(result, root = ".") {
  for (name in names(result))
    write.csv(result[[name]],
              file.path(root, "04_sensitivity", paste0("result_monte_carlo_", name, ".csv")),
              row.names = FALSE, na = "NA")
  invisible(result)
}


# Sensitivity gallery (ggplot2)

# chart_parameter_label(parameter, tables)
# Converts a "table.row.field" parameter string into a human-readable label
# for axis annotations, optionally appending the device option letter and
# venue name.
chart_parameter_label <- function(parameter, tables) {
  # Mapping from column-name fragments to plain-English descriptions
  fields <- c(
    mass_kg_s = "Ventilation",     T         = "Outdoor temperature",
    RH        = "Outdoor humidity", pressure  = "Air pressure",
    v_local   = "Baseline airspeed", power_kW = "Device power",
    v_fan     = "Fan airspeed",    airflow_m3_s = "Cooler airflow",
    dT_max    = "Outlet cooling",  capital    = "Purchase price",
    clo       = "Clothing",        met        = "Activity",
    wme       = "External work",   height     = "Height",
    weight    = "Weight",          area_m2    = "Body area",
    ltime     = "Exposure time",   tu         = "Turbulence",
    csw       = "Sweating coefficient", cdil  = "Dilation coefficient",
    cstr      = "Constriction coefficient"
  )

  parts <- strsplit(parameter, ".", fixed = TRUE)[[1]]
  field <- tail(parts, 1)
  label <- if (field %in% names(fields)) unname(fields[field]) else field

  # Append device option letter for device-table parameters
  if (length(parts) == 3 && parts[1] == "devices")
    label <- paste(label, tables$devices$option[as.integer(parts[2])])

  # Append venue name when the table has a venue column
  if (length(parts) == 3 && "venue" %in% names(tables[[parts[1]]]))
    label <- paste0(label, " [", tables[[parts[1]]]$venue[as.integer(parts[2])], "]")

  label
}


# plot_sensitivity_gallery(sensitivity, result, cfg, tables, book)
# Builds the Model-4 ggplot2 chart set:
#   S01-S06  – ranked SET sensitivity bars per venue (top 8 inputs)
#   S07-S12  – SET response curves per venue (top 4 inputs)
#   S13-S16  – sensitivity heat-maps for SET, kWh, water, cost
#   S17-S18  – efficiency and discomfort response with possible crossings
#   S19 onward – paired ranking and response charts for additional venues
plot_sensitivity_gallery <- function(sensitivity, result, cfg, tables, book) {
  d <- chart_data(sensitivity$detail)

  if (!nrow(d)) {
    chart_add(book, "S01", 4, "Sensitivity", reason = "No supplied sensitivity results")
    return(invisible(book))
  }

  # Merge baseline SET for delta calculations
  baseline       <- result$options[, c("venue", "scenario", "option", "mean_SET")]
  names(baseline)[4] <- "base_SET"
  d              <- merge(d, baseline, by = c("venue", "scenario", "option"), all.x = TRUE, sort = FALSE)
  d$delta_SET    <- d$mean_SET - d$base_SET

  # Compute human-readable labels and percentage changes from baseline
  parameters     <- unique(d$parameter)
  values         <- setNames(vapply(parameters, parameter_value, numeric(1), cfg = cfg, tables = tables), parameters)
  labels         <- setNames(vapply(parameters, chart_parameter_label, character(1), tables = tables), parameters)
  d$input_change     <- ifelse(values[d$parameter] == 0, 0, 100 * (d$value / values[d$parameter] - 1))
  d$parameter_label  <- unname(labels[d$parameter])

  # --- Per-venue ranked bar and response-curve charts ------------------------
  venues <- unique(d$venue[order(d$site)])
  for (j in seq_along(venues)) {
    venue <- venues[j]
    ranking_id <- if (j <= 6L) j else 19L + 2L * (j - 7L)
    response_id <- if (j <= 6L) j + 6L else ranking_id + 1L
    s     <- d[d$venue == venue & is.finite(d$delta_SET), ]

    # Rank parameters by maximum absolute SET impact across any option
    ranks <- dplyr::summarise(dplyr::group_by(s, parameter),
                              impact = max(abs(delta_SET)), .groups = "drop")
    ranks <- ranks[order(-ranks$impact), ]
    ranks <- ranks[ranks$impact > 1e-8, ]
    if (!nrow(ranks)) next

    # S01-S06: horizontal range bars for top-8 parameters
    top  <- head(ranks$parameter, 8)
    x    <- s[s$parameter %in% top, ]
    span <- dplyr::summarise(dplyr::group_by(x, parameter, option),
                             lo = min(delta_SET), hi = max(delta_SET), .groups = "drop")
    span$label <- factor(labels[span$parameter], levels = rev(unname(labels[top])))

    p <- ggplot2::ggplot(span, ggplot2::aes(y = label, color = option)) +
      ggplot2::geom_vline(xintercept = 0, color = "grey45", linetype = 2) +
      ggplot2::geom_linerange(ggplot2::aes(xmin = lo, xmax = hi),
                              position = ggplot2::position_dodge(width = .65), linewidth = 1.8) +
      chart_colors() + chart_theme() +
      ggplot2::labs(
        title   = paste("What changes SET most?", as.character(s$site[1])),
        x = "Change from baseline SET (degC)", y = NULL,
        caption = "Unavailable states omitted; CSV retains all sweep values. Rank = largest absolute SET change across options.")
    chart_add(book, sprintf("S%02d", ranking_id), 4,
              paste("SET sensitivity ranking:", as.character(s$site[1])), p, data = span)

    # S07-S12: continuous response curves for top-4 parameters
    top <- head(ranks$parameter, 4)
    x   <- d[d$venue == venue & d$parameter %in% top, ]
    x$parameter_label <- factor(x$parameter_label, levels = unname(labels[top]))

    p <- ggplot2::ggplot(x, ggplot2::aes(input_change, delta_SET,
                                         color = option, group = interaction(option, scenario))) +
      ggplot2::geom_hline(yintercept = 0, color = "grey70", linetype = 2) +
      ggplot2::geom_line(linewidth = .9, na.rm = TRUE) +
      ggplot2::geom_point(size = 2, na.rm = TRUE) +
      ggplot2::facet_wrap(~parameter_label, ncol = 2, scales = "free_y") +
      chart_colors() + chart_theme() +
      ggplot2::scale_x_continuous(breaks = c(-5, -2.5, 0, 2.5, 5)) +
      ggplot2::labs(
        title   = paste("SET response curves:", as.character(s$site[1])),
        x = "Input change from baseline (%)", y = "Change from baseline SET (degC)",
        caption = chart_caption())
    chart_add(book, sprintf("S%02d", response_id), 4,
              paste("SET response curves:", as.character(s$site[1])), p, data = x)
  }

  # --- S13-S16: cross-venue/parameter sensitivity heat-maps ------------------
  for (metric in c("mean_SET", "kWh", "water_kg", "purchase_cost")) {
    x            <- d[is.finite(d[[metric]]), ]
    x$metric_value <- x[[metric]]

    # Swing = max - min across sweep values per parameter/site/option
    spans  <- dplyr::summarise(dplyr::group_by(x, parameter, parameter_label, site, option),
                               swing = max(metric_value) - min(metric_value), .groups = "drop")
    by_site <- dplyr::summarise(dplyr::group_by(spans, parameter, parameter_label, site),
                                swing = max(swing), .groups = "drop")
    ranks  <- dplyr::summarise(dplyr::group_by(by_site, parameter),
                               swing = max(swing), .groups = "drop")
    ranks  <- ranks[order(-ranks$swing), ]
    top    <- head(ranks$parameter[ranks$swing > 1e-8], 10)
    if (!length(top)) next

    x <- by_site[by_site$parameter %in% top, ]
    x$parameter_label <- factor(x$parameter_label, levels = rev(unname(labels[top])))

    titles <- c(mean_SET = "SET", kWh = "electricity use", water_kg = "evaporated water", purchase_cost = "purchase cost")
    units  <- c(mean_SET = "degC", kWh = "kWh", water_kg = "kg", purchase_cost = "USD")
    title  <- paste("Sensitivity map:", titles[metric])

    p <- ggplot2::ggplot(x, ggplot2::aes(site, parameter_label, fill = swing)) +
      ggplot2::geom_tile(color = "white", linewidth = .8) +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", swing)), size = 3) +
      ggplot2::scale_fill_gradient(low = "#EBF8FF", high = "#63B3ED", name = unname(units[metric])) +
      chart_theme() +
      ggplot2::labs(title = title,
                    x = NULL, y = NULL,
                    caption = "Uses available sweep states only. 0.00 can mean an effect smaller than rounding precision.") +
      ggplot2::theme(axis.text.x  = ggplot2::element_text(angle = 20, hjust = 1),
                     panel.grid   = ggplot2::element_blank(),
                     legend.position = "right")
    chart_add(book, paste0("S", match(metric, names(titles)) + 12), 4, title, p, data = x)
  }

  # --- S17-S18: efficiency and discomfort response with possible crossings ---
  for (metric in c("eta", "L")) {
    x   <- d[is.finite(d[[metric]]), ]
    id  <- if (metric == "eta") "S17" else "S18"
    title <- if (metric == "eta") "Efficiency response and crossings" else "Discomfort response and crossings"

    if (!nrow(x)) {
      chart_add(book, id, 4, title, reason = "cfg.set_upper unset; eta/L unavailable")
      next
    }

    # Focus on the first parameter/venue combination
    first <- x[1, ]
    x     <- x[x$venue == first$venue & x$parameter == first$parameter, ]

    p <- ggplot2::ggplot(x, ggplot2::aes(input_change, .data[[metric]], color = option)) +
      ggplot2::geom_line(ggplot2::aes(group = interaction(option, scenario)), linewidth = 1) +
      ggplot2::geom_point() +
      chart_colors() + chart_theme() +
      ggplot2::labs(title = title,
                    x = "Input change (%)", y = metric, caption = chart_caption())
    chart_add(book, id, 4, title, p, data = x)
  }

  invisible(book)
}


# Full chart gallery export

# save_chart_gallery(result, sensitivity, cfg, tables, root)
# Renders all gallery charts from the four model stages, writes PNG/SVG/CSV
# for each chart, and generates a self-contained HTML index page.
# Requires ggplot2, dplyr, and scales.
save_chart_gallery <- function(result, sensitivity, cfg, tables, root = ".") {
  if (!requireNamespace("ggplot2",  quietly = TRUE) ||
      !requireNamespace("dplyr",    quietly = TRUE) ||
      !requireNamespace("scales",   quietly = TRUE))
    stop("Chart export needs ggplot2, dplyr and scales.")

  book        <- new.env(parent = emptyenv())
  book$items  <- list()

  # Populate book from all four model galleries
  plot_physics_gallery(result, tables, book)
  plot_comfort_gallery(result, cfg, book)
  plot_decision_gallery(result, cfg, book)
  plot_sensitivity_gallery(sensitivity, result, cfg, tables, book)

  out <- file.path(root, "graphs")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  # HTML-escape helper for titles embedded in markup
  esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;",  x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }

  rows <- cards <- list()

  # --- Render each chart item ------------------------------------------------
  for (item in book$items) {
    folder   <- paste0("model_", item$model)
    dir.create(file.path(out, folder), showWarnings = FALSE)

    filename <- paste0(item$id, "_", gsub("[^a-z0-9]+", "_", tolower(item$title)))
    stem     <- file.path(out, folder, filename)
    link     <- paste(folder, filename, sep = "/")
    ready    <- !is.null(item$plot)

    if (ready) {
      ggplot2::ggsave(paste0(stem, ".png"), item$plot, width = 13.5, height = 8.2, dpi = 180, bg = "white")
      ggplot2::ggsave(paste0(stem, ".svg"), item$plot, device = grDevices::svg, width = 13.5, height = 8.2, bg = "white")
      write.csv(item$data, paste0(stem, ".csv"), row.names = FALSE, na = "NA")
    } else {
      # Remove stale files from a previous run when the chart is now pending
      for (ext in c("png", "svg", "csv"))
        if (file.exists(paste0(stem, ".", ext))) unlink(paste0(stem, ".", ext))
    }

    rows[[length(rows) + 1]] <- data.frame(
      id     = item$id,
      model  = item$model,
      title  = item$title,
      status = if (ready) "ready" else "pending",
      reason = item$reason,
      png    = if (ready) paste0(link, ".png") else ""
    )

    # Build the HTML card for this chart
    cards[[length(cards) + 1]] <- paste0(
      '<article data-model="', item$model, '"><h3>', item$id, ' &middot; ', esc(item$title), '</h3>',
      if (ready)
        paste0('<a href="', link, '.png"><img loading="lazy" src="', link, '.png" alt="', esc(item$title), '"></a>',
               '<p><a href="', link, '.png">PNG</a> &middot; ',
               '<a href="', link, '.svg">Editable SVG</a> &middot; ',
               '<a href="', link, '.csv">Chart data</a></p>')
      else
        paste0('<p class="pending">Pending: ', esc(item$reason), '</p>'),
      '</article>'
    )
  }

  index <- do.call(rbind, rows)
  write.csv(index, file.path(out, "chart_index.csv"), row.names = FALSE)

  # --- Write the self-contained HTML gallery page ----------------------------
  html <- paste0(
    '<!doctype html><html lang="en"><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<title>HiMCM chart gallery</title>',
    '<style>',
    'body{font:16px system-ui;background:#f7fafc;color:#2d3748;max-width:1500px;margin:32px auto;padding:0 24px}',
    'h1{margin-bottom:8px}header p{max-width:1000px;line-height:1.6}',
    'nav{position:sticky;top:0;background:#f7fafc;padding:14px 0;z-index:2}',
    'button{padding:9px 16px;border:1px solid #cbd5e0;border-radius:7px;margin:4px;cursor:pointer;background:white}',
    'button.active{background:#2b6cb0;color:white}',
    'main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,570px),1fr));gap:20px}',
    'article{background:white;padding:18px;border:1px solid #e2e8f0;border-radius:10px}',
    'article img{width:100%}h3{font-size:17px}a{color:#2b6cb0}',
    '.pending{color:#744210;line-height:1.6}article[hidden]{display:none}',
    '</style>',
    '<header><h1>HiMCM chart gallery</h1>',
    '<p>', sum(index$status == "ready"), ' graphs ready to review. ',
    'Use the chart IDs to tell me which to keep. ',
    'Click any chart to enlarge it; SVG files retain editable vector graphics.</p>',
    '<p>Current reference model: one summer-mean hour, estimated ventilation and airspeed, ',
    'T-shirt/shorts, per-person comparison. Comfort thresholds and the fixed-cooling humidity ',
    'conflict remain on hold. Missing results are not filled in. No Monte Carlo runs were added.</p>',
    '<p>D02 is a resource radar, not a regret result. D07 is the actual minimax radar and ',
    'remains pending until regret can be computed. Current venues each have one scenario.</p></header>',
    '<nav>',
    '<button class="active" onclick="filterCharts(0,this)">All</button>',
    '<button onclick="filterCharts(1,this)">1 Physics</button>',
    '<button onclick="filterCharts(2,this)">2 Comfort</button>',
    '<button onclick="filterCharts(3,this)">3 Decision / minimax</button>',
    '<button onclick="filterCharts(4,this)">4 Sensitivity</button>',
    '</nav><main>',
    paste(cards, collapse = "\n"),
    '</main>',
    '<script>',
    'function filterCharts(n,b){',
    'document.querySelectorAll("article").forEach(x=>x.hidden=n!==0&&Number(x.dataset.model)!==n);',
    'document.querySelectorAll("button").forEach(x=>x.classList.remove("active"));',
    'b.classList.add("active")}',
    '</script></html>'
  )

  writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
  print(as.data.frame(table(model = index$model, status = index$status)), row.names = FALSE)

  invisible(index)
}
