test_that("predictor_funs inverts its own transformation", {
  for (tr in c("sqrt", "log", "identity")) {
    funs <- toxtools:::predictor_funs(tr)
    x <- c(0.5, 2, 10, 40)
    expect_equal(funs$inv(funs$fwd(x)), x, tolerance = 1e-12)
  }
  # the square root is the default because a dilution series includes a zero
  # control, which a logarithm cannot take
  expect_identical(toxtools:::predictor_funs("sqrt")$fwd(0), 0)
  expect_identical(toxtools:::predictor_funs("log")$fwd(0), -Inf)
})

test_that("axis_breaks uses the tested concentrations when there are few", {
  funs <- toxtools:::predictor_funs("sqrt")
  conc <- rep(c(0, 2.5, 5, 10, 20, 40), each = 3)
  expect_identical(toxtools:::axis_breaks(conc, funs), c(0, 2.5, 5, 10, 20, 40))

  # with many levels, breaks are spaced evenly on the fitted scale instead
  many <- seq(0, 100, length.out = 25)
  brks <- toxtools:::axis_breaks(many, funs)
  expect_lt(length(brks), length(unique(many)))
  expect_true(all(brks >= 0 & brks <= 100))
})

test_that("bnec_formula names the trials column for a count response", {
  path <- make_test_workbook()
  s <- read_analysis_sheet(path, "Form")
  f <- toxtools:::bnec_formula(
    s,
    toxtools:::predictor_funs("sqrt"),
    "decline"
  )
  expect_identical(
    deparse1(f),
    paste(
      "successes | trials(trials_total) ~",
      "crf(sqrt(concentration), model = \"decline\")"
    )
  )

  # a continuous response has no trials term
  s2 <- read_analysis_sheet(path, "Plain")
  f2 <- toxtools:::bnec_formula(
    s2,
    toxtools:::predictor_funs("log"),
    c("nec3param", "ecxexp")
  )
  expect_identical(
    deparse1(f2),
    "response ~ crf(log(concentration), model = c(\"nec3param\", \"ecxexp\"))"
  )
})

test_that("a log transformation is refused when a zero control is present", {
  skip_if_not_installed("bayesnec")
  skip_if_not_installed("brms")
  path <- make_test_workbook()
  s <- read_analysis_sheet(path, "Form")
  expect_error(
    fit_analysis_sheet(s, predictor_transform = "log"),
    "log\\(0\\) is undefined"
  )
})

test_that("safe_name makes a file name from a sheet name", {
  expect_identical(toxtools:::safe_name("Copper Ref (4)"), "Copper_Ref_4")
  expect_identical(toxtools:::safe_name("a/b:c"), "a_b_c")
  expect_identical(toxtools:::safe_name("!!!"), "sheet")
})

## A model weights table in the shape summary.bayesmanecfit() returns: one row
## per equation, with the stacking weight and the dispersion interval.
mock_weights <- function(model, wi, est, lo, hi) {
  m <- cbind(
    waic = rep(0, length(model)),
    wi = wi,
    dispersion_Estimate = est,
    dispersion_Q2.5 = lo,
    dispersion_Q97.5 = hi
  )
  rownames(m) <- model
  m
}

test_that("dispersion is only worth acting on where the equation carries weight", {
  # ecxexp is the shape of a badly fitting curve: its dispersion is enormous
  # because the residuals its curve cannot account for are counted as
  # dispersion, and it is given no weight for the same reason. ecxwb1 carries
  # the weight and passes the test.
  w <- mock_weights(
    model = c("ecxwb1", "ecx4param", "nec3param", "ecxexp"),
    wi = c(0.81, 0.06, 0.002, 1e-40),
    est = c(1.05, 1.32, 2.00, 31.96),
    lo = c(0.51, 0.66, 1.01, 16.91),
    hi = c(2.58, 3.14, 4.64, 71.86)
  )
  d <- toxtools:::dispersion_table(w)

  expect_identical(d$model, c("ecxwb1", "ecx4param", "nec3param", "ecxexp"))
  expect_identical(d$overdispersed, c(FALSE, FALSE, TRUE, TRUE))
  # both over-dispersed equations are below the weight threshold
  expect_identical(d$warn, rep(FALSE, 4))
})

test_that("dispersion warns when a weighted equation is over-dispersed", {
  w <- mock_weights(
    model = c("nec3param", "ecxexp"),
    wi = c(0.95, 0.05),
    est = c(2.00, 31.96),
    lo = c(1.01, 16.91),
    hi = c(4.64, 71.86)
  )
  d <- toxtools:::dispersion_table(w)
  expect_identical(d$warn, c(TRUE, TRUE))

  # raising the threshold above a contributing equation's weight silences it
  d2 <- toxtools:::dispersion_table(w, weight_threshold = 0.1)
  expect_identical(d2$warn, c(TRUE, FALSE))
})

test_that("dispersion_table orders by weight and copes with what is missing", {
  w <- mock_weights(
    model = c("a", "b", "c"),
    wi = c(0.1, 0.7, 0.2),
    est = c(1, 1, 1),
    lo = c(0.5, 0.5, 0.5),
    hi = c(2, 2, 2)
  )
  expect_identical(toxtools:::dispersion_table(w)$model, c("b", "c", "a"))

  # a gaussian or beta fit has no dispersion columns and no test to report
  expect_null(toxtools:::dispersion_table(w[, "wi", drop = FALSE]))
  expect_null(toxtools:::dispersion_table(NULL))

  # without weights the raw test is kept rather than every finding dropped
  no_wi <- w[, setdiff(colnames(w), "wi"), drop = FALSE]
  no_wi[, "dispersion_Q2.5"] <- c(1.1, 1.1, 1.1)
  d <- toxtools:::dispersion_table(no_wi)
  expect_true(all(d$overdispersed))
  expect_true(all(d$warn))
})

test_that("a convergence failure is qualified by the weight the equation carries", {
  w <- mock_weights(
    model = c("ecxll3", "ecxsigm", "nec4param"),
    wi = c(0.49, 0.17, 1e-8),
    est = c(1, 1, 1),
    lo = c(0.5, 0.5, 0.5),
    hi = c(2, 2, 2)
  )
  issues <- list(ecxll3 = FALSE, ecxsigm = FALSE, nec4param = TRUE)

  d <- toxtools:::rhat_flag_table(issues, w)
  expect_identical(d$model, c("ecxll3", "ecxsigm", "nec4param"))
  # the failure is reported, but it is not a reason to distrust the estimates
  expect_identical(d$flagged, c(FALSE, FALSE, TRUE))
  expect_identical(d$warn, rep(FALSE, 3))

  # the same failure in the dominant equation is worth acting on
  issues2 <- list(ecxll3 = TRUE, ecxsigm = FALSE, nec4param = TRUE)
  d2 <- toxtools:::rhat_flag_table(issues2, w)
  expect_identical(d2$warn, c(TRUE, FALSE, FALSE))

  expect_null(toxtools:::rhat_flag_table(NULL, w))
  expect_null(toxtools:::rhat_flag_table(list(), w))
})

test_that("axis labels strip a count prefix without eating the first word", {
  lab <- function(successes, family = "binomial(link = \"identity\")") {
    toxtools:::axis_label_y(list(
      labels = list(successes = successes, response = NA_character_),
      family_call = family
    ))
  }
  expect_identical(
    lab("No. Normal Development"),
    "Proportion normal development"
  )
  expect_identical(lab("Number of survivors"), "Proportion survivors")

  # the prefix has to be a separate word: these begin with the same letters
  expect_identical(lab("Normal Development"), "Proportion normal development")
  expect_identical(lab("Nauplii alive"), "Proportion nauplii alive")

  # a continuous response keeps its heading as recorded
  expect_identical(lab("Shoot length", "gaussian()"), "Shoot length")
})

test_that("a single equation is refused before anything is fitted", {
  skip_if_not_installed("bayesnec")
  skip_if_not_installed("brms")
  path <- make_test_workbook()
  s <- read_analysis_sheet(path, "Form")
  # a model average is what the whole workflow reports, so one equation cannot
  # be what is asked for; the message names the sets that can be
  expect_error(
    fit_analysis_sheet(s, model = "nec3param"),
    "fits a single equation"
  )
  expect_error(fit_analysis_sheet(s, model = "nec3param"), "decline")
})

## The parts of an analysis_fit that decide whether a saved one can be reused.
stub_fit <- function(sheet, model = "decline", transform = "sqrt") {
  structure(
    list(sheet = list(sheet = sheet), model_set = model, transform = transform),
    class = "analysis_fit"
  )
}

test_that("a saved fit is reused only when it answers the same question", {
  obj <- stub_fit("Copper Ref (4)")
  expect_true(
    toxtools:::cached_fit_usable(obj, "decline", "sqrt", "Copper Ref (4)")
  )

  # a different model set or transformation is a different model
  expect_false(toxtools:::cached_fit_usable(
    obj,
    "all",
    "sqrt",
    "Copper Ref (4)"
  ))
  expect_false(
    toxtools:::cached_fit_usable(obj, "decline", "log", "Copper Ref (4)")
  )

  # safe_name() is not one-to-one, so two sheets can share a cache file name;
  # without the sheet check the second would be reported using the first's fit
  expect_identical(
    toxtools:::safe_name("Test (1)"),
    toxtools:::safe_name("Test 1")
  )
  expect_false(toxtools:::cached_fit_usable(obj, "decline", "sqrt", "Test 1"))

  # nothing on disk, or something else entirely
  expect_false(toxtools:::cached_fit_usable(NULL, "decline", "sqrt", "x"))
  expect_false(
    toxtools:::cached_fit_usable(
      list(model_set = "decline"),
      "decline",
      "sqrt",
      "x"
    )
  )
})

test_that("axis breaks drop values the transformation cannot place", {
  log_funs <- toxtools:::predictor_funs("log")
  conc <- rep(c(0, 2.5, 5, 10, 20, 40), each = 3)

  # a zero control has no place on a log axis: kept, it is drawn at -Inf
  brks <- toxtools:::axis_breaks(conc, log_funs)
  expect_false(0 %in% brks)
  expect_true(all(is.finite(log_funs$fwd(brks))))

  # and where pretty() chooses them, a -Inf in the range collapses the set
  many <- c(0, seq(1, 100, length.out = 24))
  brks_many <- toxtools:::axis_breaks(many, log_funs)
  expect_gt(length(brks_many), 3)
  expect_true(all(is.finite(log_funs$fwd(brks_many))))

  # the square root places zero perfectly well and must keep it
  sqrt_funs <- toxtools:::predictor_funs("sqrt")
  expect_true(0 %in% toxtools:::axis_breaks(conc, sqrt_funs))
})

test_that("a sheet that fails is recorded, and a run of only failures stops", {
  skip_if_not_installed("openxlsx")
  skip_if_not_installed("bayesnec")
  skip_if_not_installed("brms")

  # this sheet passes classification -- it names a concentration and a
  # response column and has enough levels -- but fails when read, because more
  # animals responded than were scored. Nothing is fitted, so the test is cheap
  # while still exercising the per-sheet recovery.
  in_dir <- withr::local_tempdir()
  out_dir <- withr::local_tempdir()
  path <- file.path(in_dir, "bad.xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Bad")
  openxlsx::writeData(
    wb,
    "Bad",
    data.frame(
      concentration = rep(c(0, 1, 3, 9, 27), each = 2),
      `No. Normal Development` = c(rep(10, 9), 99),
      `Total scored` = rep(20, 10),
      check.names = FALSE
    )
  )
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)

  expect_true(classify_sheets(path)$analyse)
  expect_error(
    suppressMessages(run_workbook(path, output_dir = out_dir, render = FALSE)),
    "no sheet could be analysed"
  )

  # the reason is left where the user will look for it
  cls <- utils::read.csv(file.path(out_dir, "bad", "sheet_classification.csv"))
  expect_match(cls$reason[cls$sheet == "Bad"], "more animals responded")
})
