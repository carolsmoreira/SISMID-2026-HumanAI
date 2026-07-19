# output/scripts/01_cleaning.R ------------------------------------------------
# Turn the raw NHSN HRD influenza file into a tidy three-column dataset and
# produce an epicurve figure. See rules.md for the specification.
#
# Paths below are relative to the project root. Run from the root:
#   Rscript output/scripts/01_cleaning.R

library(readr)

# Paths -----------------------------------------------------------------------

raw_path <- file.path(
  "data",
  "Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv"
)

out_data_dir <- file.path("output", "data", "01_cleaning")
out_fig_dir  <- file.path("output", "figures", "01_cleaning")

out_csv <- file.path(out_data_dir, "cleaned_flu_admissions.csv")
out_png <- file.path(out_fig_dir, "epicurve_us_flu_admissions.png")

dir.create(out_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig_dir,  recursive = TRUE, showWarnings = FALSE)

if (!file.exists(raw_path)) {
  stop("Raw NHSN HRD file not found at: ", raw_path)
}

# Rule 3: select the target column --------------------------------------------
# Resolve the admissions column from the header before reading the full file.

header <- names(read_csv(raw_path, n_max = 0, show_col_types = FALSE))

allowed_cols <- c("Total.Influenza.Admissions", "Total Influenza Admissions")
admissions_col <- allowed_cols[allowed_cols %in% header][1]

if (is.na(admissions_col)) {
  stop(
    "No influenza admissions column found. Expected one of: ",
    paste(allowed_cols, collapse = ", ")
  )
}

# Rule 1: load the data --------------------------------------------------------
# Import only the required columns, all as character, then convert explicitly.

keep_cols <- c("Week Ending Date", "Geographic aggregation", admissions_col)

raw <- read_csv(
  raw_path,
  col_select = all_of(keep_cols),
  col_types  = cols(.default = col_character()),
  show_col_types = FALSE
)

# Rule 2: filter to US only ----------------------------------------------------

us <- raw[raw[["Geographic aggregation"]] == "USA", , drop = FALSE]

# Rules 4 & 5: reshape to three columns, format dates --------------------------

cleaned <- data.frame(
  week     = as.Date(us[["Week Ending Date"]], format = "%m/%d/%Y"),
  location = "US",
  value    = parse_number(us[[admissions_col]]),
  stringsAsFactors = FALSE
)

# Fall back to ISO dates if the file uses that format instead.
if (all(is.na(cleaned$week))) {
  cleaned$week <- as.Date(us[["Week Ending Date"]])
}

cleaned <- cleaned[order(cleaned$week), , drop = FALSE]
rownames(cleaned) <- NULL

# Rule 6: save the output ------------------------------------------------------

write_csv(cleaned, out_csv)

# Rule 7: generate epicurve figure ---------------------------------------------

png(out_png, width = 1600, height = 900, res = 150)
barplot(
  height    = as.numeric(cleaned$value),
  names.arg = format(cleaned$week, "%Y-%m"),
  xlab      = "Week",
  ylab      = "Influenza admissions",
  main      = "US weekly influenza hospital admissions (NHSN HRD)",
  col       = "steelblue",
  border    = NA,
  las       = 2,
  cex.names = 0.5
)
dev.off()

# Rule 8: required validation checks -------------------------------------------

stopifnot(
  "no rows after filtering to USA"        = nrow(cleaned) > 0,
  "columns must be week, location, value" =
    identical(names(cleaned), c("week", "location", "value")),
  "location must always be 'US'"          = all(cleaned$location == "US"),
  "week must be a Date"                   = inherits(cleaned$week, "Date"),
  "value must be numeric"                 = is.numeric(cleaned$value),
  "value must have no NA after parsing"   = !any(is.na(cleaned$value)),
  "cleaned CSV was not written"           = file.exists(out_csv),
  "epicurve figure was not written"       = file.exists(out_png)
)

message("Cleaning complete: ", nrow(cleaned), " rows written to ", out_csv)
