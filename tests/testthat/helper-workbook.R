## Builds a workbook in a temporary file matching the layouts the reader has to
## cope with: a laboratory form with a title block, blank leading row and
## column, derived columns and a summary block below the data; a sheet with too
## few concentrations; an empty sheet; and a plain rectangular table with a
## single response column.
##
## The fixture is written rather than committed because the workbooks these
## functions read are laboratory records that are not distributed with the
## package, and a committed binary could not be inspected in a diff.
make_test_workbook <- function() {
  skip_if_not_installed("openxlsx")
  skip_if_not_installed("readxl")
  path <- withr::local_tempfile(
    fileext = ".xlsx",
    .local_envir = parent.frame()
  )
  wb <- openxlsx::createWorkbook()

  form <- data.frame(
    conc = rep(c(0, 2.5, 5, 10, 20, 40), each = 3),
    normal = c(
      138,
      136,
      146,
      160,
      123,
      151,
      138,
      114,
      134,
      130,
      105,
      125,
      33,
      43,
      31,
      3,
      4,
      5
    ),
    abnormal = c(
      10,
      9,
      12,
      19,
      13,
      22,
      27,
      31,
      20,
      39,
      43,
      45,
      106,
      150,
      115,
      139,
      175,
      159
    )
  )
  form$pct <- 100 * form$normal / (form$normal + form$abnormal)

  openxlsx::addWorksheet(wb, "Form")
  openxlsx::writeData(
    wb,
    "Form",
    "Laboratory Form 149",
    startRow = 2,
    startCol = 2
  )
  openxlsx::writeData(
    wb,
    "Form",
    "COPPER REFERENCE",
    startRow = 5,
    startCol = 2
  )
  openxlsx::writeData(
    wb,
    "Form",
    data.frame(
      `Copper Reference (ug/L)` = form$conc,
      `No. Normal Development` = form$normal,
      `No. Abnormal Development` = form$abnormal,
      `% Normal Development` = form$pct,
      Mean = NA_real_,
      `S.D.` = NA_real_,
      check.names = FALSE
    ),
    startRow = 8,
    startCol = 2
  )
  ## The summary block a laboratory form carries below the data. Reading must
  ## stop before it, because it has no concentration.
  openxlsx::writeData(
    wb,
    "Form",
    "Average Control",
    startRow = 27,
    startCol = 5
  )
  openxlsx::writeData(
    wb,
    "Form",
    mean(form$pct[1:3]),
    startRow = 28,
    startCol = 5
  )

  openxlsx::addWorksheet(wb, "Empty")

  openxlsx::addWorksheet(wb, "TooFew")
  openxlsx::writeData(
    wb,
    "TooFew",
    data.frame(
      concentration = c(0, 0, 1, 1),
      `No. Normal` = c(10, 11, 2, 3),
      `No. Abnormal` = c(1, 2, 9, 8),
      check.names = FALSE
    ),
    startRow = 1,
    startCol = 1
  )

  openxlsx::addWorksheet(wb, "Plain")
  openxlsx::writeData(
    wb,
    "Plain",
    data.frame(
      dose = rep(c(0, 1, 3, 9, 27), each = 2),
      growth = c(10, 11, 9.5, 10.2, 8, 7.6, 4, 4.4, 1, 1.2)
    ),
    startRow = 1,
    startCol = 1
  )

  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  path
}
