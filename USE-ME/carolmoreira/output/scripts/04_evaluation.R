#!/usr/bin/env Rscript

# Evaluate Activity 3 FluSight forecasts only where the target week is observed.
suppressPackageStartupMessages({
  required <- c("readr", "dplyr", "tidyr", "ggplot2")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Required R package(s) not installed: ", paste(missing, collapse = ", "))
  library(readr); library(dplyr); library(tidyr); library(ggplot2)
})

truth_csv <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
forecast_csv <- "output/data/03_forecast/flusight_forecasts.csv"
score_csv <- "output/data/04_evaluation/forecast_scores.csv"
summary_csv <- "output/data/04_evaluation/evaluation_summary_by_horizon.csv"
evaluation_png <- "output/figures/04_evaluation/evaluation_metrics_by_horizon.png"
uncertainty_png <- "output/figures/04_evaluation/uncertainty_boxplot_by_horizon.png"
# Define outputs that compare ARIMA with simple, leakage-free baseline forecasts.
comparison_csv <- "output/data/04_evaluation/model_comparison_by_horizon.csv"
comparison_png <- "output/figures/04_evaluation/model_comparison_by_horizon.png"
# Define the retrospective interval-calibration recommendations file.
calibration_csv <- "output/data/04_evaluation/interval_calibration_recommendations.csv"
dir.create(dirname(score_csv), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(evaluation_png), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(truth_csv)) stop("Missing observed-data input: ", truth_csv)
if (!file.exists(forecast_csv)) stop("Missing forecast input: ", forecast_csv)

# Load observed admissions and retain the national weekly truth series.
truth <- read_csv(truth_csv, show_col_types = FALSE) %>%
  mutate(week = as.Date(week), value = as.numeric(value)) %>%
  select(week, location, observed = value)
if (anyNA(truth$week) || anyNA(truth$observed) || any(truth$location != "US")) stop("Observed data could not be parsed")

# Load long-format quantile forecasts and convert date columns explicitly.
fc <- read_csv(forecast_csv, show_col_types = FALSE) %>%
  mutate(reference_date = as.Date(reference_date), target_end_date = as.Date(target_end_date),
         horizon = as.integer(horizon), output_type_id = as.numeric(output_type_id), value = as.numeric(value))
if (anyNA(fc$reference_date) || anyNA(fc$target_end_date) || anyNA(fc$value)) stop("Forecast data could not be parsed")

# Keep forecast instances with an observed target; future targets cannot yet be evaluated.
scorable <- fc %>% inner_join(truth, by = c("target_end_date" = "week", "location"))
if (!nrow(scorable)) stop("No forecast target dates have observed outcomes")

# Reshape each reference-date/horizon forecast to one row containing every quantile.
wide <- scorable %>%
  select(reference_date, horizon, target_end_date, location, observed, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value, names_prefix = "q")
required_quantiles <- c("q0.01", "q0.025", "q0.05", "q0.1", "q0.15", "q0.2", "q0.25", "q0.3", "q0.35", "q0.4", "q0.45", "q0.5", "q0.55", "q0.6", "q0.65", "q0.7", "q0.75", "q0.8", "q0.85", "q0.9", "q0.95", "q0.975", "q0.99")
if (!all(required_quantiles %in% names(wide))) stop("Forecasts do not contain the full 23-quantile ladder")

# WIS combines absolute median error with interval scores across all central intervals.
levels <- c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)
lower_names <- c("q0.01", "q0.025", "q0.05", "q0.1", "q0.15", "q0.2", "q0.25", "q0.3", "q0.35", "q0.4", "q0.45")
upper_names <- c("q0.99", "q0.975", "q0.95", "q0.9", "q0.85", "q0.8", "q0.75", "q0.7", "q0.65", "q0.6", "q0.55")
alphas <- 1 - levels / 100

# Calculate one WIS value per forecast instance using raw central-interval scores.
wis <- numeric(nrow(wide))
for (i in seq_len(nrow(wide))) {
  interval_terms <- numeric(length(alphas))
  for (j in seq_along(alphas)) {
    lower <- wide[[lower_names[j]]][i]
    upper <- wide[[upper_names[j]]][i]
    y <- wide$observed[i]
    interval_score <- (upper - lower) + (2 / alphas[j]) * max(lower - y, 0) + (2 / alphas[j]) * max(y - upper, 0)
    interval_terms[j] <- (alphas[j] / 2) * interval_score
  }
  wis[i] <- (0.5 * abs(wide$q0.5[i] - wide$observed[i]) + sum(interval_terms)) / (0.5 + sum(alphas / 2))
}

# Create detailed scores for every scorable forecast, retaining 95% coverage and width.
scores <- wide %>%
  transmute(reference_date, horizon, target_end_date, location, observed,
            median = q0.5,
            absolute_error = abs(median - observed),
            squared_error = (median - observed)^2,
            wis = wis,
            lower_95 = q0.025,
            upper_95 = q0.975,
            coverage_95 = observed >= lower_95 & observed <= upper_95,
            width_95 = upper_95 - lower_95)

# Summarize accuracy, probabilistic score, calibration, and sharpness by horizon.
summary <- scores %>%
  group_by(horizon) %>%
  summarise(n_forecasts = n(),
            mae = mean(absolute_error),
            rmse = sqrt(mean(squared_error)),
            mean_wis = mean(wis),
            coverage_95 = mean(coverage_95),
            mean_width_95 = mean(width_95),
            .groups = "drop")

write_csv(scores, score_csv)
write_csv(summary, summary_csv)
if (!file.exists(score_csv) || !file.exists(summary_csv)) stop("Evaluation outputs were not written")

# Build a date-to-observed-admissions lookup for leakage-free baseline forecasts.
truth_lookup <- setNames(truth$observed, as.character(truth$week))
# Add persistence (last observed value) and seasonal-naive (same week last year) predictions.
baseline_scores <- scores %>%
  mutate(persistence = as.numeric(truth_lookup[as.character(reference_date)]),
         seasonal_naive = as.numeric(truth_lookup[as.character(target_end_date - 364)]))
# Convert all model predictions to long form so they can be scored identically.
comparison_cases <- baseline_scores %>%
  select(reference_date, horizon, target_end_date, observed, arima = median, persistence, seasonal_naive) %>%
  pivot_longer(c(arima, persistence, seasonal_naive), names_to = "model", values_to = "prediction") %>%
  filter(!is.na(prediction)) %>%
  mutate(absolute_error = abs(prediction - observed), squared_error = (prediction - observed)^2,
         model = recode(model, arima = "ARIMA", persistence = "Persistence", seasonal_naive = "Seasonal naive"))
# Summarize median-forecast accuracy for ARIMA and both baselines by horizon.
comparison <- comparison_cases %>%
  group_by(model, horizon) %>%
  summarise(n_forecasts = n(), mae = mean(absolute_error), rmse = sqrt(mean(squared_error)), .groups = "drop")
# Save the model-comparison table for transparent baseline reporting.
write_csv(comparison, comparison_csv)

# Plot MAE comparison so lower bars identify the better point-forecast model.
p_comparison <- ggplot(comparison, aes(x = factor(horizon), y = mae, fill = model)) +
  geom_col(position = position_dodge(width = .75), width = .65) +
  geom_text(aes(label = format(round(mae, 0), big.mark = ",")), position = position_dodge(width = .75), vjust = -.3, size = 3) +
  scale_fill_manual(values = c("ARIMA" = "#0072B2", "Persistence" = "#999999", "Seasonal naive" = "#D55E00")) +
  labs(x = "Forecast horizon (weeks)", y = "Mean absolute error (admissions)", fill = "Model",
       title = "ARIMA Versus Simple Forecast Baselines", subtitle = "Lower MAE is better; all baselines use only information available at the reference date.") +
  theme_minimal() + theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
                          plot.subtitle = element_text(hjust = .5, color = "black"),
                          axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
                          plot.background = element_rect(fill = "white", color = NA), panel.background = element_rect(fill = "white", color = NA))
# Save the comparison figure at report-quality resolution.
ggsave(comparison_png, p_comparison, width = 10, height = 6, dpi = 300)

# Estimate a retrospective multiplier that would make 95% intervals achieve 95% empirical coverage.
# This is diagnostic only: applying it to forecasts requires estimating it from prior, not future, errors.
calibration <- scores %>%
  mutate(half_width_95 = width_95 / 2,
         standardized_error = abs(observed - median) / half_width_95) %>%
  group_by(horizon) %>%
  summarise(n_forecasts = n(), current_coverage_95 = mean(coverage_95),
            recommended_width_multiplier = quantile(standardized_error, probs = .95, na.rm = TRUE, names = FALSE),
            .groups = "drop") %>%
  mutate(target_coverage_95 = .95,
         note = "Retrospective diagnostic; estimate from prior forecast errors before deployment.")
# Write the calibration recommendations without altering the Activity 3 forecasts.
write_csv(calibration, calibration_csv)
# Stop if any new evaluation artefact was not successfully written.
if (!file.exists(comparison_csv) || !file.exists(comparison_png) || !file.exists(calibration_csv)) stop("Baseline comparison or calibration output was not written")

# Reshape the summary so each metric can have its own readable scale and panel.
plot_data <- summary %>%
  mutate(horizon_label = factor(paste0(horizon, " week"), levels = c("1 week", "2 week", "3 week"))) %>%
  select(horizon_label, mae, rmse, mean_wis, coverage_95, mean_width_95) %>%
  pivot_longer(-horizon_label, names_to = "metric", values_to = "value") %>%
  mutate(metric = recode(metric,
                         mae = "Median MAE (admissions)",
                         rmse = "Median RMSE (admissions)",
                         mean_wis = "Mean WIS (lower is better)",
                         coverage_95 = "95% interval coverage",
                         mean_width_95 = "Mean 95% interval width"))

# Plot each evaluation measure separately, avoiding incomparable y-axis scales.
p_eval <- ggplot(plot_data, aes(x = horizon_label, y = value, fill = horizon_label)) +
  geom_col(width = 0.65, show.legend = FALSE) +
  geom_text(aes(label = ifelse(metric == "95% interval coverage", sprintf("%.1f%%", 100 * value), format(round(value, 0), big.mark = ","))),
            vjust = -0.35, size = 3.2) +
  facet_wrap(~metric, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("1 week" = "#0072B2", "2 week" = "#E69F00", "3 week" = "#009E73")) +
  labs(x = "Forecast horizon", y = NULL,
       title = "ARIMA Forecast Evaluation by Horizon",
       subtitle = "Lower values are better for MAE, RMSE, and WIS; 95% coverage should be near 95%.") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = 0.5, color = "black"),
        plot.subtitle = element_text(hjust = 0.5, color = "black"),
        strip.text = element_text(face = "bold", color = "black"),
        axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
ggsave(evaluation_png, p_eval, width = 11, height = 8, dpi = 300)
if (!file.exists(evaluation_png)) stop("Evaluation figure was not written")

# Plot the distribution of 95% prediction-interval widths across reference dates.
# A higher/wider box means that the model expressed more uncertainty at that horizon.
p_uncertainty <- scores %>%
  mutate(horizon_label = factor(paste0(horizon, " week"), levels = c("1 week", "2 week", "3 week"))) %>%
  ggplot(aes(x = horizon_label, y = width_95, fill = horizon_label)) +
  geom_boxplot(width = 0.62, outlier.alpha = 0.7, show.legend = FALSE) +
  stat_summary(fun = mean, geom = "point", shape = 23, size = 3, fill = "white") +
  scale_fill_manual(values = c("1 week" = "#0072B2", "2 week" = "#E69F00", "3 week" = "#009E73")) +
  labs(x = "Forecast horizon", y = "95% prediction-interval width (admissions)",
       title = "Forecast Uncertainty Increases with Horizon",
       subtitle = "Box: middle 50% of forecast intervals; whiskers: typical range; white diamond: mean interval width.") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = 0.5, color = "black"),
        plot.subtitle = element_text(hjust = 0.5, color = "black"),
        axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
ggsave(uncertainty_png, p_uncertainty, width = 9, height = 6, dpi = 300)
if (!file.exists(uncertainty_png)) stop("Uncertainty boxplot was not written")

cat("Evaluated ", nrow(scores), " forecast instances with observed targets.\n", sep = "")
print(summary)
