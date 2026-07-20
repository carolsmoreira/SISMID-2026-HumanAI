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
