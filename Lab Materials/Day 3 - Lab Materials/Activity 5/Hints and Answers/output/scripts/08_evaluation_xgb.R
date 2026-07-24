# 08_evaluation_xgb.R
# Mirror of 04_evaluation.R for the XGBoost quantile forecasts.
#
# Scores XGB_flusight_forecasts.csv against observed truth, one score per
# reference_date x horizon, using the scoringutils package. Reports WIS, AE,
# and 95% prediction-interval coverage, prints the tables, and writes them to
# output/data/04_evaluation/XGB_forecast_scores.csv and
# output/data/04_evaluation/XGB_forecast_scores_by_horizon.csv.
#
# The scoring logic is identical to 04_evaluation.R -- only the input path,
# output paths, and the `model` label differ. Baseline and WVAL_ score files are
# never written.
#
# See rules.md ("XGBoost Forecast Evaluation") and AGENTS.md.

# ---- Required packages -------------------------------------------------------
pkgs <- c("readr", "dplyr", "scoringutils")
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(scoringutils)
})

# ---- Paths -------------------------------------------------------------------
forecast_csv <- "output/data/03_forecast/XGB_flusight_forecasts.csv"
cleaned_csv  <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
scores_csv   <- "output/data/04_evaluation/XGB_forecast_scores.csv"
summary_csv  <- "output/data/04_evaluation/XGB_forecast_scores_by_horizon.csv"

# Refuse to write over the baseline / WVAL_ outputs.
if (!grepl("^XGB_", basename(scores_csv)))  stop("Refusing to write: scores CSV lacks XGB_ prefix")
if (!grepl("^XGB_", basename(summary_csv))) stop("Refusing to write: summary CSV lacks XGB_ prefix")

dir.create(dirname(scores_csv), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(forecast_csv)) stop(paste0("Missing input: ", forecast_csv))
if (!file.exists(cleaned_csv))  stop(paste0("Missing input: ", cleaned_csv))

# ---- Rule 1: Input Data ------------------------------------------------------
fc_raw <- read_csv(
  forecast_csv,
  col_types = cols(
    reference_date  = col_date(),
    target          = col_character(),
    horizon         = col_integer(),
    target_end_date = col_date(),
    location        = col_character(),
    output_type     = col_character(),
    output_type_id  = col_double(),
    value           = col_double()
  )
)

truth <- read_csv(cleaned_csv, col_types = cols(.default = "c"))
if (!all(c("week", "location", "value") %in% names(truth))) {
  stop("Required columns missing from cleaned CSV (expected week, location, value)")
}
truth$week  <- as.Date(truth$week)
truth$value <- parse_number(truth$value)
if (any(is.na(truth$week)))  stop("The week could not be parsed.")
if (any(is.na(truth$value))) stop("The value could not be parsed.")
truth <- truth %>%
  transmute(target_end_date = week, observed = as.numeric(value))

scorable_units <- fc_raw %>%
  distinct(reference_date, horizon, target_end_date) %>%
  left_join(truth, by = "target_end_date")

n_total   <- nrow(scorable_units)
n_dropped <- sum(is.na(scorable_units$observed))
cat("Reference_date x horizon combinations:", n_total, "\n")
cat("Dropped (no observed target):", n_dropped, "\n")
cat("Scorable:", n_total - n_dropped, "\n")

joined <- fc_raw %>%
  inner_join(truth, by = "target_end_date")
if (nrow(joined) == 0) stop("No forecasts have an observed target to score against")

# ---- Rule 2: Scoring with scoringutils ---------------------------------------
su_input <- joined %>%
  transmute(
    reference_date,
    horizon,
    target_end_date,
    location,
    model          = "xgboost",
    observed,
    predicted      = value,
    quantile_level = output_type_id
  )

fc_obj <- as_forecast_quantile(su_input)

coverage_95 <- function(observed, predicted, quantile_level) {
  interval_coverage(observed, predicted, quantile_level, interval_range = 95)
}

scored <- score(
  fc_obj,
  metrics = list(
    wis         = wis,
    ae_median   = ae_median_quantile,
    coverage_95 = coverage_95
  )
) %>%
  as.data.frame()

# ---- Rule 3: Output Table ----------------------------------------------------
observed_lookup <- scorable_units %>%
  filter(!is.na(observed)) %>%
  select(reference_date, horizon, target_end_date, observed)

scores_out <- scored %>%
  left_join(observed_lookup, by = c("reference_date", "horizon", "target_end_date")) %>%
  transmute(
    reference_date,
    horizon,
    target_end_date,
    observed,
    WIS         = round(wis, 1),
    AE          = round(ae_median, 1),
    coverage_95 = as.integer(coverage_95)
  ) %>%
  arrange(reference_date, horizon)

cat("\n--- XGBoost forecast scores (per reference_date x horizon) ---\n")
print(scores_out, row.names = FALSE)

write_csv(scores_out, scores_csv)
if (!file.exists(scores_csv)) stop("Scores CSV not written")
cat("\nWrote", nrow(scores_out), "rows to", scores_csv, "\n")

# ---- Rule 4: Summary by Horizon ----------------------------------------------
summary_out <- scores_out %>%
  group_by(horizon) %>%
  summarise(
    n                = n(),
    WIS_mean         = round(mean(WIS), 1),
    WIS_min          = round(min(WIS), 1),
    WIS_max          = round(max(WIS), 1),
    MAE_mean         = round(mean(AE), 1),
    MAE_min          = round(min(AE), 1),
    MAE_max          = round(max(AE), 1),
    coverage_95_mean = round(mean(coverage_95), 2),
    .groups = "drop"
  ) %>%
  arrange(horizon)

cat("\n--- XGBoost forecast scores summarized by horizon ---\n")
print(summary_out, row.names = FALSE)

write_csv(summary_out, summary_csv)
if (!file.exists(summary_csv)) stop("Summary CSV not written")
cat("\nWrote", nrow(summary_out), "rows to", summary_csv, "\n")
