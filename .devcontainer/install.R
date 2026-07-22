#!/usr/bin/env Rscript
# ------------------------------------------------------------------
# SISMID 2026 - R packages preloaded into the course Codespace.
# This is the ONE place to add or remove packages. After editing,
# rebuild the container (Codespaces command palette: "Rebuild Container").
# pak::pak() resolves CRAN + GitHub packages AND their apt system
# dependencies automatically.
# ------------------------------------------------------------------

if (!requireNamespace("pak", quietly = TRUE)) {
  install.packages("pak", repos = sprintf(
    "https://r-lib.github.io/p/pak/stable/%s/%s/%s",
    .Platform$pkgType, R.Version()$os, R.Version()$arch
  ))
}

core <- c(
  # GAMs & splines
  "mgcv", "gratia", "splines2",
  # Time series / ARIMA
  "forecast", "fable", "feasts", "tsibble", "fabletools",
  # Forecast evaluation (scoringutils v2)
  "scoringutils", "distributional",
  # Reporting / Quarto dashboards
  "quarto", "rmarkdown", "knitr", "flexdashboard", "DT", "gt",
  # Wrangling & viz helpers
  "here", "janitor", "glue", "arrow",
  "patchwork", "ggdist", "gghighlight"
)
pak::pak(core)

# Hubverse / FluSight tooling. Installed separately so one unavailable
# package cannot fail the whole build. If any of these are not on CRAN,
# swap the name for its GitHub source, e.g. "hubverse-org/hubData".
hubverse <- c("hubUtils", "hubData", "hubEnsembles", "hubVis")
tryCatch(
  pak::pak(hubverse),
  error = function(e) message("Hubverse install note: ", conditionMessage(e))
)

cat("\nCourse R packages installed.\n")
