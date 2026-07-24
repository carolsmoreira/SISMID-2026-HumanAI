#!/usr/bin/env Rscript

# Activity 5: Incremental revision of the Activity 3 forecast pipeline.
#
# Improvement chosen:
#   A simple ARIMA-persistence ensemble.
#
# Rationale:
#   Activity 4 showed that the Activity 3 ARIMA model beats persistence on MAE
#   at every horizon, but persistence is close at longer horizons. A small
#   persistence blend can reduce large misses while preserving most of the ARIMA
#   model's fitted epidemic trajectory. This is a controlled revision because it
#   changes only the forecast distribution emitted by Activity 3; it does not
#   alter the testing period, horizons, target definition, or FluSight schema.
#
# No-look-ahead rule:
#   The persistence value for a reference date is the observed admission count
#   at that same reference date. That value is already known when issuing a
#   forecast from that reference date. No target-week outcome is used to build
#   the improved forecast.

suppressPackageStartupMessages({
  # List every package used below. `scoringutils` is used for the same Activity 4
  # scoring metrics, keeping evaluation comparable across the original and
  # improved forecasts.
  required <- c("readr", "dplyr", "tidyr", "ggplot2", "scoringutils")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Required R package(s) not installed: ", paste(missing, collapse = ", "))
  library(readr); library(dplyr); library(tidyr); library(ggplot2); library(scoringutils)
})

# Read only validated upstream artefacts from Activities 1, 3, and 4.
truth_csv <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
baseline_forecast_csv <- "output/data/03_forecast/flusight_forecasts.csv"
baseline_scores_csv <- "output/data/04_evaluation/forecast_scores.csv"

# Write all new Activity 5 artefacts to step-specific folders. This preserves
# the Activity 3 and Activity 4 baseline outputs for direct comparison.
improved_forecast_csv <- "output/data/05_improvements/ensemble_flusight_forecasts.csv"
improved_scores_csv <- "output/data/05_improvements/ensemble_forecast_scores.csv"
improved_summary_csv <- "output/data/05_improvements/ensemble_summary_by_horizon.csv"
comparison_csv <- "output/data/05_improvements/activity5_model_comparison_by_horizon.csv"
spec_csv <- "output/data/05_improvements/ensemble_specification.csv"
forecast_png <- "output/figures/05_improvements/ensemble_forecast_vs_observed.png"
comparison_png <- "output/figures/05_improvements/activity5_metric_comparison.png"

# Create output directories before writing files.
dir.create(dirname(improved_forecast_csv), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(forecast_png), recursive = TRUE, showWarnings = FALSE)

# Stop early if any upstream input is absent.
if (!file.exists(truth_csv)) stop("Missing observed-data input: ", truth_csv)
if (!file.exists(baseline_forecast_csv)) stop("Missing Activity 3 forecast input: ", baseline_forecast_csv)
if (!file.exists(baseline_scores_csv)) stop("Missing Activity 4 score input: ", baseline_scores_csv)

# Keep the official FluSight quantile ladder explicit. The model emits exactly
# these 23 quantiles for every reference-date/horizon forecast.
quantiles <- c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45, .50,
               .55, .60, .65, .70, .75, .80, .85, .90, .95, .975, .99)
required_quantiles <- paste0("q", quantiles)

# Use a fixed, pre-declared ensemble weight. The improved forecast is:
#   75% Activity 3 ARIMA quantile + 25% persistence center.
# The same persistence shift is applied to every quantile by moving the ARIMA
# distribution center toward the latest observed value while preserving the
# original ARIMA interval spread as much as possible.
persistence_weight <- 0.25
arima_weight <- 1 - persistence_weight

# Load and validate the observed national weekly admissions series.
truth <- read_csv(truth_csv, show_col_types = FALSE) %>%
  mutate(week = as.Date(week), value = as.numeric(value), location = as.character(location)) %>%
  select(week, location, observed = value) %>%
  arrange(week)
if (!identical(names(truth), c("week", "location", "observed"))) stop("Observed data columns are invalid")
if (anyNA(truth$week) || anyNA(truth$observed)) stop("Observed data could not be parsed")
if (any(truth$location != "US")) stop("Observed data must contain only location == 'US'")
if (anyDuplicated(truth$week)) stop("Observed data contains duplicate weeks")
if (any(diff(truth$week) != 7)) stop("Observed weeks are not evenly spaced")
if (any(truth$observed < 0)) stop("Observed admissions cannot be negative")

# Load and validate the Activity 3 FluSight-format forecast file.
baseline_fc <- read_csv(baseline_forecast_csv, show_col_types = FALSE) %>%
  mutate(reference_date = as.Date(reference_date),
         target_end_date = as.Date(target_end_date),
         horizon = as.integer(horizon),
         location = as.character(location),
         output_type = as.character(output_type),
         output_type_id = as.numeric(output_type_id),
         value = as.numeric(value))
expected_fc_cols <- c("reference_date", "target", "horizon", "target_end_date",
                      "location", "output_type", "output_type_id", "value")
if (!identical(names(baseline_fc), expected_fc_cols)) stop("Forecast columns do not match the expected schema")
if (anyNA(baseline_fc$reference_date) || anyNA(baseline_fc$target_end_date) || anyNA(baseline_fc$value)) {
  stop("Forecast dates or values could not be parsed")
}
if (any(baseline_fc$location != "US")) stop("Forecast data must contain only location == 'US'")
if (any(baseline_fc$output_type != "quantile")) stop("Forecast output_type must be 'quantile'")
if (!all(baseline_fc$horizon %in% 1:3)) stop("Forecast horizons must be 1, 2, and 3")
if (any(baseline_fc$target_end_date != baseline_fc$reference_date + 7 * baseline_fc$horizon)) {
  stop("Forecast target_end_date is inconsistent with reference_date and horizon")
}

# Require every reference-date/horizon group to contain the complete quantile
# ladder before reshaping.
ladder_check <- baseline_fc %>%
  group_by(reference_date, horizon) %>%
  summarise(n_rows = n(), ladder_ok = setequal(output_type_id, quantiles), .groups = "drop")
if (any(ladder_check$n_rows != length(quantiles)) || !all(ladder_check$ladder_ok)) {
  stop("Every forecast must contain the full 23-level FluSight quantile ladder")
}

# Reshape Activity 3 forecasts so each row holds all quantiles for one forecast
# instance. This makes it straightforward to shift the forecast distribution.
baseline_wide <- baseline_fc %>%
  arrange(reference_date, horizon, output_type_id) %>%
  select(reference_date, target, horizon, target_end_date, location, output_type,
         output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
  arrange(reference_date, horizon)
if (!all(required_quantiles %in% names(baseline_wide))) stop("Wide forecasts are missing required quantile columns")

# Build a lookup table for the latest observed value at each reference date.
# Missing values would imply that persistence cannot be computed without
# external information, so the script stops instead of guessing.
truth_lookup <- setNames(truth$observed, as.character(truth$week))
baseline_wide <- baseline_wide %>%
  mutate(persistence = as.numeric(truth_lookup[as.character(reference_date)]))
if (anyNA(baseline_wide$persistence)) stop("A reference-date persistence value is missing")

# Create the improved forecast distribution. The median is blended directly:
#   improved_median = 0.75 * ARIMA_median + 0.25 * latest_observed_value.
# Other quantiles keep their original distance from the ARIMA median but are
# shifted around the improved median. `cummax()` repairs any ordering issue that
# can appear after clamping negative lower-tail counts to zero.
improved_rows <- list()
row_i <- 0L
for (i in seq_len(nrow(baseline_wide))) {
  current <- baseline_wide[i, ]
  arima_median <- as.numeric(current[["q0.5"]])
  improved_median <- round(arima_weight * arima_median + persistence_weight * current$persistence)
  adjusted_quantiles <- numeric(length(quantiles))

  for (q_i in seq_along(quantiles)) {
    q_name <- paste0("q", quantiles[q_i])
    arima_quantile <- as.numeric(current[[q_name]])
    adjusted_value <- if (quantiles[q_i] == .5) {
      improved_median
    } else {
      improved_median + (arima_quantile - arima_median)
    }
    adjusted_quantiles[q_i] <- round(pmax(adjusted_value, 0))
  }

  adjusted_quantiles <- cummax(adjusted_quantiles)
  if (any(diff(adjusted_quantiles) < 0)) {
    stop("Improved quantiles are not non-decreasing at reference date ",
         current$reference_date, " horizon ", current$horizon)
  }

  for (q_i in seq_along(quantiles)) {
    row_i <- row_i + 1L
    improved_rows[[row_i]] <- tibble(reference_date = current$reference_date,
                                     target = current$target,
                                     horizon = current$horizon,
                                     target_end_date = current$target_end_date,
                                     location = current$location,
                                     output_type = current$output_type,
                                     output_type_id = quantiles[q_i],
                                     value = adjusted_quantiles[q_i])
  }
}

improved_fc <- bind_rows(improved_rows) %>%
  arrange(reference_date, horizon, output_type_id)

# Retain Activity 3 output validations for the revised forecast table.
if (any(improved_fc$value < 0 | improved_fc$value != round(improved_fc$value))) {
  stop("Improved forecast values must be non-negative integers")
}
if (any(improved_fc$target_end_date != improved_fc$reference_date + 7 * improved_fc$horizon)) {
  stop("Improved target_end_date is incorrect")
}
improved_check <- improved_fc %>%
  group_by(reference_date, horizon) %>%
  summarise(ordered = all(diff(value[order(output_type_id)]) >= 0),
            levels_ok = setequal(output_type_id, quantiles) && n() == length(quantiles),
            .groups = "drop")
if (!all(improved_check$ordered)) stop("Improved quantile ladder is not non-decreasing")
if (!all(improved_check$levels_ok)) stop("Improved quantile level set mismatch")

# Score the improved forecasts using the same Activity 4 scoringutils metrics.
improved_wide <- improved_fc %>%
  inner_join(truth, by = c("target_end_date" = "week", "location")) %>%
  select(reference_date, horizon, target_end_date, location, observed, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q") %>%
  arrange(reference_date, horizon)
if (!all(required_quantiles %in% names(improved_wide))) stop("Scored improved forecasts are missing quantiles")

quantile_levels <- as.numeric(sub("^q", "", required_quantiles))
quantile_predictions <- as.matrix(improved_wide[, required_quantiles])
improved_wis <- scoringutils::wis(improved_wide$observed, quantile_predictions, quantile_levels,
                                  count_median_twice = TRUE)
improved_abs_error <- scoringutils::ae_median_quantile(improved_wide$observed,
                                                       quantile_predictions,
                                                       quantile_levels)
improved_coverage_95 <- scoringutils::interval_coverage(improved_wide$observed,
                                                        quantile_predictions,
                                                        quantile_levels,
                                                        interval_range = 95)

improved_scores <- improved_wide %>%
  transmute(reference_date, horizon, target_end_date, location, observed,
            median = `q0.5`,
            absolute_error = improved_abs_error,
            squared_error = (median - observed)^2,
            wis = improved_wis,
            lower_95 = `q0.025`,
            upper_95 = `q0.975`,
            coverage_95 = improved_coverage_95,
            width_95 = upper_95 - lower_95)

improved_summary <- improved_scores %>%
  group_by(horizon) %>%
  summarise(n_forecasts = n(),
            mae = mean(absolute_error),
            rmse = sqrt(mean(squared_error)),
            mean_wis = mean(wis),
            coverage_95 = mean(coverage_95),
            mean_width_95 = mean(width_95),
            .groups = "drop") %>%
  mutate(model = "ARIMA-persistence ensemble")

# Recompute the original ARIMA summary from Activity 4's detailed score file so
# both models are summarized with the same formulas.
baseline_scores <- read_csv(baseline_scores_csv, show_col_types = FALSE) %>%
  mutate(reference_date = as.Date(reference_date),
         target_end_date = as.Date(target_end_date),
         horizon = as.integer(horizon),
         model = "Original ARIMA")
baseline_summary <- baseline_scores %>%
  group_by(horizon) %>%
  summarise(n_forecasts = n(),
            mae = mean(absolute_error),
            rmse = sqrt(mean(squared_error)),
            mean_wis = mean(wis),
            coverage_95 = mean(coverage_95),
            mean_width_95 = mean(width_95),
            .groups = "drop") %>%
  mutate(model = "Original ARIMA")

model_comparison <- bind_rows(baseline_summary, improved_summary) %>%
  select(model, horizon, n_forecasts, mae, rmse, mean_wis, coverage_95, mean_width_95) %>%
  arrange(horizon, model)

# Save a small specification table so the chosen revision is documented beside
# the numeric outputs.
specification <- tibble(model = "ARIMA-persistence ensemble",
                        arima_weight = arima_weight,
                        persistence_weight = persistence_weight,
                        persistence_definition = "Observed admissions at the forecast reference date",
                        leakage_check = "Only reference-date or earlier observations are used")

# Write all machine-readable Activity 5 artefacts.
write_csv(improved_fc, improved_forecast_csv)
write_csv(improved_scores, improved_scores_csv)
write_csv(select(improved_summary, horizon, n_forecasts, mae, rmse, mean_wis, coverage_95, mean_width_95),
          improved_summary_csv)
write_csv(model_comparison, comparison_csv)
write_csv(specification, spec_csv)
expected_outputs <- c(improved_forecast_csv, improved_scores_csv, improved_summary_csv,
                      comparison_csv, spec_csv)
if (!all(file.exists(expected_outputs))) stop("One or more Activity 5 CSV outputs were not written")

# Plot observed admissions with the improved median forecasts and 95% intervals.
observed_plot <- truth %>%
  filter(week >= min(improved_fc$reference_date), week <= max(improved_fc$target_end_date)) %>%
  select(week, observed)
plot_q <- improved_fc %>%
  filter(output_type_id %in% c(.025, .5, .975)) %>%
  select(horizon, target_end_date, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(horizon_label = factor(paste0(horizon, " wk"), levels = c("1 wk", "2 wk", "3 wk")))
cols <- c("1 wk" = "#0072B2", "2 wk" = "#E69F00", "3 wk" = "#009E73")
all_dates <- seq.Date(min(c(observed_plot$week, plot_q$target_end_date)),
                      max(c(observed_plot$week, plot_q$target_end_date)), by = "week")
max_y <- max(c(observed_plot$observed, plot_q[["0.975"]]), na.rm = TRUE) + 10000

p_forecast <- ggplot() +
  geom_ribbon(data = plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`,
                                 fill = horizon_label), alpha = .20, show.legend = FALSE) +
  geom_line(data = observed_plot, aes(x = week, y = observed), color = "black", linewidth = .9) +
  geom_point(data = observed_plot, aes(x = week, y = observed), color = "black", size = 1.35) +
  geom_line(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label),
            linewidth = .85) +
  geom_point(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label),
             size = 1.45, show.legend = FALSE) +
  scale_color_manual(values = cols, name = "Forecast horizon") +
  scale_fill_manual(values = cols) +
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  coord_cartesian(ylim = c(0, max_y)) +
  labs(x = "Week", y = "Weekly Influenza Hospitalizations",
       title = "ARIMA-Persistence Ensemble Forecasts by Horizon",
       subtitle = "Black line: observed admissions; colored lines: ensemble medians; bands: 95% prediction intervals") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
        plot.subtitle = element_text(hjust = .5, color = "black"),
        axis.text = element_text(color = "black"),
        axis.title = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
ggsave(forecast_png, p_forecast, width = 11, height = 6.5, dpi = 300)

# Plot the required Activity 5 metrics side by side for original and improved
# forecasts. Separate facets avoid combining incompatible metric scales.
comparison_plot_data <- model_comparison %>%
  mutate(horizon_label = factor(paste0(horizon, " week"), levels = c("1 week", "2 week", "3 week"))) %>%
  select(model, horizon_label, mae, rmse, mean_wis, coverage_95, mean_width_95) %>%
  pivot_longer(c(mae, rmse, mean_wis, coverage_95, mean_width_95),
               names_to = "metric", values_to = "value") %>%
  mutate(metric = recode(metric,
                         mae = "MAE",
                         rmse = "RMSE",
                         mean_wis = "Mean WIS",
                         coverage_95 = "95% coverage",
                         mean_width_95 = "Mean 95% interval width"))

p_comparison <- ggplot(comparison_plot_data,
                       aes(x = horizon_label, y = value, fill = model)) +
  geom_col(position = position_dodge(width = .75), width = .62) +
  facet_wrap(~metric, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("Original ARIMA" = "#0072B2",
                               "ARIMA-persistence ensemble" = "#D55E00")) +
  labs(x = "Forecast horizon", y = NULL, fill = "Model",
       title = "Activity 5 Evaluation: Original vs Ensemble",
       subtitle = "Lower is better for MAE, RMSE, and WIS; 95% coverage should be close to 95%.") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
        plot.subtitle = element_text(hjust = .5, color = "black"),
        strip.text = element_text(face = "bold", color = "black"),
        axis.text = element_text(color = "black"),
        axis.title = element_text(color = "black"),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
ggsave(comparison_png, p_comparison, width = 11, height = 8, dpi = 300)
if (!file.exists(forecast_png) || !file.exists(comparison_png)) {
  stop("One or more Activity 5 figures were not written")
}

# Print the model specification and held-out comparison for the run log.
cat("Activity 5 model specification: 75% Activity 3 ARIMA distribution + 25% persistence center.\n")
cat("Persistence input: observed admissions at the reference date only; no target outcomes are used.\n")
print(model_comparison)
cat("Wrote Activity 5 forecasts, scores, comparison tables, specification file, and figures.\n")
