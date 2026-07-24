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

---

# Forecasting with a Wastewater Leading Indicator (ARIMAX)

Save all code in this section to:

Output folder: `output/scripts/05_incremental_changes.R`

If the folder pathway is not present, create the folder pathway prior to saving
the script.

**`STRICT RULE`:** This section is an *additive* variant of the Forecasting
section. Every rule from **Forecasting** (Rules 1, 2, 3, 5, and 6) applies
verbatim and **must not be re-derived or altered**, with exactly these
exceptions, spelled out below:

1. Rule 4 (Model Specification) is replaced by Rule 4W.
2. A new Rule 0W adds a second input (the wastewater series).
3. All output paths gain a `WVAL_` filename prefix (Rule 7W).

**`STRICT RULE`:** Nothing written by `03_forecast.R` or `04_evaluation.R` may be
overwritten. The reference-date set, horizon set, quantile ladder, FluSight
column order, clamping/rounding, and every existing `[val] …: OK` check are
carried over unchanged so the two models are directly comparable.

## 0W. Second Input: National Wastewater (NWSS WVAL)

Read `data/NWSSWVALNational.csv`. Its raw columns are:

- `Pathogen Target` — character
- `Week End` — date in `M/D/YYYY` (US format, not zero-padded)
- `National WVAL` — numeric wastewater viral activity level

Processing steps:

- Filter to `Pathogen Target == "Influenza A virus"`. Fail with a clear error if
  zero rows remain.
- Parse `Week End` with `%m/%d/%Y` into a `Date` column named `week`. If parsing
  yields any `NA`, stop with `'The Week End could not be parsed.'`
- Parse `National WVAL` with `readr::parse_number()` into a numeric column named
  `wval`. If parsing yields any `NA`, stop with `'The National WVAL could not be
  parsed.'`
- Sort ascending by `week` and de-duplicate.

**Validations:** Print the wastewater series date range and row count.
**Validations:** Confirm `week` values are all the same weekday as the flu series
(both are week-ending Saturdays) and are evenly spaced at 7 days; `stop()`
otherwise.
**Validations:** Print the number of weeks where the flu series and the
wastewater series overlap, and the overlap date range.

## 1W. Lagged Regressor Construction

**`STRICT RULE`:** The regressor is the wastewater series **lagged by exactly 3
weeks** (`WVAL_LAG <- 3`). Define, for any target week `t`:

```
wval_lag3(t) = wval at week (t - 7 * WVAL_LAG)
```

Rationale — record this in the script header. The lag is set to 3 (the maximum
forecast horizon) so that every regressor value needed for horizons 1, 2, and 3
is **already observed at the reference date** `r`:

| horizon | target week | regressor week | status at time `r` |
|---------|-------------|----------------|--------------------|
| 1       | `r + 7`     | `r - 14`       | observed           |
| 2       | `r + 14`    | `r - 7`        | observed           |
| 3       | `r + 21`    | `r`            | observed           |

This makes the forecast genuinely real-time: no future wastewater value is ever
used. Do **not** shorten the lag to raise in-sample correlation — a shorter lag
requires wastewater observations dated after the reference date, which leaks
future information into the evaluation and inflates apparent skill.

**Validations:** Print the chosen lag and the table above.
**Validations:** Confirm that for **every** reference date, all three regressor
weeks (`r - 14`, `r - 7`, `r`) are present in the wastewater series; `stop()`
listing any reference date that fails.

## 2W. Training Window Restriction

Attach `wval_lag3` to the flu series by joining on `week`. Rows where
`wval_lag3` is `NA` (i.e. weeks earlier than the first wastewater week plus 3
weeks) **cannot** be used to fit an ARIMAX model and must be dropped from the
training window.

**`STRICT RULE`:** The reference-date set is **unchanged** from Rule 3 of the
Forecasting section. Only the *training window* is shortened — for reference
date `r`, fit on all rows with `week <= r` **and** non-`NA` `wval_lag3`.

**Validations:** Print the ARIMAX training start date and state explicitly how
many weeks of flu history are dropped relative to `03_forecast.R`'s
univariate training window (which starts at the first observed flu week).
**Validations:** Confirm the restricted training window is still contiguous
(evenly spaced at 7 days, no gaps) after dropping `NA` rows; `stop()` otherwise.
**Validations:** Confirm at least 52 training rows remain at the first reference
date; `stop()` otherwise.

## 4W. Model Specification (replaces Rule 4)

- Package: **forecast** (`forecast::auto.arima()`).
- Response: the influenza admissions series, as in Rule 4.
- **External regressor:** `wval_lag3`, passed as a single-column numeric matrix
  named `wval_lag3` via the `xreg` argument. This is the one permitted deviation
  from Rule 4's "no covariates" clause.
- Model class: a non-seasonal ARIMA with one external regressor — an ARIMAX /
  regression-with-ARIMA-errors model — whose `(p, d, q)` order is selected
  automatically by `auto.arima(y, xreg = x)`.

**`STRICT RULE`:** As in Rule 4, the model is fit **exactly once per reference
date**, and all three horizons come from a single
`forecast(fit, h = 3, xreg = xreg_future, level = LEVELS)` call, where
`xreg_future` is the 3-row matrix from Rule 1W. Do **not** refit per horizon.

Carry over every Rule 4 validation (sorted / unique / evenly-spaced weeks,
numeric non-negative NA-free response, non-constant series, printed `(p, d, q)`,
fit-succeeded), and add:

**Validations:** Print confirmation that `xreg` has the same number of rows as
the response vector and contains no `NA`; `stop()` otherwise.
**Validations:** Print confirmation that the regressor is not constant within
the training window (a constant `xreg` is rank-deficient); `stop()` otherwise.
**Validations:** Print the fitted coefficient on `wval_lag3` at each reference
date, so the direction and stability of the wastewater effect is visible.
**Validations:** Print confirmation that `xreg_future` has exactly 3 rows, one
column, and no `NA`; `stop()` otherwise.

## 5W. Forecast Generation

Identical to Rule 5 of the Forecasting section — same `LEVELS`, same 23-quantile
ladder, same clamp-at-0 and round-to-integer, same 69 rows per reference date,
same FluSight column names and order, and **all** of the same output
validations (finite values, non-decreasing ladder, non-negative integers,
intervals widen with horizon, target dates correct, one fit → three horizons,
all quantile levels present, median centered / symmetric on the raw pre-clamp
forecast).

## 6W. Forecast Figure

Identical to Rule 6 of the Forecasting section (same plot type, observed line,
per-horizon medians and 95% PI ribbons, axis labels, tick rules, legend, 300
DPI), with one change: the plot title is

`'USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast, Wastewater-Informed ARIMAX (2025-26 Season)'`

Bold; Centered.

## 7W. Output Paths (WVAL_ prefix)

**`STRICT RULE`:** Write to the **same directories** used by `03_forecast.R`,
with `WVAL_` prefixed to each filename. Never write to the unprefixed names.

| Artifact | Path |
|----------|------|
| Forecast CSV | `output/data/03_forecast/WVAL_flusight_forecasts.csv` |
| Forecast figure | `output/figures/03_forecast/WVAL_forecast_vs_observed.png` |

**Validations:** Before writing, `stop()` if the target path resolves to either
`flusight_forecasts.csv` or `forecast_vs_observed.png` without the `WVAL_`
prefix.

---

# Wastewater Forecast Evaluation

Save all code in this section to `output/scripts/06_evaluation_wval.R`. If the
folder path is not present, create it before saving the script.

**`STRICT RULE`:** This section is identical to the **Forecast Evaluation**
section (same `scoringutils` usage, same join on `target_end_date == week`, same
WIS / AE / 95% coverage metrics, same output table columns and ordering, same
by-horizon summary and rounding) with only the input/output paths changed and
the `model` label changed. Do not re-derive the scoring logic; mirror
`04_evaluation.R`.

Changes from the Forecast Evaluation section:

| Item | Value |
|------|-------|
| Forecast input | `output/data/03_forecast/WVAL_flusight_forecasts.csv` |
| Truth input | `output/data/01_cleaning/cleaned_flu_admissions.csv` (unchanged) |
| `model` column | `"arimax_wval"` |
| Per-forecast scores | `output/data/04_evaluation/WVAL_forecast_scores.csv` |
| By-horizon summary | `output/data/04_evaluation/WVAL_forecast_scores_by_horizon.csv` |

**`STRICT RULE`:** Never write to `forecast_scores.csv` or
`forecast_scores_by_horizon.csv` (the unprefixed baseline outputs).

**Validations:** `stop()` if either output path lacks the `WVAL_` prefix.
**Validations:** Print the number of scorable and dropped `reference_date` ×
`horizon` combinations, as in the Forecast Evaluation section.

---

# Forecasting with Gradient-Boosted Trees (XGBoost)

Save all code in this section to:

Output folder: `output/scripts/07_xgboost_forecast.R`

If the folder pathway is not present, create the folder pathway prior to saving
the script.

**`STRICT RULE`:** This section is an *alternative-model* variant of the
Forecasting section. It swaps `auto.arima()` for **XGBoost** and uses **no
external regressor / leading indicator** — the flu admissions series is the only
data source. Everything that is not the model itself is carried over from the
Forecasting section verbatim and **must not be altered**: Rule 1 (Input Data),
Rule 2 (Season Rules), Rule 3 (Training/Testing periods and the reference-date
set), the FluSight long output format (Rule 5's 23-quantile ladder, clamp-at-0,
round-to-integer, 69 rows per reference date, column names/order), and the
figure (Rule 6). The reference-date set is **identical** to `03_forecast.R` so
all three models (ARIMA, ARIMAX-wastewater, XGBoost) are directly comparable.

**`STRICT RULE`:** Nothing written by `03_forecast.R`, `04_evaluation.R`,
`05_incremental_changes.R`, or `06_evaluation_wval.R` may be overwritten. All
XGBoost outputs carry an `XGB_` filename prefix in the same directories.

## 1X. Feature Engineering

XGBoost has no built-in autoregressive structure, so the series must be turned
into a supervised feature matrix. For an *anchor week* `t` (the most recent week
whose value is known) predicting a *target week* `t + 7h`, build these features:

- `lag1 = value(t)`, `lag2 = value(t - 7)`, `lag3 = value(t - 14)`,
  `lag4 = value(t - 21)` — the four most recent known admissions as of `t`.
- `sin1`, `cos1`, `sin2`, `cos2` — first and second seasonal harmonics of the
  **target** week's MMWR epiweek: `sin(2*pi*k*epiweek/52.18)` and the cosine, for
  `k = 1, 2`. These carry the season shape.

Rows with any `NA` feature (early weeks lacking four lags) are dropped from
training.

**Validations:** Print the feature names and confirm the feature matrix has no
`NA` after dropping incomplete rows; `stop()` otherwise.

## 3X. Direct Multi-Horizon Framing (adapts Rule 4's "one fit")

**`STRICT RULE`:** Forecasting is **direct per horizon**. For each reference date
`r` and each horizon `h ∈ {1, 2, 3}`, fit a **separate** XGBoost model whose
target is `value(t + 7h)`. Training examples for horizon `h` at reference date
`r` are all anchor weeks `t` such that both `t` has complete features and the
target `t + 7h` is an **observed** week with `t + 7h <= r` (no future leakage).
This yields **three fits per reference date** (one per horizon), replacing Rule
4's single fit. Each fit still produces all 23 quantiles for its horizon from one
model, so the "one model → all 23 quantiles" property is preserved per horizon.

Prediction for horizon `h` at reference date `r` uses anchor week `r`: lag
features are the last known admissions as of `r`, and the harmonics are those of
target week `r + 7h`.

## 4X. Model Specification (replaces Rule 4)

- Package: **xgboost** (`xgboost::xgb.train`), install-if-missing like the other
  scripts.
- Objective: **`reg:quantileerror`** with `quantile_alpha` set to the full
  23-value FluSight ladder, so a single fit predicts every quantile directly.
- Fixed hyperparameters (a deployed model would tune these; kept fixed and
  documented here for reproducibility): `eta = 0.05`, `max_depth = 3`,
  `subsample = 0.8`, `colsample_bytree = 0.8`, `nrounds = 300`, `nthread = 1`,
  and a fixed `seed` so runs are deterministic.
- Response: influenza admissions only. No external regressors / leading
  indicators.

Carry over the applicable Rule 4 validations (training weeks sorted / unique /
evenly-spaced on the base series; response numeric, non-negative, NA-free;
series non-constant; fit returns a non-null model). Add:

**Validations:** Print, at each reference date, the per-horizon training-row
count and confirm each is `>= 30`; `stop()` otherwise.
**Validations:** Confirm `predict()` returns exactly 23 values per prediction
row (one per quantile); `stop()` otherwise.

## 5X. Forecast Generation (adapts Rule 5)

Identical to Rule 5 — same 23-quantile ladder, same clamp-at-0 and
round-to-integer, same 69 rows per reference date, same FluSight column names
and order — with these model-driven differences:

- The 23 quantiles come from the XGBoost quantile model's prediction vector.
  Because gradient-boosted quantile predictions can **cross**, sort each
  prediction's 23 values ascending before mapping them to the ladder. The median
  is the directly predicted `0.5` quantile.

Keep these Rule 5 output validations as hard `stop()` checks: finite values;
quantiles non-decreasing within each horizon (guaranteed by the sort, still
verified); non-negative integers; all 23 quantile levels present exactly once;
`target_end_date == reference_date + 7 * horizon`; exactly horizons {1, 2, 3}
per reference date.

**`STRICT RULE` (adapted checks):**

- **Drop** the "median centered / quantiles symmetric" check — XGBoost quantiles
  are asymmetric by construction, so Gaussian symmetry does not apply.
- **Relax** the "intervals widen with horizon" check from a `stop()` to a
  **reported diagnostic**: compute, per reference date, whether the 95% PI width
  satisfies `h3 >= h2 >= h1`, print the fraction of reference dates that hold,
  and do **not** halt. Direct per-horizon models are not guaranteed to widen
  monotonically; this is expected, not a bug.

## 6X. Forecast Figure (adapts Rule 6)

Identical to Rule 6 (observed line, per-horizon medians and 95% PI ribbons, axis
labels, tick rules, legend, 300 DPI), with the title:

`'USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast, XGBoost Quantile Model (2025-26 Season)'`

Bold; Centered.

## 7X. Output Paths (XGB_ prefix)

**`STRICT RULE`:** Write to the same directories as `03_forecast.R`, with `XGB_`
prefixed to each filename. Never write the unprefixed names or the `WVAL_` names.

| Artifact | Path |
|----------|------|
| Forecast CSV | `output/data/03_forecast/XGB_flusight_forecasts.csv` |
| Forecast figure | `output/figures/03_forecast/XGB_forecast_vs_observed.png` |

**Validations:** Before writing, `stop()` if either target path lacks the `XGB_`
prefix.

---

# XGBoost Forecast Evaluation

Save all code in this section to `output/scripts/08_evaluation_xgb.R`. If the
folder path is not present, create it before saving the script.

**`STRICT RULE`:** Identical to the **Forecast Evaluation** section (same
`scoringutils` usage, same join on `target_end_date == week`, same
WIS / AE / 95% coverage metrics, same output table columns and ordering, same
by-horizon summary and rounding), with only the input/output paths and the
`model` label changed. Mirror `04_evaluation.R`; do not re-derive the logic.

Changes from the Forecast Evaluation section:

| Item | Value |
|------|-------|
| Forecast input | `output/data/03_forecast/XGB_flusight_forecasts.csv` |
| Truth input | `output/data/01_cleaning/cleaned_flu_admissions.csv` (unchanged) |
| `model` column | `"xgboost"` |
| Per-forecast scores | `output/data/04_evaluation/XGB_forecast_scores.csv` |
| By-horizon summary | `output/data/04_evaluation/XGB_forecast_scores_by_horizon.csv` |

**`STRICT RULE`:** Never write to the baseline or `WVAL_` score outputs.

**Validations:** `stop()` if either output path lacks the `XGB_` prefix.
**Validations:** Print the number of scorable and dropped `reference_date` ×
`horizon` combinations, as in the Forecast Evaluation section.

---

# Final FluSight Submission Prep

Save all code in this section to `output/scripts/final_prep.R`. If the folder
path is not present, create it before saving the script.

This stage does **no modeling**. It splits the finished XGBoost forecast file
into one CSV per reference date, in the shape a FluSight submission expects.

## 1. Input

Read `output/data/03_forecast/XGB_flusight_forecasts.csv` (the FluSight long
format written by `07_xgboost_forecast.R`). Parse `reference_date` and
`target_end_date` as `Date`. Fail with a clear error if the file is missing or
any of the eight expected columns is absent.

## 2. Split and Write

Create the output folder `output/data/final_flusight_submission` if it is not
present.

Split the forecasts by `reference_date`. Write one CSV per reference date to:

`output/data/final_flusight_submission/{YYYY-MM-DD}-AmandaXGBoost.csv`

where `{YYYY-MM-DD}` is that group's `reference_date` formatted as an ISO date.

**`STRICT RULE`:** Each per-date file keeps the **full FluSight long format** —
the same eight columns in the same order as the source file
(`reference_date`, `target`, `horizon`, `target_end_date`, `location`,
`output_type`, `output_type_id`, `value`) — and the same row ordering (by
`horizon`, then ascending `output_type_id`). Do not drop, rename, reorder, or
reformat any column. Dates serialize as ISO `YYYY-MM-DD` via
`readr::write_csv()`.

**`STRICT RULE`:** This script only reads the XGBoost forecast file and only
writes into `output/data/final_flusight_submission`. It must never modify any
file in `output/data/03_forecast` or `output/data/04_evaluation`.

## 3. Validations

All of these halt on failure:

- The output directory path ends in `final_flusight_submission`.
- Every emitted filename matches `^\d{4}-\d{2}-\d{2}-AmandaXGBoost\.csv$`.
- One file is written per distinct `reference_date` — file count equals the
  number of distinct reference dates.
- Each file contains exactly **69** rows (3 horizons × 23 quantiles) and has a
  single unique `reference_date` matching its filename.
- Each file's columns are exactly the eight FluSight columns, in order.
- Summed rows across all written files equals the source file's row count.
- Each written file exists on disk after writing.

Print one line per written file (`reference date → filename, n rows`) and a
closing summary of the number of files and total rows written.
