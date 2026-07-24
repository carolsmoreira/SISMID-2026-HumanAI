# 02_data_explore.R
# Reads cleaned flu admissions, validates types, computes season windows,
# produces national and seasonal plots, and writes peak_description.csv

# Required packages
pkgs <- c("readr","dplyr","lubridate","ggplot2","MMWRweek")
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}

library(readr)
library(dplyr)
library(lubridate)
library(ggplot2)
library(MMWRweek)

# Paths
cleaned_csv <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
national_plot <- "output/figures/02_data_explore/national_trend.png"
seasonal_plot <- "output/figures/02_data_explore/seasonal_comparison.png"
peak_csv <- "output/data/02_data_explore/peak_description.csv"

# Ensure output directories exist
dir.create(dirname(national_plot), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(seasonal_plot), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(peak_csv), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(cleaned_csv)) stop(paste0("Missing input: ", cleaned_csv))

# Read input and validate
df <- read_csv(cleaned_csv, col_types = cols(.default = "c"))

# Expected column names and order: week, location, value
if (!all(names(df) %in% c("week","location","value"))) {
  # Attempt to coerce common variations
  names(df) <- tolower(names(df))
  if ("week ending date" %in% names(df)) names(df)[names(df)=="week ending date"] <- "week"
  if ("geographic aggregation" %in% names(df)) names(df)[names(df)=="geographic aggregation"] <- "location"
  if ("total.influenza.admissions" %in% names(df)) names(df)[names(df)=="total.influenza.admissions"] <- "value"
  if ("total influenza admissions" %in% names(df)) names(df)[names(df)=="total influenza admissions"] <- "value"
}

# After renaming attempt, check presence
if (!all(c("week","location","value") %in% names(df))) stop("Required columns missing from cleaned CSV")

# Parse week
parsed_week <- tryCatch({
  # try multiple common formats
  w <- as.Date(df$week)
  if (all(is.na(w))) w <- ymd(df$week)
  if (all(is.na(w))) w <- mdy(df$week)
  if (all(is.na(w))) stop("parse fail")
  w
}, error = function(e) NA)
if (all(is.na(parsed_week))) stop("The week could not be parsed.")

df$week <- parsed_week

# Parse value
parsed_value <- tryCatch({
  # remove commas and parse as numeric
  v <- parse_number(df$value)
  if (all(is.na(v))) stop("parse fail")
  v
}, error = function(e) NA)
if (all(is.na(parsed_value))) stop("The value could not be parsed.")

df$value <- as.numeric(parsed_value)

# Validate location
if (!all(df$location == "US")) stop("location must be all 'US'")

# Final structural checks
if (nrow(df) == 0) stop("Data has zero rows")
if (!identical(names(df)[1:3], c("week","location","value"))) {
  # reorder/rename accordingly
  df <- df %>% select(week, location, value)
  if (!identical(names(df), c("week","location","value"))) stop("Column names must be exactly week, location, value in that order")
}
if (!inherits(df$week, "Date")) stop("week must be a Date column")
if (!is.numeric(df$value)) stop("value must be numeric")
if (any(is.na(df$value))) stop("value contains NA after parsing")

# Print season boundaries for current season 2025-26
current_season_label <- "2025-26"
season_start_year <- 2025

# Helper: find first calendar date in a year with given MMWR week
first_date_with_mmwr <- function(year, target_week) {
  start <- as.Date(paste0(year, "-01-01"))
  end <- as.Date(paste0(year, "-12-31"))
  dates <- seq.Date(start, end, by = "day")
  mmwr <- MMWRweek(dates)
  idx <- which(mmwr$MMWRweek == target_week & mmwr$MMWRyear == year)
  if (length(idx) == 0) return(NA)
  dates[min(idx)]
}

season_start <- first_date_with_mmwr(season_start_year, 40)
season_end <- first_date_with_mmwr(season_start_year + 1, 20)
if (is.na(season_start) || is.na(season_end)) stop("Could not determine season boundaries via MMWRweek")

cat("Season Start Week:", format(season_start, "%Y-%m-%d"), "\n")
cat("Season End Week:", format(season_end, "%Y-%m-%d"), "\n")

# NATIONAL TREND PLOT
plot_df <- df %>% arrange(week)

# Determine x-axis breaks: show only every 6 dates (unique weeks)
unique_weeks <- sort(unique(plot_df$week))
break_idx <- seq(1, length(unique_weeks), by = 6)
breaks <- unique_weeks[break_idx]

y_max <- max(plot_df$value, na.rm = TRUE) + 10000

p1 <- ggplot(plot_df, aes(x = week, y = value)) +
  # season highlight rectangle behind everything
  annotate("rect", xmin = season_start, xmax = season_end, ymin = -Inf, ymax = Inf, fill = "lightgrey", alpha = 0.4) +
  geom_line(color = "blue") +
  labs(x = "Week", y = "Weekly Influenza Hospitalizations", title = "USA Weekly Influenza Hospitalization Admissions") +
  scale_x_date(breaks = breaks, date_labels = "%m-%Y") +
  coord_cartesian(ylim = c(0, y_max)) +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, face = "bold"), axis.text.x = element_text(angle = 45, hjust = 1))

# place season label at top of highlight
label_y <- y_max - 0.02 * (y_max)
p1 <- p1 + annotate("text", x = season_start + (season_end - season_start)/2, y = label_y, label = paste0(current_season_label, " Season"), fontface = "bold")

# Save at 300 DPI
ggsave(national_plot, p1, dpi = 300, width = 10, height = 6)

# SEASONAL COMPARISON
# Assign MMWR week and season label to each row
mmwr_info <- MMWRweek(plot_df$week)
plot_df$mmwr_week <- mmwr_info$MMWRweek
plot_df$mmwr_year <- mmwr_info$MMWRyear
plot_df$month <- month(plot_df$week)

assign_season_start <- function(date, mmwr_week, cal_year, month) {
  # If MMWR week >= 40: if calendar month Jan-Aug attribute to previous year's season
  if (mmwr_week >= 40) {
    if (month >= 1 && month <= 8) {
      start_year <- cal_year - 1
    } else {
      start_year <- cal_year
    }
  } else if (mmwr_week <= 20) {
    start_year <- cal_year - 1
  } else {
    start_year <- NA_integer_
  }
  start_year
}

plot_df$season_start_year <- mapply(assign_season_start, plot_df$week, plot_df$mmwr_week, year(plot_df$week), plot_df$month)
plot_df$season_label <- ifelse(!is.na(plot_df$season_start_year), paste0(plot_df$season_start_year, "-", substr(as.character(plot_df$season_start_year + 1), 3,4)), NA)

# Exclude data after current season for seasonal comparison
plot_df <- plot_df %>% filter(is.na(season_label) | season_label <= current_season_label)

# Keep only weeks 40-53 and 1-20 for season plotting
season_weeks_order <- c(40:53, 1:20)
plot_df <- plot_df %>% filter(mmwr_week %in% season_weeks_order)
plot_df$week_of_season <- match(plot_df$mmwr_week, season_weeks_order)

# For plotting, remove NA seasons (outside season range)
season_plot_df <- plot_df %>% filter(!is.na(season_label))

# Define line type and color mappings
seasons <- sort(unique(season_plot_df$season_label))
colors <- setNames(RColorBrewer::brewer.pal(max(3, length(seasons)), "Set1")[1:length(seasons)], seasons)
# Force current season color to black
if (current_season_label %in% seasons) colors[current_season_label] <- "black"

linetypes <- setNames(rep("dashed", length(seasons)), seasons)
if (current_season_label %in% seasons) linetypes[current_season_label] <- "solid"

# Line sizes: current season thicker
line_sizes <- ifelse(seasons == current_season_label, 1.2, 0.8)
names(line_sizes) <- seasons

p2 <- ggplot(season_plot_df, aes(x = week_of_season, y = value, group = season_label, color = season_label, linetype = season_label)) +
  geom_line(aes(size = season_label)) +
  scale_color_manual(name = "Season", values = colors) +
  scale_linetype_manual(name = "Season", values = linetypes) +
  scale_size_manual(name = "Season", values = line_sizes) +
  labs(x = "Week of Season", y = "Weekly Total Influenza Admissions (USA)", title = "USA Weekly Influenza Hospitalization Admissions") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, face = "bold"), axis.text.x = element_text(angle = 45, hjust = 1))

# X axis labels: numeric MMWR week numbers, show every other week
week_labels <- season_weeks_order
week_positions <- seq_along(week_labels)
label_positions <- week_positions[seq(1, length(week_positions), by = 2)]
label_texts <- week_labels[label_positions]

p2 <- p2 + scale_x_continuous(breaks = label_positions, labels = label_texts) + coord_cartesian(ylim = c(0, y_max))

# Save seasonal plot
ggsave(seasonal_plot, p2, dpi = 300, width = 10, height = 6)

# PEAK ANALYSIS for CURRENT SEASON ONLY (2025-26)
peak_df <- plot_df %>% filter(season_label == current_season_label)
if (nrow(peak_df) == 0) stop("No data for current season in input")

# Only keep dates present in input (already guaranteed)
# Peak_Time: date of global max (earliest if ties)
idx_peak <- which.max(peak_df$value)
peak_time <- peak_df$week[idx_peak]
peak_intensity <- peak_df$value[idx_peak]

# Decline_Start: deterministic rule implemented per agents.md:
# "the first calendar `week` after the `Peak_Time` for which the current
# week's `value` is strictly less than the previous week's `value`."
# This loop finds that first date (if any) and preserves it as a Date.
decline_start <- NA
if (idx_peak < nrow(peak_df)) {
  for (i in (idx_peak+1):nrow(peak_df)) {
    if (peak_df$value[i] < peak_df$value[i-1]) {
      decline_start <- peak_df$week[i]
      break
    }
  }
}

peak_out <- tibble(
  Peak_Time = as.Date(peak_time),
  Peak_Intensity = as.numeric(peak_intensity),
  Decline_Start = as.Date(decline_start),
  Season_Start = as.Date(season_start),
  Season_End = as.Date(season_end)
)

write_csv(peak_out, peak_csv)

# Final existence checks
if (!file.exists(national_plot)) stop("National plot not written")
if (!file.exists(seasonal_plot)) stop("Seasonal plot not written")
if (!file.exists(peak_csv)) stop("Peak CSV not written")

cat("Done: generated national plot, seasonal plot, and peak CSV.\n")
