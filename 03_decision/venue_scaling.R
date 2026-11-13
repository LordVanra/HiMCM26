# Run from the repository root with Rscript 03_decision/venue_scaling.R.
source("01_physics/physics.R")
source("02_comfort/comfort.R")
source("03_decision/decision.R")

tables <- load_tables()
venues <- c("DAL_QUAD", "DAL_PAV", "BOS_QUAD", "BOS_PAV", "PHX_QUAD", "PHX_PAV")
for (name in c("zones", "weather_occ", "exchanges", "devices")) {
  inputs <- tables[[name]]
  tables[[name]] <- inputs[inputs$venue %in% venues, , drop = FALSE]
  stopifnot(setequal(tables[[name]]$venue, venues))
}

# Increase balanced outdoor exchange while keeping one device and its airflow
# constant. These multipliers test dilution, not physical area or occupancy.
cases <- expand.grid(exchange_multiplier = c(1, 2, 4),
                     cooler_limit = c("fixed", "saturation_limit"),
                     stringsAsFactors = FALSE)
results <- lapply(seq_len(nrow(cases)), function(i) {
  cfg <- build_config()
  cfg$cooler_limit <- cases$cooler_limit[i]
  scaled <- tables
  scaled$exchanges$mass_kg_s <- tables$exchanges$mass_kg_s * cases$exchange_multiplier[i]
  run <- run_all(cfg, scaled, quiet = TRUE)
  options <- run$options[, c("venue", "option", "physical_valid", "mean_SET",
                             "mean_SET_drop", "E", "water_kg", "purchase_cost")]
  options$exchange_multiplier <- cases$exchange_multiplier[i]
  options$cooler_limit <- cases$cooler_limit[i]
  energy <- ifelse(options$E > 0, options$E, NA_real_)
  options$set_drop_per_kwh <- options$mean_SET_drop / energy
  # Evaluate the model's per-person efficiency at illustrative upper thresholds.
  for (threshold in c(22, 24, 26)) {
    cfg$set_upper <- threshold
    comfort <- run_all(cfg, scaled, quiet = TRUE)$options
    options[[paste0("eta_per_person_upper_", threshold)]] <- comfort$eta_per_person
  }
  options
})

write.csv(do.call(rbind, results), "03_decision/result_venue_scaling.csv",
          row.names = FALSE, na = "NA")
