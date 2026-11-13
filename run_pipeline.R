# Run from the repository root with Rscript run_pipeline.R.
source("01_physics/physics.R")
source("02_comfort/comfort.R")
source("03_decision/decision.R")
source("04_sensitivity/sensitivity.R")

cfg <- build_config()
root <- normalizePath(".", winslash = "/")
tables <- load_tables(root)

result <- run_all(cfg, tables)
save_results(result, root)

sensitivity <- run_sensitivity(cfg, tables, quiet = TRUE)
save_sensitivity(sensitivity, root)
cat("Sensitivity results:", nrow(sensitivity$detail), "rows\n")

save_chart_gallery(result, sensitivity, cfg, tables, root)
