# AGENTS.md

Guidance for coding agents working in this project (SISMID — Day 2, Activity 3).

## What this project is

A small, reproducible R pipeline that turns the raw **NHSN Hospital Respiratory
Data (HRD)** influenza file into a tidy US series, explores it, and produces
1-, 2-, and 3-week-ahead influenza-hospitalization forecasts in **FluSight**
format.

## Source of truth

**`rules.md` is the specification.** Each numbered section defines exactly what a
corresponding script must do (inputs, outputs, validations, figure specs). When a
rule and the code disagree, the rule wins — update the code, or ask before
changing `rules.md`. Do not invent behavior that `rules.md` does not call for.

## Pipeline (run in order)

| Stage | Script | Reads | Writes |
|-------|--------|-------|--------|
| Clean | `01_cleaning.R` | `data/…HRD… .csv` | `output/data/01_cleaning/cleaned_flu_admissions.csv`, epicurve PNG |
| Explore | `output/scripts/02_data_explore.R` | cleaned CSV | national/seasonal PNGs, `output/data/02_data_explore/peak_description.csv` |
| Forecast | `output/scripts/03_forecast.R` | cleaned CSV | `output/data/03_forecast/flusight_forecasts.csv`, forecast PNG |
| Evaluate | `output/scripts/04_evaluation.R` | forecasts CSV + cleaned CSV | `output/data/04_evaluation/forecast_scores.csv`, `forecast_scores_by_horizon.csv` |

Every stage after cleaning reads `output/data/01_cleaning/cleaned_flu_admissions.csv`,
whose schema is exactly three columns: `week` (Date, `YYYY-MM-DD`), `location`
(character, always `"US"`), `value` (numeric).

## Forecast output (FluSight long format)

`03_forecast.R` fits an expanding-window `auto.arima()` — **one fit per reference
date**, from which horizons **1, 2, and 3** are taken from a single
`forecast(fit, h = 3, ...)` call (never refit per horizon). Each reference date
emits **69 rows** = 3 horizons × the full **23 FluSight quantiles** (`0.01 …
0.99`), obtained from one `forecast()` call with the coverage levels
`c(98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10)`. Values are clamped at 0 and
rounded to integers. Columns, in order: `reference_date`, `target`, `horizon`,
`target_end_date`, `location`, `output_type`, `output_type_id`, `value`.

The output is guarded by named `[val] …: OK` checks (all `stop()` on failure):
intervals widen with horizon, target dates correct, one fit → three horizons,
quantiles non-decreasing, all quantile levels present (exactly 23, no dup), and
median centered / quantiles symmetric.

## Forecast evaluation (scoringutils)

`04_evaluation.R` scores the FluSight forecasts against observed truth, one score
per **`reference_date` × `horizon`**, using the same metrics FluSight reports:
**WIS**, **AE**, and **95% PI coverage**. Do the scoring with the
**scoringutils** package — do not hand-code the formulas. Join forecasts to truth
on `target_end_date == week`; only combinations whose target has an observed
value are scorable (later horizons beyond the last observed week are dropped and
noted). Reshape to scoringutils conventions (`quantile_level`, `predicted`,
`observed`, a constant `model`), build the object with `as_forecast_quantile()`
(forecast unit = `reference_date`, `horizon`, `target_end_date`, `location`,
`model`), and `score()` it. Take `wis` (WIS), `ae_median` (AE), and the 95%
interval-coverage metric. Output table columns, in order: `reference_date`,
`horizon`, `target_end_date`, `observed`, `WIS`, `AE`, `coverage_95`. The
by-horizon summary then reports the mean of `AE` across reference dates as `MAE`.

## Season definition (used across stages)

A season spans **MMWR week 40 → week 20** of the following year, named `YYYY-YY`
(e.g. `2025-26`). Current season: **`2025-26`**. Season start = first calendar
date in the first year with `epiweek == 40`; season end = earliest date in the
second year with `epiweek == 20`. When assigning a row to a season, use the
**calendar year of the date** (`year(week)`) as the base year — not the
`MMWRyear` returned by `MMWRweek()`. Both the Peak Analysis and Forecasting
sections additionally apply the January/week-53 edge-case rule (see Known
gotchas below); check `rules.md` for other per-section nuances.

## Conventions to follow

- **Packages:** `readr`, `dplyr`, `lubridate`, `ggplot2`, `MMWRweek`, and (for
  forecasting) `forecast`, `tidyr`, and (for evaluation) `scoringutils`. Guard
  each with an install-if-missing block
  (`requireNamespace(...)` → `install.packages(..., repos = "https://cloud.r-project.org")`),
  matching the existing scripts.
- **Directories:** create output folders defensively with
  `dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)` before
  writing.
- **Validations halt:** required checks use `stop()` so a failed run never emits a
  silently-wrong artifact. Print progress/validation lines with `cat()`. Where
  `rules.md` gives exact validation text (e.g. `"[val] target dates correct: OK"`),
  print it verbatim.
- **Input parsing:** re-validate `week`/`location`/`value` on read; try to parse
  first, and on unrecoverable failure `stop("The {column} could not be parsed.")`.
- **Figures:** save PNGs at **300 DPI** via `ggsave()`; bold, centered titles;
  tilt dense date axes 45°.
- **CSV output:** write with `readr::write_csv()` (Dates serialize as ISO
  `YYYY-MM-DD`). Preserve the exact column names and order the spec lists.

## Known gotchas (learned the hard way)

- **`forecast()` re-sorts `level=` ascending.** When you pass multiple coverage
  levels, the columns of `fc$lower`/`fc$upper` come back ordered by the object's
  own `fc$level` (ascending), **not** the order you passed. Always index interval
  columns via `which(abs(fc$level - <level>) < 1e-6)`, never by the position in
  your input vector — otherwise you silently pull the wrong quantile.
- **Week 53 in early January.** `MMWRweek()` returns week 53 for some
  first-week-of-January dates, with `MMWRweek >= 40` but calendar year already
  incremented. Assigning the season by `year(week)` alone mislabels these into the
  *next* season and punches a one-week hole in the middle of a winter season. The
  fix (used in both `02_data_explore.R` and `03_forecast.R`): if `epiweek >= 40`
  **and** calendar month is Jan–Aug, attribute to `season_start_year = year - 1`.
- **ARIMA prediction intervals always widen with horizon**, so the
  "intervals widen with horizon" check is guaranteed by the model — a failure
  there means a bookkeeping bug (wrong column/level), not a modeling artifact.
- **Symmetry checks belong on the raw forecast, not the emitted values.** The
  Gaussian ARIMA quantiles are symmetric around the mean/median (`mean ± z·se`)
  only *before* the clamp-at-0 and rounding step; clamping a negative lower bound
  to 0 deliberately breaks that symmetry. Validate median-centering and pair
  equidistance on the pre-clamp matrix, but run non-decreasing / non-negative /
  integer checks on the emitted values.

## Running

R is not on `PATH`; invoke the full interpreter path, from the project root:

```
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "output/scripts/03_forecast.R"
```

All paths in the scripts are **relative to the project root**, so run from there.
