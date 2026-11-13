# decision.R
# Model 3 – Cost accounting, feasibility, and minimax-regret recommendation
#
# Takes the comfort summary produced by run_comfort and adds:
#   - Purchase and annual life-cycle costs
#   - Budget / energy / water cap feasibility flags
#   - Per-scenario regret scores (option loss minus scenario-best loss)
#   - A minimax-regret robust recommendation across all scenarios
#   - Benchmark comparisons (always-A, cheapest feasible, highest efficiency)
#   - Pareto plot and result-saving utilities


# annualized_capital(capital, life_years, discount_rate)
# Converts an upfront capital cost to an equivalent annual cost using the
# capital-recovery factor (uniform annual series).
#
# If discount_rate == 0 the formula collapses to straight-line: capital / life.
annualized_capital <- function(capital, life_years, discount_rate) {
  stopifnot(!anyNA(c(capital, life_years, discount_rate)),
            capital >= 0, life_years > 0, discount_rate >= 0)

  if (discount_rate == 0)
    capital / life_years
  else
    capital * discount_rate / (1 - (1 + discount_rate)^(-life_years))
}


# within_cap(value, cap)
# Returns TRUE if `value` is within `cap`, NA if `value` is NA, or TRUE if
# `cap` is NA (meaning no cap is configured).
within_cap <- function(value, cap) {
  if (is.na(cap)) TRUE else if (is.na(value)) NA else value <= cap
}


# Minimax-regret decision engine

# minimax_regret(a, cfg, log)
# Computes scenario regret for each option and identifies the robust choice
# that minimises the maximum regret across all scenarios (minimax criterion).
#
# `a` is a data frame with one row per (venue, scenario, option) containing
# at minimum: venue, scenario, option, loss, feasible, decision_cost, decision_eta.
#
# Returns a list:
#   options         – original `a` with an added column R (regret)
#   recommendations – one row per venue with the minimax-chosen option
#   switching       – per-scenario best option and contingency flags
#   benchmarks      – comparison picks (always-A / cheapest / highest-eta)
minimax_regret <- function(a, cfg, log = skip_log()) {
  # Allow callers that pass slightly different column names
  if (!"loss"          %in% names(a)) a$loss          <- a$L
  if (!"decision_cost" %in% names(a)) a$decision_cost <- a$annual_cost
  if (!"decision_eta"  %in% names(a)) a$decision_eta  <- a$eta

  a$R <- rep(NA_real_, nrow(a))
  chosen <- switching <- benchmarks <- list()

  for (venue in unique(a$venue)) {
    vi        <- which(a$venue == venue)
    v         <- a[vi, , drop = FALSE]
    scenarios <- unique(v$scenario)
    options   <- unique(v$option)

    # Flag if the matrix of (scenario × option) combinations is not complete
    incomplete <- nrow(v) != length(scenarios) * length(options) ||
      anyDuplicated(paste(v$scenario, v$option)) > 0

    # --- Per-scenario regret calculation ------------------------------------
    for (scenario in scenarios) {
      ix         <- which(v$scenario == scenario)
      s          <- v[ix, , drop = FALSE]
      good       <- which(s$feasible %in% TRUE)
      status     <- "evaluated"
      local_best <- NA_character_

      if (anyNA(s$feasible))          status <- "incomplete feasibility"
      else if (!length(good))         status <- "no feasible option"
      else if (anyNA(s$loss[good]))   status <- "incomplete loss"
      else {
        # Regret = this option's loss minus the best feasible loss in the scenario
        best          <- min(s$loss[good])
        v$R[ix[good]] <- s$loss[good] - best
        local_best    <- paste(s$option[good][s$loss[good] <= best + cfg$tie_tol], collapse = ";")
      }

      if (status != "evaluated")
        skip_output(log, 3, "regret/recommendation", status, paste(venue, scenario, sep = "/"))

      switching[[length(switching) + 1L]] <- data.frame(
        venue      = venue,
        scenario   = scenario,
        scenario_best  = local_best,
        robust_choice  = NA_character_,
        status         = status,
        contingency    = status == "no feasible option"
      )

      # --- Benchmark picks for this scenario ---------------------------------
      for (kind in c("always A", "cheapest feasible", "highest efficiency")) {
        pick <- integer()

        if (kind == "always A")
          pick <- which(s$option == "A")

        if (kind == "cheapest feasible" &&
            !anyNA(s$feasible) && length(good) && !anyNA(s$decision_cost[good]))
          pick <- good[s$decision_cost[good] <= min(s$decision_cost[good]) + cfg$tie_tol]

        active <- which(s$option != "NONE" & s$feasible %in% TRUE)
        if (kind == "highest efficiency" &&
            length(active) && all(is.finite(s$decision_eta[active])))
          pick <- active[s$decision_eta[active] >= max(s$decision_eta[active]) - cfg$tie_tol]

        if (!length(pick)) {
          skip_output(log, 3, kind,
                      if (kind == "highest efficiency")
                        "eta unavailable for compared options"
                      else
                        "feasible/decision cost unavailable",
                      paste(venue, scenario))
          benchmarks[[length(benchmarks) + 1L]] <- data.frame(
            venue = venue, scenario = scenario, benchmark = kind,
            option = NA_character_, L = NA_real_, annual_cost = NA_real_,
            eta = NA_real_, decision_cost = NA_real_, loss = NA_real_,
            decision_eta = NA_real_, feasible = NA
          )
        } else {
          for (j in pick)
            benchmarks[[length(benchmarks) + 1L]] <- data.frame(
              venue = venue, scenario = scenario, benchmark = kind,
              option = s$option[j], L = s$L[j], annual_cost = s$annual_cost[j],
              eta = s$eta[j], decision_cost = s$decision_cost[j],
              loss = s$loss[j], decision_eta = s$decision_eta[j],
              feasible = s$feasible[j]
            )
        }
      }
    }

    # Write regret back to the main data frame
    a$R[vi] <- v$R

    # --- Minimax-robust recommendation across all scenarios -----------------
    if (incomplete || anyNA(v$feasible)) {
      chosen[[length(chosen) + 1L]] <- data.frame(
        venue      = venue, option = NA_character_,
        max_regret = NA_real_, worst_L = NA_real_,
        chosen     = NA, status = "incomplete inputs"
      )
      next
    }

    # Robust options: feasible in every scenario
    robust <- options[vapply(options, function(op)
      all(v$feasible[v$option == op]), logical(1))]

    if (!length(robust)) {
      chosen[[length(chosen) + 1L]] <- data.frame(
        venue      = venue, option = NA_character_,
        max_regret = NA_real_, worst_L = NA_real_,
        chosen     = FALSE, status = "no robust feasible option; contingency needed"
      )
      next
    }

    if (anyNA(v$R[v$option %in% robust])) {
      chosen[[length(chosen) + 1L]] <- data.frame(
        venue      = venue, option = NA_character_,
        max_regret = NA_real_, worst_L = NA_real_,
        chosen     = NA, status = "incomplete loss"
      )
      next
    }

    # Compute max regret for each robust option, then pick the minimum
    result <- do.call(rbind, lapply(robust, function(op) {
      rows <- v[v$option == op, ]
      data.frame(
        venue      = venue, option = op,
        max_regret = max(rows$R), worst_L = max(rows$loss),
        chosen     = FALSE, status = "evaluated"
      )
    }))
    result$chosen <- result$max_regret <= min(result$max_regret) + cfg$tie_tol

    chosen[[length(chosen) + 1L]] <- result

    # Annotate each switching row for this venue with the robust choice
    for (j in seq_along(switching))
      if (switching[[j]]$venue == venue)
        switching[[j]]$robust_choice <- paste(result$option[result$chosen], collapse = ";")
  }

  list(
    options = a,
    recommendations = bind_rows(chosen, data.frame(
      venue = character(), option = character(),
      max_regret = numeric(), worst_L = numeric(),
      chosen = logical(), status = character()
    )),
    switching = bind_rows(switching, data.frame(
      venue = character(), scenario = character(),
      scenario_best = character(), robust_choice = character(),
      status = character(), contingency = logical()
    )),
    benchmarks = bind_rows(benchmarks, data.frame(
      venue = character(), scenario = character(), benchmark = character(),
      option = character(), L = numeric(), annual_cost = numeric(), eta = numeric(),
      decision_cost = numeric(), loss = numeric(), decision_eta = numeric(),
      feasible = logical()
    ))
  )
}


# run_decision(cfg, tables, comfort, log)
# Adds cost and feasibility columns to the comfort summary and runs the
# minimax-regret decision engine.
#
# Cost columns added:
#   purchase_cost    – sum of device capital costs
#   electricity_cost – energy cost for this scenario
#   annual_cost      – life-cycle annualised total (only when cost_basis="annual")
#   decision_cost    – whichever of purchase/annual is active
#
# Feasibility flags:
#   resource_feasible – within budget, kWh cap, and water cap
#   feasible          – physical_valid AND resource_feasible
run_decision <- function(cfg, tables, comfort, log = skip_log()) {
  require_model_data(cfg, tables, through = 3L)

  a <- comfort$summary

  # Initialise cost columns
  a$annual_cost    <- a$purchase_cost <- a$electricity_cost <- rep(NA_real_, nrow(a))

  # Safety assessment is out of scope for this model; mark explicitly
  a$safety_status   <- rep("unassessed", nrow(a))

  # Record which bases were used so results are self-documenting
  a$cost_basis    <- rep(cfg$cost_basis,    nrow(a))
  a$comfort_basis <- rep(cfg$comfort_basis, nrow(a))

  # decision columns routed from either per-person or aggregate metrics
  a$loss         <- if (cfg$comfort_basis == "per_person") a$L_per_person else a$L
  a$decision_eta <- if (cfg$comfort_basis == "per_person") a$eta_per_person else a$eta

  a$decision_cost      <- rep(NA_real_, nrow(a))
  a$feasible           <- rep(NA, nrow(a))
  a$resource_feasible  <- rep(NA, nrow(a))

  # Tracking text explaining why a cap/budget was or was not applied
  a$budget_status    <- rep(if (is.na(cfg$budget))    "disabled by configuration" else "applied", nrow(a))
  a$kwh_cap_status   <- rep(if (is.na(cfg$kwh_cap))   "disabled by configuration" else "applied", nrow(a))
  a$water_cap_status <- rep(if (is.na(cfg$water_cap)) "disabled by configuration" else "applied", nrow(a))

  # Warn once if annual-cost required fields are missing
  if (cfg$cost_basis == "annual") {
    complete_for(tables$devices,     c("capital", "maintenance", "life_years",
                                       "discount_rate", "electricity_price"),
                 "devices",     log, 3, "annual_cost", "active options")
    complete_for(tables$weather_occ, "annual_weight",
                 "weather_occ", log, 3, "annual_cost", "active options")
  }

  # ---- Per-option cost and feasibility computation --------------------------
  for (i in seq_len(nrow(a))) {
    row     <- a[i, ]
    context <- paste(row$venue, row$scenario, row$option, sep = "/")
    dd      <- tables$devices[which(tables$devices$venue  == row$venue &
                                      tables$devices$option == row$option), , drop = FALSE]

    if (row$option == "NONE") {
      # NONE baseline has zero cost by definition
      a$purchase_cost[i]    <- 0
      a$electricity_cost[i] <- 0

    } else {
      # Purchase cost: sum of device capital
      if (complete_for(dd, "capital", "devices", log, 3, "purchase_cost", context))
        a$purchase_cost[i] <- sum(dd$capital)

      # Electricity cost: energy × price (requires a unique price across devices)
      if (nrow(dd) && !anyNA(dd$electricity_price) &&
          length(unique(dd$electricity_price)) == 1)
        a$electricity_cost[i] <- unique(dd$electricity_price) * row$E
    }

    # Annual life-cycle cost
    if (row$option == "NONE") {
      a$annual_cost[i] <- 0

    } else if (cfg$cost_basis == "annual") {
      dd <- tables$devices[which(tables$devices$venue  == row$venue &
                                   tables$devices$option == row$option), , drop = FALSE]
      ww <- tables$weather_occ[which(tables$weather_occ$venue    == row$venue &
                                       tables$weather_occ$scenario == row$scenario), , drop = FALSE]

      okd <- complete_for(dd, c("capital", "maintenance", "life_years",
                                "discount_rate", "electricity_price"),
                          "devices",     log, 3, "annual_cost", context)
      okw <- complete_for(ww, "annual_weight", "weather_occ", log, 3, "annual_cost", context)

      if (okd && okw && !is.na(row$E)) {
        annual <- unique(ww$annual_weight)
        price  <- unique(dd$electricity_price)

        if (length(annual) != 1 || length(price) != 1 || annual < 0 || price < 0) {
          skip_output(log, 3, "annual_cost",
                      "invalid: inconsistent or negative annual_weight/electricity_price", context)
        } else {
          # Annualised capital + annual O&M + annual electricity cost
          capital         <- attempt(sum(mapply(annualized_capital,
                                               dd$capital, dd$life_years, dd$discount_rate)),
                                     log, 3, "annual_cost", context)
          a$annual_cost[i] <- capital + sum(dd$maintenance) + price * row$E * annual

          # Add annual water cost for evaporative devices if water_price is provided
          water_price <- unique(dd$water_price[dd$type %in% c("B", "C")])
          if (length(water_price)) {
            if (length(water_price) != 1 || anyNA(water_price) || water_price < 0) {
              a$annual_cost[i] <- NA_real_
              skip_output(log, 3, "annual_cost", "invalid: water_price", context)
            } else {
              a$annual_cost[i] <- a$annual_cost[i] + water_price * row$water_kg * annual
            }
          }
        }

      } else if (is.na(row$E)) {
        skip_output(log, 3, "annual_cost",
                    "energy unavailable (devices.power_kW/weather_occ.hour)", context)
      }
    }

    # Route the active cost basis to decision_cost used by minimax
    a$decision_cost[i] <- if (cfg$cost_basis == "purchase") a$purchase_cost[i] else a$annual_cost[i]

    # Feasibility: must be within all configured resource caps
    a$resource_feasible[i] <- all(c(
      within_cap(a$decision_cost[i], cfg$budget),
      within_cap(row$E,              cfg$kwh_cap),
      within_cap(row$water_kg,       cfg$water_cap)
    ))

    # Overall feasibility: physically valid AND within resource limits
    a$feasible[i] <- a$physical_valid[i] && a$resource_feasible[i]
  }

  # Readable status columns for diagnostics
  a$physical_status <- ifelse(a$physical_valid,
                              "valid model solution", "no valid model solution")
  a$decision_ready  <- a$physical_valid &
    is.finite(a$loss) & is.finite(a$decision_cost) & !is.na(a$resource_feasible)

  minimax_regret(a, cfg, log)
}


# Top-level pipeline runner

# run_all(cfg, tables, quiet)
# Runs the full three-stage pipeline (physics → comfort → decision) and
# returns a named list of all result tables.  Annotates outputs with a
# `model_basis` column describing the active configuration.
run_all <- function(cfg, tables, quiet = FALSE) {
  require_model_data(cfg, tables)

  log     <- skip_log()
  physics <- run_physics(cfg, tables, log)
  comfort <- run_comfort(cfg, tables, physics, log)
  decision <- run_decision(cfg, tables, comfort, log)

  # Attach the number of scenarios per venue so recommendations are interpretable
  decision$recommendations$scenario_count <- vapply(
    decision$recommendations$venue,
    function(v) length(unique(tables$weather_occ$scenario[tables$weather_occ$venue == v])),
    integer(1)
  )
  decision$recommendations$decision_scope <- ifelse(
    decision$recommendations$scenario_count > 1,
    "multiple supplied scenarios",
    "single scenario; not an uncertainty comparison"
  )

  # Augment the switching table with observed weather ranges and cap values
  sw <- decision$switching
  for (field in c("T_min", "T_max", "RH_min", "RH_max", "budget", "kwh_cap", "water_cap"))
    sw[[field]] <- rep(NA_real_, nrow(sw))

  for (i in seq_len(nrow(sw))) {
    obs <- tables$weather_occ[which(tables$weather_occ$venue    == sw$venue[i] &
                                      tables$weather_occ$scenario == sw$scenario[i]), , drop = FALSE]
    if (nrow(obs)) {
      sw$T_min[i]  <- min(obs$T);  sw$T_max[i]  <- max(obs$T)
      sw$RH_min[i] <- min(obs$RH); sw$RH_max[i] <- max(obs$RH)
    }
    sw$budget[i]    <- cfg$budget
    sw$kwh_cap[i]   <- cfg$kwh_cap
    sw$water_cap[i] <- cfg$water_cap
  }
  decision$switching <- sw

  # Assemble the unified result list
  result <- list(
    outdoor          = physics$outdoor,
    zone_conditions  = physics$zones,
    mass_balance     = physics$mass_balance,
    hourly_resources = physics$resources,
    comfort_detail   = comfort$detail,
    options          = decision$options,
    recommendations  = decision$recommendations,
    switching        = decision$switching,
    benchmarks       = decision$benchmarks,
    skipped          = skipped_table(log)
  )

  # Stamp every output table with a human-readable model-basis description
  basis <- paste(
    "heat:", cfg$heat_model,
    "; radiation:", cfg$radiant_model,
    "; comfort:", cfg$comfort_basis,
    "; costs:", cfg$cost_basis,
    "; evaporative limit:", cfg$cooler_limit,
    "; assigned reference person/equipment, not measured installation performance"
  )
  for (name in c("zone_conditions", "comfort_detail", "options",
                 "recommendations", "switching", "benchmarks"))
    result[[name]]$model_basis <- rep(basis, nrow(result[[name]]))

  # Print a brief summary table when not running silently
  if (!quiet) {
    print(data.frame(
      output = c("outdoor", "zone_conditions", "options", "recommendations"),
      rows   = vapply(result[c("outdoor", "zone_conditions", "options", "recommendations")],
                      nrow, integer(1))
    ), row.names = FALSE)

    if (nrow(result$skipped)) {
      grouped <- split(result$skipped$inputs, result$skipped$output)
      cat("Skipped: ",
          paste(vapply(names(grouped), function(k)
            paste0(k, " [", paste(unique(grouped[[k]]), collapse = "; "), "]"), ""),
            collapse = " | "),
          "\n", sep = "")
    } else {
      cat("Skipped: none\n")
    }
  }

  result
}


# Visualisation helpers

# pareto_plot(a, path)
# Writes a base-R PNG showing the cost vs. discomfort Pareto frontier for
# each venue/scenario panel.  Returns TRUE if the plot was written, FALSE if
# there were no finite data points to plot.
pareto_plot <- function(a, path) {
  # Normalise column names so callers can pass decision-stage or raw columns
  if ("decision_cost" %in% names(a)) a$annual_cost <- a$decision_cost
  if ("loss"          %in% names(a)) a$L           <- a$loss

  a <- a[is.finite(a$annual_cost) & is.finite(a$L), , drop = FALSE]
  if (!nrow(a)) return(FALSE)

  panels <- split(a, paste(a$venue, a$scenario))
  columns <- min(3L, length(panels))
  rows <- ceiling(length(panels)/columns)
  grDevices::png(path, width = 1500, height = max(800, 420*rows), res = 120)
  on.exit(grDevices::dev.off())

  par(mfrow = c(rows, columns), mar = c(5, 4, 3, 1))

  for (label in names(panels)) {
    d <- panels[[label]]

    # Mark Pareto-nondominated options (no other option strictly better on both axes)
    frontier <- vapply(seq_len(nrow(d)), function(i)
      !any(d$annual_cost <= d$annual_cost[i] & d$L <= d$L[i] &
             (d$annual_cost < d$annual_cost[i] | d$L < d$L[i])), logical(1))

    plot(d$annual_cost, d$L,
         pch = 19,
         col = ifelse(frontier, "#007C83", "#777777"),
         xlab = paste(if ("cost_basis" %in% names(d)) d$cost_basis[1] else "annual",
                      "cost (input currency)"),
         ylab = if ("comfort_basis" %in% names(d) && d$comfort_basis[1] == "per_person")
           "Residual discomfort (degC-h per reference person)"
         else
           "Residual discomfort (person-degC-h)",
         main = label)
    text(d$annual_cost, d$L, labels = d$option, pos = 3, cex = .8)

    # Draw the Pareto frontier line
    front <- d[frontier, ]
    front <- front[order(front$annual_cost), ]
    lines(front$annual_cost, front$L, col = "#007C83")
  }

  TRUE
}


# save_results(result, root)
# Writes all result tables as CSVs into the appropriate output sub-folders
# and generates the Pareto PNG.  If no plottable data exist the PNG is
# removed so stale files are not left from a previous run.
save_results <- function(result, root = ".") {
  folders <- c(
    outdoor          = "01_physics",
    zone_conditions  = "01_physics",
    mass_balance     = "01_physics",
    hourly_resources = "01_physics",
    comfort_detail   = "02_comfort",
    options          = "03_decision",
    recommendations  = "03_decision",
    switching        = "03_decision",
    benchmarks       = "03_decision",
    skipped          = "03_decision"
  )

  # Write each result table to its designated folder
  for (name in names(folders))
    write.csv(result[[name]],
              file.path(root, folders[[name]], paste0("result_", name, ".csv")),
              row.names = FALSE, na = "NA")

  # Pareto plot: remove stale file if no data are plottable
  plotted <- pareto_plot(result$options, file.path(root, "03_decision", "result_pareto.png"))
  if (!plotted) {
    path <- file.path(root, "03_decision", "result_pareto.png")
    if (file.exists(path)) unlink(path)
    cat("Skipped: Pareto plot [complete decision cost and discomfort loss]\n")
  }

  invisible(result)
}


# Decision gallery charts (ggplot2)

# chart_radar(book, id, d, fields, labels, title, subtitle)
# Builds a radar (spider) chart normalising each axis to its own maximum so
# different units can be compared visually.  Axes are scaled to [0, 1] where
# 0 is best (smallest) and 1 is the displayed maximum.
chart_radar <- function(book, id, d, fields, labels, title, subtitle = NULL) {
  d        <- chart_data(d)
  complete <- apply(d[, fields, drop = FALSE], 1, function(x) all(is.finite(x)))
  incomplete <- sum(!complete)
  d        <- d[complete, , drop = FALSE]

  if (!nrow(d)) {
    chart_add(book, id, 3, title,
              reason = "Complete regret/cost/resource profiles unavailable; comfort threshold remains unset.")
    return(invisible(NULL))
  }

  # One common maximum per axis across all displayed venues preserves cross-panel comparability.
  maxima <- vapply(fields, function(f) max(d[[f]]), numeric(1))

  # Pivot to long format with polar (x, y) coordinates
  long <- do.call(rbind, lapply(seq_along(fields), function(i) {
    x            <- d
    x$axis       <- i
    x$metric     <- labels[i]
    x$raw        <- d[[fields[i]]]
    x$scaled     <- if (maxima[i] == 0) 0 else x$raw / maxima[i]
    x$axis_maximum <- maxima[i]
    x
  }))

  n       <- length(fields)
  long$x  <- long$scaled * sin(2 * pi * (long$axis - 1) / n)
  long$y  <- long$scaled * cos(2 * pi * (long$axis - 1) / n)

  # Reference rings at 25 %, 50 %, 75 %, 100 % of maximum
  rings   <- expand.grid(axis = seq_len(n), ring = c(.25, .5, .75, 1))
  rings$x <- rings$ring * sin(2 * pi * (rings$axis - 1) / n)
  rings$y <- rings$ring * cos(2 * pi * (rings$axis - 1) / n)

  axes    <- data.frame(
    x     = sin(2 * pi * (seq_len(n) - 1) / n),
    y     = cos(2 * pi * (seq_len(n) - 1) / n),
    label = labels
  )

  p <- ggplot2::ggplot() +
    ggplot2::geom_polygon(data = rings, ggplot2::aes(x, y, group = ring),
                          fill = NA, color = "grey85") +
    ggplot2::geom_segment(data = axes,
                          ggplot2::aes(x = 0, y = 0, xend = x, yend = y), color = "grey85") +
    ggplot2::geom_polygon(data = long,
                          ggplot2::aes(x, y, group = option, color = option, fill = option),
                          alpha = .10, linewidth = .85) +
    ggplot2::geom_point(data = long,
                        ggplot2::aes(x, y, color = option), size = 1.8) +
    ggplot2::geom_text(data = axes,
                       ggplot2::aes(x * 1.22, y * 1.22, label = label), size = 3.1) +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    ggplot2::coord_equal(xlim = c(-1.55, 1.55), ylim = c(-1.4, 1.4)) +
    chart_colors(fill = TRUE) +
    ggplot2::theme_void(base_size = 12) +
    ggplot2::theme(
      legend.position  = "bottom",
      legend.title     = ggplot2::element_blank(),
      strip.text       = ggplot2::element_text(face = "bold"),
      plot.title       = ggplot2::element_text(face = "bold", size = 17),
      plot.subtitle    = ggplot2::element_text(size = 10, color = "grey40",
                                               margin = ggplot2::margin(b = 15)),
      plot.caption     = ggplot2::element_text(hjust = 0, size = 9),
      plot.margin      = ggplot2::margin(20, 20, 20, 20)
    ) +
    ggplot2::labs(
      title    = title,
      caption  = "Each axis is divided by its displayed maximum; smaller means lower. Rings: 0.25, 0.50, 0.75, 1.00. Area is not a score."
    )

  chart_add(book, id, 3, title, p, data = long)
}


# plot_decision_gallery(result, cfg, book)
# Populates the gallery book with the Model-3 decision charts: cost bars,
# resource radars, Pareto frontier, regret heatmap, and minimax radar.
plot_decision_gallery <- function(result, cfg, book) {
  a <- result$options

  # D01 – Cost of each option
  chart_metric(book, "D01", 3, a, "decision_cost",
               "Cost of each cooling option", "Purchase cost (USD)")

  # D02 – Resource radar (not a regret result — just cost, electricity, water)
  chart_radar(book, "D02", a,
              c("decision_cost", "E", "water_kg"),
              c("Purchase\ncost", "Electricity", "Water"),
              "Decision-input radar: cost, electricity and water")

  # D03 – Cost vs. felt-temperature reduction scatter
  d <- chart_data(a)
  d <- d[is.finite(d$mean_SET_drop), ]
  p <- ggplot2::ggplot(d, ggplot2::aes(decision_cost, mean_SET_drop, color = option)) +
    ggplot2::geom_point(size = 3.5) +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    chart_colors() + chart_theme() +
    ggplot2::scale_x_continuous(labels = scales::label_dollar()) +
    ggplot2::labs(
      title   = "Purchase cost versus felt-temperature reduction",
      x = "Purchase cost (USD)", y = "SET reduction (degC)", caption = chart_caption())
  chart_add(book, "D03", 3, "Purchase cost versus felt-temperature reduction", p, data = d)

  # D04 – Electricity vs. water trade-off
  d <- chart_data(a)
  d <- d[is.finite(d$water_kg), ]
  p <- ggplot2::ggplot(d, ggplot2::aes(E, water_kg, color = option)) +
    ggplot2::geom_point(size = 4) +
    ggplot2::facet_wrap(~panel, ncol = 3) +
    chart_colors() + chart_theme() +
    ggplot2::labs(
      title   = "Electricity and water trade-off",
      x = "Energy (kWh / modeled scenario)", y = "Evaporated water (kg / modeled scenario)",
      caption = chart_caption())
  chart_add(book, "D04", 3, "Electricity and water trade-off", p, data = d)

  # D05 – Regret heatmap
  chart_heatmap(book, "D05", 3, a, "R", "Regret by option and scenario", "Regret")

  # D06 / D07 – Minimax regret lollipop and radar (only when regret is computable)
  r <- result$recommendations
  if (any(is.finite(r$max_regret))) {
    r$scenario <- "all scenarios"
    chart_metric(book, "D06", 3, r, "max_regret",
                 "Minimax: worst regret for each option", "Maximum regret", "lollipop")

    # Merge worst-case resource usage for the minimax radar
    resources <- dplyr::summarise(
      dplyr::group_by(a, venue, option),
      decision_cost = max(decision_cost), E = max(E), water_kg = max(water_kg),
      .groups = "drop"
    )
    rr <- merge(r, resources, by = c("venue", "option"))
    chart_radar(book, "D07", rr,
                c("max_regret", "decision_cost", "E", "water_kg"),
                c("Maximum\nregret", "Cost", "Electricity", "Water"),
                "Minimax decision radar")

  } else {
    # Regret cannot be computed without a SET threshold
    for (id in c("D06", "D07"))
      chart_add(book, id, 3,
                if (id == "D07") "Minimax decision radar"
                else "Minimax: worst regret for each option",
                reason = "cfg.set_upper unset; regret and recommendations unavailable. Fixed-drop cooler conflicts also remain on hold.")
  }

  # D08 – Comfort-cost Pareto frontier (ggplot2 version)
  d <- chart_data(a)
  d <- d[is.finite(d$loss) & is.finite(d$decision_cost) & d$feasible %in% TRUE, ]

  if (nrow(d)) {
    # Mark Pareto-nondominated feasible options within each panel
    d$frontier <- FALSE
    for (panel in unique(d$panel)) {
      ix <- which(d$panel == panel)
      s  <- d[ix, ]
      d$frontier[ix] <- vapply(seq_len(nrow(s)), function(i)
        !any(s$decision_cost <= s$decision_cost[i] & s$loss <= s$loss[i] &
               (s$decision_cost < s$decision_cost[i] | s$loss < s$loss[i])), logical(1))
    }

    front <- d[d$frontier, ]
    front <- front[ave(rep(1, nrow(front)), front$panel, FUN = length) >= 2, , drop = FALSE]
    front <- front[order(front$decision_cost), ]

    p <- ggplot2::ggplot(d, ggplot2::aes(decision_cost, loss, color = option)) +
      ggplot2::geom_line(data = front, ggplot2::aes(group = panel),
                         color = "grey55", linetype = 2) +
      ggplot2::geom_point(size = 4) +
      ggplot2::facet_wrap(~panel, ncol = 3) +
      chart_colors() + chart_theme() +
      ggplot2::labs(
        title   = "Comfort-cost Pareto frontier",
        x = "Decision cost", y = "Residual discomfort", caption = chart_caption())
    chart_add(book, "D08", 3, "Comfort-cost Pareto frontier", p, data = d)

  } else {
    chart_add(book, "D08", 3, "Comfort-cost Pareto frontier",
              reason = "cfg.set_upper unset; discomfort unavailable.")
  }

  invisible(book)
}
