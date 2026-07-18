# AGENTS.md

Agent instructions for this project. The task is to generate an R script,
`01_cleaning.R`, that transforms the raw NHSN HRD influenza file into a tidy,
three-column dataset and produces an epicurve figure. These instructions are
derived from [rules.md](rules.md); if the two ever disagree, `rules.md` wins.

## Project layout

```
Bleichrodt_Amanda/
├── data/
│   └── Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv
├── output/
│   ├── data/01_cleaning/
│   │   └── cleaned_flu_admissions.csv          # produced by the script
│   └── figures/01_cleaning/
│       └── epicurve_us_flu_admissions.png      # produced by the script
├── rules.md
└── AGENTS.md
```

Create any `output/` subfolders that do not exist before writing to them
(`dir.create(..., recursive = TRUE, showWarnings = FALSE)`).

## Conventions

- **Language:** R.
- **Primary package:** `readr` for I/O and parsing. Base R (`barplot`) is
  acceptable for the epicurve; `ggplot2` is fine if preferred, but keep the
  numeric-vector requirement below in mind either way.
- **Determinism:** the script must be re-runnable from a clean checkout and
  produce identical outputs.
- **Fail loud:** validation checks must `stop()` on failure — never warn and
  continue.

## Build the script: `01_cleaning.R`

Follow these steps in order.

### 1. Load the data
Read the NHSN HRD CSV from `data/` with `readr::read_csv()`. Import **only** the
required columns to avoid parsing warnings from unrelated fields:

- `Week Ending Date`
- `Geographic aggregation`
- the influenza admissions column (see step 3)

Import these as character first, then parse/convert explicitly.

### 2. Filter to US only
Keep only rows where `Geographic aggregation == "USA"`.

### 3. Select the target column
Use the influenza admissions column, accepting either allowed name:

- `Total.Influenza.Admissions`
- `Total Influenza Admissions`

If neither column exists, `stop()` with a clear error message.

### 4. Reshape to three columns
Restructure to exactly three columns, in this order:

- `week`
- `location` — constant `"US"`
- `value`

Parse `value` with `readr::parse_number()` so comma-formatted counts like
`1,110` are handled. Do **not** call `parse_double()` directly on those values.

### 5. Format dates
Convert `Week Ending Date` into an R `Date` in `week`. Sort ascending by `week`.

### 6. Save the cleaned data
Write to `output/data/01_cleaning/cleaned_flu_admissions.csv`.

### 7. Generate the epicurve
Create an epicurve from the cleaned data and save to
`output/figures/01_cleaning/epicurve_us_flu_admissions.png`.

- X-axis: `week`
- Y-axis: `value`
- Ensure the plotting height input is a numeric vector (e.g.
  `as.numeric(value)`) so `barplot()` does not fail with height-type errors.

### 8. Validation checks (must `stop()` on failure)
Include checks that halt execution when any of these fail:

- [ ] Row count is greater than 0
- [ ] Column names are exactly `week`, `location`, `value`, in that order
- [ ] `location` is always `"US"`
- [ ] `week` inherits class `Date`
- [ ] `value` is numeric
- [ ] `value` has no `NA` values after parsing
- [ ] Output CSV exists at `output/data/01_cleaning/cleaned_flu_admissions.csv`
- [ ] Epicurve exists at `output/figures/01_cleaning/epicurve_us_flu_admissions.png`

## Definition of done

Running `Rscript 01_cleaning.R` from the project root completes without error,
writes both output files, and passes every validation check in step 8.
