# Data Cleaning Agent — `clean_flu_admissions`

## Purpose
Turn the raw NHSN HRD influenza CSV into a tidy three-column dataset and
produce an epicurve figure. The agent implements the cleaning rules from
`rules.md` as a reproducible, checkable process.

## Inputs
- `data/Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv`

## Outputs
- `output/data/01_cleaning/cleaned_flu_admissions.csv`
- `output/figures/01_cleaning/epicurve_us_flu_admissions.png`

## Steps (ordered)
1. Load the data
   - Use `readr::read_csv()` to read the CSV from the `data/` folder.
   - Import only these columns as `character` initially:
     - `Week Ending Date`
     - `Geographic aggregation`
     - One of the allowed influenza admissions columns (see Step 3)

2. Filter to US only
   - Keep only rows where `Geographic aggregation` == `"USA"`.

3. Select the target column
   - Allowed names (in order of preference):
     - `Total.Influenza.Admissions`
     - `Total Influenza Admissions`
   - If neither column exists, the agent must stop with a clear error message.

4. Reshape to three columns
   - Rename and produce exactly these columns, in this order:
     1. `week`
     2. `location` — set every row to the string `"US"`
     3. `value`
   - Parse `value` using `readr::parse_number()` so comma-formatted numbers parse
     correctly (e.g., `"1,110"` -> `1110`). Do not use `parse_double()` on
     comma-formatted strings directly.

5. Format dates
   - Convert `Week Ending Date` into an R `Date` object and store in `week`.
   - Sort the data ascending by `week`.

6. Save the cleaned data
   - Write `cleaned_flu_admissions.csv` to `output/data/01_cleaning/`.

7. Generate epicurve
   - Produce an epicurve saved to
     `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.
   - Plot specs:
     - X-axis: `week`
     - Y-axis: `value` (ensure numeric; use e.g. `as.numeric(value)`)
     - Use a bar plot (or similar) that accepts a numeric `height` vector.

## Validation checks (must stop on failure)
- Row count > 0 after cleaning.
- Column names are exactly `week`, `location`, `value` in that order.
- All values in `location` are the string `"US"`.
- `week` column inherits from `Date`.
- `value` is numeric.
- `value` contains no `NA` after parsing.
- Output CSV exists at `output/data/01_cleaning/cleaned_flu_admissions.csv`.
- Epicurve file exists at `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.

## Failure behavior
- When a validation fails, the agent must stop execution and print a clear
  diagnostic message explaining which check failed and why.

## Implementation notes / best practices
- Read required columns as `character` first, then explicitly parse/convert
  (`readr::parse_number()`, `as.Date()` with an appropriate format).
- Create output directories if they do not exist before writing files.
- Keep error messages user-friendly and actionable.
- Prefer base R plotting or `ggplot2` as available; ensure the plotting input
  uses numeric types to avoid `height` errors in bar plots.

## Example R pseudocode outline

1. Read CSV with `col_select` or `select()` to the minimal columns.
2. Detect the influenza column name, error if missing.
3. Subset to `Geographic aggregation == "USA"`.
4. Build a tibble/data.frame with columns `week`, `location` ("US"), `value`.
5. Parse numbers and dates, sort, run validations.
6. Write CSV and save plot.

---

Generated from `rules.md` to be used by an automated agent or as a human
checklist for `01_cleaning.R` implementation.