# Data Cleaning Rules

These rules define how the agent should generate `01_cleaning.R`. Follow each
step in order. The goal is to turn the raw NHSN HRD influenza file into a tidy,
three-column dataset ready for downstream modeling and produce an epicurve
figure.

## 1. Load the data

Read the NHSN HRD CSV from the `data/` folder using **readr** (`read_csv()`).
To avoid parsing warnings from unrelated fields, import only required columns:

- `Week Ending Date`
- `Geographic aggregation`
- Influenza admissions column (see Rule 3)

Import these columns as character first, then parse/convert explicitly.

## 2. Filter to US only

Use the `Geographic aggregation` column. Keep only the rows where the value is
`"USA"`.

## 3. Select the target column

Use influenza admissions from one of these allowed column names:

- `Total.Influenza.Admissions`
- `Total Influenza Admissions`

Fail with a clear error if neither exists.

## 4. Reshape to three columns

Rename and restructure the data to exactly three columns:

- `week`
- `location` — set to `"US"`
- `value`

Convert `value` with `readr::parse_number()` so values like `1,110` are valid.
Do not use `parse_double()` directly on comma-formatted counts.

## 5. Format dates

Convert `Week Ending Date` to an R `Date` object in `week`. Sort ascending by
`week`.

## 6. Save the output

Write the cleaned data to `cleaned_flu_admissions.csv` in the `output/data/01_cleaning` folder.

## 7. Generate epicurve figure

Create an epicurve from the cleaned data and save to:

- `output/figures/01_cleaning/epicurve_us_flu_admissions.png`

Plot requirements:

- X-axis: `week`
- Y-axis: `value`
- Ensure plotting input is a numeric vector (for example `as.numeric(value)`) so
	`barplot()` does not fail with height-type errors.

## 8. Required validation checks

The script must include checks that stop execution on failure:

- Row count is greater than 0
- Column names are exactly `week`, `location`, `value` in that order
- `location` is always `"US"`
- `week` inherits class `Date`
- `value` is numeric
- `value` has no `NA` values after parsing
- Output CSV exists at `output/data/01_cleaning/cleaned_flu_admissions.csv`
- Epicurve file exists at `output/figures/01_cleaning/epicurve_us_flu_admissions.png`

---

# Visualization

Save all code in this section to the following output script:

Output folder: `output/scripts/02_data_explore.R`

If the folder pathway is not present, create the folder pathway prior to saving the script. 

## National Plot

## 1. Input Data

Read in the input data set from `output/data/01_cleaning/cleaned_flu_admissions.csv`. Ensure the column names and column types/formats match the following:

- `week`: Date column, YYYY-MM-DD
- `location`: Character; all values should be "US" 
- `value`: Numeric 

If any columns have violations please first try to parse to the correct format, and then notify the user. If any columns can not be parsed, please return the following error: 

'The {column} could not be parsed.'

## 2. Season Rules 

A 'season' spans from MMWR week 40 through week 20 of the following year. 

- Labeling Rule: A season spans two calendar years and is named for both. Use a YYYY-YY naming scheme (Example: `2025-26`)

- Current Season: `2025-26`
- Season Start: first calendar date in the first year with epiweek == 40. This is a fixed calendar week and should be the same every season. Please account for any leap years in this determination as well.
- Season End: earliest calendar date in the second year with epiweek == 20.

Implementation note: when computing `season_start_year` for each `week`, use
the calendar year of the date (`year(week)`) as the base year passed to the
assignment logic — do not use the `MMWRyear` returned by `MMWRweek()` as the
base. This avoids mis-attribution when MMWR week numbers span calendar-year
boundaries.

Return the current season determination as a message using the following format:

`Season Start Week:` {Season start week YYYY-MM-DD}
`Season End Week:` {Season end week YYYY-MM-DD}

## 3. Plotting 

Output the figure created in this section to the following pathway:

`output/figures/02_data_explore/national_trend.png`

If the folder path is not present, create the folder prior to saving the image. 

Image save requirements:

- 300 DPI

`Figure Specifications:`

- `Plot Type`: Line Chart; Blue
- `X-Axis Label`: 'Week'
- `Y-Axis Label`: 'Weekly Influenza Hospitalizations`
- `X-Axis Range/Tick Labels`: Use MM-YYYY Format; Only show every other date to ensure all dates can be seen. Tilt the dates to 45 degrees. 

**`STRICT RULE`: Only show every 6 dates.**

- `Y-Axis Range/Tick Labels`: Start at 0 and max label at 10000 past max point in the data. 
- `Plot Title`: 'USA Weekly Influenza Hospitalization Admissions'; Bold; Centered
- `Season Highlight`: Light Grey bar that spans the vertical height of the figure. It starts on the first day of the current season and ends on the last day of the current season. Do not change the x-axis labels AT ALL in the highlight. **Strict Rule:** The box should sit behind all other graph elements (i.e., in the background).
- `Season Highlight Label`: Label should sit in the season highlight bar at the top of the plot. Explicitly use "2025-26 Season" and bold it. 

## Season Plot 

## 1. Input Data

Read in the input data set from `output/data/01_cleaning/cleaned_flu_admissions.csv`. Ensure the column names and column types/formats match the following:

- `week`: Date column, YYYY-MM-DD
- `location`: Character; all values should be "US" 
- `value`: Numeric 

If any columns have violations please first try to parse to the correct format, and then notify the user. If any columns can not be parsed, please return the following error: 

'The {column} could not be parsed.'

## 2. Season Rules 

A 'season' spans from MMWR week 40 through week 20 of the following year. 

- Labeling Rule: A season spans two calendar years and is named for both. Use a YYYY-YY naming scheme (Example: `2025-26`)

 - Current Season: `2025-26`
 - Season Start: first calendar date in the first year with epiweek == 40. This is a fixed calendar week and should be the same every season. Please account for any leap years in this determination as well.
 - Season End: earliest calendar date in the second year with epiweek == 20.

Return the current season determination as a message using the following format:

`Season Start Week:` {Season start week YYYY-MM-DD}
`Season End Week:` {Season end week YYYY-MM-DD}

## 3. Plotting 

Output the figure created in this section to the following pathway:

`output/figures/02_data_explore/seasonal_comparison.png`

If the folder path is not present, create the folder prior to saving the image. 

Image save requirements:

- 300 DPI

`Figure Specifications:`

- `Plot Type`: Line Chart; Each season is its own line, where a season is defined using the above mentioned rules. All seasons should share the same x-axis. Only show points weeks 40 through 20. 

`X-Axis Label`: 'Week of Season'
`Y-Axis Label`: 'Weekly Total Influenza Admissions (USA)'
`X-Axis Range/Tick Labels`: Use numeric MMWR week number only (e.g., 40, 41, ...). Only show every other week number to ensure readability; tilt the labels 45°. This is a hard rule.
`Y-Axis Range/Tick Labels`: Start at 0 and max label at 10000 past max point in the data.
`Plot Title`: 'USA Weekly Influenza Hospitalization Admissions'; Bold; Centered
`Legend/Line Style`: Use a single legend titled **Season** that maps both color and linetype to each season. Non-current season lines should be dashed; the current season line should be solid and visually emphasized by increased line width (thicker). Do not overlay a separate black line; the legend must match the final plotted appearance (color + linetype) and show the current season as solid.

- `Legend/Line Style`: Use a single legend titled **Season** that maps both color and linetype to each season. Non-current season lines should be dashed; the current season line should be solid, black, and visually emphasized by increased line width (thicker). Do not overlay a separate black line; the legend must match the final plotted appearance (color + linetype) and show the current season as solid.

The current season is `2025-26` do not plot anything after this.

Note: the seasonal plot must present the full season chronologically by plotting MMWR weeks 40–53 followed by weeks 1–20 (so weeks 1–20 appear after 40–53 on the x-axis). The plotting implementation must ensure weeks 1–20 are not dropped and are positioned after weeks 40–53 so the full season displays continuously.

## Peak Analysis 

## 1. Input Data

Read in the input data set from `output/data/01_cleaning/cleaned_flu_admissions.csv`. Ensure the column names and column types/formats match the following:

- `week`: Date column, YYYY-MM-DD
- `location`: Character; all values should be "US" 
- `value`: Numeric 

If any columns have violations please first try to parse to the correct format, and then notify the user. If any columns can not be parsed, please return the following error: 

'The {column} could not be parsed.'

## 2. Season Rules 

**STRICT:** Disregard any season definition rules above. 

A 'season' spans from MMWR week 40 through week 20 of the following year. 

- Labeling Rule: A season spans two calendar years and is named for both. Use a YYYY-YY naming scheme (Example: `2025-26`)

 - Current Season: `2025-26`
 - Season Start: first calendar date in the first year with epiweek == 40. This is a fixed calendar week and should be the same every season. Please account for any leap years in this determination as well.
 - Season End: earliest calendar date in the second year with epiweek == 20. Please account for any leap years in this determination as well.

- Season-to-date mapping note: when mapping calendar dates to MMWR epiweeks,
  handle week numbers that fall in early January (for example epiweek 53)
  by using the calendar month to assign the season start year. Concretely:
  if a date's epiweek is >= 40 but its calendar month is January–August,
  attribute that date to the previous year's season (i.e., season_start_year = year - 1).

Return the current season determination as a message using the following format:

`Season Start Week:` {Season start week YYYY-MM-DD}
`Season End Week:` {Season end week YYYY-MM-DD}

## 3. Peak Output

Output the data created in this section to the following pathway:

`output/data/02_data_explore/peak_description.csv`

If the folder path is not present, create the folder prior to saving the CSV. 

`Data Specifications`

`Strict Rule`: Only apply the rules and data filtering to the CURRENT SEASON (2025-26). Ignore all other seasons of data. 
`Strict Rule`: Only return dates that are also present in the input data set.

- `Column Names, Order, and (Type)`: Peak_Time (Date, YYYY-MM-DD), Peak_Intensity (Numeric), Decline_Start (Date, YYYY-MM-DD), Season_Start (Date, YYYY-MM-DD), Season_End (Date, YYYY-MM-DD)
- `Peak Time`: The date on which the global max for the season spanning two years was reached. To determine, take all values that occured during the season and determine the week in which the max of those values occured.  
- `Peak Intensity`: The value that corresponds to result of peak time.  
- `Decline Start`: The week in which the decline of the season starts. 
- `Season Start`: The start week date of the season. 
- `Season End`: The end week date of the season. 

Implementation note: `Decline_Start` must be a `Date` and deterministically
computed. The canonical rule to use (and the one implemented in
`output/scripts/02_data_explore.R`) is: the first date after the season
`Peak_Time` on which the `value` is strictly less than the previous week's
`value`. Preserve `Decline_Start` as a `Date` when writing CSV (avoid
`ifelse()`-style coercion which can convert dates to numeric).

---
 
# Forecasting
 
Save all code in this section to the following output script:
 
Output folder: `output/scripts/03_forecast.R`
 
If the folder pathway is not present, create the folder pathway prior to saving the script.
 
## 1. Input Data
 
Read in the input data set from `output/data/01_cleaning/cleaned_flu_admissions.csv`. Ensure the column names and column types/formats match the following:
 
- `week`: Date column, YYYY-MM-DD
- `location`: Character; all values should be "US"
- `value`: Numeric
If any columns have violations please first try to parse to the correct format, and then notify the user. If any columns can not be parsed, please return the following error:
 
'The {column} could not be parsed.'
 
## 2. Season Rules
 
Use the season definition established earlier in this document (do **not** redefine it here):
 
A 'season' spans from MMWR week 40 through week 20 of the following year.
 
- Labeling Rule: A season spans two calendar years and is named for both. Use a YYYY-YY naming scheme (Example: `2025-26`).
- Current Season: `2025-26`
- Season Start: first calendar date in the first year with epiweek == 40. This is a fixed calendar week and should be the same every season. Account for leap years.
- Season End: earliest calendar date in the second year with epiweek == 20.
Implementation note: when computing `season_start_year` for each `week`, use the
calendar year of the date (`year(week)`) as the base year passed to the assignment
logic — do not use the `MMWRyear` returned by `MMWRweek()` as the base.

Season-to-date mapping note (same as Peak Analysis): an MMWR week `>= 40` can
land in early January (for example epiweek 53 on a first-week-of-January date).
Handle this by the calendar month: if a date's epiweek is `>= 40` **and** its
calendar month is January–August, attribute it to the previous year's season
(`season_start_year = year - 1`). This keeps a winter season continuous across
the calendar-year boundary so no mid-season week is dropped.
 
Assign every row in the input to a season using this logic. Define a **complete
season** as any season for which both the Season Start (week 40) and Season End
(week 20 of the following year) are present in the data.
 
Return the current season determination as a message using the following format:
 
`Season Start Week:` {Season start week YYYY-MM-DD}
`Season End Week:` {Season end week YYYY-MM-DD}
 
## 3. Training and Testing Periods

- `Training Period`: all observed weeks strictly before the first week of the testing period present in the data. Use these rows as the fixed initial training set; subsequent forecasts use an expanding window that adds earlier test-season weeks as they become observed.
- `Testing Period`: the `2025-26` season only.
- `Forecast Horizons`: 1, 2, and 3 weeks ahead (`horizon ∈ {1, 2, 3}`). Every
  reference date produces all three horizons and no others. Do not forecast any
  other horizon.

**`STRICT RULE`:** Forecasts are produced with an **expanding window** keyed on a
**reference date**. Define the set of reference dates as every observed week `r`
such that the 1-week-ahead target `r + 7` falls within the testing period and is
present in the input data (this preserves the original 1-week anchoring). For
each reference date the model is fit on all observed weeks with `week <= r`. The
initial fitting window is the set of weeks strictly before the first testing-week
present in the data; as each test week becomes observed it is added to the
fitting window for subsequent reference dates.

**`STRICT RULE`:** For each reference date the model is fit **exactly once**, and
all three horizons (h = 1, 2, 3) are taken from that single forecast object (a
single `forecast(fit, h = 3, level = LEVELS)` call, with `LEVELS` as defined in
Rule 5 step 3). Do **not** refit per horizon.

**`STRICT RULE`:** The 1-week-ahead (`horizon = 1`) target of every reference
date must be present in the input data (so each reference date has an observed
value to anchor against). The 2- and 3-week-ahead targets are still emitted even
when they fall beyond the last observed week.

**Validations:** Print the `Training Period` start date, and the rolling-window end (reference) dates. 
**Validations:** Print the `Testing Period` start date, and each reference date together with its three target dates. 
**Validations:** Print the specified forecasting horizons that will be used (`1, 2, 3`). 

## 4. Model Specification

- Package: **forecast** (`forecast::auto.arima()`).
- Response: the influenza admissions series **only.** Sort the training window by `week`, extract the ordered value vector, and use that as the only input. No covariates or external regressors are permitted.
- Model class: a non-seasonal ARIMA whose order is selected automatically by `auto.arima()`. The series is passed as a plain numeric vector, so `auto.arima()` performs its own `(p, d, q)` selection.

**Validations:** Print confirmation that the training window is sorted ascending by `week` with no missing or duplicate weeks.
**Validations:** Print confirmation that the `week` index is evenly spaced (no skipped weeks); halt if this fails.
**Validations:** Print the extracted response vector's length, and confirm it is numeric, non-negative, and free of `NA` values.
**Validations:** Print confirmation that the series is not constant before fitting.
**Validations:** Print the `(p, d, q)` order that `auto.arima()` selected at each reference-date refit (one fit per reference date, reused for all three horizons).
**Validations:** Print confirmation that the fit succeeded at each reference date (a non-null model was returned).

## 5. Forecast Generation

For each reference date `r` in the testing period (defined in Rule 3):

1. Use `r` directly as the `reference_date` (a calendar `Date`) for both
   training-window selection and for output. When writing CSVs, format
   `reference_date` and `target_end_date` as ISO dates (`YYYY-MM-DD`).
2. Fit the ARIMA model (Rule 4) **once** on all rows with `week <= reference_date`
   (expanding-window).
3. Forecast with a single call `forecast(fit, h = 3, level = LEVELS)`, where
   `LEVELS` is the set of central-interval coverage levels that reproduce every
   required quantile pair (see the table in step 5):
   `c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)`.
4. From the forecast object, pull the point forecast (`mean`, which is the `0.5`
   quantile) plus the lower and upper bound at **every** level for **each** of the
   three horizons. Row `h` of the forecast object is the h-week-ahead value
   (`h = 1, 2, 3`); the lower and upper bounds come back with **one column per
   level**, so a level's lower column is its lower-tail quantile and its upper
   column is its upper-tail quantile. All three horizons and all quantiles must be
   read from this one forecast object — do not refit.

**`STRICT RULE`:** Clamp all forecast values at a floor of 0 (`pmax(value, 0)`)
and round to the nearest integer (admissions are non-negative counts).

**Validations:** Confirm mean, lower, and upper are all finite (no NA/NaN/Inf) at every horizon of every reference date; halt if not.
**Validations:** Confirm the full quantile ladder is non-decreasing within every horizon of every reference date (`0.01 ≤ 0.025 ≤ … ≤ 0.5 ≤ … ≤ 0.975 ≤ 0.99`). Halt on any violation.
**Validations:** Confirm all value entries are non-negative integers.
**Validations:** Confirm intervals get wider (or stay equal) as the horizon grows: the emitted 95% PI width (`0.975` quantile − `0.025` quantile) satisfies width at h=3 ≥ h=2 ≥ h=1 for every reference date. Print `[val] intervals widen with horizon: OK`; `stop()` otherwise.
**Validations:** Confirm `target_end_date == reference_date + 7 * horizon` for every row. Print `[val] target dates correct: OK`; `stop()` otherwise.
**Validations:** Confirm each reference date is fit once, with all three horizons taken from that single forecast (e.g. verify exactly one model object per reference date and exactly three horizons {1,2,3} emitted per reference date). Print `[val] one fit, three horizons: OK`; `stop()` otherwise.
**Validations:** For each reference date and horizon, confirm the quantiles are non-decreasing across every level (`0.01 ≤ 0.025 ≤ … ≤ 0.975 ≤ 0.99`). Print `[val] quantiles non-decreasing: OK`; `stop()` otherwise.
**Validations:** Confirm every reference-date/horizon carries the exact required set of quantile levels — none missing, none extra (exactly the 23 `output_type_id` values, no duplicates). Print `[val] all quantile levels present: OK`; `stop()` otherwise.
**Validations:** Confirm the median (`0.5`) equals the point forecast and that symmetric pairs are equidistant from it (e.g. `0.5 − 0.025` equals `0.975 − 0.5`). Compute this on the **raw** (pre-clamp) forecast, since clamping at 0 and rounding intentionally break symmetry in the emitted counts. Print `[val] median centered, quantiles symmetric: OK`; `stop()` otherwise.

5. **Reshape wide → long, one row per quantile per horizon.** For each horizon,
map each forecast piece to an `output_type_id`: `mean` → `0.5` (median); each
level's lower/upper bound → its two quantiles, per the table. Emit the full
FluSight quantile set — all 23 `output_type_id` values below.

| Coverage Level | LB Quantile (`output_type_id`) | UB Quantile (`output_type_id`) |
|----------------|--------------------------------|--------------------------------|
| 98             | 0.01                           | 0.99                           |
| 95             | 0.025                          | 0.975                          |
| 90             | 0.05                           | 0.95                           |
| 80             | 0.10                           | 0.90                           |
| 70             | 0.15                           | 0.85                           |
| 60             | 0.20                           | 0.80                           |
| 50             | 0.25                           | 0.75                           |
| 40             | 0.30                           | 0.70                           |
| 30             | 0.35                           | 0.65                           |
| 20             | 0.40                           | 0.60                           |
| 10             | 0.45                           | 0.55                           |
| — (median)     | 0.5 (from `mean`)              | —                              |

The 23 quantiles, in order, are: `0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25,
0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90,
0.95, 0.975, 0.99`.

**Write** to `output/data/03_forecast/flusight_forecasts.csv` (create the folder
if absent), keeping the FluSight long format with these columns in order:

| Column            | Type / Value                                    |
|-------------------|-------------------------------------------------|
| `reference_date`  | Date (YYYY-MM-DD)                               |
| `target`          | `"wk inc flu hosp"`                             |
| `horizon`         | `1`, `2`, or `3`                               |
| `target_end_date` | Date — `reference_date + 7 * horizon`           |
| `location`        | `"US"`                                          |
| `output_type`     | `"quantile"`                                    |
| `output_type_id`  | the quantile from the table above (`0.5` = mean)|
| `value`           | forecasted count (Date cols serialize as ISO)   |

Each reference date therefore emits 69 rows: 3 horizons × 23 quantiles.

## 6. Forecast Figure
 
Output the figure to:
 
`output/figures/03_forecast/forecast_vs_observed.png`
 
If the folder path is not present, create the folder prior to saving the image.
 
Image save requirements:
 
- 300 DPI

`Figure Specifications:`
 
- `Plot Type`: Line chart of observed `value` over the testing period
  (`2025-26` season) with the 1-, 2-, and 3-week-ahead forecasts overlaid on the
  same axes.
- `Observed`: solid black line plus points for observed weekly admissions.
- `Forecast Medians`: **one line plus points per horizon** (`h = 1, 2, 3`)
  connecting the `0.5` quantile at each `target_end_date` — just like the current
  single-horizon line, but repeated for each horizon. **Each horizon is its own
  line in a distinct, clearly different color** (use a colorblind-friendly set,
  e.g. h1 = blue, h2 = orange, h3 = green). Map color to horizon.
- `Forecast Intervals`: **one shaded ribbon per horizon** spanning the
  `0.025`–`0.975` quantiles (the 95% PI) at each `target_end_date`, filled with
  the matching horizon color at low opacity. All ribbons must sit **behind** the
  observed and median lines.
- `X-Axis Label`: 'Week'
- `Y-Axis Label`: 'Weekly Influenza Hospitalizations'
- `Y-Axis Range/Tick Labels`: Start at 0 and max label at 10000 past the max
  plotted value (max of observed and all horizons' upper PI bounds).
- `X-Axis Range/Tick Labels:` Use calendar dates from the first observed/target
  week to the last `target_end_date` in the 2025-26 testing period, with weekly
  spacing (7-day increments). Show every 4 date labels, and tilt labels 45 degrees.  
- `Plot Title`: 'USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast (2025-26 Season)';
  Bold; Centered
- `Legend`: A single legend that **clearly includes every graph element** —
  `Observed`, and for each horizon (`1 wk`, `2 wk`, `3 wk`) both its
  **Forecast Median** line and its **95% PI** band. Color must map to horizon
  consistently between each median line and its PI band; the 95% PI legend
  elements show the color swatch for the band.

---

# Forecast Evaluation

Save all code in this section to `output/scripts/04_evaluation.R`. If the folder
path is not present, create it before saving the script.

Use the **scoringutils** package to compute the metrics — do not hand-code the scoring
formulas.

## 1. Input Data

Read the forecasts from `output/data/03_forecast/flusight_forecasts.csv` (the
FluSight long format: one row per `reference_date`, `horizon`, and
`output_type_id` quantile). Read the observed truth from
`output/data/01_cleaning/cleaned_flu_admissions.csv` (`week`, `location`,
`value`).

Join each forecast row to the observed truth by matching the forecast's
`target_end_date` to the observed `week` (both are US, weekly). 

## 2. Scoring with scoringutils

Shape the joined data into the long quantile format that scoringutils expects,
renaming columns to its conventions: `output_type_id` → `quantile_level`,
`value` → `predicted`, and the joined truth → `observed`. Add a constant
`model` column (e.g. `"arima"`).

Build the forecast object with `scoringutils::as_forecast_quantile()`, setting
the forecast unit to `reference_date`, `horizon`, `target_end_date`, `location`,
and `model` so each `reference_date` × `horizon` is scored as its own forecast.
Then call `scoringutils::score()` on it.

From the scored output, take the metrics FluSight reports:

- **WIS** — the `wis` column returned by `score()`.
- **AE** — the `ae_median` column (absolute error of the median forecast).
- **95% PI coverage** — the 95% interval-coverage metric. If `score()`'s
  defaults do not already include it, add it via scoringutils' interval-coverage
  metric at the 95% range (e.g. supply a custom `interval_coverage` metric with
  the interval range set to 95).

## 3. Output Table

Keep one row per scored `reference_date` × `horizon` with these columns in
order: `reference_date`, `horizon`, `target_end_date`, `observed`, `WIS`,
`AE`, `coverage_95`. Sort ascending by `reference_date`, then `horizon`. Round
`WIS` and `AE` to one decimal.

Print the table to the console and write it to
`output/data/04_evaluation/forecast_scores.csv` (create the folder if absent).

## 4. Summary by Horizon

Summarize the per-reference-date scores across all reference dates, grouped by
`horizon`, to show how forecast skill changes with lead time. For each horizon
(`1`, `2`, `3`), compute over that horizon's scored reference dates:

- the **mean** of `WIS`, `AE`, and `coverage_95` (the mean of the per-forecast
  `AE` is the mean absolute error, `MAE`; the mean of the 0/1 coverage is the
  empirical 95% coverage rate), and
- the **range** (minimum and maximum) of `WIS` and `AE`.

Assemble one row per horizon with these columns in order: `horizon`, `n`
(number of scored reference dates), `WIS_mean`, `WIS_min`, `WIS_max`, `MAE_mean`,
`MAE_min`, `MAE_max`, `coverage_95_mean`. Sort ascending by `horizon`. Round the
`WIS_*` and `MAE_*` columns to one decimal and `coverage_95_mean` to two.

Print this table to the console and write it to
`output/data/04_evaluation/forecast_scores_by_horizon.csv`.
