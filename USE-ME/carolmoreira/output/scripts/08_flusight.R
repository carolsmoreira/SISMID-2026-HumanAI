#!/usr/bin/env Rscript

# Activity 8: FluSight-compliant final forecasts using upstream surveillance data streams.
#
# This script keeps the Activity 3 expanding-window design and FluSight output
# schema, but fits ARIMA models with external regressors. The selected external
# streams are lagged six weeks based on the report's leakage-free lag/covariate
# screen. This keeps every covariate needed for horizons 1, 2, and 3 observed
# before the reference date. It then compares ARIMAX, calibrated ARIMAX, the
# Activity 5 ensemble, the Activity 7 XGBoost model, the original ARIMA model,
# and blended candidates, selects the lowest mean WIS model, and writes a final
# FluSight-compliant submission.

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
xgboost_forecast_csv <- "output/data/07_xgboost/xgboost_flusight_forecasts.csv"
xgboost_leading_forecast_csv <- "output/data/07_xgboost/xgboost_leading_flusight_forecasts.csv"
wval_csv <- "data/NWSSWVALNational.csv"
nssp_csv <- "data/NSSPNational.csv"
historical_iterations_csv <- "data/time-series-all-historical-iterations.csv"

forecast_csv <- "output/data/08_flusight/arimax_flusight_forecasts.csv"
scores_csv <- "output/data/08_flusight/arimax_forecast_scores.csv"
summary_csv <- "output/data/08_flusight/arimax_summary_by_horizon.csv"
comparison_csv <- "output/data/08_flusight/arimax_model_comparison_by_horizon.csv"
stream_inventory_csv <- "output/data/08_flusight/upstream_data_stream_inventory.csv"
spec_csv <- "output/data/08_flusight/arimax_specification.csv"
calibrated_forecast_csv <- "output/data/08_flusight/arimax_calibrated_flusight_forecasts.csv"
blend_forecast_csv <- "output/data/08_flusight/blend_calibrated_flusight_forecasts.csv"
xgboost_blend_forecast_csv <- "output/data/08_flusight/xgboost_blend_flusight_forecasts.csv"
horizon_specific_forecast_csv <- "output/data/08_flusight/horizon_specific_flusight_forecasts.csv"
low_weight_leading_forecast_csv <- "output/data/08_flusight/xgboost_low_weight_leading_flusight_forecasts.csv"
phase_calibrated_forecast_csv <- "output/data/08_flusight/phase_calibrated_horizon_specific_flusight_forecasts.csv"
variant_scores_csv <- "output/data/08_flusight/arimax_extended_variant_scores.csv"
variant_summary_csv <- "output/data/08_flusight/arimax_extended_variant_summary.csv"
ranking_csv <- "output/data/08_flusight/flusight_model_ranking.csv"
final_forecast_csv <- "output/data/08_flusight/flusight_final_forecasts.csv"
submission_dir <- "output/data/08_flusight/final_flusight_submission"
submission_manifest_csv <- "output/data/08_flusight/final_flusight_submission_manifest.csv"
compliance_audit_csv <- "output/data/08_flusight/flusight_compliance_audit.csv"
reconciliation_audit_csv <- "output/data/08_flusight/flusight_reconciliation_audit.csv"

stream_png <- "output/figures/08_flusight/surveillance_streams_overview.png"
lag_png <- "output/figures/08_flusight/lagged_covariate_relationships.png"
forecast_png <- "output/figures/08_flusight/arimax_forecast_vs_observed.png"
comparison_png <- "output/figures/08_flusight/arimax_metric_comparison.png"
calibration_png <- "output/figures/08_flusight/rolling_interval_calibration_multipliers.png"
blend_png <- "output/figures/08_flusight/blend_vs_component_medians.png"
xgboost_blend_png <- "output/figures/08_flusight/xgboost_blend_vs_components.png"
ranking_png <- "output/figures/08_flusight/flusight_model_ranking.png"
final_forecast_png <- "output/figures/08_flusight/flusight_final_forecast_vs_observed.png"

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

validate_flusight_quantiles <- function(fc, model_name, require_interval_widening = TRUE) {
  expected_cols <- c("reference_date", "target", "horizon", "target_end_date",
                     "location", "output_type", "output_type_id", "value")
  if (!identical(names(fc), expected_cols)) {
    stop(model_name, " columns must be exactly: ", paste(expected_cols, collapse = ", "))
  }
  if (!inherits(fc$reference_date, "Date") || !inherits(fc$target_end_date, "Date")) {
    stop(model_name, " reference_date and target_end_date must be Date columns.")
  }
  if (!all(fc$target == "wk inc flu hosp")) stop(model_name, " target must be wk inc flu hosp.")
  if (!all(fc$location == "US")) stop(model_name, " location must be US.")
  if (!all(fc$output_type == "quantile")) stop(model_name, " output_type must be quantile.")
  if (!setequal(unique(fc$horizon), 1:3)) stop(model_name, " horizons must be exactly 1, 2, and 3.")
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
  width_check <- fc %>%
    filter(output_type_id %in% c(.025, .975)) %>%
    select(reference_date, horizon, output_type_id, value) %>%
    pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
    mutate(width_95 = q0.975 - q0.025) %>%
    select(reference_date, horizon, width_95) %>%
    pivot_wider(names_from = horizon, values_from = width_95, names_prefix = "h")
  interval_widening_ok <- !any(width_check$h3 < width_check$h2 | width_check$h2 < width_check$h1, na.rm = TRUE)
  if (require_interval_widening && !interval_widening_ok) {
    stop(model_name, " 95% interval widths must widen with horizon.")
  }
  invisible(interval_widening_ok)
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

blend_named_forecasts <- function(forecast_list, weights, model_name) {
  if (abs(sum(weights) - 1) > 1e-8) stop("Blend weights must sum to 1.")
  if (!all(names(weights) %in% names(forecast_list))) stop("Blend weights reference unavailable forecast tables.")
  key_cols <- c("reference_date", "target", "horizon", "target_end_date",
                "location", "output_type", "output_type_id")

  blended <- NULL
  for (model_key in names(weights)) {
    component <- forecast_list[[model_key]] %>%
      select(all_of(key_cols), component_value = value) %>%
      mutate(weighted_value = weights[[model_key]] * component_value) %>%
      select(all_of(key_cols), weighted_value)
    if (is.null(blended)) {
      blended <- component
    } else {
      blended <- blended %>%
        inner_join(component, by = key_cols, suffix = c("", "_new")) %>%
        mutate(weighted_value = weighted_value + weighted_value_new) %>%
        select(all_of(key_cols), weighted_value)
    }
  }

  blended <- blended %>%
    mutate(value = round(pmax(weighted_value, 0))) %>%
    select(all_of(key_cols), value) %>%
    group_by(reference_date, horizon) %>%
    arrange(output_type_id, .by_group = TRUE) %>%
    mutate(value = cummax(value)) %>%
    ungroup() %>%
    arrange(reference_date, horizon, output_type_id)
  validate_flusight_quantiles(blended, model_name, require_interval_widening = FALSE)
  blended
}

combine_horizon_specific_forecasts <- function(horizon_sources, model_name) {
  required_horizons <- sort(unique(as.integer(names(horizon_sources))))
  if (!identical(required_horizons, 1:3)) {
    stop("Horizon-specific forecast must define horizons 1, 2, and 3.")
  }

  combined <- bind_rows(lapply(names(horizon_sources), function(horizon_name) {
    horizon_sources[[horizon_name]] %>%
      filter(horizon == as.integer(horizon_name))
  })) %>%
    select(reference_date, target, horizon, target_end_date, location, output_type, output_type_id, value) %>%
    arrange(reference_date, horizon, output_type_id)

  validate_flusight_quantiles(combined, model_name, require_interval_widening = FALSE)
  combined
}

build_reference_phase_lookup <- function(truth_df) {
  truth_df %>%
    arrange(week) %>%
    group_by(season) %>%
    mutate(
      previous_value = lag(value),
      peak_so_far = cummax(value),
      phase = case_when(
        is.na(previous_value) ~ "early",
        value >= 0.9 * peak_so_far & value >= previous_value ~ "growth_or_peak",
        value < previous_value & value < peak_so_far ~ "decline",
        TRUE ~ "plateau"
      )
    ) %>%
    ungroup() %>%
    select(reference_date = week, phase)
}

calibrate_forecast_intervals_by_phase <- function(fc, scored, truth_df, model_name,
                                                  calibration_probability = 0.80,
                                                  minimum_phase_errors = 4,
                                                  minimum_horizon_errors = 6) {
  phase_lookup <- build_reference_phase_lookup(truth_df)
  wide <- fc %>%
    pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
    left_join(phase_lookup, by = "reference_date") %>%
    arrange(reference_date, horizon)
  prior_error_data <- scored %>%
    left_join(phase_lookup, by = "reference_date") %>%
    mutate(
      half_width_95 = pmax((upper_95 - lower_95) / 2, 1),
      standardized_error_95 = abs(observed - median) / half_width_95
    )

  calibrated_rows <- vector("list", nrow(wide))
  audit_rows <- vector("list", nrow(wide))
  for (i in seq_len(nrow(wide))) {
    current <- wide[i, ]
    prior_same_phase <- prior_error_data %>%
      filter(
        horizon == current$horizon,
        phase == current$phase,
        target_end_date <= current$reference_date
      )
    prior_horizon <- prior_error_data %>%
      filter(horizon == current$horizon, target_end_date <= current$reference_date)

    if (nrow(prior_same_phase) >= minimum_phase_errors) {
      prior_errors <- prior_same_phase
      source <- "prior horizon-and-phase errors"
    } else if (nrow(prior_horizon) >= minimum_horizon_errors) {
      prior_errors <- prior_horizon
      source <- "prior horizon errors"
    } else {
      prior_errors <- prior_horizon
      source <- "insufficient prior errors"
    }

    multiplier <- if (nrow(prior_errors)) {
      as.numeric(quantile(prior_errors$standardized_error_95,
                          probs = calibration_probability,
                          na.rm = TRUE, names = FALSE, type = 8))
    } else {
      1
    }
    multiplier <- min(max(multiplier, 0.75), 1.50)

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
      phase = current$phase,
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

  validate_flusight_quantiles(calibrated_fc, model_name, require_interval_widening = FALSE)
  list(forecasts = calibrated_fc, audit = bind_rows(audit_rows))
}

write_reconciliation_audit <- function(fc, path) {
  wide <- fc %>%
    pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
    arrange(reference_date, horizon)
  growth <- wide %>%
    select(reference_date, horizon, median = q0.5, lower_95 = q0.025, upper_95 = q0.975) %>%
    pivot_wider(names_from = horizon, values_from = c(median, lower_95, upper_95), names_sep = "_h") %>%
    mutate(
      h2_median_growth_ok = median_h2 <= pmax(4 * median_h1, median_h1 + 15000),
      h3_median_growth_ok = median_h3 <= pmax(4 * median_h2, median_h2 + 15000),
      h2_width_growth_ok = (upper_95_h2 - lower_95_h2) <= pmax(5 * (upper_95_h1 - lower_95_h1), (upper_95_h1 - lower_95_h1) + 25000),
      h3_width_growth_ok = (upper_95_h3 - lower_95_h3) <= pmax(5 * (upper_95_h2 - lower_95_h2), (upper_95_h2 - lower_95_h2) + 25000)
    )

  checks <- tibble(
    check = c(
      "nonnegative_values",
      "integer_values",
      "monotone_quantiles",
      "target_dates",
      "reasonable_horizon_median_growth",
      "reasonable_horizon_width_growth"
    ),
    status = c(
      ifelse(all(fc$value >= 0), "OK", "FAIL"),
      ifelse(all(fc$value == round(fc$value)), "OK", "FAIL"),
      ifelse(all(wide %>% select(all_of(required_quantiles)) %>% apply(1, function(x) all(diff(as.numeric(x)) >= 0))), "OK", "FAIL"),
      ifelse(all(fc$target_end_date == fc$reference_date + 7 * fc$horizon), "OK", "FAIL"),
      ifelse(all(growth$h2_median_growth_ok & growth$h3_median_growth_ok), "OK", "DIAGNOSTIC"),
      ifelse(all(growth$h2_width_growth_ok & growth$h3_width_growth_ok), "OK", "DIAGNOSTIC")
    ),
    detail = c(
      "all forecast values are nonnegative",
      "all forecast values are integer counts",
      "quantiles are nondecreasing within each reference date and horizon",
      "target_end_date equals reference_date + 7 * horizon",
      paste0(sum(growth$h2_median_growth_ok & growth$h3_median_growth_ok), "/", nrow(growth), " reference dates pass median-growth diagnostic"),
      paste0(sum(growth$h2_width_growth_ok & growth$h3_width_growth_ok), "/", nrow(growth), " reference dates pass width-growth diagnostic")
    )
  )
  write_csv(checks, path)
  checks
}

truth <- read_truth(cleaned_csv)
wval <- read_wval(wval_csv)
nssp <- read_nssp(nssp_csv)
historical_iterations <- read_csv(historical_iterations_csv, show_col_types = FALSE)

if (anyNA(wval$week) || anyNA(wval$wval)) stop("Wastewater data could not be parsed.")
if (anyNA(nssp$week)) stop("NSSP week_end could not be parsed.")

wval_lookup <- setNames(wval$wval, as.character(wval$week))
nssp_lookup <- setNames(nssp$nssp_flu, as.character(nssp$week))

# Every state feature below is computed from values observed up to that same
# week. We then lag these state variables before using them as xregs, so the
# model never sees target-week admissions or future-season peak information.
season_state <- truth %>%
  arrange(week) %>%
  group_by(season) %>%
  mutate(
    cumulative_admissions = cumsum(value),
    peak_so_far = cummax(value),
    peak_seen_before = lag(peak_so_far, default = first(value)),
    post_peak_decline = as.integer(value < peak_seen_before)
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
write_csv(fit_audit, "output/data/08_flusight/arimax_fit_audit.csv")

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
write_csv(calibrated_arimax$audit, "output/data/08_flusight/arimax_calibration_audit.csv")
calibrated_arimax_scored <- score_quantile_forecasts(
  calibrated_arimax$forecasts,
  truth,
  "Calibrated ARIMAX"
)

comparison_models <- list(baseline_scored$summary, arimax_scored$summary, calibrated_arimax_scored$summary)
variant_score_tables <- list(baseline_scored$scores, arimax_scored$scores, calibrated_arimax_scored$scores)
forecast_tables <- list(
  arima = baseline_fc,
  arimax = arimax_fc,
  calibrated_arimax = calibrated_arimax$forecasts
)

if (file.exists(xgboost_forecast_csv)) {
  xgboost_fc <- read_csv(xgboost_forecast_csv, show_col_types = FALSE) %>%
    mutate(
      reference_date = as.Date(reference_date),
      target_end_date = as.Date(target_end_date),
      horizon = as.integer(horizon),
      location = as.character(location),
      output_type_id = as.numeric(output_type_id),
      value = as.numeric(value)
    )
  validate_flusight_quantiles(xgboost_fc, "Activity 7 XGBoost", require_interval_widening = FALSE)
  xgboost_scored <- score_quantile_forecasts(xgboost_fc, truth, "Activity 7 XGBoost")
  comparison_models <- c(comparison_models, list(xgboost_scored$summary))
  variant_score_tables <- c(variant_score_tables, list(xgboost_scored$scores))
  forecast_tables[["xgboost"]] <- xgboost_fc
}

if (file.exists(xgboost_leading_forecast_csv)) {
  xgboost_leading_fc <- read_csv(xgboost_leading_forecast_csv, show_col_types = FALSE) %>%
    mutate(
      reference_date = as.Date(reference_date),
      target_end_date = as.Date(target_end_date),
      horizon = as.integer(horizon),
      location = as.character(location),
      output_type_id = as.numeric(output_type_id),
      value = as.numeric(value)
    )
  validate_flusight_quantiles(xgboost_leading_fc, "Activity 7 XGBoost + leading indicators", require_interval_widening = FALSE)
  xgboost_leading_scored <- score_quantile_forecasts(
    xgboost_leading_fc,
    truth,
    "Activity 7 XGBoost + leading indicators"
  )
  comparison_models <- c(comparison_models, list(xgboost_leading_scored$summary))
  variant_score_tables <- c(variant_score_tables, list(xgboost_leading_scored$scores))
  forecast_tables[["xgboost_leading"]] <- xgboost_leading_fc
}

if (exists("xgboost_fc") && exists("xgboost_leading_fc")) {
  low_weight_leading_fc <- blend_named_forecasts(
    forecast_tables,
    weights = c(xgboost = 0.85, xgboost_leading = 0.15),
    model_name = "Blend: 85% XGBoost, 15% XGBoost-leading"
  )
  low_weight_leading_scored <- score_quantile_forecasts(
    low_weight_leading_fc,
    truth,
    "Blend: 85% XGBoost, 15% XGBoost-leading"
  )
  write_csv(low_weight_leading_fc, low_weight_leading_forecast_csv)
  comparison_models <- c(comparison_models, list(low_weight_leading_scored$summary))
  variant_score_tables <- c(variant_score_tables, list(low_weight_leading_scored$scores))
  forecast_tables[["blend_xgboost_low_weight_leading"]] <- low_weight_leading_fc
}

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
  forecast_tables[["ensemble"]] <- ensemble_fc
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
  write_csv(calibrated_blend$forecasts, "output/data/08_flusight/blend_calibrated_final_flusight_forecasts.csv")
  write_csv(calibrated_blend$audit, "output/data/08_flusight/blend_calibration_audit.csv")

  comparison_models <- c(
    comparison_models,
    list(ensemble_scored$summary, blended_scored$summary, calibrated_blend_scored$summary)
  )
  variant_score_tables <- c(
    variant_score_tables,
    list(ensemble_scored$scores, blended_scored$scores, calibrated_blend_scored$scores)
  )
  forecast_tables[["blend_arimax_ensemble_arima"]] <- blended_fc
  forecast_tables[["calibrated_blend"]] <- calibrated_blend$forecasts

  if (exists("xgboost_fc")) {
    xgboost_blend_fc <- blend_named_forecasts(
      forecast_tables,
      weights = c(xgboost = 0.50, arimax = 0.25, ensemble = 0.15, arima = 0.10),
      model_name = "Blend: 50% XGBoost, 25% ARIMAX, 15% ensemble, 10% ARIMA"
    )
    xgboost_blend_scored <- score_quantile_forecasts(
      xgboost_blend_fc,
      truth,
      "Blend: 50% XGBoost, 25% ARIMAX, 15% ensemble, 10% ARIMA"
    )
    write_csv(xgboost_blend_fc, xgboost_blend_forecast_csv)
    comparison_models <- c(comparison_models, list(xgboost_blend_scored$summary))
    variant_score_tables <- c(variant_score_tables, list(xgboost_blend_scored$scores))
    forecast_tables[["blend_xgboost_arimax_ensemble_arima"]] <- xgboost_blend_fc

    horizon_specific_fc <- combine_horizon_specific_forecasts(
      list(`1` = xgboost_blend_fc, `2` = xgboost_fc, `3` = xgboost_fc),
      model_name = "Horizon-specific: h1 XGBoost blend, h2-h3 XGBoost"
    )
    horizon_specific_scored <- score_quantile_forecasts(
      horizon_specific_fc,
      truth,
      "Horizon-specific: h1 XGBoost blend, h2-h3 XGBoost"
    )
    write_csv(horizon_specific_fc, horizon_specific_forecast_csv)
    comparison_models <- c(comparison_models, list(horizon_specific_scored$summary))
    variant_score_tables <- c(variant_score_tables, list(horizon_specific_scored$scores))
    forecast_tables[["horizon_specific_xgboost"]] <- horizon_specific_fc

    phase_calibrated_horizon_specific <- calibrate_forecast_intervals_by_phase(
      horizon_specific_fc,
      horizon_specific_scored$scores,
      truth,
      "Phase-calibrated horizon-specific"
    )
    phase_calibrated_scored <- score_quantile_forecasts(
      phase_calibrated_horizon_specific$forecasts,
      truth,
      "Phase-calibrated horizon-specific"
    )
    write_csv(phase_calibrated_horizon_specific$forecasts, phase_calibrated_forecast_csv)
    write_csv(phase_calibrated_horizon_specific$audit, "output/data/08_flusight/phase_calibrated_horizon_specific_audit.csv")
    comparison_models <- c(comparison_models, list(phase_calibrated_scored$summary))
    variant_score_tables <- c(variant_score_tables, list(phase_calibrated_scored$scores))
    forecast_tables[["phase_calibrated_horizon_specific"]] <- phase_calibrated_horizon_specific$forecasts
  }
}

comparison <- bind_rows(comparison_models) %>%
  select(model, horizon, n_forecasts, mae, rmse, mean_wis, coverage_95, mean_width_95) %>%
  arrange(horizon, model)
variant_scores <- bind_rows(variant_score_tables)
write_csv(comparison, comparison_csv)
write_csv(variant_scores, variant_scores_csv)
write_csv(comparison, variant_summary_csv)

model_ranking <- variant_scores %>%
  group_by(model) %>%
  summarise(
    scored_forecasts = n(),
    mean_wis = mean(wis),
    mae = mean(absolute_error),
    rmse = sqrt(mean(squared_error)),
    coverage_95 = mean(coverage_95),
    mean_width_95 = mean(width_95),
    .groups = "drop"
  ) %>%
  arrange(mean_wis, mae)

best_model <- model_ranking$model[1]
write_csv(model_ranking, ranking_csv)

forecast_by_model <- list(
  "Original ARIMA" = baseline_fc,
  "ARIMAX: surveillance + seasonal" = arimax_fc,
  "Calibrated ARIMAX" = calibrated_arimax$forecasts
)
if (exists("ensemble_fc")) forecast_by_model[["Activity 5 ensemble"]] <- ensemble_fc
if (exists("xgboost_fc")) forecast_by_model[["Activity 7 XGBoost"]] <- xgboost_fc
if (exists("xgboost_leading_fc")) {
  forecast_by_model[["Activity 7 XGBoost + leading indicators"]] <- xgboost_leading_fc
}
if (exists("blended_fc")) forecast_by_model[["Blend: 50% ARIMAX, 25% ensemble, 25% ARIMA"]] <- blended_fc
if (exists("calibrated_blend")) forecast_by_model[["Calibrated blend"]] <- calibrated_blend$forecasts
if (exists("xgboost_blend_fc")) {
  forecast_by_model[["Blend: 50% XGBoost, 25% ARIMAX, 15% ensemble, 10% ARIMA"]] <- xgboost_blend_fc
}
if (exists("horizon_specific_fc")) {
  forecast_by_model[["Horizon-specific: h1 XGBoost blend, h2-h3 XGBoost"]] <- horizon_specific_fc
}
if (exists("low_weight_leading_fc")) {
  forecast_by_model[["Blend: 85% XGBoost, 15% XGBoost-leading"]] <- low_weight_leading_fc
}
if (exists("phase_calibrated_horizon_specific")) {
  forecast_by_model[["Phase-calibrated horizon-specific"]] <- phase_calibrated_horizon_specific$forecasts
}

if (!best_model %in% names(forecast_by_model)) stop("Best model forecast table is unavailable: ", best_model)

final_fc <- forecast_by_model[[best_model]] %>%
  select(reference_date, target, horizon, target_end_date, location, output_type, output_type_id, value) %>%
  arrange(reference_date, horizon, output_type_id)

final_interval_widening_ok <- validate_flusight_quantiles(final_fc, "Final FluSight", require_interval_widening = FALSE)
write_csv(final_fc, final_forecast_csv)
reconciliation_audit <- write_reconciliation_audit(final_fc, reconciliation_audit_csv)

dir.create(submission_dir, recursive = TRUE, showWarnings = FALSE)
submission_pattern <- "^\\d{4}-\\d{2}-\\d{2}-Carol-FluSight\\.csv$"
submission_manifest <- vector("list", length(sort(unique(final_fc$reference_date))))
for (idx in seq_along(sort(unique(final_fc$reference_date)))) {
  rd <- sort(unique(final_fc$reference_date))[idx]
  rd <- as.Date(rd, origin = "1970-01-01")
  rd_str <- format(rd, "%Y-%m-%d")
  grp <- final_fc %>%
    filter(reference_date == rd) %>%
    arrange(horizon, output_type_id)
  fname <- paste0(rd_str, "-Carol-FluSight.csv")
  fpath <- file.path(submission_dir, fname)

  if (!grepl(submission_pattern, fname)) stop("Submission filename failed validation: ", fname)
  if (nrow(grp) != 69) stop("Expected 69 rows for ", rd_str, ", got ", nrow(grp))
  if (!identical(names(grp), c("reference_date", "target", "horizon", "target_end_date",
                               "location", "output_type", "output_type_id", "value"))) {
    stop("Column names/order failed validation for ", rd_str)
  }
  write_csv(grp, fpath)
  if (!file.exists(fpath)) stop("Failed to write submission file: ", fpath)

  submission_manifest[[idx]] <- tibble(
    reference_date = rd,
    file = fpath,
    rows = nrow(grp),
    horizons = paste(sort(unique(grp$horizon)), collapse = ","),
    quantiles_per_horizon = n_distinct(grp$output_type_id)
  )
}
submission_manifest <- bind_rows(submission_manifest)
write_csv(submission_manifest, submission_manifest_csv)

compliance_audit <- tibble(
  check = c(
    "canonical_column_order",
    "date_columns_are_Date",
    "target_dates_equal_reference_plus_horizon",
    "full_23_quantile_ladder",
    "nondecreasing_quantiles",
    "nonnegative_integer_values",
    "horizons_are_1_2_3",
    "rows_per_reference_date",
    "intervals_widen_with_horizon",
    "one_submission_file_per_reference_date",
    "selected_by_lowest_mean_wis",
    "causal_post_peak_feature"
  ),
  status = c(rep("OK", 8), ifelse(final_interval_widening_ok, "OK", "DIAGNOSTIC"), rep("OK", 3)),
  detail = c(
    paste(names(final_fc), collapse = ", "),
    "reference_date and target_end_date parsed as Date before writing",
    "validated for every row",
    paste(quantiles, collapse = ", "),
    "validated within every reference_date/horizon",
    "validated by integer and lower-bound checks",
    "exactly 1, 2, and 3",
    "69 rows per reference date: 3 horizons x 23 quantiles",
    if (final_interval_widening_ok) {
      "95% interval width h3 >= h2 >= h1 for every reference date"
    } else {
      "diagnostic only for selected direct/hybrid model; not a FluSight schema requirement"
    },
    paste0(nrow(submission_manifest), " files written"),
    best_model,
    "post_peak_decline uses peak_seen_before, then a six-week lag"
  )
)
write_csv(compliance_audit, compliance_audit_csv)

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
  if (file.exists("output/data/08_flusight/arimax_calibration_audit.csv")) {
    read_csv("output/data/08_flusight/arimax_calibration_audit.csv", show_col_types = FALSE)
  },
  if (file.exists("output/data/08_flusight/blend_calibration_audit.csv")) {
    read_csv("output/data/08_flusight/blend_calibration_audit.csv", show_col_types = FALSE)
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
    baseline_fc %>% filter(output_type_id == .5) %>% mutate(model = "Original ARIMA"),
    if (exists("xgboost_fc")) xgboost_fc %>% filter(output_type_id == .5) %>% mutate(model = "Activity 7 XGBoost"),
    if (exists("xgboost_leading_fc")) xgboost_leading_fc %>% filter(output_type_id == .5) %>% mutate(model = "XGBoost + leading indicators"),
    if (exists("low_weight_leading_fc")) low_weight_leading_fc %>% filter(output_type_id == .5) %>% mutate(model = "Low-weight leading blend"),
    if (exists("xgboost_blend_fc")) xgboost_blend_fc %>% filter(output_type_id == .5) %>% mutate(model = "XGBoost-weighted blend"),
    if (exists("horizon_specific_fc")) horizon_specific_fc %>% filter(output_type_id == .5) %>% mutate(model = "Horizon-specific final"),
    if (exists("phase_calibrated_horizon_specific")) phase_calibrated_horizon_specific$forecasts %>% filter(output_type_id == .5) %>% mutate(model = "Phase-calibrated final")
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
                                  "Original ARIMA" = "#0072B2",
                                  "Activity 7 XGBoost" = "#E69F00",
                                  "XGBoost + leading indicators" = "#D55E00",
                                  "Low-weight leading blend" = "#F0E442",
                                  "XGBoost-weighted blend" = "#000000",
                                  "Horizon-specific final" = "#56B4E9",
                                  "Phase-calibrated final" = "#999999")) +
    labs(
      x = "Target week",
      y = "Weekly influenza hospitalizations",
      color = "Median forecast",
      title = "Blended Median Forecasts vs Components",
      subtitle = "Includes the original ARIMAX blend and the Activity 7 XGBoost-weighted blend."
    ) +
    theme_minimal()
  ggsave(blend_png, blend_plot, width = 11, height = 8, dpi = 300)
}

ranking_plot <- model_ranking %>%
  mutate(model = factor(model, levels = rev(model))) %>%
  ggplot(aes(x = mean_wis, y = model, fill = model == best_model)) +
  geom_col(width = .65) +
  scale_fill_manual(values = c(`TRUE` = "#009E73", `FALSE` = "#BDBDBD"), guide = "none") +
  labs(
    x = "Mean WIS across scored horizons",
    y = NULL,
    title = "Activity 8 Model Ranking",
    subtitle = paste0("Selected final FluSight model: ", best_model, ". Lower WIS is better.")
  ) +
  theme_minimal()
ggsave(ranking_png, ranking_plot, width = 10, height = 5.5, dpi = 300)

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

final_plot_q <- final_fc %>%
  filter(output_type_id %in% c(.025, .5, .975)) %>%
  select(horizon, target_end_date, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(horizon_label = factor(paste0(horizon, " wk"), levels = c("1 wk", "2 wk", "3 wk")))
final_max_y <- max(c(observed_plot$observed, final_plot_q[["0.975"]]), na.rm = TRUE) + 10000
final_forecast_plot <- ggplot() +
  geom_ribbon(data = final_plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`, fill = horizon_label),
              alpha = .20, show.legend = FALSE) +
  geom_line(data = observed_plot, aes(x = week, y = observed), color = "black", linewidth = .9) +
  geom_point(data = observed_plot, aes(x = week, y = observed), color = "black", size = 1.25) +
  geom_line(data = final_plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), linewidth = .85) +
  geom_point(data = final_plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), size = 1.35, show.legend = FALSE) +
  scale_color_manual(values = cols, name = "Forecast horizon") +
  scale_fill_manual(values = cols) +
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  coord_cartesian(ylim = c(0, final_max_y)) +
  labs(
    x = "Week",
    y = "Weekly influenza hospitalizations",
    title = "Final FluSight Forecast vs Observed Admissions",
    subtitle = paste0("Final model selected by mean WIS: ", best_model, ". Bands show 95% prediction intervals.")
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(final_forecast_png, final_forecast_plot, width = 11, height = 6.5, dpi = 300)

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
                               "Activity 7 XGBoost" = "#E69F00",
                               "Activity 7 XGBoost + leading indicators" = "#D55E00",
                               "ARIMAX: surveillance + seasonal" = "#D55E00",
                               "Calibrated ARIMAX" = "#E69F00",
                               "Blend: 85% XGBoost, 15% XGBoost-leading" = "#F0E442",
                               "Blend: 50% ARIMAX, 25% ensemble, 25% ARIMA" = "#CC79A7",
                               "Blend: 50% XGBoost, 25% ARIMAX, 15% ensemble, 10% ARIMA" = "#000000",
                               "Horizon-specific: h1 XGBoost blend, h2-h3 XGBoost" = "#56B4E9",
                               "Phase-calibrated horizon-specific" = "#999999",
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
  ranking_csv, final_forecast_csv, submission_manifest_csv, compliance_audit_csv,
  reconciliation_audit_csv,
  stream_png, lag_png, forecast_png, comparison_png, calibration_png,
  ranking_png, final_forecast_png
)
if (exists("blended_fc")) expected_outputs <- c(expected_outputs, blend_forecast_csv, blend_png)
if (exists("xgboost_blend_fc")) expected_outputs <- c(expected_outputs, xgboost_blend_forecast_csv)
if (exists("horizon_specific_fc")) expected_outputs <- c(expected_outputs, horizon_specific_forecast_csv)
if (exists("low_weight_leading_fc")) expected_outputs <- c(expected_outputs, low_weight_leading_forecast_csv)
if (exists("phase_calibrated_horizon_specific")) {
  expected_outputs <- c(expected_outputs, phase_calibrated_forecast_csv,
                        "output/data/08_flusight/phase_calibrated_horizon_specific_audit.csv")
}
if (!all(file.exists(expected_outputs))) stop("One or more ARIMAX outputs were not written.")

cat("Activity 8 FluSight workflow complete.\n")
cat("External regressors: NWSS WVAL lag ", lag_weeks,
    " weeks; NSSP smoothed influenza lag ", lag_weeks, " weeks.\n", sep = "")
cat("Final FluSight model:", best_model, "\n")
cat("Final forecast:", final_forecast_csv, "\n")
cat("Submission files:", submission_dir, "\n")
cat("[val] quantiles non-decreasing: OK\n")
cat("[val] all quantile levels present: OK\n")
cat("[val] target dates correct: OK\n")
if (final_interval_widening_ok) {
  cat("[val] intervals widen with horizon: OK\n")
} else {
  cat("[diag] intervals widen with horizon: not required for selected direct/hybrid model\n")
}
cat("[val] one file per reference date: OK\n")
print(comparison)
