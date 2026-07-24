# 07_xgboost_forecast.R
# XGBoost variant of 03_forecast.R.
#
# Same pipeline as 03_forecast.R -- reads cleaned flu admissions, assigns
# seasons, uses the SAME expanding-window reference-date set over the 2025-26
# testing season, and emits 1/2/3-week-ahead forecasts in FluSight long format
# (23 quantiles x 3 horizons per reference date) -- but swaps auto.arima() for
# XGBoost quantile regression and uses NO external regressor / leading indicator.
#
# Modeling choices (see rules.md "Forecasting with Gradient-Boosted Trees"):
#   * Features (XGBoost has no built-in AR structure): four admissions lags as of
#     the anchor week + first/second seasonal harmonics of the target epiweek.
#   * Direct per-horizon: a separate model is fit for each horizon h in {1,2,3},
#     target = value(t + 7h). Three fits per reference date.
#   * Native quantile regression: objective "reg:quantileerror" with a 23-value
#     quantile_alpha, so one fit predicts every FluSight quantile. Crossed
#     quantiles are sorted ascending to guarantee a non-decreasing ladder.
#
# Two ARIMA-specific checks are adapted (documented at their call sites):
#   * "median centered / symmetric" is dropped -- XGBoost quantiles are asymmetric.
#   * "intervals widen with horizon" becomes a printed diagnostic, not a stop --
#     direct per-horizon models need not widen monotonically.
#
# All outputs carry an XGB_ prefix; no baseline or WVAL_ artifact is touched.
#
# See rules.md and AGENTS.md.

# ---- Required packages -------------------------------------------------------
pkgs <- c("readr", "dplyr", "tidyr", "lubridate", "ggplot2", "MMWRweek", "xgboost")
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(ggplot2)
  library(MMWRweek)
  library(xgboost)
})

# ---- Paths -------------------------------------------------------------------
cleaned_csv   <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
forecast_csv  <- "output/data/03_forecast/XGB_flusight_forecasts.csv"
forecast_png  <- "output/figures/03_forecast/XGB_forecast_vs_observed.png"

# Rule 7X: refuse to write over the baseline / WVAL_ artifacts.
if (!grepl("^XGB_", basename(forecast_csv))) stop("Refusing to write: forecast CSV lacks XGB_ prefix")
if (!grepl("^XGB_", basename(forecast_png))) stop("Refusing to write: forecast PNG lacks XGB_ prefix")

dir.create(dirname(forecast_csv), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(forecast_png), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(cleaned_csv)) stop(paste0("Missing input: ", cleaned_csv))

# ---- Rule 1: Input Data ------------------------------------------------------
# Read as character first, then parse/validate each column. If a column cannot
# be parsed, stop with: 'The {column} could not be parsed.'
df <- read_csv(cleaned_csv, col_types = cols(.default = "c"))

if (!all(c("week", "location", "value") %in% names(df))) {
  stop("Required columns missing from cleaned CSV (expected week, location, value)")
}

# week -> Date
parsed_week <- suppressWarnings({
  w <- as.Date(df$week)
  if (all(is.na(w))) w <- ymd(df$week)
  if (all(is.na(w))) w <- mdy(df$week)
  w
})
if (all(is.na(parsed_week)) || any(is.na(parsed_week))) stop("The week could not be parsed.")
df$week <- parsed_week

# value -> numeric (handles comma formatting)
parsed_value <- suppressWarnings(parse_number(df$value))
if (all(is.na(parsed_value)) || any(is.na(parsed_value))) stop("The value could not be parsed.")
df$value <- as.numeric(parsed_value)

# location -> character, all "US"
df$location <- as.character(df$location)
if (!all(df$location == "US")) stop("The location could not be parsed.")

df <- df %>% select(week, location, value) %>% arrange(week)
if (nrow(df) == 0) stop("Input has zero rows")

# ---- Rule 2: Season Rules ----------------------------------------------------
# Season spans MMWR week 40 -> week 20 of the following year; named YYYY-YY.
current_season_label <- "2025-26"
current_start_year   <- 2025

first_date_with_mmwr <- function(year, target_week) {
  dates <- seq.Date(as.Date(paste0(year, "-01-01")),
                    as.Date(paste0(year, "-12-31")), by = "day")
  m <- MMWRweek(dates)
  idx <- which(m$MMWRweek == target_week & m$MMWRyear == year)
  if (length(idx) == 0) return(as.Date(NA))
  dates[min(idx)]
}

season_start <- first_date_with_mmwr(current_start_year, 40)
season_end   <- first_date_with_mmwr(current_start_year + 1, 20)
if (is.na(season_start) || is.na(season_end)) {
  stop("Could not determine 2025-26 season boundaries via MMWRweek")
}

cat("Season Start Week:", format(season_start, "%Y-%m-%d"), "\n")
cat("Season End Week:",   format(season_end,   "%Y-%m-%d"), "\n")

# Assign each observed week to a season (calendar year base; Jan-Aug week-53 fix).
mmwr_info      <- MMWRweek(df$week)
df$epiweek     <- mmwr_info$MMWRweek
df$cal_year    <- year(df$week)
df$cal_month   <- month(df$week)

assign_start_year <- function(epiweek, cal_year, cal_month) {
  if (epiweek >= 40) {
    if (cal_month >= 1 && cal_month <= 8) cal_year - 1 else cal_year
  } else if (epiweek <= 20) {
    cal_year - 1
  } else {
    NA_integer_
  }
}

df$season_start_year <- mapply(assign_start_year, df$epiweek, df$cal_year, df$cal_month)
df$season_label <- ifelse(
  is.na(df$season_start_year), NA_character_,
  paste0(df$season_start_year, "-", substr(as.character(df$season_start_year + 1), 3, 4))
)

# ---- Rule 3: Training and Testing Periods (identical to 03_forecast.R) --------
test_weeks <- df %>% filter(season_label == current_season_label) %>% arrange(week)
if (nrow(test_weeks) == 0) stop("No 2025-26 testing-season weeks present in the input")
first_test_week <- min(test_weeks$week)

observed_weeks   <- sort(unique(df$week))
test_week_set    <- test_weeks$week
is_ref <- vapply(observed_weeks, function(r) {
  (r + 7) %in% observed_weeks && (r + 7) %in% test_week_set
}, logical(1))
reference_dates <- observed_weeks[is_ref]
if (length(reference_dates) == 0) stop("No valid reference dates for the testing period")

train_start       <- min(df$week)
initial_train_end <- max(df$week[df$week < first_test_week])

cat("\n--- Rule 3 validations ---\n")
cat("[val] Training Period start:", format(train_start, "%Y-%m-%d"), "\n")
cat("[val] Initial training window end (last pre-test week):",
    format(initial_train_end, "%Y-%m-%d"), "\n")
cat("[val] Testing Period start:", format(first_test_week, "%Y-%m-%d"), "\n")
cat("[val] Forecast horizons: 1, 2, 3\n")
cat("[val] Number of reference dates:", length(reference_dates), "\n")

# ---- Rule 1X: Feature Engineering --------------------------------------------
# Base series validations (sorted / unique / evenly spaced) on the whole series.
if (is.unsorted(df$week)) stop("Series not sorted ascending by week")
if (any(duplicated(df$week))) stop("Duplicate weeks in series")
base_gaps <- as.numeric(diff(df$week))
if (any(base_gaps != 7)) stop("Series weeks not evenly spaced at 7 days")

# value lookup keyed by week for O(1) lag/target access.
val_lookup <- setNames(df$value, as.character(df$week))
val_at <- function(dates) unname(val_lookup[as.character(dates)])

SEASON_WEEKS <- 52.18  # MMWR year length for harmonic period

# epiweek lookup for seasonal harmonics of any calendar week.
ew_of <- function(dates) MMWRweek(dates)$MMWRweek

# Build the feature row(s) for a set of anchor weeks predicting target = anchor + 7h.
# lags are values as of the anchor week; harmonics describe the target week.
make_features <- function(anchor_weeks, h) {
  target_weeks <- anchor_weeks + 7 * h
  ew <- ew_of(target_weeks)
  data.frame(
    lag1 = val_at(anchor_weeks),
    lag2 = val_at(anchor_weeks - 7),
    lag3 = val_at(anchor_weeks - 14),
    lag4 = val_at(anchor_weeks - 21),
    sin1 = sin(2 * pi * 1 * ew / SEASON_WEEKS),
    cos1 = cos(2 * pi * 1 * ew / SEASON_WEEKS),
    sin2 = sin(2 * pi * 2 * ew / SEASON_WEEKS),
    cos2 = cos(2 * pi * 2 * ew / SEASON_WEEKS)
  )
}
FEATURE_NAMES <- c("lag1", "lag2", "lag3", "lag4", "sin1", "cos1", "sin2", "cos2")

cat("\n--- Rule 1X validations (features) ---\n")
cat("[val] feature names:", paste(FEATURE_NAMES, collapse = ", "), "\n")

# ---- Rule 5 setup: coverage levels & quantile ladder -------------------------
level_map <- data.frame(
  level = c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10),
  lo_q  = c(0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45),
  hi_q  = c(0.99, 0.975, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55),
  stringsAsFactors = FALSE
)
quantile_ladder <- c(0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35,
                     0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80,
                     0.85, 0.90, 0.95, 0.975, 0.99)

# ---- Rule 4X: XGBoost hyperparameters ----------------------------------------
XGB_SEED   <- 42
XGB_NROUND <- 300
xgb_params <- list(
  objective        = "reg:quantileerror",
  quantile_alpha   = quantile_ladder,
  eta              = 0.05,
  max_depth        = 3,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  nthread          = 1,
  seed             = XGB_SEED
)
set.seed(XGB_SEED)

# ---- Rules 3X/4X/5X: fit per reference date x horizon, predict, reshape ------
cat("\n--- Rule 4X & 5X validations ---\n")

all_rows <- list()
row_i <- 0

for (r in reference_dates) {
  rd <- as.Date(r, origin = "1970-01-01")

  for (h in 1:3) {
    target_end <- rd + 7 * h

    # Direct-h training set: anchor weeks t with complete features whose target
    # t + 7h is observed AND t + 7h <= rd (no future leakage).
    cand_anchor <- df$week[df$week <= rd]
    feat_all    <- make_features(cand_anchor, h)
    y_target    <- val_at(cand_anchor + 7 * h)
    keep <- stats::complete.cases(feat_all) &
            !is.na(y_target) &
            (cand_anchor + 7 * h) <= rd
    Xtr <- as.matrix(feat_all[keep, FEATURE_NAMES, drop = FALSE])
    ytr <- y_target[keep]

    if (anyNA(Xtr)) stop(paste0("Feature matrix has NA at ref ", format(rd, "%Y-%m-%d"), " h ", h))
    if (nrow(Xtr) < 30) {
      stop(paste0("Only ", nrow(Xtr), " training rows at ref ", format(rd, "%Y-%m-%d"),
                  " horizon ", h, " (need >= 30)"))
    }
    if (!is.numeric(ytr) || any(is.na(ytr))) stop("Response not numeric / has NA")
    if (any(ytr < 0)) stop("Response has negative values")
    if (length(unique(ytr)) <= 1) stop(paste0("Response constant at ref ", format(rd, "%Y-%m-%d"), " h ", h))

    dtrain <- xgb.DMatrix(data = Xtr, label = ytr)
    fit <- xgb.train(params = xgb_params, data = dtrain,
                     nrounds = XGB_NROUND, verbose = 0)
    if (is.null(fit)) stop(paste0("xgb.train returned NULL at ref ", format(rd, "%Y-%m-%d"), " h ", h))

    # Predict the 23 quantiles for the anchor = reference date.
    Xpred <- as.matrix(make_features(rd, h)[, FEATURE_NAMES, drop = FALSE])
    if (anyNA(Xpred)) stop(paste0("Prediction features NA at ref ", format(rd, "%Y-%m-%d"), " h ", h))
    pred <- as.numeric(predict(fit, Xpred))
    if (length(pred) != length(quantile_ladder)) {
      stop(paste0("Expected ", length(quantile_ladder), " quantiles, got ", length(pred),
                  " at ref ", format(rd, "%Y-%m-%d"), " h ", h))
    }
    if (any(!is.finite(pred))) stop(paste0("Non-finite prediction at ref ", format(rd, "%Y-%m-%d"), " h ", h))

    # Quantiles can cross -> sort ascending to enforce a non-decreasing ladder,
    # then clamp at 0 and round to integer counts.
    q_sorted <- sort(pred)
    emit_vec <- round(pmax(q_sorted, 0))

    if (h == 1) {
      cat("[val] ref", format(rd, "%Y-%m-%d"),
          "| n_train(h1) =", nrow(Xtr),
          "| 23 quantiles OK | features no-NA OK | fit OK\n")
    }

    for (qi in seq_along(quantile_ladder)) {
      row_i <- row_i + 1
      all_rows[[row_i]] <- data.frame(
        reference_date  = rd,
        target          = "wk inc flu hosp",
        horizon         = h,
        target_end_date = target_end,
        location        = "US",
        output_type     = "quantile",
        output_type_id  = quantile_ladder[qi],
        value           = as.numeric(emit_vec[qi]),
        stringsAsFactors = FALSE
      )
    }
  }
}

forecasts <- bind_rows(all_rows)

# ---- Rule 5X validations -----------------------------------------------------
cat("\n--- Rule 5X output validations ---\n")

# Non-negative integers.
if (any(forecasts$value < 0) || any(forecasts$value != round(forecasts$value))) {
  stop("value entries must be non-negative integers")
}

# Quantiles non-decreasing across the ladder within each ref/horizon.
nd_ok <- forecasts %>%
  arrange(reference_date, horizon, output_type_id) %>%
  group_by(reference_date, horizon) %>%
  summarise(ok = all(diff(value) >= 0), .groups = "drop")
if (!all(nd_ok$ok)) stop("Quantile ladder is not non-decreasing somewhere")
cat("[val] quantiles non-decreasing: OK\n")

# Exactly the 23 required quantile levels, no missing/extra/dup, per ref/horizon.
lvl_ok <- forecasts %>%
  group_by(reference_date, horizon) %>%
  summarise(ok = setequal(output_type_id, quantile_ladder) &&
                 length(output_type_id) == length(quantile_ladder),
            .groups = "drop")
if (!all(lvl_ok$ok)) stop("Quantile level set mismatch (missing/extra/duplicate)")
cat("[val] all quantile levels present: OK\n")

# Exactly horizons {1,2,3} per reference date (now three fits, one per horizon).
h_ok <- forecasts %>%
  group_by(reference_date) %>%
  summarise(ok = setequal(unique(horizon), c(1, 2, 3)), .groups = "drop")
if (!all(h_ok$ok)) stop("Each reference date must emit exactly horizons 1, 2, 3")
cat("[val] three horizons (one direct fit each): OK\n")

# target_end_date == reference_date + 7 * horizon.
if (any(forecasts$target_end_date != forecasts$reference_date + 7 * forecasts$horizon)) {
  stop("target_end_date does not equal reference_date + 7 * horizon")
}
cat("[val] target dates correct: OK\n")

# ADAPTED: intervals widening is a diagnostic, not a stop (direct per-horizon
# models need not widen monotonically).
width_tbl <- forecasts %>%
  filter(output_type_id %in% c(0.025, 0.975)) %>%
  select(reference_date, horizon, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(w = `0.975` - `0.025`) %>%
  select(reference_date, horizon, w) %>%
  pivot_wider(names_from = horizon, values_from = w, names_prefix = "h")
widen_ok <- with(width_tbl, (h3 >= h2) & (h2 >= h1))
cat(sprintf("[diag] intervals widen with horizon (h3>=h2>=h1): %d/%d reference dates (%.0f%%)\n",
            sum(widen_ok), length(widen_ok), 100 * mean(widen_ok)))

# NOTE: the "median centered / quantiles symmetric" check is intentionally
# omitted -- XGBoost quantile predictions are asymmetric by construction.

# ---- Write FluSight long CSV (XGB_ prefixed) ---------------------------------
forecasts_out <- forecasts %>%
  arrange(reference_date, horizon, match(output_type_id, quantile_ladder)) %>%
  select(reference_date, target, horizon, target_end_date,
         location, output_type, output_type_id, value)

write_csv(forecasts_out, forecast_csv)
if (!file.exists(forecast_csv)) stop("Forecast CSV not written")
cat("\nWrote", nrow(forecasts_out), "rows to", forecast_csv,
    "(", length(reference_dates), "reference dates x 69 rows )\n")

# ---- Rule 6X: Forecast Figure ------------------------------------------------
plot_start <- min(reference_dates)
observed_plot <- df %>%
  filter(week >= plot_start) %>%
  select(week, value) %>%
  arrange(week)

horizon_levels  <- c("1 wk", "2 wk", "3 wk")
horizon_colors  <- c("1 wk" = "#0072B2", "2 wk" = "#E69F00", "3 wk" = "#009E73")

med_df <- forecasts %>%
  filter(output_type_id == 0.5) %>%
  transmute(target_end_date, horizon,
            hlab = factor(paste0(horizon, " wk"), levels = horizon_levels),
            value)

pi_df <- forecasts %>%
  filter(output_type_id %in% c(0.025, 0.975)) %>%
  select(target_end_date, horizon, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  transmute(target_end_date, horizon,
            hlab = factor(paste0(horizon, " wk"), levels = horizon_levels),
            lo = `0.025`, hi = `0.975`)

y_max <- max(c(observed_plot$value, med_df$value, pi_df$hi), na.rm = TRUE) + 10000

x_min <- min(observed_plot$week)
x_max <- max(med_df$target_end_date)
all_x <- seq.Date(x_min, x_max, by = 7)
x_breaks <- all_x[seq(1, length(all_x), by = 4)]

p <- ggplot() +
  geom_ribbon(data = pi_df,
              aes(x = target_end_date, ymin = lo, ymax = hi,
                  fill = hlab, group = hlab),
              alpha = 0.20) +
  geom_line(data = observed_plot, aes(x = week, y = value, color = "Observed"),
            linewidth = 0.9) +
  geom_point(data = observed_plot, aes(x = week, y = value, color = "Observed"),
             size = 1.6) +
  geom_line(data = med_df, aes(x = target_end_date, y = value, color = hlab, group = hlab),
            linewidth = 0.9) +
  geom_point(data = med_df, aes(x = target_end_date, y = value, color = hlab),
             size = 1.6) +
  scale_color_manual(
    name = "Series",
    values = c("Observed" = "black", horizon_colors),
    breaks = c("Observed", horizon_levels),
    labels = c("Observed", "1 wk Forecast Median",
               "2 wk Forecast Median", "3 wk Forecast Median")
  ) +
  scale_fill_manual(
    name = "95% PI",
    values = horizon_colors,
    labels = c("1 wk 95% PI", "2 wk 95% PI", "3 wk 95% PI")
  ) +
  scale_x_date(breaks = x_breaks, date_labels = "%Y-%m-%d") +
  coord_cartesian(ylim = c(0, y_max)) +
  labs(
    x = "Week",
    y = "Weekly Influenza Hospitalizations",
    title = paste0("USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast, ",
                   "XGBoost Quantile Model (2025-26 Season)")
  ) +
  theme_minimal() +
  theme(
    plot.title  = element_text(hjust = 0.5, face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

ggsave(forecast_png, p, dpi = 300, width = 11, height = 6.5)
if (!file.exists(forecast_png)) stop("Forecast figure not written")

cat("\nDone: wrote", forecast_csv, "and", forecast_png, "\n")
