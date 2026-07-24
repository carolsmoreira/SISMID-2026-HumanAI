# final_prep.R
# Final FluSight submission prep -- no modeling.
#
# Splits the finished XGBoost forecast file
# (output/data/03_forecast/XGB_flusight_forecasts.csv) into one CSV per
# reference date, written to output/data/final_flusight_submission/ as
# {YYYY-MM-DD}-AmandaXGBoost.csv.
#
# Each per-date file keeps the full FluSight long format: the same eight columns
# in the same order, the same row ordering, 69 rows (3 horizons x 23 quantiles).
# Nothing in 03_forecast or 04_evaluation is modified.
#
# See rules.md ("Final FluSight Submission Prep") and AGENTS.md.

# ---- Required packages -------------------------------------------------------
pkgs <- c("readr", "dplyr")
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

# ---- Paths -------------------------------------------------------------------
forecast_csv <- "output/data/03_forecast/XGB_flusight_forecasts.csv"
submit_dir   <- "output/data/final_flusight_submission"

# Guard: only ever write into the submission folder.
if (basename(submit_dir) != "final_flusight_submission") {
  stop("Refusing to write: output directory is not final_flusight_submission")
}

dir.create(submit_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(forecast_csv)) stop(paste0("Missing input: ", forecast_csv))

# ---- Rule 1: Input -----------------------------------------------------------
FLUSIGHT_COLS <- c("reference_date", "target", "horizon", "target_end_date",
                   "location", "output_type", "output_type_id", "value")

fc <- read_csv(
  forecast_csv,
  col_types = cols(
    reference_date  = col_date(),
    target          = col_character(),
    horizon         = col_integer(),
    target_end_date = col_date(),
    location        = col_character(),
    output_type     = col_character(),
    output_type_id  = col_double(),
    value           = col_double()
  )
)

missing_cols <- setdiff(FLUSIGHT_COLS, names(fc))
if (length(missing_cols) > 0) {
  stop(paste0("Input missing FluSight column(s): ", paste(missing_cols, collapse = ", ")))
}
if (nrow(fc) == 0) stop("Input forecast file has zero rows")

# Keep the canonical column order.
fc <- fc %>% select(all_of(FLUSIGHT_COLS))

ref_dates <- sort(unique(fc$reference_date))
cat("Read", nrow(fc), "rows from", forecast_csv, "\n")
cat("Distinct reference dates:", length(ref_dates), "\n\n")

# ---- Rule 2: Split and Write -------------------------------------------------
FNAME_PATTERN <- "^\\d{4}-\\d{2}-\\d{2}-AmandaXGBoost\\.csv$"

written_files <- character(0)
written_rows  <- 0L

for (rd in ref_dates) {
  rd <- as.Date(rd, origin = "1970-01-01")
  rd_str <- format(rd, "%Y-%m-%d")

  # Same row ordering as the source: by horizon, then ascending quantile.
  grp <- fc %>%
    filter(reference_date == rd) %>%
    arrange(horizon, output_type_id) %>%
    select(all_of(FLUSIGHT_COLS))

  fname <- paste0(rd_str, "-AmandaXGBoost.csv")
  fpath <- file.path(submit_dir, fname)

  # ---- Rule 3: per-file validations (halt on failure) ----
  if (!grepl(FNAME_PATTERN, fname)) {
    stop(paste0("Filename does not match required pattern: ", fname))
  }
  if (nrow(grp) != 69) {
    stop(paste0("Expected 69 rows for reference date ", rd_str, ", got ", nrow(grp)))
  }
  if (length(unique(grp$reference_date)) != 1 || unique(grp$reference_date) != rd) {
    stop(paste0("Non-unique / mismatched reference_date in group ", rd_str))
  }
  if (!identical(names(grp), FLUSIGHT_COLS)) {
    stop(paste0("Column names/order wrong for ", rd_str))
  }

  write_csv(grp, fpath)
  if (!file.exists(fpath)) stop(paste0("Failed to write ", fpath))

  written_files <- c(written_files, fname)
  written_rows  <- written_rows + nrow(grp)

  cat("[ok]", rd_str, "->", fname, "|", nrow(grp), "rows\n")
}

# ---- Rule 3: cross-file validations ------------------------------------------
cat("\n--- Final validations ---\n")

if (length(written_files) != length(ref_dates)) {
  stop(paste0("Wrote ", length(written_files), " files for ",
              length(ref_dates), " reference dates"))
}
cat("[val] one file per reference date:", length(written_files), "files: OK\n")

if (!all(grepl(FNAME_PATTERN, written_files))) {
  stop("Some filenames do not match {YYYY-MM-DD}-AmandaXGBoost.csv")
}
cat("[val] all filenames match {YYYY-MM-DD}-AmandaXGBoost.csv: OK\n")

if (written_rows != nrow(fc)) {
  stop(paste0("Row total mismatch: wrote ", written_rows, ", source had ", nrow(fc)))
}
cat("[val] total rows written equals source:", written_rows, "= OK\n")

on_disk <- list.files(submit_dir, pattern = FNAME_PATTERN)
if (length(on_disk) != length(written_files)) {
  stop("Files on disk do not match the files written this run")
}
cat("[val] all files present on disk: OK\n")

cat("\nDone: wrote", length(written_files), "files (", written_rows, "rows ) to",
    submit_dir, "\n")
