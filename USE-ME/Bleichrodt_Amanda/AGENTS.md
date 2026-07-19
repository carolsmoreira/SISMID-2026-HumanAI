# AGENTS.md

Guidance for agents working in this repository.

## Project

Clean the raw NHSN Hospital Respiratory Data (HRD) influenza file into a tidy,
three-column dataset and produce an epicurve figure. The authoritative
specification is [rules.md](rules.md) — read it before writing or editing code,
and follow its steps in order.

## Layout

```
data/                                   # raw NHSN HRD CSV (read-only; never modify)
output/scripts/01_cleaning.R            # the script agents generate/maintain
output/data/01_cleaning/                # cleaned CSV output
output/figures/01_cleaning/             # epicurve PNG output
```

Scripts live under `output/scripts/` but all paths inside them are relative to
the **project root** — run them from the root (`Rscript output/scripts/01_cleaning.R`),
not from the script's own directory.

## Language and tools

- R only. Use **readr** for I/O (`read_csv()`, `parse_number()`).
- Parse numbers with `readr::parse_number()`, not `parse_double()` — counts in
  the raw file are comma-formatted (e.g. `1,110`).
- Read only the columns the task needs, importing as character first and
  converting explicitly, so unrelated fields do not raise parsing warnings.

## Data contract

The cleaned dataset has exactly three columns, in this order:

| column     | type      | notes                     |
| ---------- | --------- | ------------------------- |
| `week`     | `Date`    | sorted ascending          |
| `location` | character | always `"US"`             |
| `value`    | numeric   | influenza admissions      |

Rows are filtered to `Geographic aggregation == "USA"`. The influenza
admissions source column is one of `Total.Influenza.Admissions` or
`Total Influenza Admissions`; stop with a clear error if neither is present.

## Outputs

- `output/data/01_cleaning/cleaned_flu_admissions.csv`
- `output/figures/01_cleaning/epicurve_us_flu_admissions.png` — x-axis `week`,
  y-axis `value`; coerce the plotting input with `as.numeric()` so `barplot()`
  does not fail on height type.

Create output directories if they do not exist rather than assuming them.

## Validation

Scripts must include checks that **stop execution on failure** (`stopifnot()` or
an explicit `stop()`), covering: non-zero row count; exact column names and
order; `location` always `"US"`; `week` inherits `Date`; `value` numeric with no
`NA` after parsing; and both output files existing on disk.

Never weaken or remove a validation check to make a script pass — fix the
underlying data handling instead.

## Working conventions

- Keep changes scoped to what was asked; do not restructure the pipeline
  unprompted.
- If `rules.md` and this file disagree, `rules.md` wins — and say so.
- Report failures honestly, including the actual error output.
