#!/usr/bin/env Rscript

# Activity 3: expanding-window national influenza forecasts in FluSight format.
# Suppress non-essential package startup messages so model diagnostics are easier to read.
suppressPackageStartupMessages({
  # List every R package used for data processing, season assignment, modelling, and graphics.
  required <- c("readr", "dplyr", "tidyr", "lubridate", "ggplot2", "MMWRweek", "forecast")
  # Test whether each required package is installed without attaching it yet.
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  # Stop early with a useful message if the environment cannot run this script.
  if (length(missing)) stop("Required R package(s) not installed: ", paste(missing, collapse = ", "))
  # Attach the packages used below; semicolons allow closely related calls on one line.
  library(readr); library(dplyr); library(tidyr); library(lubridate)
  # Attach plotting, MMWR-week, and forecasting packages.
  library(ggplot2); library(MMWRweek); library(forecast)
})

# Define the cleaned weekly-admissions input file.
input_csv <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
# Define the FluSight CSV that this script will write.
output_csv <- "output/data/03_forecast/flusight_forecasts.csv"
# Define the combined-horizon figure that this script will write.
output_png <- "output/figures/03_forecast/forecast_vs_observed.png"
# Define the detailed, one-panel-per-horizon figure that this script will write.
components_png <- "output/figures/03_forecast/forecast_components_by_horizon.png"
# Define the residual-diagnostics figure for the final expanding-window ARIMA fit.
diagnostics_png <- "output/figures/03_forecast/arima_residual_diagnostics.png"
# Define the machine-readable residual-diagnostics summary file.
diagnostics_csv <- "output/data/03_forecast/arima_residual_diagnostics.csv"
# Create the forecast-data directory, including missing parent directories.
dir.create(dirname(output_csv), recursive = TRUE, showWarnings = FALSE)
# Create the forecast-figure directory, including missing parent directories.
dir.create(dirname(output_png), recursive = TRUE, showWarnings = FALSE)
# Stop before modelling if the cleaned input file is absent.
if (!file.exists(input_csv)) stop("Missing input: ", input_csv)

# Read character data first so parsing failures have the required message.
df <- read_csv(input_csv, col_types = cols(.default = col_character()), show_col_types = FALSE)
# Require precisely the three-column structure produced by Activity 1.
if (!identical(names(df), c("week", "location", "value"))) stop("Required columns missing or out of order")
# Convert the ISO week strings into R Date objects while suppressing parser noise.
df$week <- suppressWarnings(as.Date(df$week))
# Stop when even one week string cannot be interpreted as a calendar date.
if (anyNA(df$week)) stop("The week could not be parsed.")
# Parse admissions strings as numbers, allowing formatted values such as "1,234".
df$value <- suppressWarnings(parse_number(df$value))
# Stop when even one admission value cannot be interpreted as a number.
if (anyNA(df$value)) stop("The value could not be parsed.")
# Explicitly retain location as character data.
df$location <- as.character(df$location)
# This national pipeline must contain US observations only.
if (!all(df$location == "US")) stop("The location could not be parsed.")
# Put all weekly observations in chronological order before any time-series work.
df <- arrange(df, week)
# Reject an empty input file.
if (!nrow(df)) stop("Input has zero rows")
# Reject duplicate weekly endpoints because a time series needs one value per week.
if (anyDuplicated(df$week)) stop("Input contains duplicate weeks")
# Reject missing weeks because ARIMA assumes an evenly spaced series.
if (any(diff(df$week) != 7)) stop("Input weeks are not evenly spaced at seven-day intervals")
# Reject impossible negative hospital-admission counts.
if (any(df$value < 0)) stop("Input contains negative admissions")

# Name the testing season used throughout this activity.
current_season <- "2025-26"
# Store the first calendar year of the current season as an integer.
season_start_year <- 2025L
# Define a helper that finds the first calendar date in a requested MMWR week.
first_mmwr_date <- function(year, target_week) {
  # Generate every actual date in the year so leap years are handled naturally.
  dates <- seq.Date(as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-12-31", year)), by = "day")
  # Calculate the MMWR year and week associated with every generated date.
  m <- MMWRweek(dates)
  # Locate dates that are in both the requested MMWR year and target week.
  hit <- which(m$MMWRyear == year & m$MMWRweek == target_week)
  # Return a missing Date if that requested week cannot be found.
  if (!length(hit)) return(as.Date(NA))
  # Return the first date of the requested MMWR week.
  dates[min(hit)]
}
# Find the first date of MMWR week 40 in 2025.
season_start <- first_mmwr_date(season_start_year, 40)
# Find the first date of MMWR week 20 in 2026.
season_end <- first_mmwr_date(season_start_year + 1L, 20)
# Halt if season boundaries could not be computed.
if (is.na(season_start) || is.na(season_end)) stop("Could not determine current season boundaries")
# Print the start boundary required by the activity instructions.
cat("Season Start Week:", format(season_start), "\n")
# Print the end boundary required by the activity instructions.
cat("Season End Week:", format(season_end), "\n")

# Use calendar year/month rather than MMWRyear for January week-53 assignment.
mmwr <- MMWRweek(df$week)
# Add MMWR week plus calendar year/month fields used for season assignment.
df <- mutate(df, epiweek = mmwr$MMWRweek, cal_year = year(week), cal_month = month(week))
# Define the season-start-year rule for every observed week.
assign_start_year <- function(epiweek, cal_year, cal_month) {
  # Week 40 or later belongs to this calendar year except early-year week-53 dates.
  if (epiweek >= 40) return(if (cal_month <= 8) cal_year - 1L else cal_year)
  # Weeks 1 through 20 belong to the season that started in the prior year.
  if (epiweek <= 20) return(cal_year - 1L)
  # Weeks 21 through 39 are outside an influenza season.
  NA_integer_
}
# Apply the season-start-year helper to every input row.
df$season_start_year <- mapply(assign_start_year, df$epiweek, df$cal_year, df$cal_month)
# Turn each start year into a human-readable YYYY-YY season label.
df$season <- ifelse(is.na(df$season_start_year), NA_character_,
                    paste0(df$season_start_year, "-", substr(df$season_start_year + 1L, 3, 4)))

# Keep only the observations belonging to the current testing season.
test <- filter(df, season == current_season) %>% arrange(week)
# Stop if the source data does not contain testing-season observations.
if (!nrow(test)) stop("No 2025-26 testing-season weeks present")
# Identify the first observed testing-season week.
first_test <- min(test$week)
# Store the complete observed weekly-date vector for reference-date construction.
observed <- df$week
# Keep dates whose one-week-ahead target is observed and belongs to the testing season.
reference_dates <- observed[vapply(observed, function(r) (r + 7) %in% observed && (r + 7) %in% test$week, logical(1))]
# Stop if no reference dates meet the one-week-ahead anchoring rule.
if (!length(reference_dates)) stop("No valid reference dates for the testing period")
# Report the earliest available historical observation.
cat("Training Period start:", format(min(df$week)), "\n")
# Report the first testing-season observation.
cat("Testing Period start:", format(first_test), "\n")
# Report the only allowed forecast horizons.
cat("Forecast horizons: 1, 2, 3\n")
# Print each reference date and its three forecast target dates for auditing.
for (r_raw in reference_dates) {
  # Restore Date class because iterating over a Date vector yields a numeric value.
  r <- as.Date(r_raw, origin = "1970-01-01")
  # Display this origin and its one-, two-, and three-week target endpoints.
  cat("Reference date:", format(r), "targets:", paste(format(r + 7 * (1:3)), collapse = ", "), "\n")
}

levels <- c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)
# Map every central prediction-interval level to its lower and upper FluSight quantiles.
level_map <- tibble(level = levels,
                    lower_q = c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45),
                    upper_q = c(.99, .975, .95, .90, .85, .80, .75, .70, .65, .60, .55))
quantiles <- c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45, .50,
               .55, .60, .65, .70, .75, .80, .85, .90, .95, .975, .99)

# Initialise lists for rounded emitted forecasts and unrounded values used for symmetry checks.
emitted <- list(); raw <- list(); out_i <- 0L; raw_i <- 0L
# Initialise objects that will retain the final rolling fit for residual diagnostics.
last_fit <- NULL; last_train <- NULL; last_reference <- as.Date(NA)
# Refit an expanding-window ARIMA model once at every reference date.
for (r_raw in reference_dates) {
  # Iterating over a Date vector drops its class; restore it explicitly.
  r <- as.Date(r_raw, origin = "1970-01-01")
  # Select all information available on or before this reference date; this prevents leakage.
  train <- filter(df, week <= r) %>% arrange(week)
  # Recheck the weekly index inside each expanding training window.
  if (is.unsorted(train$week) || anyDuplicated(train$week) || any(diff(train$week) != 7)) stop("Invalid training-week index at ", format(r))
  # Extract the ordered admission counts as the univariate ARIMA response.
  y <- as.numeric(train$value)
  # Require a usable, non-negative, nonconstant response series.
  if (anyNA(y) || any(y < 0) || length(unique(y)) < 2) stop("Invalid training response at ", format(r))
  # Select and fit the best-supported non-seasonal ARIMA order automatically.
  fit <- auto.arima(y)
  # Stop if the forecasting package did not return a fitted model.
  if (is.null(fit)) stop("auto.arima() returned NULL at ", format(r))
  # Extract the selected p, d, and q orders for the run log.
  ord <- arimaorder(fit)
  # Print the selected ARIMA order for this rolling refit.
  cat("Fit", format(r), "ARIMA(", ord["p"], ",", ord["d"], ",", ord["q"], ")\n", sep = "")
  # Produce all three horizons and every requested prediction-interval level in one call.
  fc <- forecast(fit, h = 3, level = levels)
  # Save this fit and its training data; after the loop they represent the latest reference date.
  last_fit <- fit; last_train <- train; last_reference <- r
  # Process forecast rows h = 1, h = 2, and h = 3 from that single forecast object.
  for (h in 1:3) {
    # Create a named vector that will hold all 23 quantiles for this horizon.
    q <- setNames(numeric(length(quantiles)), as.character(quantiles))
    # Store the forecast mean as the FluSight median (0.5 quantile).
    q["0.5"] <- as.numeric(fc$mean[h])
    # Extract both interval endpoints for every requested central coverage level.
    for (j in seq_len(nrow(level_map))) {
      # Find the forecast-object column corresponding to this coverage level.
      col <- which(fc$level == level_map$level[j])
      # Stop if that interval was not returned exactly once.
      if (length(col) != 1L) stop("Missing forecast interval level")
      # Put the lower interval endpoint into its mapped lower-tail quantile slot.
      q[as.character(level_map$lower_q[j])] <- fc$lower[h, col]
      # Put the upper interval endpoint into its mapped upper-tail quantile slot.
      q[as.character(level_map$upper_q[j])] <- fc$upper[h, col]
    }
    # Reorder the named quantiles into the official ascending FluSight ladder.
    q <- q[as.character(quantiles)]
    # Reject NA, NaN, or infinite forecast values before emitting output.
    if (any(!is.finite(q))) stop("Non-finite forecast at ", format(r))
    # Write both raw and rounded values one quantile at a time.
    for (k in seq_along(quantiles)) {
      # Advance the index for the raw-forecast validation record.
      raw_i <- raw_i + 1L
      # Save the unrounded quantile so symmetry is checked before clamping changes it.
      raw[[raw_i]] <- tibble(reference_date = r, horizon = h, output_type_id = quantiles[k], raw_value = as.numeric(q[k]))
      # Advance the index for the official FluSight output record.
      out_i <- out_i + 1L
      # Write one long-format FluSight row after flooring at zero and rounding counts.
      emitted[[out_i]] <- tibble(reference_date = r, target = "wk inc flu hosp", horizon = h,
                                 target_end_date = r + 7 * h, location = "US", output_type = "quantile",
                                 output_type_id = quantiles[k], value = as.numeric(round(pmax(q[k], 0))))
    }
  }
}
# Combine all long-format forecast rows and sort them for a stable CSV order.
forecasts <- bind_rows(emitted) %>% arrange(reference_date, horizon, output_type_id)
# Combine all raw forecast rows used only for pre-rounding validation.
raw_forecasts <- bind_rows(raw)

# Confirm all emitted values are whole, non-negative admission counts.
if (any(forecasts$value < 0 | forecasts$value != round(forecasts$value))) stop("Forecast values must be non-negative integers")
# Confirm every target endpoint is exactly the requested number of weeks after its reference date.
if (any(forecasts$target_end_date != forecasts$reference_date + 7 * forecasts$horizon)) stop("target_end_date is incorrect")
# Compute per-reference-date/horizon checks for quantile order and exact quantile membership.
per_horizon <- forecasts %>% group_by(reference_date, horizon) %>% summarise(
  ordered = all(diff(value[order(output_type_id)]) >= 0),
  levels_ok = setequal(output_type_id, quantiles) && n() == 23, .groups = "drop")
if (!all(per_horizon$ordered)) stop("Quantile ladder is not non-decreasing")
if (!all(per_horizon$levels_ok)) stop("Quantile level set mismatch")
# Check that every fitted reference date emitted all and only the three required horizons.
per_ref <- forecasts %>% group_by(reference_date) %>% summarise(ok = setequal(horizon, 1:3), .groups = "drop")
if (!all(per_ref$ok)) stop("Each reference date must emit horizons 1, 2, and 3")
# Reshape the two 95% interval endpoints to calculate each horizon's interval width.
widths <- forecasts %>% filter(output_type_id %in% c(.025, .975)) %>%
  select(reference_date, horizon, output_type_id, value) %>% pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(width = `0.975` - `0.025`) %>% select(reference_date, horizon, width) %>%
  pivot_wider(names_from = horizon, values_from = width, names_prefix = "h")
if (any(widths$h3 < widths$h2 | widths$h2 < widths$h1)) stop("95% intervals do not widen with horizon")
# Reshape raw quantiles wide so paired endpoints can be compared to the raw median.
raw_wide <- raw_forecasts %>% pivot_wider(names_from = output_type_id, values_from = raw_value)
# Validate symmetry around the raw median for every central interval level.
for (j in seq_len(nrow(level_map))) {
  # Convert the two numeric quantile labels into the wide-table column names.
  lo <- as.character(level_map$lower_q[j]); hi <- as.character(level_map$upper_q[j])
  # Stop if lower and upper endpoints are not equidistant from the unrounded median.
  if (any(abs((raw_wide[["0.5"]] - raw_wide[[lo]]) - (raw_wide[[hi]] - raw_wide[["0.5"]])) > 1e-6)) stop("Raw intervals are not symmetric")
}
# Print the activity-required success messages after every validation passes.
cat("[val] quantiles non-decreasing: OK\n[val] all quantile levels present: OK\n[val] target dates correct: OK\n[val] one fit, three horizons: OK\n[val] intervals widen with horizon: OK\n[val] median centered, quantiles symmetric: OK\n")
# Save the completed FluSight-format table to disk.
write_csv(forecasts, output_csv)
# Confirm the CSV write operation created the expected file.
if (!file.exists(output_csv)) stop("Forecast CSV not written")

# Extract residuals from the final available expanding-window ARIMA model.
final_residuals <- as.numeric(residuals(last_fit))
# Use a conventional lag while ensuring the test has enough observations.
ljung_lag <- min(10L, max(1L, floor(length(final_residuals) / 5)))
# Count fitted ARIMA coefficients so the Ljung-Box test accounts for model complexity.
fit_df <- sum(arimaorder(last_fit)[c("p", "q")])
# Test whether residual autocorrelation remains after fitting the ARIMA model.
ljung_box <- Box.test(final_residuals, lag = ljung_lag, type = "Ljung-Box", fitdf = fit_df)
# Save concise numerical diagnostics for later review or reporting.
diagnostics <- tibble(reference_date = last_reference,
                      arima_order = paste0("(", paste(arimaorder(last_fit)[c("p", "d", "q")], collapse = ","), ")"),
                      residual_mean = mean(final_residuals), residual_sd = sd(final_residuals),
                      ljung_box_lag = ljung_lag, ljung_box_statistic = as.numeric(ljung_box$statistic),
                      ljung_box_p_value = ljung_box$p.value)
# Write the diagnostics table alongside the FluSight forecasts.
write_csv(diagnostics, diagnostics_csv)
# Create a two-panel PNG with residuals over time and their autocorrelation function.
png(diagnostics_png, width = 3300, height = 1800, res = 300)
# Place the residual trace and ACF side by side in the output image.
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
# Plot residuals against the weekly dates used by the final training window.
plot(last_train$week, final_residuals, type = "b", pch = 16, col = "#0072B2",
     xlab = "Week", ylab = "Residual", main = "Final ARIMA Residuals")
# Add zero as the reference for unbiased residuals.
abline(h = 0, lty = 2, col = "grey40")
# Plot the residual autocorrelation to reveal remaining temporal structure.
acf(final_residuals, main = "Residual Autocorrelation")
# Close the graphics device so the diagnostics image is saved.
dev.off()
# Confirm both residual-diagnostics outputs exist.
if (!file.exists(diagnostics_csv) || !file.exists(diagnostics_png)) stop("ARIMA diagnostics outputs were not written")
# Print the Ljung-Box p-value; a small value suggests residual structure remains.
cat("Final-fit Ljung-Box p-value:", format(ljung_box$p.value, digits = 4), "\n")

# Plot observed values and median/95% PI for each horizon.
# Keep observed current-season values beginning at the first forecast reference date.
observed_plot <- filter(df, week >= min(reference_dates), season == current_season) %>% select(week, value)
# Keep only the lower 95% endpoint, median, and upper 95% endpoint for plotting.
plot_q <- forecasts %>% filter(output_type_id %in% c(.025, .5, .975)) %>%
  # Retain the fields needed to position and reshape each forecast interval.
  select(horizon, target_end_date, output_type_id, value) %>% pivot_wider(names_from = output_type_id, values_from = value) %>%
  # Create an ordered, readable label for each forecast horizon.
  mutate(horizon_label = factor(paste0(horizon, " wk"), levels = c("1 wk", "2 wk", "3 wk")))
# Define a colorblind-friendly color for each forecast horizon.
cols <- c("1 wk" = "#0072B2", "2 wk" = "#E69F00", "3 wk" = "#009E73")
# Define combined legend labels that describe each horizon's median and interval together.
median_labels <- c("1 wk" = "1 wk forecast (median + 95% PI)", "2 wk" = "2 wk forecast (median + 95% PI)", "3 wk" = "3 wk forecast (median + 95% PI)")
# Attach the matching legend label to every horizon-specific plotting row.
plot_q <- mutate(plot_q,
                 forecast_legend = unname(median_labels[as.character(horizon_label)]))
# Set the y-axis ceiling to 10,000 above the largest observed or upper-interval value.
max_y <- max(c(observed_plot$value, plot_q[["0.975"]]), na.rm = TRUE) + 10000
# Convert all plotted dates to numeric temporarily so one earliest date can be found safely.
date_start <- as.Date(min(c(as.numeric(observed_plot$week), as.numeric(plot_q$target_end_date))), origin = "1970-01-01")
# Convert the final forecast target date back to a Date object.
date_end <- as.Date(max(as.numeric(plot_q$target_end_date)), origin = "1970-01-01")
# Build weekly x-axis tick positions through the final forecast target.
all_dates <- seq.Date(date_start, date_end, by = "week")
# Start an empty ggplot object and add layers from back to front.
p <- ggplot() +
  # Draw translucent 95% prediction-interval ribbons behind all lines.
  geom_ribbon(data = plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`, fill = forecast_legend), alpha = .18) +
  # Draw one colored median line per forecast horizon.
  geom_line(data = plot_q, aes(x = target_end_date, y = `0.5`, color = forecast_legend, linetype = forecast_legend), linewidth = .8) +
  # Add points to make individual median forecasts visible.
  geom_point(data = plot_q, aes(x = target_end_date, y = `0.5`, color = forecast_legend), size = 1.5, show.legend = FALSE) +
  # Draw observed weekly admissions as a solid black line.
  geom_line(data = observed_plot, aes(x = week, y = value, color = "Observed", linetype = "Observed"), linewidth = .9) +
  # Add black points for individual observed admissions.
  geom_point(data = observed_plot, aes(x = week, y = value, color = "Observed"), size = 1.5, show.legend = FALSE) +
  # Map forecast-median and observed line colors to the defined palette.
  scale_color_manual(name = "Element", values = c("Observed" = "black", setNames(cols, unname(median_labels)))) +
  # Use solid line types while retaining legend entries for all line elements.
  scale_linetype_manual(name = "Element", values = c("Observed" = "solid", setNames(rep("solid", 3), unname(median_labels)))) +
  # Map interval-ribbon fills to the same forecast-horizon colors.
  scale_fill_manual(name = "Element", values = c("Observed" = "black", setNames(cols, unname(median_labels)))) +
  # Show every fourth weekly x-axis label in month-day-year format.
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  # Apply the required zero-based y-axis display range without discarding data.
  coord_cartesian(ylim = c(0, max_y)) +
  # Supply the required axis labels and combined-forecast title.
  labs(x = "Week", y = "Weekly Influenza Hospitalizations", title = "USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast (2025-26 Season)") +
  # Start from a clean minimal plotting theme.
  theme_minimal() +
  # Set readable title, axes, background, and legend styling.
  theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
        axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA),
        legend.background = element_rect(fill = "white", color = NA))
# Save the combined-horizon plot at the required 300 DPI.
ggsave(output_png, p, width = 11, height = 6.5, dpi = 300)
# Confirm the combined forecast figure was created.
if (!file.exists(output_png)) stop("Forecast figure not written")

# Detailed companion view: one panel per horizon to remove visual overlap.
# Start a second figure that separates the three forecast horizons into facets.
p_components <- ggplot() +
  # Draw the horizon-specific 95% ribbon in each facet.
  geom_ribbon(data = plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`, fill = horizon_label), alpha = .22, show.legend = FALSE) +
  # Draw the same observed series in black for direct comparison in every facet.
  geom_line(data = observed_plot, aes(x = week, y = value), color = "black", linewidth = .8) +
  # Add points to the observed series in every facet.
  geom_point(data = observed_plot, aes(x = week, y = value), color = "black", size = 1.25) +
  # Draw the median forecast for the facet's horizon.
  geom_line(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), linewidth = .9, show.legend = FALSE) +
  # Add points for each horizon-specific median forecast.
  geom_point(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), size = 1.6, show.legend = FALSE) +
  # Stack one facet per horizon so overlapping elements are separated.
  facet_wrap(~horizon_label, ncol = 1) +
  # Reuse the consistent horizon color palette for lines and ribbons.
  scale_color_manual(values = cols) + scale_fill_manual(values = cols) +
  # Reuse the same every-four-weeks date labels as the combined figure.
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  # Keep the same y-axis range in every panel to support visual comparison.
  coord_cartesian(ylim = c(0, max_y)) +
  # Explain the visual encodings in the subtitle instead of repeating a legend per facet.
  labs(x = "Week", y = "Weekly Influenza Hospitalizations",
       title = "Influenza Forecast Components by Horizon (2025-26 Season)",
       subtitle = "Black: observed admissions; colored line: forecast median; shaded band: 95% prediction interval") +
  # Start again from a clean minimal theme.
  theme_minimal() +
  # Apply readable text, angled dates, and white plotting surfaces.
  theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
        plot.subtitle = element_text(hjust = .5, color = "black"),
        axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
# Save the separated-horizon companion figure at 300 DPI.
ggsave(components_png, p_components, width = 11, height = 11, dpi = 300)
# Confirm the detailed component figure was created.
if (!file.exists(components_png)) stop("Detailed forecast-components figure not written")
# Report successful completion and the number of long-format FluSight rows written.
cat("Wrote ", nrow(forecasts), " forecast rows and two forecast figures.\n", sep = "")
