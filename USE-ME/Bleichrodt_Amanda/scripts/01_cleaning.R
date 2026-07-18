# 01_cleaning.R
# Transform the raw NHSN HRD influenza file into a tidy, three-column dataset
# and produce an epicurve figure.
#
# Run from the project root (Bleichrodt_Amanda/):
#   Rscript scripts/01_cleaning.R
#
# Instructions derived from AGENTS.md / rules.md.

library(readr)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
input_csv   <- file.path(
  "data",
  "Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv"
)
output_dir  <- file.path("output", "data", "01_cleaning")
figure_dir  <- file.path("output", "figures", "01_cleaning")
output_csv  <- file.path(output_dir, "cleaned_flu_admissions.csv")
figure_png  <- file.path(figure_dir, "epicurve_us_flu_admissions.png")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 3. Determine the target influenza admissions column (before reading)
# ---------------------------------------------------------------------------
# Read only the header to discover which allowed name is present.
header <- names(read_csv(input_csv, n_max = 0, show_col_types = FALSE))

allowed_admissions <- c("Total.Influenza.Admissions", "Total Influenza Admissions")
admissions_col <- allowed_admissions[allowed_admissions %in% header]
if (length(admissions_col) == 0) {
  stop(
    "Could not find an influenza admissions column. Expected one of: ",
    paste(allowed_admissions, collapse = ", ")
  )
}
admissions_col <- admissions_col[1]

# ---------------------------------------------------------------------------
# 1. Load the data (import only required columns, all as character)
# ---------------------------------------------------------------------------
required_cols <- c("Week Ending Date", "Geographic aggregation", admissions_col)

raw <- read_csv(
  input_csv,
  col_select = all_of(required_cols),
  col_types  = cols(.default = col_character()),
  show_col_types = FALSE
)

# ---------------------------------------------------------------------------
# 2. Filter to US only
# ---------------------------------------------------------------------------
raw <- raw[raw[["Geographic aggregation"]] == "USA", , drop = FALSE]

# ---------------------------------------------------------------------------
# 4. Reshape to exactly three columns: week, location, value
# ---------------------------------------------------------------------------
cleaned <- data.frame(
  week     = raw[["Week Ending Date"]],
  location = "US",
  value    = parse_number(raw[[admissions_col]]),
  stringsAsFactors = FALSE
)

# ---------------------------------------------------------------------------
# 5. Format dates and sort ascending by week
# ---------------------------------------------------------------------------
cleaned$week <- as.Date(cleaned$week)
cleaned <- cleaned[order(cleaned$week), , drop = FALSE]
rownames(cleaned) <- NULL

# ---------------------------------------------------------------------------
# 6. Save the cleaned data
# ---------------------------------------------------------------------------
write_csv(cleaned, output_csv)

# ---------------------------------------------------------------------------
# 7. Generate the epicurve
# ---------------------------------------------------------------------------
png(figure_png, width = 1200, height = 600, res = 120)
# Wider bottom/left margins so the axis titles can sit clear of the tick labels.
op <- par(mar = c(7, 6, 4, 2) + 0.1)
barplot(
  height    = as.numeric(cleaned$value),
  names.arg = cleaned$week,
  xlab      = "",
  ylab      = "",
  main      = "US Weekly Influenza Admissions Epicurve",
  col       = "steelblue",
  border    = NA,
  ylim      = c(0, max(as.numeric(cleaned$value), na.rm = TRUE)),
  las       = 2,
  cex.names = 0.7,           # dates a smidge smaller
  space     = 0              # continuous bars, no gaps between them
)
# Push the axis titles out so they don't crowd the tick labels.
title(xlab = "Week", line = 5.5)
title(ylab = "Total Influenza Admissions", line = 4.5)
par(op)
dev.off()

# ---------------------------------------------------------------------------
# 8. Validation checks (stop on failure)
# ---------------------------------------------------------------------------
if (!(nrow(cleaned) > 0)) {
  stop("Validation failed: cleaned data has 0 rows.")
}
if (!identical(names(cleaned), c("week", "location", "value"))) {
  stop(
    "Validation failed: columns must be exactly 'week', 'location', 'value' ",
    "in that order. Got: ", paste(names(cleaned), collapse = ", ")
  )
}
if (!all(cleaned$location == "US")) {
  stop("Validation failed: 'location' is not always 'US'.")
}
if (!inherits(cleaned$week, "Date")) {
  stop("Validation failed: 'week' does not inherit class 'Date'.")
}
if (!is.numeric(cleaned$value)) {
  stop("Validation failed: 'value' is not numeric.")
}
if (any(is.na(cleaned$value))) {
  stop("Validation failed: 'value' contains NA after parsing.")
}
if (!file.exists(output_csv)) {
  stop("Validation failed: output CSV not found at ", output_csv)
}
if (!file.exists(figure_png)) {
  stop("Validation failed: epicurve figure not found at ", figure_png)
}

message("01_cleaning.R completed successfully.")
message("  Rows written:   ", nrow(cleaned))
message("  Cleaned CSV:    ", output_csv)
message("  Epicurve figure: ", figure_png)
