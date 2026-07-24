#!/usr/bin/env Rscript

# 01_cleaning.R
# Reads the HRD CSV, extracts US influenza admissions, validates,
# writes cleaned CSV to output/data/01_cleaning/ and saves epicurve PNG.

suppressPackageStartupMessages({
  if (!requireNamespace("readr", quietly = TRUE)) stop("Package 'readr' is required")
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Package 'dplyr' is required")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package 'ggplot2' is required")
  if (!requireNamespace("lubridate", quietly = TRUE)) stop("Package 'lubridate' is required")
})

library(readr)
library(dplyr)
library(ggplot2)
library(lubridate)

infile <- file.path("data", "Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv")
out_data_dir <- file.path("output", "data", "01_cleaning")
out_fig_dir <- file.path("output", "figures", "01_cleaning")
out_csv <- file.path(out_data_dir, "cleaned_flu_admissions.csv")
out_png <- file.path(out_fig_dir, "epicurve_us_flu_admissions.png")

dir.create(out_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(infile)) stop(paste0("Input file not found: ", infile))

# Read all columns as character first
df <- readr::read_csv(infile, col_types = cols(.default = col_character()))

# Detect influenza admissions column
preferred_names <- c("Total.Influenza.Admissions", "Total Influenza Admissions")
influenza_col <- intersect(preferred_names, names(df))
if (length(influenza_col) == 0) {
  stop(paste0("No influenza admissions column found. Tried: ", paste(preferred_names, collapse = ", ")))
}
influenza_col <- influenza_col[1]

# Filter to USA
if (!("Geographic aggregation" %in% names(df))) stop("Column 'Geographic aggregation' not found")
df_us <- df %>% filter(`Geographic aggregation` == "USA")

# Build cleaned tibble
if (!("Week Ending Date" %in% names(df_us))) stop("Column 'Week Ending Date' not found")

cleaned <- df_us %>%
  transmute(
    week_raw = `Week Ending Date`,
    location = "US",
    value_raw = !!rlang::sym(influenza_col)
  )

# Parse value as number (handles commas)
cleaned <- cleaned %>%
  mutate(
    value = readr::parse_number(value_raw),
    # Try multiple date formats for Week Ending Date
    week = {
      dt <- parse_date_time(week_raw, orders = c("mdy", "ymd", "dmy", "BdY", "Ymd"))
      as.Date(dt)
    }
  ) %>%
  select(week, location, value)

# Sort by week
cleaned <- cleaned %>% arrange(week)

# Validation checks
if (nrow(cleaned) == 0) stop("Validation failed: no rows after filtering to USA and selecting influenza column")
expected_names <- c("week", "location", "value")
if (!identical(names(cleaned), expected_names)) stop(paste0("Validation failed: column names must be exactly: ", paste(expected_names, collapse = ", ")))
if (!all(cleaned$location == "US")) stop("Validation failed: all 'location' values must be 'US'")
if (!inherits(cleaned$week, "Date")) stop("Validation failed: 'week' must be a Date column")
if (!is.numeric(cleaned$value)) stop("Validation failed: 'value' must be numeric")
if (any(is.na(cleaned$value))) stop("Validation failed: 'value' contains NA after parsing")

# Write cleaned CSV
readr::write_csv(cleaned, out_csv)
if (!file.exists(out_csv)) stop(paste0("Failed to write output CSV: ", out_csv))

# Create epicurve plot
p <- ggplot(cleaned, aes(x = week, y = value)) +
  geom_col(fill = "#2c7fb8") +
  labs(title = "US Influenza Admissions (epicurve)", x = "Week", y = "Admissions") +
  theme_minimal()

ggsave(out_png, plot = p, width = 10, height = 4, dpi = 300)
if (!file.exists(out_png)) stop(paste0("Failed to write epicurve PNG: ", out_png))

cat("Cleaning complete. Cleaned CSV:", out_csv, "\nEpicurve PNG:", out_png, "\n")
