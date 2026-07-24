#!/usr/bin/env Rscript

# Activity 6: ARIMAX forecasts using upstream surveillance data streams.
#
# This script keeps the Activity 3 expanding-window design and FluSight output
# schema, but fits ARIMA models with external regressors. The selected external
# streams are lagged six weeks based on the report's leakage-free lag/covariate
# screen. This keeps every covariate needed for horizons 1, 2, and 3 observed
# before the reference date.

suppressPackageStartupMessages({
  required <- c("readr", "dplyr", "tidyr", "lubridate", "ggplot2", "MMWRweek", "forecast", "scoringutils")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Required R package(s) not installed: ", paste(missing, collapse = ", "))
  library(readr)
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(ggplot2)
  library(MMWRweek)
  library(forecast)
  library(scoringutils)
})

cleaned_csv <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
baseline_forecast_csv <- "output/data/03_forecast/flusight_forecasts.csv"
ensemble_forecast_csv <- "output/data/05_improvements/ensemble_flusight_forecasts.csv"
wval_csv <- "data/NWSSWVALNational.csv"
nssp_csv <- "data/NSSPNational.csv"
historical_iterations_csv <- "data/time-series-all-historical-iterations.csv"

forecast_csv <- "output/data/06_arimax/arimax_flusight_forecasts.csv"
scores_csv <- "output/data/06_arimax/arimax_forecast_scores.csv"
summary_csv <- "output/data/06_arimax/arimax_summary_by_horizon.csv"
comparison_csv <- "output/data/06_arimax/arimax_model_comparison_by_horizon.csv"
stream_inventory_csv <- "output/data/06_arimax/upstream_data_stream_inventory.csv"
spec_csv <- "output/data/06_arimax/arimax_specification.csv"
calibrated_forecast_csv <- "output/data/06_arimax/arimax_calibrated_flusight_forecasts.csv"
blend_forecast_csv <- "output/data/06_arimax/blend_calibrated_flusight_forecasts.csv"
variant_scores_csv <- "output/data/06_arimax/arimax_extended_variant_scores.csv"
variant_summary_csv <- "output/data/06_arimax/arimax_extended_variant_summary.csv"

stream_png <- "output/figures/06_arimax/surveillance_streams_overview.png"
lag_png <- "output/figures/06_arimax/lagged_covariate_relationships.png"
forecast_png <- "output/figures/06_arimax/arimax_forecast_vs_observed.png"
comparison_png <- "output/figures/06_arimax/arimax_metric_comparison.png"
calibration_png <- "output/figures/06_arimax/rolling_interval_calibration_multipliers.png"
blend_png <- "output/figures/06_arimax/blend_vs_component_medians.png"

dir.create(dirname(forecast_csv), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(stream_png), recursive = TRUE, showWarnings = FALSE)

for (path in c(cleaned_csv, baseline_forecast_csv, wval_csv, nssp_csv, historical_iterations_csv)) {
  if (!file.exists(path)) stop("Missing input: ", path)
}

quantiles <- c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45, .50,
               .55, .60, .65, .70, .75, .80, .85, .90, .95, .975, .99)
required_quantiles <- paste0("q", quantiles)
levels <- c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)
level_map <- tibble(
  level = levels,
  lower_q = c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45),
  upper_q = c(.99, .975, .95, .90, .85, .80, .75, .70, .65, .60, .55)
)

lag_weeks <- 6L
current_season <- "2025-26"
season_start_year <- 2025L

first_mmwr_date <- function(year, target_week) {
  dates <- seq.Date(as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-12-31", year)), by = "day")
  m <- MMWRweek(dates)
  hit <- which(m$MMWRyear == year & m$MMWRweek == target_week)
  if (!length(hit)) return(as.Date(NA))
  dates[min(hit)]
}

assign_start_year <- function(epiweek, cal_year, cal_month) {
  if (epiweek >= 40) return(if (cal_month <= 8) cal_year - 1L else cal_year)
  if (epiweek <= 20) return(cal_year - 1L)
  NA_integer_
}

read_truth <- function(path) {
  truth <- read_csv(path, col_types = cols(.default = col_character()), show_col_types = FALSE) %>%
    mutate(
      week = as.Date(week),
      location = as.character(location),
      value = parse_number(value)
    ) %>%
    select(week, location, value) %>%
    arrange(week)

  if (!identical(names(truth), c("week", "location", "value"))) stop("Cleaned truth columns are invalid.")
  if (anyNA(truth$week)) stop("The week could not be parsed.")
  if (anyNA(truth$value)) stop("The value could not be parsed.")
  if (any(truth$location != "US")) stop("The location could not be parsed.")
  if (anyDuplicated(truth$week) || any(diff(truth$week) != 7)) stop("Truth weeks must be unique and weekly.")
  if (any(truth$value < 0)) stop("Truth values cannot be negative.")

  mmwr <- MMWRweek(truth$week)
  truth$epiweek <- mmwr$MMWRweek
  truth$cal_year <- year(truth$week)
  truth$cal_month <- month(truth$week)
  truth$season_start_year <- mapply(assign_start_year, truth$epiweek, truth$cal_year, truth$cal_month)
  truth$season <- ifelse(
    is.na(truth$season_start_year),
    NA_character_,
    paste0(truth$season_start_year, "-", substr(truth$season_start_year + 1L, 3, 4))
  )
  truth
}

read_wval <- function(path) {
  raw <- read_csv(path, col_types = cols(.default = col_character()), show_col_types = FALSE)
  needed <- c("Pathogen Target", "Week End", "National WVAL")
  if (!all(needed %in% names(raw))) stop("Wastewater CSV missing required columns.")

  raw %>%
    filter(`Pathogen Target` == "Influenza A virus") %>%
    transmute(
      week = as.Date(`Week End`, format = "%m/%d/%Y"),
      wval = parse_number(`National WVAL`)
    ) %>%
    distinct(week, .keep_all = TRUE) %>%
    arrange(week)
}

read_nssp <- function(path) {
  raw <- read_csv(path, col_types = cols(.default = col_character()), show_col_types = FALSE)
  needed <- c("week_end", "geography", "percent_visits_smoothed_influenza")
  if (!all(needed %in% names(raw))) stop("NSSP CSV missing required columns.")

  raw %>%
    filter(geography == "United States") %>%
    transmute(
      week = as.Date(week_end, format = "%m/%d/%Y"),
      nssp_flu = parse_number(percent_visits_smoothed_influenza)
    ) %>%
    distinct(week, .keep_all = TRUE) %>%
    arrange(week)
}

score_quantile_forecasts <- function(fc, truth, model_name) {
  wide <- fc %>%
    inner_join(truth %>% select(week, location, observed = value), by = c("target_end_date" = "week", "location")) %>%
    select(reference_date, horizon, target_end_date, location, observed, output_type_id, value) %>%
    pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
    arrange(reference_date, horizon)

  if (!nrow(wide)) stop("No scorable forecasts for ", model_name)
  if (!all(required_quantiles %in% names(wide))) stop("Missing quantile columns for ", model_name)

  q_levels <- as.numeric(sub("^q", "", required_quantiles))
  q_matrix <- as.matrix(wide[, required_quantiles])
  wis <- scoringutils::wis(wide$observed, q_matrix, q_levels, count_median_twice = TRUE)
  ae <- scoringutils::ae_median_quantile(wide$observed, q_matrix, q_levels)
  coverage <- scoringutils::interval_coverage(wide$observed, q_matrix, q_levels, interval_range = 95)

  scores <- wide %>%
    transmute(
      model = model_name,
      reference_date,
      horizon,
      target_end_date,
      location,
      observed,
      median = q0.5,
      absolute_error = ae,
      squared_error = (median - observed)^2,
      wis = wis,
      lower_95 = q0.025,
      upper_95 = q0.975,
      coverage_95 = coverage,
      width_95 = upper_95 - lower_95
    )

  summary <- scores %>%
    group_by(model, horizon) %>%
    summarise(
      n_forecasts = n(),
      mae = mean(absolute_error),
      rmse = sqrt(mean(squared_error)),
      mean_wis = mean(wis),
      coverage_95 = mean(coverage_95),
      mean_width_95 = mean(width_95),
      .groups = "drop"
    )

  list(scores = scores, summary = summary)
}

validate_flusight_quantiles <- function(fc, model_name) {
  if (any(fc$value < 0 | fc$value != round(fc$value))) {
    stop(model_name, " forecast values must be non-negative integers.")
  }
  if (any(fc$target_end_date != fc$reference_date + 7 * fc$horizon)) {
    stop(model_name, " target dates are invalid.")
  }
  ladder_check <- fc %>%
    group_by(reference_date, horizon) %>%
    summarise(
      ordered = all(diff(value[order(output_type_id)]) >= 0),
      levels_ok = setequal(output_type_id, quantiles) && n() == length(quantiles),
      .groups = "drop"
    )
  if (!all(ladder_check$ordered) || !all(ladder_check$levels_ok)) {
    stop(model_name, " quantile ladder failed validation.")
  }
  invisible(TRUE)
}

calibrate_forecast_intervals <- function(fc, scored, model_name,
                                         calibration_probability = 0.90,
                                         minimum_prior_errors = 6) {
  # Estimate interval widening from prior realized errors only. The median is
  # left unchanged so calibration targets uncertainty rather than central trend.
  wide <- fc %>%
    pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
    arrange(reference_date, horizon)
  prior_error_data <- scored %>%
    mutate(
      half_width_95 = pmax((upper_95 - lower_95) / 2, 1),
      standardized_error_95 = abs(observed - median) / half_width_95
    )

  calibrated_rows <- vector("list", nrow(wide))
  audit_rows <- vector("list", nrow(wide))
  for (i in seq_len(nrow(wide))) {
    current <- wide[i, ]
    prior_errors <- prior_error_data %>%
      filter(horizon == current$horizon, target_end_date <= current$reference_date)

    if (nrow(prior_errors) >= minimum_prior_errors) {
      multiplier <- as.numeric(quantile(prior_errors$standardized_error_95,
                                        probs = calibration_probability,
                                        na.rm = TRUE, names = FALSE, type = 8))
      multiplier <- max(1, multiplier)
      source <- "prior horizon-specific errors"
    } else {
      multiplier <- 1
      source <- "insufficient prior errors"
    }

    adjusted <- current
    median_value <- as.numeric(current$q0.5)
    for (q_name in required_quantiles) {
      if (q_name == "q0.5") {
        adjusted[[q_name]] <- median_value
      } else {
        adjusted[[q_name]] <- round(pmax(median_value + multiplier * (as.numeric(current[[q_name]]) - median_value), 0))
      }
    }
    adjusted[required_quantiles] <- as.list(cummax(as.numeric(adjusted[required_quantiles])))
    calibrated_rows[[i]] <- adjusted
    audit_rows[[i]] <- tibble(
      model = model_name,
      reference_date = current$reference_date,
      horizon = current$horizon,
      n_prior_errors = nrow(prior_errors),
      calibration_probability = calibration_probability,
      interval_multiplier = multiplier,
      calibration_source = source
    )
  }

  calibrated_fc <- bind_rows(calibrated_rows) %>%
    select(reference_date, target, horizon, target_end_date, location, output_type, all_of(required_quantiles)) %>%
    pivot_longer(all_of(required_quantiles), names_to = "output_type_id", values_to = "value") %>%
    mutate(output_type_id = as.numeric(sub("^q", "", output_type_id))) %>%
    arrange(reference_date, horizon, output_type_id)

  validate_flusight_quantiles(calibrated_fc, model_name)
  list(forecasts = calibrated_fc, audit = bind_rows(audit_rows))
}

blend_forecast_distributions <- function(arimax_fc, ensemble_fc, baseline_fc,
                                         weights = c(arimax = 0.50, ensemble = 0.25, arima = 0.25)) {
  # Blend matching quantiles directly, then repair monotonicity after rounding.
  if (abs(sum(weights) - 1) > 1e-8) stop("Blend weights must sum to 1.")
  key_cols <- c("reference_date", "target", "horizon", "target_end_date",
                "location", "output_type", "output_type_id")
  blended <- arimax_fc %>%
    select(all_of(key_cols), arimax_value = value) %>%
    inner_join(ensemble_fc %>% select(all_of(key_cols), ensemble_value = value), by = key_cols) %>%
    inner_join(baseline_fc %>% select(all_of(key_cols), arima_value = value), by = key_cols) %>%
    mutate(value = round(pmax(weights["arimax"] * arimax_value +
                                weights["ensemble"] * ensemble_value +
                                weights["arima"] * arima_value, 0))) %>%
    select(all_of(key_cols), value) %>%
    group_by(reference_date, horizon) %>%
    arrange(output_type_id, .by_group = TRUE) %>%
    mutate(value = cummax(value)) %>%
    ungroup() %>%
    arrange(reference_date, horizon, output_type_id)
  validate_flusight_quantiles(blended, "Blended")
  blended
}

truth <- read_truth(cleaned_csv)
wval <- read_wval(wval_csv)
nssp <- read_nssp(nssp_csv)
historical_iterations <- read_csv(historical_iterations_csv, show_col_types = FALSE)

if (anyNA(wval$week) || anyNA(wval$wval)) stop("Wastewater data could not be parsed.")
if (anyNA(nssp$week)) stop("NSSP week_end could not be parsed.")

wval_lookup <- setNames(wval$wval, as.character(wval$week))
nssp_lookup <- setNames(nssp$nssp_flu, as.character(nssp$week))

season_state <- truth %>%
  arrange(week) %>%
  group_by(season) %>%
  mutate(
    cumulative_admissions = cumsum(value),
    peak_so_far = cummax(value),
    post_peak_decline = as.integer(value < peak_so_far & row_number() > which.max(value))
  ) %>%
  ungroup() %>%
  select(week, cumulative_admissions, post_peak_decline)
cum_lookup <- setNames(season_state$cumulative_admissions, as.character(season_state$week))
post_peak_lookup <- setNames(season_state$post_peak_decline, as.character(season_state$week))

covariates <- truth %>%
  select(week, value) %>%
  left_join(wval, by = "week") %>%
  left_join(nssp, by = "week") %>%
  mutate(mmwr_week = MMWRweek(week)$MMWRweek) %>%
  mutate(
    wval_lag3 = as.numeric(wval_lookup[as.character(week - 7 * lag_weeks)]),
    nssp_flu_lag3 = as.numeric(nssp_lookup[as.character(week - 7 * lag_weeks)]),
    mmwr_sin = sin(2 * pi * mmwr_week / 52),
    mmwr_cos = cos(2 * pi * mmwr_week / 52),
    weeks_since_season_start = pmax(ifelse(mmwr_week >= 40, mmwr_week - 40, mmwr_week + 13), 0),
    cumulative_admissions_lag = as.numeric(cum_lookup[as.character(week - 7 * lag_weeks)]),
    post_peak_decline_lag = as.numeric(post_peak_lookup[as.character(week - 7 * lag_weeks)])
  ) %>%
  arrange(week)

model_df <- truth %>%
  left_join(covariates %>% select(week, wval_lag3, nssp_flu_lag3, mmwr_sin, mmwr_cos,
                                  weeks_since_season_start, cumulative_admissions_lag,
                                  post_peak_decline_lag), by = "week") %>%
  filter(!is.na(wval_lag3), !is.na(nssp_flu_lag3), !is.na(cumulative_admissions_lag),
         !is.na(post_peak_decline_lag)) %>%
  arrange(week)

if (nrow(model_df) < 52) stop("Not enough aligned truth/covariate rows for ARIMAX.")
if (any(diff(model_df$week) != 7)) stop("Aligned ARIMAX rows are not weekly.")

season_start <- first_mmwr_date(season_start_year, 40)
season_end <- first_mmwr_date(season_start_year + 1L, 20)
cat("Season Start Week:", format(season_start), "\n")
cat("Season End Week:", format(season_end), "\n")

test <- truth %>% filter(season == current_season) %>% arrange(week)
if (!nrow(test)) stop("No 2025-26 testing-season weeks present.")
reference_dates <- truth$week[vapply(truth$week, function(r) {
  (r + 7) %in% truth$week && (r + 7) %in% test$week
}, logical(1))]
if (!length(reference_dates)) stop("No valid reference dates for the testing period.")

stream_inventory <- tibble(
  stream = c("Cleaned HRD admissions", "NWSS WVAL", "NSSP influenza ED visits", "Historical truth iterations"),
  source_file = c(cleaned_csv, wval_csv, nssp_csv, historical_iterations_csv),
  rows = c(nrow(truth), nrow(wval), nrow(nssp), nrow(historical_iterations)),
  date_start = as.character(c(
    min(truth$week),
    min(wval$week),
    min(nssp$week),
    min(as.Date(historical_iterations$target_end_date, format = "%m/%d/%Y"), na.rm = TRUE)
  )),
  date_end = as.character(c(
    max(truth$week),
    max(wval$week),
    max(nssp$week),
    max(as.Date(historical_iterations$target_end_date, format = "%m/%d/%Y"), na.rm = TRUE)
  )),
  model_use = c(
    "Forecast target",
    paste0("External regressor, lagged ", lag_weeks, " weeks"),
    paste0("External regressor, lagged ", lag_weeks, " weeks"),
    "Inventory only; real-time truth archive, not an exogenous predictor"
  )
)
write_csv(stream_inventory, stream_inventory_csv)

stream_plot_data <- bind_rows(
  truth %>% transmute(week, stream = "Admissions", value = as.numeric(scale(value))),
  wval %>% transmute(week, stream = "NWSS WVAL", value = as.numeric(scale(wval))),
  nssp %>% transmute(week, stream = "NSSP influenza", value = as.numeric(scale(nssp_flu)))
) %>%
  filter(!is.na(value))

stream_plot <- ggplot(stream_plot_data, aes(x = week, y = value, color = stream)) +
  geom_line(linewidth = .8) +
  scale_color_manual(values = c("Admissions" = "black", "NWSS WVAL" = "#0072B2", "NSSP influenza" = "#D55E00")) +
  labs(
    x = "Week",
    y = "Standardized value",
    color = "Stream",
    title = "Available National Surveillance Streams",
    subtitle = "Series are standardized to compare timing rather than scale."
  ) +
  theme_minimal()
ggsave(stream_png, stream_plot, width = 10, height = 6, dpi = 300)

lag_plot_data <- covariates %>%
  filter(!is.na(wval_lag3), !is.na(nssp_flu_lag3)) %>%
  select(week, admissions = value, wval_lag3, nssp_flu_lag3) %>%
  pivot_longer(c(wval_lag3, nssp_flu_lag3), names_to = "covariate", values_to = "covariate_value") %>%
  mutate(covariate = recode(covariate,
                            wval_lag3 = paste0("NWSS WVAL lagged ", lag_weeks, " weeks"),
                            nssp_flu_lag3 = paste0("NSSP influenza lagged ", lag_weeks, " weeks")))

lag_plot <- ggplot(lag_plot_data, aes(x = covariate_value, y = admissions)) +
  geom_point(alpha = .75, color = "#0072B2") +
  geom_smooth(method = "loess", se = FALSE, color = "#D55E00", linewidth = .9) +
  facet_wrap(~covariate, scales = "free_x") +
  labs(
    x = "Lagged covariate value",
    y = "Weekly influenza hospitalizations",
    title = "Lagged External Regressors vs Admissions",
    subtitle = paste0("The ", lag_weeks, "-week lag prevents future covariate leakage for horizons 1-3.")
  ) +
  theme_minimal()
ggsave(lag_png, lag_plot, width = 10, height = 5.5, dpi = 300)

arimax_xreg_cols <- c("wval_lag3", "nssp_flu_lag3", "mmwr_sin", "mmwr_cos",
                      "weeks_since_season_start", "cumulative_admissions_lag",
                      "post_peak_decline_lag")
emitted <- list()
raw <- list()
out_i <- 0L
raw_i <- 0L
fit_audit <- list()

for (r_raw in reference_dates) {
  r <- as.Date(r_raw, origin = "1970-01-01")
  target_dates <- r + 7 * (1:3)
  train <- model_df %>% filter(week <= r) %>% arrange(week)
  if (nrow(train) < 52) stop("Too few ARIMAX training rows at ", format(r))
  if (max(train$week) > r) stop("Training leakage at ", format(r))

  future_x <- covariates %>%
    filter(week %in% target_dates) %>%
    arrange(week) %>%
    select(all_of(arimax_xreg_cols))
  if (nrow(future_x) != 3 || anyNA(future_x)) stop("Missing future xreg rows at ", format(r))

  train_x <- as.matrix(train %>% select(all_of(arimax_xreg_cols)))
  future_x <- as.matrix(future_x)
  y <- as.numeric(train$value)

  fit <- auto.arima(y, xreg = train_x)
  ord <- arimaorder(fit)
  fc <- forecast(fit, h = 3, xreg = future_x, level = levels)

  fit_audit[[length(fit_audit) + 1L]] <- tibble(
    reference_date = r,
    n_training_weeks = nrow(train),
    training_start = min(train$week),
    training_end = max(train$week),
    arima_order = paste0("(", paste(ord[c("p", "d", "q")], collapse = ","), ")")
  )

  for (h in 1:3) {
    q <- setNames(numeric(length(quantiles)), as.character(quantiles))
    q["0.5"] <- as.numeric(fc$mean[h])
    for (j in seq_len(nrow(level_map))) {
      col <- which(fc$level == level_map$level[j])
      if (length(col) != 1L) stop("Missing forecast interval level.")
      q[as.character(level_map$lower_q[j])] <- fc$lower[h, col]
      q[as.character(level_map$upper_q[j])] <- fc$upper[h, col]
    }
    q <- q[as.character(quantiles)]
    if (any(!is.finite(q))) stop("Non-finite ARIMAX forecast at ", format(r))
    q <- round(pmax(q, 0))
    q <- cummax(q)

    for (k in seq_along(quantiles)) {
      raw_i <- raw_i + 1L
      raw[[raw_i]] <- tibble(reference_date = r, horizon = h, output_type_id = quantiles[k], raw_value = as.numeric(q[k]))
      out_i <- out_i + 1L
      emitted[[out_i]] <- tibble(
        reference_date = r,
        target = "wk inc flu hosp",
        horizon = h,
        target_end_date = r + 7 * h,
        location = "US",
        output_type = "quantile",
        output_type_id = quantiles[k],
        value = as.numeric(q[k])
      )
    }
  }
}

arimax_fc <- bind_rows(emitted) %>% arrange(reference_date, horizon, output_type_id)
fit_audit <- bind_rows(fit_audit)

validate_flusight_quantiles(arimax_fc, "ARIMAX")

write_csv(arimax_fc, forecast_csv)
write_csv(fit_audit, "output/data/06_arimax/arimax_fit_audit.csv")

arimax_scored <- score_quantile_forecasts(arimax_fc, truth, "ARIMAX: surveillance + seasonal")
write_csv(arimax_scored$scores, scores_csv)
write_csv(arimax_scored$summary, summary_csv)

baseline_fc <- read_csv(baseline_forecast_csv, show_col_types = FALSE) %>%
  mutate(
    reference_date = as.Date(reference_date),
    target_end_date = as.Date(target_end_date),
    horizon = as.integer(horizon),
    location = as.character(location),
    output_type_id = as.numeric(output_type_id),
    value = as.numeric(value)
  )
baseline_scored <- score_quantile_forecasts(baseline_fc, truth, "Original ARIMA")

calibrated_arimax <- calibrate_forecast_intervals(
  arimax_fc,
  arimax_scored$scores,
  "Calibrated ARIMAX",
  calibration_probability = 0.90
)
write_csv(calibrated_arimax$forecasts, calibrated_forecast_csv)
write_csv(calibrated_arimax$audit, "output/data/06_arimax/arimax_calibration_audit.csv")
calibrated_arimax_scored <- score_quantile_forecasts(
  calibrated_arimax$forecasts,
  truth,
  "Calibrated ARIMAX"
)

comparison_models <- list(baseline_scored$summary, arimax_scored$summary, calibrated_arimax_scored$summary)
variant_score_tables <- list(arimax_scored$scores, calibrated_arimax_scored$scores)
if (file.exists(ensemble_forecast_csv)) {
  ensemble_fc <- read_csv(ensemble_forecast_csv, show_col_types = FALSE) %>%
    mutate(
      reference_date = as.Date(reference_date),
      target_end_date = as.Date(target_end_date),
      horizon = as.integer(horizon),
      location = as.character(location),
      output_type_id = as.numeric(output_type_id),
      value = as.numeric(value)
    )
  ensemble_scored <- score_quantile_forecasts(ensemble_fc, truth, "Activity 5 ensemble")
  blended_fc <- blend_forecast_distributions(
    arimax_fc,
    ensemble_fc,
    baseline_fc,
    weights = c(arimax = 0.50, ensemble = 0.25, arima = 0.25)
  )
  blended_scored <- score_quantile_forecasts(blended_fc, truth, "Blend: 50% ARIMAX, 25% ensemble, 25% ARIMA")
  calibrated_blend <- calibrate_forecast_intervals(
    blended_fc,
    blended_scored$scores,
    "Calibrated blend",
    calibration_probability = 0.90
  )
  calibrated_blend_scored <- score_quantile_forecasts(calibrated_blend$forecasts, truth, "Calibrated blend")

  write_csv(blended_fc, blend_forecast_csv)
  write_csv(calibrated_blend$forecasts, "output/data/06_arimax/blend_calibrated_final_flusight_forecasts.csv")
  write_csv(calibrated_blend$audit, "output/data/06_arimax/blend_calibration_audit.csv")

  comparison_models <- c(
    comparison_models,
    list(ensemble_scored$summary, blended_scored$summary, calibrated_blend_scored$summary)
  )
  variant_score_tables <- c(
    variant_score_tables,
    list(ensemble_scored$scores, blended_scored$scores, calibrated_blend_scored$scores)
  )
}

comparison <- bind_rows(comparison_models) %>%
  select(model, horizon, n_forecasts, mae, rmse, mean_wis, coverage_95, mean_width_95) %>%
  arrange(horizon, model)
write_csv(comparison, comparison_csv)
write_csv(bind_rows(variant_score_tables), variant_scores_csv)
write_csv(comparison, variant_summary_csv)

specification <- tibble(
  model = "ARIMAX: surveillance + seasonal",
  regressors = paste(c("NWSS National WVAL",
                       "NSSP smoothed influenza ED visit percentage",
                       "MMWR week sine/cosine",
                       "weeks since season start",
                       "lagged current-season cumulative admissions",
                       "lagged post-peak decline indicator"),
                     collapse = "; "),
  regressor_lag_weeks = lag_weeks,
  leakage_rule = paste0("For target week t, use covariates from t - ", 7 * lag_weeks,
                        " days; horizon 3 uses covariates no later than ",
                        7 * (lag_weeks - 3), " days before the reference date."),
  reference_dates = length(reference_dates),
  quantile_levels = length(quantiles)
)
write_csv(specification, spec_csv)

observed_plot <- truth %>%
  filter(week >= min(arimax_fc$reference_date), week <= max(arimax_fc$target_end_date)) %>%
  select(week, observed = value)

calibration_audit <- bind_rows(
  if (file.exists("output/data/06_arimax/arimax_calibration_audit.csv")) {
    read_csv("output/data/06_arimax/arimax_calibration_audit.csv", show_col_types = FALSE)
  },
  if (file.exists("output/data/06_arimax/blend_calibration_audit.csv")) {
    read_csv("output/data/06_arimax/blend_calibration_audit.csv", show_col_types = FALSE)
  }
)
if (nrow(calibration_audit)) {
  calibration_plot <- calibration_audit %>%
    mutate(horizon_label = factor(paste0(horizon, " week"), levels = c("1 week", "2 week", "3 week"))) %>%
    ggplot(aes(x = reference_date, y = interval_multiplier, color = model)) +
    geom_line(linewidth = .75) +
    geom_point(size = 1.4) +
    facet_wrap(~horizon_label, ncol = 1) +
    labs(
      x = "Reference date",
      y = "Rolling interval multiplier",
      color = "Model",
      title = "Rolling Interval Calibration",
      subtitle = "Multipliers are estimated from prior realized errors only; values above 1 widen intervals."
    ) +
    theme_minimal()
  ggsave(calibration_png, calibration_plot, width = 10, height = 8, dpi = 300)
}

if (exists("blended_fc")) {
  median_components <- bind_rows(
    arimax_fc %>% filter(output_type_id == .5) %>% mutate(model = "ARIMAX"),
    blended_fc %>% filter(output_type_id == .5) %>% mutate(model = "Blend"),
    ensemble_fc %>% filter(output_type_id == .5) %>% mutate(model = "Activity 5 ensemble"),
    baseline_fc %>% filter(output_type_id == .5) %>% mutate(model = "Original ARIMA")
  ) %>%
    mutate(horizon_label = factor(paste0(horizon, " week"), levels = c("1 week", "2 week", "3 week")))

  blend_plot <- ggplot() +
    geom_line(data = observed_plot, aes(x = week, y = observed), color = "black", linewidth = .8) +
    geom_line(data = median_components,
              aes(x = target_end_date, y = value, color = model),
              linewidth = .75) +
    facet_wrap(~horizon_label, ncol = 1) +
    scale_color_manual(values = c("ARIMAX" = "#D55E00",
                                  "Blend" = "#CC79A7",
                                  "Activity 5 ensemble" = "#009E73",
                                  "Original ARIMA" = "#0072B2")) +
    labs(
      x = "Target week",
      y = "Weekly influenza hospitalizations",
      color = "Median forecast",
      title = "Blended Median Forecasts vs Components",
      subtitle = "Blend = 50% ARIMAX, 25% Activity 5 ensemble, 25% original ARIMA."
    ) +
    theme_minimal()
  ggsave(blend_png, blend_plot, width = 11, height = 8, dpi = 300)
}

plot_q <- arimax_fc %>%
  filter(output_type_id %in% c(.025, .5, .975)) %>%
  select(horizon, target_end_date, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(horizon_label = factor(paste0(horizon, " wk"), levels = c("1 wk", "2 wk", "3 wk")))
cols <- c("1 wk" = "#0072B2", "2 wk" = "#E69F00", "3 wk" = "#009E73")
all_dates <- seq.Date(min(c(observed_plot$week, plot_q$target_end_date)),
                      max(c(observed_plot$week, plot_q$target_end_date)), by = "week")
max_y <- max(c(observed_plot$observed, plot_q[["0.975"]]), na.rm = TRUE) + 10000

forecast_plot <- ggplot() +
  geom_ribbon(data = plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`, fill = horizon_label),
              alpha = .20, show.legend = FALSE) +
  geom_line(data = observed_plot, aes(x = week, y = observed), color = "black", linewidth = .9) +
  geom_point(data = observed_plot, aes(x = week, y = observed), color = "black", size = 1.25) +
  geom_line(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), linewidth = .85) +
  geom_point(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), size = 1.35, show.legend = FALSE) +
  scale_color_manual(values = cols, name = "Forecast horizon") +
  scale_fill_manual(values = cols) +
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  coord_cartesian(ylim = c(0, max_y)) +
  labs(
    x = "Week",
    y = "Weekly influenza hospitalizations",
    title = "ARIMAX Forecasts Using Wastewater and NSSP Signals",
    subtitle = "Black line: observed admissions; colored lines: ARIMAX medians; bands: 95% prediction intervals."
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(forecast_png, forecast_plot, width = 11, height = 6.5, dpi = 300)

comparison_plot_data <- comparison %>%
  mutate(horizon_label = factor(paste0(horizon, " week"), levels = c("1 week", "2 week", "3 week"))) %>%
  pivot_longer(c(mae, rmse, mean_wis, coverage_95, mean_width_95), names_to = "metric", values_to = "value") %>%
  mutate(metric = recode(metric,
                         mae = "MAE",
                         rmse = "RMSE",
                         mean_wis = "Mean WIS",
                         coverage_95 = "95% coverage",
                         mean_width_95 = "Mean 95% interval width"))

comparison_plot <- ggplot(comparison_plot_data, aes(x = horizon_label, y = value, fill = model)) +
  geom_col(position = position_dodge(width = .75), width = .62) +
  facet_wrap(~metric, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("Original ARIMA" = "#0072B2",
                               "Activity 5 ensemble" = "#009E73",
                               "ARIMAX: surveillance + seasonal" = "#D55E00",
                               "Calibrated ARIMAX" = "#E69F00",
                               "Blend: 50% ARIMAX, 25% ensemble, 25% ARIMA" = "#CC79A7",
                               "Calibrated blend" = "#999999")) +
  labs(
    x = "Forecast horizon",
    y = NULL,
    fill = "Model",
    title = "Original ARIMA vs ARIMAX with Surveillance Covariates",
    subtitle = "Lower is better for MAE, RMSE, and WIS; 95% coverage should be near 95%."
  ) +
  theme_minimal()
ggsave(comparison_png, comparison_plot, width = 11, height = 8, dpi = 300)

expected_outputs <- c(
  forecast_csv, scores_csv, summary_csv, comparison_csv, stream_inventory_csv,
  spec_csv, calibrated_forecast_csv, variant_scores_csv, variant_summary_csv,
  stream_png, lag_png, forecast_png, comparison_png, calibration_png
)
if (exists("blended_fc")) expected_outputs <- c(expected_outputs, blend_forecast_csv, blend_png)
if (!all(file.exists(expected_outputs))) stop("One or more ARIMAX outputs were not written.")

cat("ARIMAX complete.\n")
cat("External regressors: NWSS WVAL lag ", lag_weeks,
    " weeks; NSSP smoothed influenza lag ", lag_weeks, " weeks.\n", sep = "")
print(comparison)
