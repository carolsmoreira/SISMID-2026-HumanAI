# SISMID 2026: Building an Influenza Forecasting Pipeline

**A Human-AI Teaming Approach to Infectious Disease Modeling**
July 22 through July 24, 2026

Welcome! Over the next three days you will work as a **human-AI team** to build a national influenza hospitalization forecasting pipeline from real CDC data. You will start with a raw surveillance file and finish with FluSight-format quantile forecasts, the same format used by the CDC's forecasting hub.

The guiding idea is simple: **you make the decisions, the AI writes the code.** You describe *what* the pipeline should do in plain language, and an AI coding assistant (GitHub Copilot) turns your instructions into working R scripts. You stay the domain expert, reviewing, correcting, and refining every step.

## How the workflow works

Every activity follows the same loop:

1. **Write the rules.** You edit `rules.md`, a plain-language spec describing what this step should do.
2. **Generate the agent.** You prompt Copilot to turn `rules.md` into `AGENTS.md`, the machine-readable instructions the AI follows.
3. **Generate the script.** Using `AGENTS.md`, Copilot writes the R script (for example, `03_forecast.R`).
4. **Run and check.** You run the script in VS Code and confirm the output looks right.
5. **Push and submit.** You commit your work, push it to your fork, and open a pull request. Automated checks review your submission and give feedback.

In short: `rules.md` is what **you** control, `AGENTS.md` is what the **AI** builds from it, and the scripts are what the agent **produces**. At the end of the day, you are still the expert making the decisions.

## The five activities

| # | Activity | Script | You produce |
|---|----------|--------|-------------|
| 1 | Data Cleaning & Visuals | `01_cleaning.R` | a tidy weekly series (`cleaned_flu_admissions.csv`) and an epicurve |
| 2 | Data Exploration | `02_data_explore.R` | national-trend and season-comparison figures, plus a peak-analysis table |
| 3 | Modeling & Forecasting | `03_forecast.R` | FluSight-format quantile forecasts (`flusight_forecasts.csv`) and a forecast-vs-observed plot |
| 4 | Evaluation | `04_evaluation.R` | forecast scores (such as the weighted interval score) and coverage checks |
| 5 | Incremental Revisions | `05_improvements.R` | an improved pipeline, swapping models and refining the rules |

Two setup sessions come first, **Intro to GitHub** and **Intro to VS Code**, to get your environment ready before Activity 1.

## The data

Everything is built on the **CDC NHSN Hospital Respiratory Data (HRD)**: weekly hospital respiratory metrics reported to the CDC's National Healthcare Safety Network. You will work with the national (`US`) Total Influenza Admissions series, cleaned in Activity 1 into three columns: `week`, `location`, and `value`.

## What is in this repository

- **`Lab-Materials/`** contains the lecture slides, demos, and hints & answers for each activity, organized by day. If you fall behind or get stuck, the `Demo/` folder for each activity holds starting materials you can pick up from.
- **`USE-ME/`** is your workspace. You will create a folder named after yourself here and do all of your work inside it.

Inside `Lab-Materials/`, a new folder appears for each day of the course, and every activity folder follows the same three-part format:

```
Lab-Materials/
├── Day 1/
│   ├── Activity 1/
│   │   ├── Demo/                # starting materials, in case you need to catch up
│   │   ├── Hints and Answers/   # the completed lab and its base R scripts
│   │   └── PowerPoints/         # the slides we review together
│   └── ...                      # additional activities for the day
├── Day 2/
│   └── ...
└── Day 3/
    └── ...
```

You will only see the `Day 1/` folder at first; the `Day 2/` and `Day 3/` folders are added as the course progresses.

As you move through the lab, your own named folder in `USE-ME/` will grow to look like this:

```
YOUR-NAME/
├── rules.md                     # your plain-language spec (you write this)
├── AGENTS.md                    # AI instructions (generated from rules.md)
├── data/
│   └── Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv
└── output/
    ├── scripts/
    │   ├── 01_cleaning.R
    │   ├── 02_data_explore.R
    │   ├── 03_forecast.R
    │   ├── 04_evaluation.R
    │   └── 05_improvements.R
    ├── data/                    # cleaned data, forecasts, scores (one subfolder per step)
    └── figures/                 # epicurves, trend plots, forecast plots (one subfolder per step)
```

Each script writes its results into a step-specific subfolder, for example `output/data/03_forecast/` and `output/figures/03_forecast/`, so nothing overwrites your earlier work.

## Getting started

Work through these in order. The first three get your environment set up:

1. **Fork this repository** to your own GitHub account (*Intro to GitHub*).
2. **Clone your fork into VS Code**, install the R extension, and connect GitHub Copilot (*Intro to VS Code*).
3. **Create your folder** inside `USE-ME/`, then move a copy of the `data/` folder and the starting `rules.md` into it.
4. **Work through Activities 1 through 5**, one at a time.
5. **Commit and open a pull request** after each activity (*Commits & Pull Requests*) so your results are saved to your fork and submitted for review.

## Submitting your work

After each activity:

- **Commit** your changes and **push** them to your fork (through VS Code, or the GitHub web upload).
- **Open a pull request** from your fork to the class repository.
- Automated checks run on your submission and post feedback. Read it, and do not worry if something needs fixing. Catching and correcting issues is part of the loop.

## A note on working with AI

Think of the AI as a capable but literal intern: fast and genuinely helpful, but it needs clear direction, and it does not always remember constraints you set earlier. The clearer your rules, the better the output, and vague rules give vague results. When something looks off, the fix is almost always in the rules. You are the expert; the AI just writes the code.

If you hit a snag along the way, ask. An instructor is always happy to help.
