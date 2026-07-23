# Agent Instructions

Purpose
- Convert the raw NHSN HRD influenza CSV into a tidy, three-column dataset and produce required figures and downstream scripts per `rules.md`.

Data cleaning task (script: `01_cleaning.R`)
1. Load only required columns from `data/Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv` using `readr::read_csv()` as characters:
   - `Week Ending Date`
   - `Geographic aggregation`
   - Influenza admissions column (see selection rule)
2. Filter: keep rows where `Geographic aggregation` == "USA".
3. Select influenza admissions column: accept only `Total.Influenza.Admissions` or `Total Influenza Admissions`. If neither column exists, stop with a clear error.
4. Reshape/rename to exactly three columns (in order): `week`, `location`, `value`.
   - Set `location` to the literal "US" for all rows.
   - Parse `value` with `readr::parse_number()` to handle comma-formatted counts.
5. Convert `Week Ending Date` into a `Date` and assign to `week`. Sort by `week` ascending.
6. Save cleaned CSV to `output/data/01_cleaning/cleaned_flu_admissions.csv`.
7. Create an epicurve bar plot and save to `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.
   - X: `week`; Y: `value` (numeric). Ensure heights passed to `barplot()` are numeric (e.g., `as.numeric(value)`).

Required validation checks (fail fast with informative messages)
- Data has > 0 rows.
- Column names are exactly `week`, `location`, `value` in that order.
- `location` values are all "US".
- `week` inherits `Date` class.
- `value` is numeric and contains no `NA` after parsing.
- Output CSV exists at `output/data/01_cleaning/cleaned_flu_admissions.csv`.
- Epicurve image exists at `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.

Visualization tasks (save code to `output/scripts/02_data_explore.R`)
- Ensure output folder exists before writing the script.

National Trend (script behavior)
- Read input from `output/data/01_cleaning/cleaned_flu_admissions.csv`.
- Validate column names and types; attempt to parse if violations; if parsing fails, stop with: `The {column} could not be parsed.`
- Season rules:
  - Season spans MMWR week 40 through week 20 of the following year.
  - Use YYYY-YY naming (example: `2025-26`).
  - Current season is `2025-26`.
  - Season start: first calendar date in the first year with epiweek == 40.
  - Season end: earliest calendar date in the second year with epiweek == 20.
  - When mapping dates with epiweek >= 40 that fall in months Jan–Aug, attribute them to previous year's season (season_start_year = year - 1).
    - Implementation detail: compute `season_start_year` using the calendar
      year of the `week` date (i.e., `year(week)`) when calling the assignment
      logic. Do not rely on `MMWRyear` returned by `MMWRweek()` as the base
      year, since that can mis-attribute dates around calendar boundaries. In
      practice: pass `year(week)` into the season-assignment helper so that
      dates in early January are attributed correctly per the month-based rule.
- Print exactly two messages reporting the season boundaries:
  - `Season Start Week:` YYYY-MM-DD
  - `Season End Week:` YYYY-MM-DD
- Plot specification for `output/figures/02_data_explore/national_trend.png` (300 DPI):
  - Line chart, blue; X = `week`, Y = `value`.
  - X-axis labels in `MM-YYYY` format; show only every 6th date (STRICT RULE: only show every 6 dates) and tilt 45°.
  - Y-axis starts at 0 and max tick at data max plus 10000.
  - Title: `USA Weekly Influenza Hospitalization Admissions` (bold, centered).
  - Add a light grey season highlight rectangle spanning season start to end behind all plot elements with the label `2025-26 Season` in bold placed at the top of the highlight.

Seasonal Comparison (script behavior)
- Read and validate input as above; attempt to parse columns; on parse failure, stop with `The {column} could not be parsed.`
- Build seasons using MMWR weeks 40–53 then 1–20 so the season is continuous (weeks 1–20 placed after 40–53).
- Only plot seasons up to and including the current season `2025-26`; do not plot data after the current season.
- Save to `output/figures/02_data_explore/seasonal_comparison.png` (300 DPI).
- Plot specs:
  - Line chart where each season is a line; X-axis labeled `Week of Season` using numeric MMWR week numbers; show every other week label only; tilt 45°.
  - Y-axis starts at 0 and max tick at data max plus 10000.
  - Title: `USA Weekly Influenza Hospitalization Admissions` (bold, centered).
  - Legend: single legend titled **Season** mapping color and linetype to each season. Non-current seasons dashed; current season solid, black, thicker line. Legend must match final plotted appearance (no overlay tricks).

Peak Analysis (script behavior)
- Read and validate input as above; attempt to parse columns; on parse failure, stop with `The {column} could not be parsed.`
- Strict: Only analyze the CURRENT SEASON (`2025-26`). Ignore other seasons.
- Season start/end rules same as above (include month-based season attribution rule).
- Determine:
  - `Peak_Time`: date of the global max within the current season (must be a date present in the input).
  - `Peak_Intensity`: corresponding numeric value.
  - `Decline_Start`: the week date when the decline begins. This must be
    deterministically computed and preserved as a `Date` in the output CSV
    (ISO format `YYYY-MM-DD`). Recommended/implemented rule: the first
    calendar `week` after the `Peak_Time` for which the current week's
    `value` is strictly less than the previous week's `value`. Avoid
    `ifelse()`-style coercion when constructing the output (it can convert
    `Date` to numeric); use explicit `as.Date()` when needed before writing
    the CSV.
  - `Season_Start` and `Season_End` dates.
- Save CSV to `output/data/02_data_explore/peak_description.csv` with columns (in order): `Peak_Time` (Date), `Peak_Intensity` (numeric), `Decline_Start` (Date), `Season_Start` (Date), `Season_End` (Date).

Strict rules & error handling
- Fail fast with informative errors when required inputs/columns are absent or cannot be parsed.
- Do not drop weeks 1–20 when producing seasonal views; ensure season ordering is 40–53 then 1–20.
- When the rules require the current season to be `2025-26`, ensure plots and peak calculations exclude any later dates.

Outputs (summary)
- `output/data/01_cleaning/cleaned_flu_admissions.csv` (CSV)
- `output/figures/01_cleaning/epicurve_us_flu_admissions.png` (PNG)
- `output/scripts/02_data_explore.R` (R script)
- `output/figures/02_data_explore/national_trend.png` (PNG)
- `output/figures/02_data_explore/seasonal_comparison.png` (PNG)
- `output/data/02_data_explore/peak_description.csv` (CSV)

Notes for implementer
- Create any missing output directories before writing files.
- Use `readr` and base plotting or `ggplot2` in R, but ensure numeric conversions and `Date` conversions are explicit and validated.
- Document the method used to compute `Decline_Start` inside the script.

Contact
- If a parsing issue cannot be resolved programmatically, stop and return a clear error message as specified above.

---

# Activity 3: Modeling and Forecasting

Forecasting task (script: `output/scripts/03_forecast.R`)

1. Read `output/data/01_cleaning/cleaned_flu_admissions.csv` and validate
   exactly `week`, `location`, `value`: parse `week` as Date, `value` as
   numeric, and require every `location` to be `US`. If parsing cannot be
   completed, stop with `The {column} could not be parsed.`
2. Use the existing MMWR week-40-to-week-20 season definition and label
   `2025-26` as current. Assign season start years from `year(week)`, not
   `MMWRyear`; map early-January/August-or-earlier epiweeks >= 40 to the
   previous season. Print the 2025-26 season boundaries.
3. Test only on `2025-26`. Define reference dates as observed weeks whose
   one-week-ahead target is observed and in the testing season. At each
   reference date, train on all rows with `week <= reference_date`. This is an
   expanding window and is the required protection against data leakage.
4. Fit exactly one non-seasonal `forecast::auto.arima()` model per reference
   date, using only the ordered admissions value vector: no covariates,
   external regressors, or separate refit per horizon. Generate all three
   horizons with one `forecast(fit, h = 3, level = LEVELS)` call, where
   `LEVELS <- c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)`.
5. Before each fit, validate sorted, unique weekly dates with no seven-day
   gaps; numeric, non-negative, non-missing, nonconstant response; and a
   successful model fit. Print the training/testing/reference dates, horizons,
   and selected ARIMA `(p,d,q)` order.
6. Extract the mean as quantile 0.5 and all lower/upper interval endpoints for
   horizons 1, 2, and 3. Use the exact 23 FluSight quantile levels:
   `0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
   0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 0.975, 0.99`.
   Clamp at zero and round emitted values to non-negative integers.
7. Write `output/data/03_forecast/flusight_forecasts.csv` with columns in this
   exact order: `reference_date`, `target`, `horizon`, `target_end_date`,
   `location`, `output_type`, `output_type_id`, `value`. Use `wk inc flu hosp`
   for target, `US` for location, `quantile` for output_type, ISO Date values,
   and `target_end_date = reference_date + 7 * horizon`. Emit 69 rows per
   reference date (3 horizons by 23 quantiles).
8. Validate finite forecast values; nondecreasing quantiles; the exact
   23-level set per reference-date/horizon; correct target dates; one model fit
   yielding exactly horizons 1, 2, 3; 95% PI widths h3 >= h2 >= h1; and,
   before clamping/rounding, median centering and symmetric quantile pairs.
   Print the required `[val]` success messages and stop on failures.
9. Create `output/figures/03_forecast/forecast_vs_observed.png` at 300 DPI.
   Plot black observed 2025-26 values, distinct colorblind-friendly median
   lines and points for 1-, 2-, and 3-week horizons, and matching low-opacity
   95% PI ribbons behind them. Use the required axis labels, weekly x-axis
   labels every four weeks, zero-based y-axis ending 10,000 above the plotted
   maximum, specified bold centered title, and a comprehensive legend.

Create all missing output directories before writing. Confirm both Activity 3
output files exist after writing.
