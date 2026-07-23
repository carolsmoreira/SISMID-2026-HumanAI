#!/usr/bin/env Rscript

# Activity 3: expanding-window national influenza forecasts in FluSight format.
suppressPackageStartupMessages({
  required <- c("readr", "dplyr", "tidyr", "lubridate", "ggplot2", "MMWRweek", "forecast")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Required R package(s) not installed: ", paste(missing, collapse = ", "))
  library(readr); library(dplyr); library(tidyr); library(lubridate)
  library(ggplot2); library(MMWRweek); library(forecast)
})

input_csv <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
output_csv <- "output/data/03_forecast/flusight_forecasts.csv"
output_png <- "output/figures/03_forecast/forecast_vs_observed.png"
components_png <- "output/figures/03_forecast/forecast_components_by_horizon.png"
dir.create(dirname(output_csv), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(output_png), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(input_csv)) stop("Missing input: ", input_csv)

# Read character data first so parsing failures have the required message.
df <- read_csv(input_csv, col_types = cols(.default = col_character()), show_col_types = FALSE)
if (!identical(names(df), c("week", "location", "value"))) stop("Required columns missing or out of order")
df$week <- suppressWarnings(as.Date(df$week))
if (anyNA(df$week)) stop("The week could not be parsed.")
df$value <- suppressWarnings(parse_number(df$value))
if (anyNA(df$value)) stop("The value could not be parsed.")
df$location <- as.character(df$location)
if (!all(df$location == "US")) stop("The location could not be parsed.")
df <- arrange(df, week)
if (!nrow(df)) stop("Input has zero rows")
if (anyDuplicated(df$week)) stop("Input contains duplicate weeks")
if (any(diff(df$week) != 7)) stop("Input weeks are not evenly spaced at seven-day intervals")
if (any(df$value < 0)) stop("Input contains negative admissions")

current_season <- "2025-26"
season_start_year <- 2025L
first_mmwr_date <- function(year, target_week) {
  dates <- seq.Date(as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-12-31", year)), by = "day")
  m <- MMWRweek(dates)
  hit <- which(m$MMWRyear == year & m$MMWRweek == target_week)
  if (!length(hit)) return(as.Date(NA))
  dates[min(hit)]
}
season_start <- first_mmwr_date(season_start_year, 40)
season_end <- first_mmwr_date(season_start_year + 1L, 20)
if (is.na(season_start) || is.na(season_end)) stop("Could not determine current season boundaries")
cat("Season Start Week:", format(season_start), "\n")
cat("Season End Week:", format(season_end), "\n")

# Use calendar year/month rather than MMWRyear for January week-53 assignment.
mmwr <- MMWRweek(df$week)
df <- mutate(df, epiweek = mmwr$MMWRweek, cal_year = year(week), cal_month = month(week))
assign_start_year <- function(epiweek, cal_year, cal_month) {
  if (epiweek >= 40) return(if (cal_month <= 8) cal_year - 1L else cal_year)
  if (epiweek <= 20) return(cal_year - 1L)
  NA_integer_
}
df$season_start_year <- mapply(assign_start_year, df$epiweek, df$cal_year, df$cal_month)
df$season <- ifelse(is.na(df$season_start_year), NA_character_,
                    paste0(df$season_start_year, "-", substr(df$season_start_year + 1L, 3, 4)))

test <- filter(df, season == current_season) %>% arrange(week)
if (!nrow(test)) stop("No 2025-26 testing-season weeks present")
first_test <- min(test$week)
observed <- df$week
reference_dates <- observed[vapply(observed, function(r) (r + 7) %in% observed && (r + 7) %in% test$week, logical(1))]
if (!length(reference_dates)) stop("No valid reference dates for the testing period")
cat("Training Period start:", format(min(df$week)), "\n")
cat("Testing Period start:", format(first_test), "\n")
cat("Forecast horizons: 1, 2, 3\n")
for (r_raw in reference_dates) {
  r <- as.Date(r_raw, origin = "1970-01-01")
  cat("Reference date:", format(r), "targets:", paste(format(r + 7 * (1:3)), collapse = ", "), "\n")
}

levels <- c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)
level_map <- tibble(level = levels,
                    lower_q = c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45),
                    upper_q = c(.99, .975, .95, .90, .85, .80, .75, .70, .65, .60, .55))
quantiles <- c(.01, .025, .05, .10, .15, .20, .25, .30, .35, .40, .45, .50,
               .55, .60, .65, .70, .75, .80, .85, .90, .95, .975, .99)

emitted <- list(); raw <- list(); out_i <- 0L; raw_i <- 0L
for (r_raw in reference_dates) {
  # Iterating over a Date vector drops its class; restore it explicitly.
  r <- as.Date(r_raw, origin = "1970-01-01")
  train <- filter(df, week <= r) %>% arrange(week)
  if (is.unsorted(train$week) || anyDuplicated(train$week) || any(diff(train$week) != 7)) stop("Invalid training-week index at ", format(r))
  y <- as.numeric(train$value)
  if (anyNA(y) || any(y < 0) || length(unique(y)) < 2) stop("Invalid training response at ", format(r))
  fit <- auto.arima(y)
  if (is.null(fit)) stop("auto.arima() returned NULL at ", format(r))
  ord <- arimaorder(fit)
  cat("Fit", format(r), "ARIMA(", ord["p"], ",", ord["d"], ",", ord["q"], ")\n", sep = "")
  fc <- forecast(fit, h = 3, level = levels)
  for (h in 1:3) {
    q <- setNames(numeric(length(quantiles)), as.character(quantiles))
    q["0.5"] <- as.numeric(fc$mean[h])
    for (j in seq_len(nrow(level_map))) {
      col <- which(fc$level == level_map$level[j])
      if (length(col) != 1L) stop("Missing forecast interval level")
      q[as.character(level_map$lower_q[j])] <- fc$lower[h, col]
      q[as.character(level_map$upper_q[j])] <- fc$upper[h, col]
    }
    q <- q[as.character(quantiles)]
    if (any(!is.finite(q))) stop("Non-finite forecast at ", format(r))
    for (k in seq_along(quantiles)) {
      raw_i <- raw_i + 1L
      raw[[raw_i]] <- tibble(reference_date = r, horizon = h, output_type_id = quantiles[k], raw_value = as.numeric(q[k]))
      out_i <- out_i + 1L
      emitted[[out_i]] <- tibble(reference_date = r, target = "wk inc flu hosp", horizon = h,
                                 target_end_date = r + 7 * h, location = "US", output_type = "quantile",
                                 output_type_id = quantiles[k], value = as.numeric(round(pmax(q[k], 0))))
    }
  }
}
forecasts <- bind_rows(emitted) %>% arrange(reference_date, horizon, output_type_id)
raw_forecasts <- bind_rows(raw)

if (any(forecasts$value < 0 | forecasts$value != round(forecasts$value))) stop("Forecast values must be non-negative integers")
if (any(forecasts$target_end_date != forecasts$reference_date + 7 * forecasts$horizon)) stop("target_end_date is incorrect")
per_horizon <- forecasts %>% group_by(reference_date, horizon) %>% summarise(
  ordered = all(diff(value[order(output_type_id)]) >= 0),
  levels_ok = setequal(output_type_id, quantiles) && n() == 23, .groups = "drop")
if (!all(per_horizon$ordered)) stop("Quantile ladder is not non-decreasing")
if (!all(per_horizon$levels_ok)) stop("Quantile level set mismatch")
per_ref <- forecasts %>% group_by(reference_date) %>% summarise(ok = setequal(horizon, 1:3), .groups = "drop")
if (!all(per_ref$ok)) stop("Each reference date must emit horizons 1, 2, and 3")
widths <- forecasts %>% filter(output_type_id %in% c(.025, .975)) %>%
  select(reference_date, horizon, output_type_id, value) %>% pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(width = `0.975` - `0.025`) %>% select(reference_date, horizon, width) %>%
  pivot_wider(names_from = horizon, values_from = width, names_prefix = "h")
if (any(widths$h3 < widths$h2 | widths$h2 < widths$h1)) stop("95% intervals do not widen with horizon")
raw_wide <- raw_forecasts %>% pivot_wider(names_from = output_type_id, values_from = raw_value)
for (j in seq_len(nrow(level_map))) {
  lo <- as.character(level_map$lower_q[j]); hi <- as.character(level_map$upper_q[j])
  if (any(abs((raw_wide[["0.5"]] - raw_wide[[lo]]) - (raw_wide[[hi]] - raw_wide[["0.5"]])) > 1e-6)) stop("Raw intervals are not symmetric")
}
cat("[val] quantiles non-decreasing: OK\n[val] all quantile levels present: OK\n[val] target dates correct: OK\n[val] one fit, three horizons: OK\n[val] intervals widen with horizon: OK\n[val] median centered, quantiles symmetric: OK\n")
write_csv(forecasts, output_csv)
if (!file.exists(output_csv)) stop("Forecast CSV not written")

# Plot observed values and median/95% PI for each horizon.
observed_plot <- filter(df, week >= min(reference_dates), season == current_season) %>% select(week, value)
plot_q <- forecasts %>% filter(output_type_id %in% c(.025, .5, .975)) %>%
  select(horizon, target_end_date, output_type_id, value) %>% pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(horizon_label = factor(paste0(horizon, " wk"), levels = c("1 wk", "2 wk", "3 wk")))
cols <- c("1 wk" = "#0072B2", "2 wk" = "#E69F00", "3 wk" = "#009E73")
median_labels <- c("1 wk" = "1 wk forecast (median + 95% PI)", "2 wk" = "2 wk forecast (median + 95% PI)", "3 wk" = "3 wk forecast (median + 95% PI)")
plot_q <- mutate(plot_q,
                 forecast_legend = unname(median_labels[as.character(horizon_label)]))
max_y <- max(c(observed_plot$value, plot_q[["0.975"]]), na.rm = TRUE) + 10000
date_start <- as.Date(min(c(as.numeric(observed_plot$week), as.numeric(plot_q$target_end_date))), origin = "1970-01-01")
date_end <- as.Date(max(as.numeric(plot_q$target_end_date)), origin = "1970-01-01")
all_dates <- seq.Date(date_start, date_end, by = "week")
p <- ggplot() +
  geom_ribbon(data = plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`, fill = forecast_legend), alpha = .18) +
  geom_line(data = plot_q, aes(x = target_end_date, y = `0.5`, color = forecast_legend, linetype = forecast_legend), linewidth = .8) +
  geom_point(data = plot_q, aes(x = target_end_date, y = `0.5`, color = forecast_legend), size = 1.5, show.legend = FALSE) +
  geom_line(data = observed_plot, aes(x = week, y = value, color = "Observed", linetype = "Observed"), linewidth = .9) +
  geom_point(data = observed_plot, aes(x = week, y = value, color = "Observed"), size = 1.5, show.legend = FALSE) +
  scale_color_manual(name = "Element", values = c("Observed" = "black", setNames(cols, unname(median_labels)))) +
  scale_linetype_manual(name = "Element", values = c("Observed" = "solid", setNames(rep("solid", 3), unname(median_labels)))) +
  scale_fill_manual(name = "Element", values = c("Observed" = "black", setNames(cols, unname(median_labels)))) +
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  coord_cartesian(ylim = c(0, max_y)) +
  labs(x = "Week", y = "Weekly Influenza Hospitalizations", title = "USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast (2025-26 Season)") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
        axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA),
        legend.background = element_rect(fill = "white", color = NA))
ggsave(output_png, p, width = 11, height = 6.5, dpi = 300)
if (!file.exists(output_png)) stop("Forecast figure not written")

# Detailed companion view: one panel per horizon to remove visual overlap.
p_components <- ggplot() +
  geom_ribbon(data = plot_q, aes(x = target_end_date, ymin = `0.025`, ymax = `0.975`, fill = horizon_label), alpha = .22, show.legend = FALSE) +
  geom_line(data = observed_plot, aes(x = week, y = value), color = "black", linewidth = .8) +
  geom_point(data = observed_plot, aes(x = week, y = value), color = "black", size = 1.25) +
  geom_line(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), linewidth = .9, show.legend = FALSE) +
  geom_point(data = plot_q, aes(x = target_end_date, y = `0.5`, color = horizon_label), size = 1.6, show.legend = FALSE) +
  facet_wrap(~horizon_label, ncol = 1) +
  scale_color_manual(values = cols) + scale_fill_manual(values = cols) +
  scale_x_date(breaks = all_dates[seq(1, length(all_dates), by = 4)], date_labels = "%m-%d-%Y") +
  coord_cartesian(ylim = c(0, max_y)) +
  labs(x = "Week", y = "Weekly Influenza Hospitalizations",
       title = "Influenza Forecast Components by Horizon (2025-26 Season)",
       subtitle = "Black: observed admissions; colored line: forecast median; shaded band: 95% prediction interval") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = .5, color = "black"),
        plot.subtitle = element_text(hjust = .5, color = "black"),
        axis.text = element_text(color = "black"), axis.title = element_text(color = "black"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA))
ggsave(components_png, p_components, width = 11, height = 11, dpi = 300)
if (!file.exists(components_png)) stop("Detailed forecast-components figure not written")
cat("Wrote ", nrow(forecasts), " forecast rows and two forecast figures.\n", sep = "")
