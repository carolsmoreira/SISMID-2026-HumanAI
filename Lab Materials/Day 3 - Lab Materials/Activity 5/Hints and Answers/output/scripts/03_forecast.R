# 03_forecast.R
# Reads cleaned flu admissions, assigns seasons, fits an expanding-window
# auto.arima() per reference date over the 2025-26 testing season, and emits
# 1/2/3-week-ahead forecasts in FluSight long format (23 quantiles x 3 horizons
# per reference date). Also produces a forecast-vs-observed figure.
#
# See rules.md (Forecasting section) and AGENTS.md for the full specification.

# ---- Required packages -------------------------------------------------------
pkgs <- c("readr", "dplyr", "tidyr", "lubridate", "ggplot2", "MMWRweek", "forecast")
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
  library(forecast)
})

# ---- Paths -------------------------------------------------------------------
cleaned_csv   <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
forecast_csv  <- "output/data/03_forecast/flusight_forecasts.csv"
forecast_png  <- "output/figures/03_forecast/forecast_vs_observed.png"

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

# First calendar date in `year` whose MMWR week == target_week (and MMWR year
# matches), accounting for leap years by scanning actual dates.
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

# Assign each observed week to a season. Use the calendar year of the date as
# the base year (NOT MMWRyear). Handle the early-January / week-53 edge case:
# if epiweek >= 40 but the calendar month is Jan-Aug, attribute the date to the
# previous year's season so a winter season stays continuous across the
# calendar-year boundary.
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

# ---- Rule 3: Training and Testing Periods ------------------------------------
# Testing period: the 2025-26 season only.
test_weeks <- df %>% filter(season_label == current_season_label) %>% arrange(week)
if (nrow(test_weeks) == 0) stop("No 2025-26 testing-season weeks present in the input")
first_test_week <- min(test_weeks$week)

# Reference dates: every observed week r whose 1-week-ahead target (r + 7) is
# present in the data AND falls within the testing (2025-26) season.
observed_weeks   <- sort(unique(df$week))
test_week_set    <- test_weeks$week
is_ref <- vapply(observed_weeks, function(r) {
  (r + 7) %in% observed_weeks && (r + 7) %in% test_week_set
}, logical(1))
reference_dates <- observed_weeks[is_ref]
if (length(reference_dates) == 0) stop("No valid reference dates for the testing period")

# Training period: all observed weeks strictly before the first testing week.
train_start <- min(df$week)
initial_train_end <- max(df$week[df$week < first_test_week])

cat("\n--- Rule 3 validations ---\n")
cat("[val] Training Period start:", format(train_start, "%Y-%m-%d"), "\n")
cat("[val] Initial training window end (last pre-test week):",
    format(initial_train_end, "%Y-%m-%d"), "\n")
cat("[val] Testing Period start:", format(first_test_week, "%Y-%m-%d"), "\n")
cat("[val] Forecast horizons: 1, 2, 3\n")
cat("[val] Rolling-window reference (end) dates & their 3 target dates:\n")
for (r in reference_dates) {
  rd <- as.Date(r, origin = "1970-01-01")
  tg <- rd + 7 * (1:3)
  cat("   ref", format(rd, "%Y-%m-%d"),
      "-> targets", paste(format(tg, "%Y-%m-%d"), collapse = ", "), "\n")
}

# ---- Rule 5 setup: coverage levels & quantile map ----------------------------
LEVELS <- c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)

# Each central coverage level maps to a lower-tail and upper-tail quantile.
level_map <- data.frame(
  level = LEVELS,
  lo_q  = c(0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45),
  hi_q  = c(0.99, 0.975, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55),
  stringsAsFactors = FALSE
)

# The full FluSight quantile ladder, in ascending order (23 values).
quantile_ladder <- c(0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35,
                     0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80,
                     0.85, 0.90, 0.95, 0.975, 0.99)

# ---- Rules 4 & 5: fit per reference date, forecast, reshape long -------------
cat("\n--- Rule 4 & 5 validations ---\n")

all_rows  <- list()
raw_rows  <- list()   # pre-clamp values, for symmetry checks
row_i <- 0
raw_i <- 0

for (r in reference_dates) {
  rd <- as.Date(r, origin = "1970-01-01")

  # Expanding window: all observed weeks with week <= reference_date.
  train <- df %>% filter(week <= rd) %>% arrange(week)

  # Rule 4 validations on the training window.
  wk <- train$week
  if (is.unsorted(wk)) stop(paste0("Training window not sorted ascending at ref ", format(rd, "%Y-%m-%d")))
  if (any(duplicated(wk))) stop(paste0("Duplicate weeks in training window at ref ", format(rd, "%Y-%m-%d")))
  gaps <- as.numeric(diff(wk))
  if (length(gaps) > 0 && any(gaps != 7)) {
    stop(paste0("Training weeks not evenly spaced (7-day) at ref ", format(rd, "%Y-%m-%d")))
  }

  y <- train$value
  if (!is.numeric(y)) stop("Response vector is not numeric")
  if (any(is.na(y)))  stop("Response vector contains NA")
  if (any(y < 0))     stop("Response vector contains negative values")
  if (length(unique(y)) <= 1) stop(paste0("Series is constant at ref ", format(rd, "%Y-%m-%d")))

  # Fit exactly once; reuse for all three horizons.
  fit <- auto.arima(y)
  if (is.null(fit)) stop(paste0("auto.arima() returned NULL at ref ", format(rd, "%Y-%m-%d")))
  ord <- forecast::arimaorder(fit)  # named c(p, d, q) for non-seasonal

  cat("[val] ref", format(rd, "%Y-%m-%d"),
      "| sorted+unique+evenly-spaced OK | n =", length(y),
      "| numeric/non-neg/no-NA OK | non-constant OK",
      "| ARIMA(", ord["p"], ",", ord["d"], ",", ord["q"], ") | fit OK\n")

  fc <- forecast(fit, h = 3, level = LEVELS)

  # For each horizon assemble the 23 raw (pre-clamp) quantiles.
  for (h in 1:3) {
    target_end <- rd + 7 * h

    raw_q <- setNames(numeric(0), character(0))
    med   <- as.numeric(fc$mean[h])
    raw_q["0.5"] <- med

    for (k in seq_len(nrow(level_map))) {
      L   <- level_map$level[k]
      col <- which(abs(fc$level - L) < 1e-6)  # index by level value, not input order
      if (length(col) != 1) stop(paste0("Could not locate forecast column for level ", L))
      raw_q[as.character(level_map$lo_q[k])] <- as.numeric(fc$lower[h, col])
      raw_q[as.character(level_map$hi_q[k])] <- as.numeric(fc$upper[h, col])
    }

    # Order by the canonical ladder.
    raw_vec <- raw_q[as.character(quantile_ladder)]
    if (any(!is.finite(raw_vec))) {
      stop(paste0("Non-finite forecast at ref ", format(rd, "%Y-%m-%d"), " horizon ", h))
    }

    # Store raw (pre-clamp) rows for symmetry validation.
    for (qi in seq_along(quantile_ladder)) {
      raw_i <- raw_i + 1
      raw_rows[[raw_i]] <- data.frame(
        reference_date = rd, horizon = h,
        output_type_id = quantile_ladder[qi], raw_value = as.numeric(raw_vec[qi]),
        stringsAsFactors = FALSE
      )
    }

    # Clamp at 0 and round to nearest integer for the emitted counts.
    emit_vec <- round(pmax(raw_vec, 0))

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
raw_all   <- bind_rows(raw_rows)

# ---- Rule 5 validations ------------------------------------------------------
cat("\n--- Rule 5 output validations ---\n")

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

# One fit -> three horizons: exactly horizons {1,2,3} per reference date.
h_ok <- forecasts %>%
  group_by(reference_date) %>%
  summarise(ok = setequal(unique(horizon), c(1, 2, 3)), .groups = "drop")
if (!all(h_ok$ok)) stop("Each reference date must emit exactly horizons 1, 2, 3")
cat("[val] one fit, three horizons: OK\n")

# target_end_date == reference_date + 7 * horizon.
if (any(forecasts$target_end_date != forecasts$reference_date + 7 * forecasts$horizon)) {
  stop("target_end_date does not equal reference_date + 7 * horizon")
}
cat("[val] target dates correct: OK\n")

# Intervals widen (or hold) with horizon: 95% PI width h3 >= h2 >= h1.
width_tbl <- forecasts %>%
  filter(output_type_id %in% c(0.025, 0.975)) %>%
  select(reference_date, horizon, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  mutate(w = `0.975` - `0.025`) %>%
  select(reference_date, horizon, w) %>%
  pivot_wider(names_from = horizon, values_from = w, names_prefix = "h")
if (any(width_tbl$h3 < width_tbl$h2) || any(width_tbl$h2 < width_tbl$h1)) {
  stop("95% PI width does not satisfy h3 >= h2 >= h1")
}
cat("[val] intervals widen with horizon: OK\n")

# Median centered & symmetric pairs equidistant, computed on RAW forecast.
sym_tol <- 1e-6
raw_wide <- raw_all %>%
  pivot_wider(names_from = output_type_id, values_from = raw_value)
med_centered <- TRUE
sym_ok <- TRUE
for (i in seq_len(nrow(raw_wide))) {
  med <- raw_wide[["0.5"]][i]
  for (k in seq_len(nrow(level_map))) {
    lo <- raw_wide[[as.character(level_map$lo_q[k])]][i]
    hi <- raw_wide[[as.character(level_map$hi_q[k])]][i]
    if (abs((med - lo) - (hi - med)) > sym_tol * max(1, abs(med))) sym_ok <- FALSE
  }
}
if (!med_centered || !sym_ok) stop("Median not centered / quantiles not symmetric on raw forecast")
cat("[val] median centered, quantiles symmetric: OK\n")

# ---- Write FluSight long CSV -------------------------------------------------
forecasts_out <- forecasts %>%
  arrange(reference_date, horizon,
          match(output_type_id, quantile_ladder)) %>%
  select(reference_date, target, horizon, target_end_date,
         location, output_type, output_type_id, value)

write_csv(forecasts_out, forecast_csv)
if (!file.exists(forecast_csv)) stop("Forecast CSV not written")
cat("\nWrote", nrow(forecasts_out), "rows to", forecast_csv,
    "(", length(reference_dates), "reference dates x 69 rows )\n")

# ---- Rule 6: Forecast Figure -------------------------------------------------
# Observed series over the testing period, with 1/2/3-week-ahead forecast
# medians (one line per horizon) and 95% PI ribbons overlaid.

# Observed: from the first reference date onward through the last observed
# testing week (the plotted forecast window).
plot_start <- min(reference_dates)
observed_plot <- df %>%
  filter(week >= plot_start) %>%
  select(week, value) %>%
  arrange(week)

horizon_levels  <- c("1 wk", "2 wk", "3 wk")
horizon_colors  <- c("1 wk" = "#0072B2", "2 wk" = "#E69F00", "3 wk" = "#009E73")

# Median line + points per horizon.
med_df <- forecasts %>%
  filter(output_type_id == 0.5) %>%
  transmute(target_end_date, horizon,
            hlab = factor(paste0(horizon, " wk"), levels = horizon_levels),
            value)

# 95% PI ribbon per horizon.
pi_df <- forecasts %>%
  filter(output_type_id %in% c(0.025, 0.975)) %>%
  select(target_end_date, horizon, output_type_id, value) %>%
  pivot_wider(names_from = output_type_id, values_from = value) %>%
  transmute(target_end_date, horizon,
            hlab = factor(paste0(horizon, " wk"), levels = horizon_levels),
            lo = `0.025`, hi = `0.975`)

# Y axis: 0 to (max plotted value + 10000).
y_max <- max(c(observed_plot$value, med_df$value, pi_df$hi), na.rm = TRUE) + 10000

# X axis: weekly dates from first plotted week to last target_end_date; label
# every 4th, tilted 45 degrees.
x_min <- min(observed_plot$week)
x_max <- max(med_df$target_end_date)
all_x <- seq.Date(x_min, x_max, by = 7)
x_breaks <- all_x[seq(1, length(all_x), by = 4)]

p <- ggplot() +
  # Ribbons behind everything.
  geom_ribbon(data = pi_df,
              aes(x = target_end_date, ymin = lo, ymax = hi,
                  fill = hlab, group = hlab),
              alpha = 0.20) +
  # Observed solid black line + points.
  geom_line(data = observed_plot, aes(x = week, y = value, color = "Observed"),
            linewidth = 0.9) +
  geom_point(data = observed_plot, aes(x = week, y = value, color = "Observed"),
             size = 1.6) +
  # Forecast median line + points per horizon.
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
    title = "USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast (2025-26 Season)"
  ) +
  theme_minimal() +
  theme(
    plot.title  = element_text(hjust = 0.5, face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

ggsave(forecast_png, p, dpi = 300, width = 11, height = 6.5)
if (!file.exists(forecast_png)) stop("Forecast figure not written")

cat("\nDone: wrote", forecast_csv, "and", forecast_png, "\n")
