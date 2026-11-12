annualized_capital <- function(capital, life_years, discount_rate) {
  stopifnot(!anyNA(c(capital, life_years, discount_rate)), capital >= 0, life_years > 0, discount_rate >= 0)
  if (discount_rate == 0) capital/life_years else capital*discount_rate/(1 - (1 + discount_rate)^(-life_years))
}

within_cap <- function(value, cap) {
  if (is.na(cap)) TRUE else if (is.na(value)) NA else value <= cap
}

minimax_regret <- function(a, cfg, log = skip_log()) {
  if (!"loss" %in% names(a)) a$loss <- a$L
  if (!"decision_cost" %in% names(a)) a$decision_cost <- a$annual_cost
  if (!"decision_eta" %in% names(a)) a$decision_eta <- a$eta
  a$R <- rep(NA_real_, nrow(a)); chosen <- switching <- benchmarks <- list()
  for (venue in unique(a$venue)) {
    vi <- which(a$venue == venue); v <- a[vi, , drop = FALSE]
    scenarios <- unique(v$scenario); options <- unique(v$option)
    incomplete <- nrow(v) != length(scenarios)*length(options) || anyDuplicated(paste(v$scenario, v$option)) > 0
    for (scenario in scenarios) {
      ix <- which(v$scenario == scenario); s <- v[ix, , drop = FALSE]
      good <- which(s$feasible %in% TRUE)
      status <- "evaluated"; local_best <- NA_character_
      if (anyNA(s$feasible)) status <- "incomplete feasibility"
      else if (!length(good)) status <- "no feasible option"
      else if (anyNA(s$loss[good])) status <- "incomplete loss"
      else {
        best <- min(s$loss[good]); v$R[ix] <- s$loss - best
        local_best <- paste(s$option[good][s$loss[good] <= best + cfg$tie_tol], collapse = ";")
      }
      if (status != "evaluated") skip_output(log, 3, "regret/recommendation", status, paste(venue, scenario, sep = "/"))
      switching[[length(switching) + 1L]] <- data.frame(venue = venue, scenario = scenario,
        scenario_best = local_best, robust_choice = NA_character_, status = status,
        contingency = status == "no feasible option")
      for (kind in c("always A", "cheapest feasible", "highest efficiency")) {
        pick <- integer()
        if (kind == "always A") pick <- which(s$option == "A")
        if (kind == "cheapest feasible" && !anyNA(s$feasible) && length(good) && !anyNA(s$decision_cost[good]))
          pick <- good[s$decision_cost[good] <= min(s$decision_cost[good]) + cfg$tie_tol]
        active <- which(s$option != "NONE")
        if (kind == "highest efficiency" && length(active) && all(is.finite(s$decision_eta[active])))
          pick <- active[s$decision_eta[active] >= max(s$decision_eta[active]) - cfg$tie_tol]
        if (!length(pick)) {
          skip_output(log, 3, kind, if (kind == "highest efficiency") "eta unavailable for compared options" else "feasible/decision cost unavailable", paste(venue, scenario))
          benchmarks[[length(benchmarks) + 1L]] <- data.frame(venue = venue, scenario = scenario, benchmark = kind, option = NA_character_, L = NA_real_, annual_cost = NA_real_, eta = NA_real_, decision_cost = NA_real_, loss = NA_real_, decision_eta = NA_real_, feasible = NA)
        } else for (j in pick) benchmarks[[length(benchmarks) + 1L]] <- data.frame(venue = venue, scenario = scenario, benchmark = kind,
          option = s$option[j], L = s$L[j], annual_cost = s$annual_cost[j], eta = s$eta[j], decision_cost = s$decision_cost[j], loss = s$loss[j], decision_eta = s$decision_eta[j], feasible = s$feasible[j])
      }
    }
    a$R[vi] <- v$R
    if (incomplete || anyNA(v$feasible)) {
      chosen[[length(chosen) + 1L]] <- data.frame(venue = venue, option = NA_character_, max_regret = NA_real_, worst_L = NA_real_, chosen = NA, status = "incomplete inputs")
      next
    }
    robust <- options[vapply(options, function(op) all(v$feasible[v$option == op]), logical(1))]
    if (!length(robust)) {
      chosen[[length(chosen) + 1L]] <- data.frame(venue = venue, option = NA_character_, max_regret = NA_real_, worst_L = NA_real_, chosen = FALSE, status = "no robust feasible option; contingency needed")
      next
    }
    if (anyNA(v$R[v$option %in% robust])) {
      chosen[[length(chosen) + 1L]] <- data.frame(venue = venue, option = NA_character_, max_regret = NA_real_, worst_L = NA_real_, chosen = NA, status = "incomplete loss")
      next
    }
    result <- do.call(rbind, lapply(robust, function(op) {
      rows <- v[v$option == op, ]
      data.frame(venue = venue, option = op, max_regret = max(rows$R), worst_L = max(rows$loss), chosen = FALSE, status = "evaluated")
    }))
    result$chosen <- result$max_regret <= min(result$max_regret) + cfg$tie_tol
    chosen[[length(chosen) + 1L]] <- result
    for (j in seq_along(switching)) if (switching[[j]]$venue == venue)
      switching[[j]]$robust_choice <- paste(result$option[result$chosen], collapse = ";")
  }
  list(options = a,
    recommendations = bind_rows(chosen, data.frame(venue = character(), option = character(), max_regret = numeric(), worst_L = numeric(), chosen = logical(), status = character())),
    switching = bind_rows(switching, data.frame(venue = character(), scenario = character(), scenario_best = character(), robust_choice = character(), status = character(), contingency = logical())),
    benchmarks = bind_rows(benchmarks, data.frame(venue = character(), scenario = character(), benchmark = character(), option = character(), L = numeric(), annual_cost = numeric(), eta = numeric(), decision_cost = numeric(), loss = numeric(), decision_eta = numeric(), feasible = logical())))
}

run_decision <- function(cfg, tables, comfort, log = skip_log()) {
  a <- comfort$summary
  a$annual_cost <- a$purchase_cost <- a$electricity_cost <- rep(NA_real_, nrow(a))
  a$safety_status <- rep("unassessed", nrow(a))
  a$cost_basis <- rep(cfg$cost_basis, nrow(a)); a$comfort_basis <- rep(cfg$comfort_basis, nrow(a))
  a$loss <- if (cfg$comfort_basis == "per_person") a$L_per_person else a$L
  a$decision_eta <- if (cfg$comfort_basis == "per_person") a$eta_per_person else a$eta
  a$decision_cost <- rep(NA_real_, nrow(a)); a$feasible <- rep(NA, nrow(a))
  if (cfg$cost_basis == "annual") {
    complete_for(tables$devices, c("capital", "maintenance", "life_years", "discount_rate", "electricity_price"), "devices", log, 3, "annual_cost", "active options")
    complete_for(tables$weather_occ, "annual_weight", "weather_occ", log, 3, "annual_cost", "active options")
  }
  for (i in seq_len(nrow(a))) {
    row <- a[i, ]; context <- paste(row$venue, row$scenario, row$option, sep = "/")
    dd <- tables$devices[which(tables$devices$venue == row$venue & tables$devices$option == row$option), , drop = FALSE]
    if (row$option == "NONE") {
      a$purchase_cost[i] <- a$electricity_cost[i] <- 0
    } else {
      if (complete_for(dd, "capital", "devices", log, 3, "purchase_cost", context)) a$purchase_cost[i] <- sum(dd$capital)
      if (nrow(dd) && !anyNA(dd$electricity_price) && length(unique(dd$electricity_price)) == 1)
        a$electricity_cost[i] <- unique(dd$electricity_price)*row$E
    }
    if (row$option == "NONE") a$annual_cost[i] <- 0 else if (cfg$cost_basis == "annual") {
      dd <- tables$devices[which(tables$devices$venue == row$venue & tables$devices$option == row$option), , drop = FALSE]
      ww <- tables$weather_occ[which(tables$weather_occ$venue == row$venue & tables$weather_occ$scenario == row$scenario), , drop = FALSE]
      okd <- complete_for(dd, c("capital", "maintenance", "life_years", "discount_rate", "electricity_price"), "devices", log, 3, "annual_cost", context)
      okw <- complete_for(ww, "annual_weight", "weather_occ", log, 3, "annual_cost", context)
      if (okd && okw && !is.na(row$E)) {
        annual <- unique(ww$annual_weight); price <- unique(dd$electricity_price)
        if (length(annual) != 1 || length(price) != 1 || annual < 0 || price < 0)
          skip_output(log, 3, "annual_cost", "invalid: inconsistent or negative annual_weight/electricity_price", context)
        else {
          capital <- attempt(sum(mapply(annualized_capital, dd$capital, dd$life_years, dd$discount_rate)), log, 3, "annual_cost", context)
          a$annual_cost[i] <- capital + sum(dd$maintenance) + price*row$E*annual
          water_price <- unique(dd$water_price[!is.na(dd$water_price)])
          if (length(water_price)) {
            if (length(water_price) != 1 || water_price < 0) {
              a$annual_cost[i] <- NA_real_; skip_output(log, 3, "annual_cost", "invalid: water_price", context)
            } else a$annual_cost[i] <- a$annual_cost[i] + water_price*row$water_kg*annual
          }
        }
      } else if (is.na(row$E)) skip_output(log, 3, "annual_cost", "energy unavailable (devices.power_kW/weather_occ.hour)", context)
    }
    a$decision_cost[i] <- if (cfg$cost_basis == "purchase") a$purchase_cost[i] else a$annual_cost[i]
    a$feasible[i] <- all(c(within_cap(a$decision_cost[i], cfg$budget), within_cap(row$E, cfg$kwh_cap),
      within_cap(row$water_kg, cfg$water_cap)))
  }
  minimax_regret(a, cfg, log)
}

run_all <- function(cfg, tables, quiet = FALSE) {
  log <- skip_log()
  physics <- run_physics(cfg, tables, log)
  comfort <- run_comfort(cfg, tables, physics, log)
  decision <- run_decision(cfg, tables, comfort, log)
  sw <- decision$switching
  for (field in c("T_min", "T_max", "RH_min", "RH_max", "budget", "kwh_cap", "water_cap")) sw[[field]] <- rep(NA_real_, nrow(sw))
  for (i in seq_len(nrow(sw))) {
    obs <- tables$weather_occ[which(tables$weather_occ$venue == sw$venue[i] & tables$weather_occ$scenario == sw$scenario[i]), , drop = FALSE]
    if (nrow(obs)) {
      sw$T_min[i] <- min(obs$T); sw$T_max[i] <- max(obs$T)
      sw$RH_min[i] <- min(obs$RH); sw$RH_max[i] <- max(obs$RH)
    }
    sw$budget[i] <- cfg$budget; sw$kwh_cap[i] <- cfg$kwh_cap; sw$water_cap[i] <- cfg$water_cap
  }
  decision$switching <- sw
  result <- list(outdoor = physics$outdoor, zone_conditions = physics$zones,
    mass_balance = physics$mass_balance, hourly_resources = physics$resources,
    comfort_detail = comfort$detail, options = decision$options,
    recommendations = decision$recommendations, switching = decision$switching,
    benchmarks = decision$benchmarks, skipped = skipped_table(log))
  basis <- paste("heat:", cfg$heat_model, "; radiation:", cfg$radiant_model,
    "; comfort:", cfg$comfort_basis, "; costs:", cfg$cost_basis, "; evaporative limit:", cfg$cooler_limit,
    "; assigned reference person/equipment, not measured installation performance")
  for (name in c("zone_conditions", "comfort_detail", "options", "recommendations", "switching", "benchmarks"))
    result[[name]]$model_basis <- rep(basis, nrow(result[[name]]))
  if (!quiet) {
    print(data.frame(output = c("outdoor", "zone_conditions", "options", "recommendations"),
      rows = vapply(result[c("outdoor", "zone_conditions", "options", "recommendations")], nrow, integer(1))), row.names = FALSE)
    if (nrow(result$skipped)) {
      grouped <- split(result$skipped$inputs, result$skipped$output)
      cat("Skipped: ", paste(vapply(names(grouped), function(k) paste0(k, " [", paste(unique(grouped[[k]]), collapse = "; "), "]"), ""), collapse = " | "), "\n", sep = "")
    } else cat("Skipped: none\n")
  }
  result
}

pareto_plot <- function(a, path) {
  if ("decision_cost" %in% names(a)) a$annual_cost <- a$decision_cost
  if ("loss" %in% names(a)) a$L <- a$loss
  a <- a[is.finite(a$annual_cost) & is.finite(a$L), , drop = FALSE]
  if (!nrow(a)) return(FALSE)
  grDevices::png(path, width = 1200, height = 800, res = 120)
  on.exit(grDevices::dev.off())
  panels <- split(a, paste(a$venue, a$scenario))
  par(mfrow = c(ceiling(sqrt(length(panels))), ceiling(length(panels)/ceiling(sqrt(length(panels))))))
  for (label in names(panels)) {
    d <- panels[[label]]
    frontier <- vapply(seq_len(nrow(d)), function(i)
      !any(d$annual_cost <= d$annual_cost[i] & d$L <= d$L[i] & (d$annual_cost < d$annual_cost[i] | d$L < d$L[i])), logical(1))
    plot(d$annual_cost, d$L, pch = 19, col = ifelse(frontier, "#007C83", "#777777"),
      xlab = paste(if ("cost_basis" %in% names(d)) d$cost_basis[1] else "annual", "cost (input currency)"),
      ylab = if ("comfort_basis" %in% names(d) && d$comfort_basis[1] == "per_person") "Residual discomfort (degC-h per reference person)" else "Residual discomfort (person-degC-h)", main = label)
    text(d$annual_cost, d$L, labels = d$option, pos = 3, cex = .8)
    front <- d[frontier, ]; front <- front[order(front$annual_cost), ]
    lines(front$annual_cost, front$L, col = "#007C83")
  }
  TRUE
}

save_results <- function(result, root = ".") {
  folders <- c(outdoor = "01_physics", zone_conditions = "01_physics", mass_balance = "01_physics",
    hourly_resources = "01_physics", comfort_detail = "02_comfort", options = "03_decision",
    recommendations = "03_decision", switching = "03_decision", benchmarks = "03_decision", skipped = "03_decision")
  for (name in names(folders)) write.csv(result[[name]], file.path(root, folders[[name]], paste0("result_", name, ".csv")), row.names = FALSE, na = "NA")
  plotted <- pareto_plot(result$options, file.path(root, "03_decision", "result_pareto.png"))
  if (!plotted) {
    path <- file.path(root, "03_decision", "result_pareto.png")
    if (file.exists(path)) unlink(path)
    cat("Skipped: Pareto plot [complete decision cost and discomfort loss]\n")
  }
  invisible(result)
}
