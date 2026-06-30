library(readr)
library(dplyr)

input_path <- "data/Weekly Hospital Respiratory Data (HRD) Metrics by Jurisdiction.csv"
output_path <- "output/data/01_cleaning/cleaned_flu_admissions.csv"
figure_path <- "output/figures/01_cleaning/epicurve_us_flu_admissions.png"

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(figure_path), recursive = TRUE, showWarnings = FALSE)

raw <- read_csv(
  input_path,
  col_select = c(
    `Week Ending Date`,
    `Geographic aggregation`,
    any_of(c("Total.Influenza.Admissions", "Total Influenza Admissions"))
  ),
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
)

# Support both dotted and spaced versions of the influenza admissions column name.
influenza_col <- c("Total.Influenza.Admissions", "Total Influenza Admissions")
influenza_col <- influenza_col[influenza_col %in% names(raw)][1]

if (is.na(influenza_col)) {
  stop("Could not find influenza admissions column in input data.")
}

cleaned <- raw %>%
  filter(`Geographic aggregation` == "USA") %>%
  transmute(
    week = as.Date(`Week Ending Date`),
    location = "US",
    value = readr::parse_number(.data[[influenza_col]])
  ) %>%
  arrange(week)

# Acceptance checks from the agent instructions.
stopifnot(nrow(cleaned) > 0)
stopifnot(all(names(cleaned) == c("week", "location", "value")))
stopifnot(all(cleaned$location == "US"))
stopifnot(inherits(cleaned$week, "Date"))
stopifnot(is.numeric(cleaned$value))
stopifnot(!anyNA(cleaned$value))

write_csv(cleaned, output_path)
stopifnot(file.exists(output_path))

png(filename = figure_path, width = 1400, height = 800, res = 150)
op <- par(no.readonly = TRUE)
on.exit(par(op), add = TRUE)

plot_values <- as.numeric(cleaned$value)

barplot(
  height = plot_values,
  names.arg = format(cleaned$week, "%Y-%m-%d"),
  space = 0,
  border = NA,
  col = "#1f78b4",
  las = 2,
  cex.names = 0.5,
  main = "US Weekly Influenza Admissions Epicurve",
  xlab = "Week Ending Date",
  ylab = "Admissions"
)

dev.off()
stopifnot(file.exists(figure_path))
