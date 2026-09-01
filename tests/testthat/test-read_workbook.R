test_that("classify_sheets identifies the fittable sheets and says why not", {
  path <- make_test_workbook()
  cls <- classify_sheets(path)

  expect_identical(cls$sheet, c("Form", "Empty", "TooFew", "Plain"))
  expect_identical(cls$analyse, c(TRUE, FALSE, FALSE, TRUE))

  # the column names sit on row 8 of the form, below its title block
  expect_identical(cls$header_row[cls$sheet == "Form"], 8L)
  expect_identical(cls$n_rows[cls$sheet == "Form"], 18L)
  expect_identical(cls$n_levels[cls$sheet == "Form"], 6L)

  expect_match(cls$reason[cls$sheet == "Empty"], "empty")
  expect_match(cls$reason[cls$sheet == "TooFew"], "at least 4")
  expect_true(all(is.na(cls$reason[cls$analyse])))
})

test_that("read_analysis_sheet takes the counts and ignores derived columns", {
  path <- make_test_workbook()
  s <- read_analysis_sheet(path, "Form")

  expect_s3_class(s, "analysis_sheet")
  expect_identical(s$y_var, "successes")
  expect_identical(s$trials_var, "trials_total")
  expect_identical(s$family_call, "binomial(link = \"identity\")")

  # % Normal Development, Mean and S.D. are worked out from the counts, so they
  # must not be read as data
  expect_named(
    s$data,
    c("concentration", "successes", "failures", "replicate", "trials_total")
  )

  expect_identical(nrow(s$data), 18L)
  expect_identical(s$data$successes[1:3], c(138L, 136L, 146L))
  expect_identical(s$data$failures[1:3], c(10L, 9L, 12L))
  expect_identical(s$data$trials_total[1:3], c(148L, 145L, 158L))
  # replicate is numbered within concentration when the sheet does not record it
  expect_identical(s$data$replicate[1:6], c(1L, 2L, 3L, 1L, 2L, 3L))
})

test_that("reading stops at the summary block below the data", {
  path <- make_test_workbook()
  s <- read_analysis_sheet(path, "Form")
  # the Average Control block occupies sheet rows 27 and 28 and has no
  # concentration, so 18 data rows is the whole of the data
  expect_identical(max(s$data$concentration), 40)
  expect_identical(nrow(s$data), 18L)
})

test_that("a plain table with one response column is read as continuous", {
  path <- make_test_workbook()
  s <- read_analysis_sheet(path, "Plain")

  expect_identical(s$response, "continuous")
  expect_identical(s$y_var, "response")
  expect_true(is.na(s$trials_var))
  expect_identical(s$family_call, "gaussian()")
  expect_identical(nrow(s$data), 10L)
  expect_identical(s$labels$x, "dose")
})

test_that("read_analysis_sheet refuses a sheet that holds no data", {
  path <- make_test_workbook()
  expect_error(read_analysis_sheet(path, "Empty"), "does not hold fittable")
})

test_that("read_workbook reads every fittable sheet", {
  path <- make_test_workbook()
  out <- read_workbook(path)
  expect_named(out, c("Form", "Plain"))
  expect_true(all(vapply(out, inherits, logical(1), "analysis_sheet")))
})

test_that("header_roles discards derived columns and orders normal after abnormal", {
  roles <- toxtools:::header_roles(c(
    "Copper Reference (ug/L)",
    "No. Normal Development",
    "No. Abnormal Development",
    "% Normal Development",
    "% Control",
    "Mean",
    "S.D."
  ))
  expect_identical(
    roles,
    c("x", "successes", "failures", NA, NA, NA, NA)
  )
})

test_that("find_workbook returns one workbook and explains when it cannot", {
  dir <- withr::local_tempdir()
  expect_error(find_workbook(file.path(dir, "nope")), "does not exist")
  expect_error(find_workbook(dir), "no Excel workbook")

  file.create(file.path(dir, "one.xlsx"))
  # a lock file left by an open workbook is not a workbook
  file.create(file.path(dir, "~$one.xlsx"))
  expect_identical(basename(find_workbook(dir)), "one.xlsx")

  file.create(file.path(dir, "two.xlsx"))
  expect_error(find_workbook(dir), "more than one")
})

test_that("the reader reproduces the hand-extracted sea_urchin dataset", {
  # data-raw/sea_urchin.R takes this sheet by absolute cell range, having been
  # written against the form by hand. The reader here finds the same block by
  # column name. Agreeing with that extraction is the check that the search is
  # picking up the counts and not the percentages derived from them.
  #
  # The workbook is a laboratory record and is not held in the repository, so
  # the test is skipped where it is absent.
  path <- "../../inputs/Test data.xlsx"
  skip_if_not(file.exists(path), "example workbook not present")
  skip_if_not_installed("readxl")

  s <- read_analysis_sheet(path, "Copper Ref (4)")
  expect_identical(s$data$concentration, sea_urchin$concentration)
  expect_identical(s$data$replicate, sea_urchin$replicate)
  expect_identical(s$data$successes, sea_urchin$n_normal)
  expect_identical(s$data$failures, sea_urchin$n_abnormal)
})

test_that("a sheet counting only the animals that did not respond is refused", {
  skip_if_not_installed("openxlsx")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "fail_only.xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "FailOnly")
  openxlsx::writeData(
    wb,
    "FailOnly",
    data.frame(
      concentration = rep(c(0, 1, 3, 9, 27), each = 2),
      `No. Abnormal Development` = c(1, 2, 3, 4, 9, 8, 20, 22, 40, 38),
      check.names = FALSE
    )
  )
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)

  # the number of trials is unknown without the matching count, so the sheet
  # must be reported as unfittable here rather than accepted and then failing
  # inside bnec() after the user has waited for the fit
  cls <- classify_sheets(path)
  expect_false(cls$analyse)
  expect_match(cls$reason, "total number scored")
  expect_error(read_analysis_sheet(path, "FailOnly"), "does not hold fittable")
})

## Builds a one-sheet workbook of counts, so that a single bad value can be
## introduced without disturbing the shared fixture.
counts_sheet <- function(dir, name, successes, trials_col = NULL) {
  path <- file.path(dir, paste0(name, ".xlsx"))
  d <- data.frame(
    concentration = rep(c(0, 1, 3, 9, 27), each = 2),
    `No. Normal Development` = successes,
    check.names = FALSE
  )
  if (is.null(trials_col)) {
    d[["No. Abnormal Development"]] <- rep(5, 10)
  } else {
    d[["Total scored"]] <- trials_col
  }
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "S")
  openxlsx::writeData(wb, "S", d)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  path
}

test_that("impossible counts are refused by name rather than left to brms", {
  skip_if_not_installed("openxlsx")
  dir <- withr::local_tempdir()

  # more animals responding than were scored: a keying error on the form
  p <- counts_sheet(
    dir,
    "toomany",
    successes = c(rep(10, 9), 99),
    trials_col = rep(20, 10)
  )
  expect_error(read_analysis_sheet(p, "S"), "more animals responded")

  p2 <- counts_sheet(
    dir,
    "negative",
    successes = c(rep(10, 9), -1),
    trials_col = rep(20, 10)
  )
  expect_error(read_analysis_sheet(p2, "S"), "negative count")
})

test_that("rows left out for a missing value are reported, not dropped quietly", {
  skip_if_not_installed("openxlsx")
  dir <- withr::local_tempdir()
  d <- data.frame(
    concentration = rep(c(0, 1, 3, 9, 27), each = 2),
    `No. Normal Development` = c(10, 11, 9, 10, 8, 7, 4, 4, 1, NA),
    `No. Abnormal Development` = rep(5, 10),
    check.names = FALSE
  )
  path <- file.path(dir, "gap.xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "S")
  openxlsx::writeData(wb, "S", d)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)

  s <- read_analysis_sheet(path, "S")
  expect_identical(nrow(s$data), 9L)
  expect_match(s$notes, "1 row was left out")
})
