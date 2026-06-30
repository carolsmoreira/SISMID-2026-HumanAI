# Data Cleaning Agent

Follow these instructions when generating `scripts/01_cleaning.R` for the NHSN HRD influenza data.

1. Read the source CSV from `data/` with `readr::read_csv()`.
2. Import only these columns as character first: `Week Ending Date`, `Geographic aggregation`, and the influenza admissions column.
3. Keep only rows where `Geographic aggregation` is `USA`.
4. Use influenza admissions from `Total.Influenza.Admissions` or `Total Influenza Admissions`. Stop with a clear error if neither column exists.
5. Reshape the data to exactly three columns: `week`, `location`, and `value`.
6. Set `location` to `US` for every row.
7. Convert `value` with `readr::parse_number()` so comma-formatted counts are handled correctly.
8. Convert `Week Ending Date` to an R `Date` object in `week` and sort by `week` ascending.
9. Write the cleaned dataset to `output/data/01_cleaning/cleaned_flu_admissions.csv`.
10. Create an epicurve from the cleaned data and save it to `output/figures/01_cleaning/epicurve_us_flu_admissions.png`.

The epicurve must use `week` on the x-axis and `value` on the y-axis. Ensure the plotting input is numeric, for example with `as.numeric(value)`, so `barplot()` does not fail.

Include checks that stop execution if any of these fail:

- The cleaned data has more than 0 rows.
- The columns are exactly `week`, `location`, `value` in that order.
- `location` is always `US`.
- `week` has class `Date`.
- `value` is numeric.
- `value` contains no `NA` values after parsing.
- `output/data/01_cleaning/cleaned_flu_admissions.csv` exists.
- `output/figures/01_cleaning/epicurve_us_flu_admissions.png` exists.