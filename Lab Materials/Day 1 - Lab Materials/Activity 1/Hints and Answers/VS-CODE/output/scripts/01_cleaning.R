#!/usr/bin/env Rscript

# 01_cleaning.R
# ---------------------------------------------------------------------------
# Turns the raw NHSN HRD file into a tidy three-column US influenza admissions
# dataset and saves an epicurve figure.
#
# Implements the rules in rules.md / agents.md.
#
# Run from the project root (the folder that contains data/):
#   Rscript "output/scripts/01_cleaning.R"
# ---------------------------------------------------------------------------

## ---- Dependencies ---------------------------------------------------------

required_pkgs <- c("readr", "dplyr", "ggplot2")
missing_pkgs <- required_pkgs[!vapply(
  required_pkgs, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing_pkgs) > 0) {
  stop(
    "Missing required package(s): ", paste(missing_pkgs, collapse = ", "),
    ". Install with install.packages(c(",
    paste0('"', missing_pkgs, '"', collapse = ", "), ")).",
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(ggplot2)
})

## ---- Paths ----------------------------------------------------------------

in_csv <- file.path(
  "data", "Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv"
)
out_data_dir <- file.path("output", "data", "01_cleaning")
out_fig_dir  <- file.path("output", "figures", "01_cleaning")
out_csv <- file.path(out_data_dir, "cleaned_flu_admissions.csv")
out_png <- file.path(out_fig_dir, "epicurve_us_flu_admissions.png")

if (!file.exists(in_csv)) {
  stop(
    "Input file not found: ", in_csv,
    "\nSet the working directory to the project root (the folder containing ",
    "data/). Current working directory: ", getwd(),
    call. = FALSE
  )
}

## ---- Rule 1: Load the data ------------------------------------------------
# Read the header first so we can import only the columns we need. The raw file
# has ~400 columns; importing everything as character avoids parsing warnings
# from unrelated fields.

header <- names(read_csv(in_csv, n_max = 0, col_types = cols(.default = col_character())))

## ---- Rule 3: Select the target column -------------------------------------

allowed_flu_cols <- c("Total.Influenza.Admissions", "Total Influenza Admissions")
flu_col <- allowed_flu_cols[allowed_flu_cols %in% header]
if (length(flu_col) == 0) {
  stop(
    "No influenza admissions column found in ", in_csv,
    ". Expected one of: ", paste(allowed_flu_cols, collapse = " or "), ".",
    call. = FALSE
  )
}
flu_col <- flu_col[1]

required_cols <- c("Week Ending Date", "Geographic aggregation", flu_col)
missing_cols <- setdiff(required_cols, header)
if (length(missing_cols) > 0) {
  stop(
    "Required column(s) not found in ", in_csv, ": ",
    paste(missing_cols, collapse = ", "), ".",
    call. = FALSE
  )
}

raw <- read_csv(
  in_csv,
  col_select = all_of(required_cols),
  col_types  = cols(.default = col_character())
)

## ---- Rules 2, 4, 5: Filter, reshape, and format ---------------------------

cleaned <- raw %>%
  filter(.data[["Geographic aggregation"]] == "USA") %>%
  transmute(
    week     = as.Date(.data[["Week Ending Date"]], format = "%Y-%m-%d"),
    location = "US",
    # parse_number() handles comma-formatted counts such as "1,110"
    value    = parse_number(.data[[flu_col]])
  ) %>%
  arrange(week)

## ---- Rule 8: Validation checks --------------------------------------------

if (nrow(cleaned) == 0) {
  stop(
    "Validation failed: no rows remain after filtering to ",
    "`Geographic aggregation` == \"USA\".",
    call. = FALSE
  )
}

if (!identical(names(cleaned), c("week", "location", "value"))) {
  stop(
    "Validation failed: columns must be exactly week, location, value (in that ",
    "order). Found: ", paste(names(cleaned), collapse = ", "), ".",
    call. = FALSE
  )
}

if (!all(cleaned$location == "US")) {
  stop(
    "Validation failed: every `location` value must be \"US\". Found: ",
    paste(unique(cleaned$location), collapse = ", "), ".",
    call. = FALSE
  )
}

if (!inherits(cleaned$week, "Date")) {
  stop(
    "Validation failed: `week` must be a Date. Found class: ",
    paste(class(cleaned$week), collapse = "/"), ".",
    call. = FALSE
  )
}

if (any(is.na(cleaned$week))) {
  stop(
    "Validation failed: `week` contains ", sum(is.na(cleaned$week)),
    " NA value(s) after date parsing. Check the format of `Week Ending Date`.",
    call. = FALSE
  )
}

if (!is.numeric(cleaned$value)) {
  stop(
    "Validation failed: `value` must be numeric. Found class: ",
    paste(class(cleaned$value), collapse = "/"), ".",
    call. = FALSE
  )
}

if (any(is.na(cleaned$value))) {
  stop(
    "Validation failed: `value` contains ", sum(is.na(cleaned$value)),
    " NA value(s) after parsing column `", flu_col, "`.",
    call. = FALSE
  )
}

## ---- Rule 6: Save the cleaned data ----------------------------------------

dir.create(out_data_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(cleaned, out_csv)

if (!file.exists(out_csv)) {
  stop("Validation failed: expected output CSV was not created at ", out_csv, ".",
       call. = FALSE)
}

## ---- Rule 7: Generate the epicurve -----------------------------------------

dir.create(out_fig_dir, recursive = TRUE, showWarnings = FALSE)

epicurve <- ggplot(cleaned, aes(x = week, y = as.numeric(value))) +
  geom_col(fill = "#2C7FB8", width = 6) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "6 months") +
  labs(
    title = "Weekly influenza hospital admissions, United States",
    subtitle = paste0(
      format(min(cleaned$week), "%d %b %Y"), " to ",
      format(max(cleaned$week), "%d %b %Y"), " (NHSN HRD)"
    ),
    x = "Week ending",
    y = "Admissions"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

ggsave(out_png, plot = epicurve, width = 10, height = 4.5, dpi = 300)

if (!file.exists(out_png)) {
  stop("Validation failed: expected epicurve was not created at ", out_png, ".",
       call. = FALSE)
}

## ---- Summary ---------------------------------------------------------------

cat(
  "01_cleaning.R complete.\n",
  "  Source column: ", flu_col, "\n",
  "  Rows written:  ", nrow(cleaned), "\n",
  "  Date range:    ", format(min(cleaned$week)), " to ", format(max(cleaned$week)), "\n",
  "  Cleaned data:  ", out_csv, "\n",
  "  Epicurve:      ", out_png, "\n",
  sep = ""
)
