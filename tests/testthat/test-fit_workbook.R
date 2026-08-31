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
