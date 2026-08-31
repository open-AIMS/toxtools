## Prepare the `sea_urchin` dataset.
##
## Source: data-raw/sea_urchin/Test data.xlsx, sheet "Copper Ref (4)" — the
## first of four copper reference-toxicant tests recorded in that workbook.
## Laboratory Form 149, 72 hr sea urchin development test.
##
## The workbook itself is not held in this repository: source laboratory
## records are excluded by .gitignore. Obtain it from the study authors and
## place it at the path below to re-run this script. The prepared dataset it
## produces, data/sea_urchin.rda, ships with the package, so nothing here is
## needed to use `sea_urchin`.
##
## readxl, dplyr and usethis are used here only. Packages used to prepare data
## are not declared in DESCRIPTION, because data-raw/ is excluded from the
## build (.Rbuildignore) and so is never needed by a user installing the
## package.

xlsx_path <- file.path("data-raw", "sea_urchin", "Test data.xlsx")
sheet <- "Copper Ref (4)"

if (!file.exists(xlsx_path)) {
  stop(
    "source workbook not found at ",
    xlsx_path,
    ". ",
    "It is excluded from version control; see the note at the top of this file.",
    call. = FALSE
  )
}

## The sheet is a laboratory form, not a rectangular table. Column A and row 1
## are empty, the title block occupies rows 2-7, column names sit on row 8 in
## columns B:H, the 18 data rows (6 copper concentrations x 3 replicates) run
## from row 9 to row 26, and an "Average Control" summary follows below.
##
## Cells are therefore taken by absolute range rather than by read_excel()'s
## inference. read_excel() trims leading empty rows and columns when no range
## is given, which silently renumbers everything and makes any skip = n
## argument wrong by one in each direction.
cols <- c(
  "concentration",
  "n_normal",
  "n_abnormal",
  "pct_normal",
  "pct_control",
  "mean_pct_control",
  "sd_pct_control"
)

header <- unlist(
  readxl::read_excel(
    xlsx_path,
    sheet = sheet,
    range = readxl::cell_limits(c(8, 2), c(9, 8)),
    col_names = FALSE,
    col_types = "text",
    .name_repair = "minimal"
  )[1, ],
  use.names = FALSE
)

stopifnot(
  "sheet layout has changed: column names are not on row 8, columns B:H" = identical(
    header[1:3],
    c(
      "Copper Reference (ug/L)",
      "No. Normal Development",
      "No. Abnormal Development"
    )
  )
)

raw <- readxl::read_excel(
  xlsx_path,
  sheet = sheet,
  range = readxl::cell_limits(c(9, 2), c(26, 8)),
  col_names = cols,
  col_types = rep("numeric", length(cols))
)

## Only the counts are kept. Every other column on the form is derived from
## them, and storing a derived value alongside its inputs invites the two to
## drift apart; percent normal development is recovered with
## n_normal / (n_normal + n_abnormal).
sea_urchin <- raw |>
  dplyr::transmute(
    concentration = concentration,
    n_normal = as.integer(n_normal),
    n_abnormal = as.integer(n_abnormal)
  ) |>
  dplyr::mutate(
    replicate = as.integer(dplyr::row_number()),
    .by = concentration
  ) |>
  dplyr::relocate(replicate, .after = concentration) |>
  ## Stored as a plain data.frame rather than a tibble. The package has no
  ## Imports, and a shipped tbl_df would create a soft dependency on tibble
  ## for correct printing.
  as.data.frame()

## Integrity check: percent normal development recomputed from the retained
## counts must reproduce the value the laboratory form already holds. This
## confirms the correct rows and columns were extracted.
stopifnot(
  "recomputed % normal development does not match the sheet" = isTRUE(all.equal(
    100 * sea_urchin$n_normal / (sea_urchin$n_normal + sea_urchin$n_abnormal),
    raw$pct_normal
  ))
)

usethis::use_data(sea_urchin, overwrite = TRUE)
