numeric_parameters <- function(cfg, tables) {
  parameters <- character()
  for (name in setdiff(names(tables), "bounds")) for (field in names(tables[[name]])) {
    if (field == "hour") next
    x <- tables[[name]][[field]]
    if (is.numeric(x)) for (row in which(is.finite(x))) parameters <- c(parameters, paste(name, row, field, sep = "."))
  }
  for (name in c("set_upper", "set_lower", "budget", "kwh_cap", "water_cap"))
    if (is.numeric(cfg[[name]]) && !is.na(cfg[[name]])) parameters <- c(parameters, paste0("cfg.", name))
  parameters
}

parameter_value <- function(parameter, cfg, tables) {
  parts <- strsplit(parameter, ".", fixed = TRUE)[[1]]
  if (length(parts) == 2 && parts[1] == "cfg") return(cfg[[parts[2]]])
  if (length(parts) == 3 && parts[1] %in% names(tables) && parts[3] %in% names(tables[[parts[1]]])) {
    row <- suppressWarnings(as.integer(parts[2]))
    if (!is.na(row) && row >= 1 && row <= nrow(tables[[parts[1]]])) return(tables[[parts[1]]][[parts[3]]][row])
  }
  NA_real_
}

set_parameter <- function(parameter, value, cfg, tables) {
  parts <- strsplit(parameter, ".", fixed = TRUE)[[1]]
  if (parts[1] == "cfg") cfg[[parts[2]]] <- value
  else {
    row <- as.integer(parts[2])
    tables[[parts[1]]][[parts[3]]][row] <- value
    # The one-zone outdoor exchange is one balanced throughflow, stored twice.
    if (parts[1] == "exchanges" && parts[3] == "mass_kg_s") {
      f <- tables$exchanges
      pair <- which(f$venue == f$venue[row])
      if (length(pair) == 2L &&
          f$from[pair[1]] == f$to[pair[2]] &&
          f$to[pair[1]] == f$from[pair[2]] &&
          "OUTSIDE" %in% f$from[pair])
        tables$exchanges$mass_kg_s[pair] <- value
    }
  }
  list(cfg = cfg, tables = tables)
}

usable_bounds <- function(cfg, tables, log, every_numeric = TRUE) {
  b <- tables$bounds
  parameters <- if (every_numeric) unique(c(numeric_parameters(cfg, tables), b$parameter[!is.na(b$parameter)])) else unique(b$parameter[!is.na(b$parameter)])
  rows <- list()
  if (!length(parameters)) skip_output(log, 4, "sensitivity/Monte Carlo", "bounds.parameter/lower/upper")
  for (parameter in parameters) {
    x <- b[which(b$parameter == parameter), , drop = FALSE]
    if (nrow(x) != 1L) { skip_output(log, 4, "sweep", paste0("bounds.lower/upper for ", parameter), parameter); next }
    if (anyNA(x[c("lower", "upper")])) { skip_output(log, 4, "sweep", missing_fields(x, c("lower", "upper"), "bounds"), parameter); next }
    value <- parameter_value(parameter, cfg, tables)
    policy <- parameter %in% paste0("cfg.", c("set_upper", "set_lower", "budget", "kwh_cap", "water_cap"))
    if (!policy && (length(value) != 1 || !is.numeric(value) || !is.finite(value))) {
      skip_output(log, 4, "sweep", paste0(parameter, " is NA or nonnumeric; bounds cannot fill missing data"), parameter); next
    }
    if (!all(is.finite(c(x$lower, x$upper))) || x$lower > x$upper) {
      skip_output(log, 4, "sweep", "invalid lower/upper bounds", parameter); next
    }
    if (startsWith(parameter, "cfg.") && !sub("cfg.", "", parameter, fixed = TRUE) %in% c("set_upper", "set_lower", "budget", "kwh_cap", "water_cap")) {
      skip_output(log, 4, "sweep", "only cfg thresholds/caps are sweep parameters", parameter); next
    }
    rows[[length(rows) + 1L]] <- x
  }
  result <- bind_rows(rows, empty_input("bounds"))
  # A paired inlet/outlet is one uncertainty parameter, not two independent draws.
  drop <- integer()
  for (i in seq_len(nrow(result))) {
    parts <- strsplit(result$parameter[i], ".", fixed = TRUE)[[1]]
    if (length(parts) != 3 || parts[1] != "exchanges" || parts[3] != "mass_kg_s") next
    row <- as.integer(parts[2]); flows <- tables$exchanges
    pair <- which(flows$venue == flows$venue[row])
    if (length(pair) != 2 || !identical(sort(flows$from[pair]), sort(flows$to[pair])) || !"OUTSIDE" %in% flows$from[pair]) next
    other <- match(paste("exchanges", setdiff(pair, row), "mass_kg_s", sep = "."), result$parameter)
    if (is.na(other) || other <= i) next
    if (result$lower[i] != result$lower[other] || result$upper[i] != result$upper[other]) {
      skip_output(log, 4, "sweep", "paired inlet/outlet bounds disagree", result$parameter[i])
      drop <- c(drop, i, other)
    } else drop <- c(drop, other)
  }
  if (length(drop)) result <- result[-unique(drop), , drop = FALSE]
  result
}

choice_for <- function(result, venue) {
  r <- result$recommendations[result$recommendations$venue == venue, , drop = FALSE]
  if (!nrow(r)) return(NA_character_)
  good <- r$option[r$chosen %in% TRUE]
  if (length(good)) paste(sort(good), collapse = ";")
  else if (any(grepl("no .*feasible option", r$status))) "no feasible option" else NA_character_
}

run_sensitivity <- function(cfg, tables, quiet = FALSE) {
  log <- skip_log(); bounds <- usable_bounds(cfg, tables, log)
  base <- run_all(cfg, tables, quiet = TRUE); rows <- list()
  for (i in seq_len(nrow(bounds))) {
    b <- bounds[i, ]
    for (value in seq(b$lower, b$upper, length.out = cfg$sweep_levels)) {
      changed <- set_parameter(b$parameter, value, cfg, tables)
      result <- run_all(changed$cfg, changed$tables, quiet = TRUE)
      a <- result$options
      if (nrow(a) && (!any(is.finite(a$decision_eta)) || !any(is.finite(a$loss)) || all(is.na(result$recommendations$chosen))))
        skip_output(log, 4, "eta/L/chosen option", unique(result$skipped$inputs), b$parameter)
      if (!nrow(a)) { skip_output(log, 4, "sweep outcomes", "Models 1-3 have no complete case keys; see run_all skipped summary", b$parameter); next }
      for (j in seq_len(nrow(a))) {
        old <- base$options[which(base$options$venue == a$venue[j] & base$options$scenario == a$scenario[j] & base$options$option == a$option[j]), , drop = FALSE]
        old_eta <- old_L <- NA_real_
        if (nrow(old) == 1) { old_eta <- old$decision_eta; old_L <- old$loss }
        rows[[length(rows) + 1L]] <- data.frame(parameter = b$parameter, value = value, venue = a$venue[j],
          scenario = a$scenario[j], option = a$option[j], mean_SET = a$mean_SET[j],
          mean_SET_drop = a$mean_SET_drop[j], kWh = a$E[j], water_kg = a$water_kg[j], purchase_cost = a$purchase_cost[j],
          eta = a$decision_eta[j], L = a$loss[j], comfort_basis = a$comfort_basis[j],
          delta_eta = a$decision_eta[j] - old_eta, delta_L = a$loss[j] - old_L,
          chosen_option = choice_for(result, a$venue[j]), baseline_choice = choice_for(base, a$venue[j]))
      }
    }
  }
  detail <- bind_rows(rows, data.frame(parameter = character(), value = numeric(), venue = character(), scenario = character(), option = character(), mean_SET = numeric(), mean_SET_drop = numeric(), kWh = numeric(), water_kg = numeric(), purchase_cost = numeric(), eta = numeric(), L = numeric(), comfort_basis = character(), delta_eta = numeric(), delta_L = numeric(), chosen_option = character(), baseline_choice = character()))
  switching <- list()
  for (key in unique(paste(detail$parameter, detail$venue))) {
    d <- unique(detail[paste(detail$parameter, detail$venue) == key, c("parameter", "venue", "value", "chosen_option")])
    d <- d[order(d$value), , drop = FALSE]
    if (nrow(d) < 2) next
    for (i in seq_len(nrow(d) - 1L)) if (!anyNA(d$chosen_option[c(i, i + 1L)]) && d$chosen_option[i] != d$chosen_option[i + 1L])
      switching[[length(switching) + 1L]] <- data.frame(parameter = d$parameter[i], venue = d$venue[i], lower = d$value[i], upper = d$value[i + 1L],
        choice_below = d$chosen_option[i], choice_above = d$chosen_option[i + 1L])
  }
  result <- list(detail = detail,
    switching = bind_rows(switching, data.frame(parameter = character(), venue = character(), lower = numeric(), upper = numeric(), choice_below = character(), choice_above = character())),
    skipped = skipped_table(log))
  if (!quiet) cat("Sensitivity: ", nrow(detail), " outcome rows; skipped: ",
    if (nrow(result$skipped)) paste(unique(paste(result$skipped$context, result$skipped$inputs, sep = ": ")), collapse = " | ") else "none", "\n", sep = "")
  result
}

break_even_plot <- function(d, path) {
  useful <- d[is.finite(d$value) & (is.finite(d$eta) | is.finite(d$L)), , drop = FALSE]
  if (!nrow(useful)) return(FALSE)
  first <- useful[1, ]; a <- useful[useful$parameter == first$parameter & useful$venue == first$venue & useful$scenario == first$scenario, , drop = FALSE]
  grDevices::png(path, width = 1400, height = 700, res = 120)
  on.exit(grDevices::dev.off())
  par(mfrow = c(1, 2), mar = c(6, 4, 4, 1))
  colors <- setNames(seq_along(unique(a$option)), unique(a$option))
  for (metric in c("eta", "L")) {
    good <- a[is.finite(a[[metric]]), , drop = FALSE]
    if (!nrow(good)) { plot.new(); title(paste(metric, "unavailable")); next }
    plot(range(good$value), range(good[[metric]]), type = "n", xlab = first$parameter,
      ylab = if (metric == "eta") "Efficiency (see comfort_basis in CSV)" else "Residual discomfort (see comfort_basis in CSV)",
      main = paste(first$venue, first$scenario, sep = " / "))
    for (op in unique(good$option)) {
      x <- good[good$option == op, ]; x <- x[order(x$value), ]
      lines(x$value, x[[metric]], type = "b", pch = 19, col = colors[op])
    }
    legend("topright", legend = names(colors), col = colors, lty = 1, bty = "n")
  }
  TRUE
}

save_sensitivity <- function(result, root = ".") {
  for (name in names(result)) write.csv(result[[name]], file.path(root, "04_sensitivity", paste0("result_sensitivity_", name, ".csv")), row.names = FALSE, na = "NA")
  if (!break_even_plot(result$detail, file.path(root, "04_sensitivity", "result_break_even.png"))) {
    path <- file.path(root, "04_sensitivity", "result_break_even.png")
    if (file.exists(path)) unlink(path)
    cat("Skipped: break-even plot [complete bounded sweep with eta or L]\n")
  }
  invisible(result)
}

run_monte_carlo <- function(cfg, tables, quiet = FALSE) {
  log <- skip_log(); bounds <- usable_bounds(cfg, tables, log, every_numeric = FALSE)
  rows <- choices <- list()
  if (nrow(bounds)) {
    set.seed(cfg$seed)
    for (draw in seq_len(cfg$mc_n)) {
      changed <- list(cfg = cfg, tables = tables)
      for (i in seq_len(nrow(bounds))) {
        b <- bounds[i, ]; value <- runif(1, b$lower, b$upper)
        changed <- set_parameter(b$parameter, value, changed$cfg, changed$tables)
      }
      r <- run_all(changed$cfg, changed$tables, quiet = TRUE)
      if (nrow(r$options)) { a <- r$options; a$draw <- draw; rows[[length(rows) + 1L]] <- a }
      for (venue in unique(r$options$venue)) choices[[length(choices) + 1L]] <- data.frame(draw = draw, venue = venue, choice = choice_for(r, venue))
    }
  }
  draws <- bind_rows(rows, data.frame()); selections <- bind_rows(choices, data.frame(draw = integer(), venue = character(), choice = character()))
  frequencies <- quantiles <- list()
  label <- "Conditional on independent uniform draws within supplied bounds; not confidence intervals"
  for (venue in unique(selections$venue)) {
    s <- selections[selections$venue == venue, ]; known <- !is.na(s$choice)
    for (choice in unique(c(s$choice[known], if (any(!known)) "unresolved"))) {
      count <- if (choice == "unresolved") sum(!known) else sum(s$choice[known] == choice)
      frequencies[[length(frequencies) + 1L]] <- data.frame(venue = venue, choice = choice, count = count,
        draws = cfg$mc_n, frequency = count/cfg$mc_n, interpretation = label)
    }
  }
  if (nrow(draws)) for (key in unique(paste(draws$venue, draws$scenario, draws$option))) {
    d <- draws[paste(draws$venue, draws$scenario, draws$option) == key, ]
    for (metric in c("decision_eta", "loss", "decision_cost")) {
      complete <- nrow(d) == cfg$mc_n && all(is.finite(d[[metric]]))
      q <- if (complete) quantile(d[[metric]], c(.05, .5, .95), names = FALSE) else rep(NA_real_, 3)
      if (!complete) skip_output(log, 4, "Monte Carlo quantiles", paste(metric, "incomplete across draws"), key)
      quantiles[[length(quantiles) + 1L]] <- data.frame(venue = d$venue[1], scenario = d$scenario[1], option = d$option[1],
        metric = metric, probability = c(.05, .5, .95), value = q, complete_draws = sum(is.finite(d[[metric]])), interpretation = label)
    }
  }
  if (!length(rows)) skip_output(log, 4, "Monte Carlo", "no usable bounds or no complete scenario keys")
  result <- list(frequencies = bind_rows(frequencies, data.frame(venue = character(), choice = character(), count = integer(), draws = integer(), frequency = numeric(), interpretation = character())),
    quantiles = bind_rows(quantiles, data.frame(venue = character(), scenario = character(), option = character(), metric = character(), probability = numeric(), value = numeric(), complete_draws = integer(), interpretation = character())),
    skipped = skipped_table(log))
  if (!quiet) cat("Monte Carlo: ", nrow(result$frequencies), " frequency rows; ", label, ". Skipped: ",
    if (nrow(result$skipped)) paste(unique(result$skipped$inputs), collapse = " | ") else "none", "\n", sep = "")
  result
}

save_monte_carlo <- function(result, root = ".") {
  for (name in names(result)) write.csv(result[[name]], file.path(root, "04_sensitivity", paste0("result_monte_carlo_", name, ".csv")), row.names = FALSE, na = "NA")
  invisible(result)
}
