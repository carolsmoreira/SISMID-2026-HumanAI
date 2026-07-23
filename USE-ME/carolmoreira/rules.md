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

Save all code in this section to `output/scripts/03_forecast.R`. Create the
folder path first if it is absent.

## 1. Input Data

Read `output/data/01_cleaning/cleaned_flu_admissions.csv`. Validate and, when
possible, parse the required structure:

- `week`: Date, `YYYY-MM-DD`
- `location`: character and always `"US"`
- `value`: numeric

If a required column cannot be parsed, stop with: `The {column} could not be parsed.`

## 2. Season Rules

Use the established influenza-season definition: MMWR week 40 through MMWR
week 20 of the following year, labeled `YYYY-YY`. The current season is
`2025-26`.

- Season start is the first calendar date in the first year whose MMWR week is
  40; season end is the earliest calendar date in the second year whose MMWR
  week is 20. Account for leap years.
- Assign seasons using the calendar year of `week`, not `MMWRyear`. When an
  MMWR week is >= 40 in January through August, assign it to the previous
  season start year. This preserves early-January week-53 observations in the
  winter season.
- Assign every input row to a season. A complete season contains both the
  season-start week and season-end week in the input.
- Print exactly:
  - `Season Start Week:` YYYY-MM-DD
  - `Season End Week:` YYYY-MM-DD

## 3. Training and Testing Periods

- Testing period: only the `2025-26` season.
- Initial training period: all observed weeks strictly before the first testing
  week present in the data.
- Use expanding-window forecasts. A reference date is every observed week `r`
  for which `r + 7` is present in the input and belongs to the testing period.
  For each reference date, fit on all observed weeks with `week <= r`.
- Forecast horizons are exactly 1, 2, and 3 weeks. Every reference date emits
  all three horizons; do not emit any other horizon.
- Fit exactly once per reference date and take all three horizons from that one
  forecast object. Do not refit separately per horizon.
- The one-week-ahead target must be observed and in the testing period. Still
  emit horizons 2 and 3 when those target weeks are beyond the last observed
  week.

Print the training-period start and reference dates, testing-period start and
each reference date with its three target dates, and the horizons `1, 2, 3`.

## 4. Model Specification

- Use `forecast::auto.arima()` to fit a non-seasonal ARIMA model.
- Sort each training window by `week`, extract only its ordered influenza
  admissions `value` vector, and use no covariates or external regressors.

For every fit, validate and print that weeks are sorted, unique, and evenly
spaced at seven-day intervals; halt on skipped weeks. Confirm the response is
numeric, non-negative, non-missing, and nonconstant. Print the selected `(p,d,q)`
order and confirm that a non-null fit was returned.

## 5. Forecast Generation

For each reference date `r`:

1. Use `r` directly as a Date `reference_date` for training-window selection
   and output. Serialize `reference_date` and `target_end_date` as ISO dates.
2. Fit the model once on rows with `week <= reference_date`.
3. Call `forecast(fit, h = 3, level = LEVELS)` once, where
   `LEVELS = c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)`.
4. Extract the forecast mean as quantile `0.5`, and lower/upper bounds for all
   requested levels at each horizon. Clamp every emitted forecast at zero and
   round to the nearest integer.
5. Reshape to one row per quantile per horizon using this full quantile ladder:
   `0.01, 0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
   0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 0.975, 0.99`.

The central coverage levels map to lower/upper quantiles as follows: 98 to
0.01/0.99; 95 to 0.025/0.975; 90 to 0.05/0.95; 80 to 0.10/0.90; 70 to
0.15/0.85; 60 to 0.20/0.80; 50 to 0.25/0.75; 40 to 0.30/0.70; 30 to
0.35/0.65; 20 to 0.40/0.60; and 10 to 0.45/0.55.

Write `output/data/03_forecast/flusight_forecasts.csv`, creating its folder
when absent. Use exactly these columns, in order:

| Column | Type / value |
|---|---|
| `reference_date` | Date, YYYY-MM-DD |
| `target` | `"wk inc flu hosp"` |
| `horizon` | `1`, `2`, or `3` |
| `target_end_date` | `reference_date + 7 * horizon` |
| `location` | `"US"` |
| `output_type` | `"quantile"` |
| `output_type_id` | one required quantile level |
| `value` | non-negative integer forecast count |

Each reference date must produce 69 rows: 3 horizons by 23 quantiles.

Validate that forecast means and bounds are finite; emitted values are
non-negative integers; quantiles are non-decreasing within every
reference-date/horizon; every reference-date/horizon has exactly the 23
required quantiles; and `target_end_date == reference_date + 7 * horizon`.
Validate that emitted 95% PI widths satisfy h3 >= h2 >= h1, printing
`[val] intervals widen with horizon: OK`, and that exactly one fit produces
horizons 1, 2, and 3, printing `[val] one fit, three horizons: OK`.
On the raw, pre-clamp forecast, validate that the median equals the point
forecast and symmetric quantile pairs are equidistant from it. Print
`[val] quantiles non-decreasing: OK`, `[val] all quantile levels present: OK`,
`[val] target dates correct: OK`, and `[val] median centered, quantiles symmetric: OK`;
stop on any failed validation.

## 6. Forecast Figure

Save `output/figures/03_forecast/forecast_vs_observed.png`, creating the folder
when absent, at 300 DPI.

- Plot observed `value` over the `2025-26` testing period as a solid black line
  with points.
- Plot the 0.5 quantile at `target_end_date` as one line with points per
  horizon: 1 week blue, 2 weeks orange, 3 weeks green (or an equivalently
  colorblind-friendly distinct palette).
- Add a low-opacity 95% PI ribbon (`0.025` to `0.975`) per horizon using the
  matching color; ribbons must be behind observed and median lines.
- Label axes `Week` and `Weekly Influenza Hospitalizations`. Start the y-axis
  at zero and end at 10,000 above the maximum plotted observed or upper-PI
  value.
- Use weekly dates from the first observed/target week through the last target
  end date, show every fourth date label, and tilt labels 45 degrees.
- Use the bold, centered title `USA 1-, 2-, & 3-Week-Ahead Influenza Hospitalization Forecast (2025-26 Season)`.
- Provide one legend that includes Observed plus the forecast median and 95% PI
  for every horizon, with consistent horizon colors.


 
