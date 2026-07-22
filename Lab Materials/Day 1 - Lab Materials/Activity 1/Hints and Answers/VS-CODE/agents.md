# Data Cleaning Agent — `clean_flu_admissions`

## Purpose

Turn the raw NHSN Hospital Respiratory Data (HRD) file into a tidy, three-column
US influenza admissions dataset and produce an epicurve figure. This agent is the
executable form of `rules.md`: every rule there is implemented as a step below and
enforced by a validation check.

## Scope

- Owns: `output/scripts/01_cleaning.R`
- Reads: `data/Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv`
- Writes:
  - `output/data/01_cleaning/cleaned_flu_admissions.csv`
  - `output/figures/01_cleaning/epicurve_us_flu_admissions.png`
- Does not modify anything in `data/`. The raw file is read-only.

## Working directory

The script uses paths relative to the project root (the folder containing `data/`).
Run it from that folder:

```r
setwd("<path to>/DEMO")
source("output/scripts/01_cleaning.R")
```

or from a terminal: `Rscript "output/scripts/01_cleaning.R"`

## Dependencies

`readr`, `dplyr`, `ggplot2`. The script stops with a clear message naming any
package that is missing rather than failing partway through.

## Steps (ordered)

1. **Load the data** — read the CSV with `readr::read_csv()`, importing only the
   three columns that are needed (`Week Ending Date`, `Geographic aggregation`,
   and the influenza admissions column). Import everything as `character` so the
   ~400 unrelated columns cannot trigger parsing warnings, then convert types
   explicitly.
2. **Filter to US only** — keep rows where `Geographic aggregation == "USA"`.
   Note the raw value is `"USA"`; the output label is `"US"`.
3. **Select the target column** — accept `Total.Influenza.Admissions` or
   `Total Influenza Admissions`, in that order of preference. Stop with an
   actionable error if neither is present.
4. **Reshape to three columns** — produce exactly `week`, `location`, `value`, in
   that order, with `location` set to `"US"` on every row. Parse `value` with
   `readr::parse_number()` so comma-formatted counts such as `"1,110"` become
   `1110`. Do not use `parse_double()` on those strings.
5. **Format dates** — convert `Week Ending Date` to a `Date` in `week` (the file
   uses ISO `YYYY-MM-DD`) and sort ascending by `week`.
6. **Save the cleaned data** — write `cleaned_flu_admissions.csv` to
   `output/data/01_cleaning/`, creating the folder if needed.
7. **Generate the epicurve** — bar-style plot of `value` (numeric) against `week`,
   saved to `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.

## Validation checks (stop on failure)

Each check calls `stop()` with a message naming the failed rule:

- Row count is greater than 0.
- Column names are exactly `week`, `location`, `value`, in that order.
- Every `location` value is `"US"`.
- `week` inherits class `Date`, with no `NA` after parsing.
- `value` is numeric.
- `value` has no `NA` after parsing.
- The output CSV exists at `output/data/01_cleaning/cleaned_flu_admissions.csv`.
- The figure exists at `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.

## Failure behavior

Stop immediately on the first failed check and print a diagnostic that says which
check failed and what was observed instead. Never write a partial or unvalidated
output file — validation runs before the CSV is written.

## Conventions

- Create output directories with `dir.create(..., recursive = TRUE)` before writing.
- Refer to raw columns with backticks; they contain spaces.
- Keep the script re-runnable: running it twice produces identical outputs.
- Print a short summary (rows written, date range, output paths) on success.

## Expected result

As of the current data file: 307 US weeks spanning 2020-08-08 through 2026-06-20,
no missing values.
