#' Fit the bayesnec model set to one analysis sheet
#'
#' Fits a set of concentration-response curves to the data read from one sheet
#' and returns the model-averaged fit, together with the information the report
#' needs to describe it.
#'
#' Concentration is transformed before fitting, by default with a square root.
#' The square root is the default rather than a logarithm because these designs
#' include a zero control: a logarithm of zero is undefined, so a log-scaled
#' fit would either drop the controls or require an arbitrary offset added to
#' every concentration. The square root spreads the low concentrations, where
#' the curve turns, without either.
#'
#' The response is fitted as recorded, not as a per cent of control.
#' [bayesnec::ecx()] measures decline relative to the fitted control value one
#' posterior draw at a time, so it already accounts for uncertainty in the
#' control; dividing by the observed control mean beforehand discards that
#' uncertainty and biases the effect concentrations upwards.
#'
#' @param sheet An `analysis_sheet` object from [read_analysis_sheet()].
#' @param model Model set passed to [bayesnec::bnec()]. The default,
#'   `"decline"`, fits the equations that decrease monotonically with
#'   concentration. Use `"all"` to include the hormesis equations, which allow
#'   the response to rise before it falls.
#' @param predictor_transform One of `"sqrt"`, `"log"` or `"identity"`.
#' @param chains,cores,seed Passed to [bayesnec::bnec()].
#' @param ... Further arguments passed to [bayesnec::bnec()], and from there to
#'   [brms::brm()]; for example `iter`, `backend` or `control`.
#'
#' @return An object of class `analysis_fit`: a list holding the fit
#'   (`fit`), the `analysis_sheet` it was fitted to, the formula used and the
#'   transformation functions.
#' @export
#' @examples
#' \dontrun{
#' s <- read_analysis_sheet(find_workbook(), "Copper Ref (4)")
#' fit_analysis_sheet(s)
#' }
fit_analysis_sheet <- function(
  sheet,
  model = "decline",
  predictor_transform = c(
    "sqrt",
    "log",
    "identity"
  ),
  chains = 4,
  cores = chains,
  seed = 101,
  ...
) {
  check_pkgs("bayesnec", "brms")
  stopifnot(inherits(sheet, "analysis_sheet"))
  transform <- match.arg(predictor_transform)
  d <- sheet$data

  if (identical(transform, "log") && any(d[[sheet$x_var]] <= 0)) {
    stop(
      "predictor_transform = \"log\" cannot be used: the sheet includes a ",
      "concentration of zero, and log(0) is undefined. Use \"sqrt\", which ",
      "keeps the controls.",
      call. = FALSE
    )
  }
  funs <- predictor_funs(transform)

  ## set.seed() as well as bnec(seed =): the seed argument is passed to the
  ## sampler, but the model set is also assembled using random starting values
  ## drawn in this session.
  set.seed(seed)

  form <- bnec_formula(sheet, funs, model)
  family <- eval(
    parse(text = sheet$family_call),
    envir = list2env(
      list(
        binomial = stats::binomial,
        gaussian = stats::gaussian,
        Beta = brms::Beta
      ),
      parent = baseenv()
    )
  )

  fit <- bayesnec::bnec(
    formula = form,
    data = d,
    family = family,
    seed = seed,
    chains = chains,
    cores = cores,
    ...
  )

  structure(
    list(
      fit = fit,
      sheet = sheet,
      formula = deparse1(form),
      transform = transform,
      funs = funs,
      model_set = model
    ),
    class = "analysis_fit"
  )
}

## Build the bayesnec formula from the columns identified on the sheet.
##
## The formula is assembled as text because the response, the trials column and
## the predictor transformation are all decided at run time from the sheet.
## Its environment is set to the namespace's parent, so that the transformation
## resolves to base R rather than to whatever the user happens to have defined.
bnec_formula <- function(sheet, funs, model) {
  lhs <- if (!is.na(sheet$trials_var)) {
    sprintf("%s | trials(%s)", sheet$y_var, sheet$trials_var)
  } else {
    sheet$y_var
  }
  txt <- sprintf(
    "%s ~ crf(%s, model = %s)",
    lhs,
    funs$term(sheet$x_var),
    deparse(model)
  )
  stats::as.formula(txt, env = baseenv())
}

#' @export
print.analysis_fit <- function(x, ...) {
  cat("bayesnec fit for sheet: ", x$sheet$sheet, "\n", sep = "")
  cat("  formula:   ", x$formula, "\n", sep = "")
  cat("  family:    ", x$sheet$family_call, "\n", sep = "")
  cat(
    "  models:    ",
    paste(x$fit$success_models, collapse = ", "),
    "\n",
    sep = ""
  )
  invisible(x)
}

#' No-effect and effect concentrations
#'
#' Extracts the model-averaged no-effect concentration and the effect
#' concentrations from a fit, returned in the units recorded on the sheet.
#'
#' The estimates are back-transformed. The curve is fitted to transformed
#' concentration, so [bayesnec::nec()] and [bayesnec::ecx()] report on that
#' scale unless the inverse transformation is supplied; the values here are
#' square roots or logarithms of concentrations otherwise, which are easy to
#' mistake for concentrations.
#'
#' For a model set holding both threshold and smooth equations, `nec()` returns
#' the model-averaged N(S)EC: the `nec` parameter of the threshold equations
#' combined with the no-significant-effect concentration of the smooth ones.
#'
#' @param x An `analysis_fit` object from [fit_analysis_sheet()].
#' @param ecx_vals Effect sizes, as percentages.
#'
#' @return A data frame with the columns `estimate`, `value`, `lower` and
#'   `upper`, where the interval is the 95% credible interval.
#' @export
#' @examples
#' \dontrun{
#' workbook_estimates(fit)
#' }
workbook_estimates <- function(x, ecx_vals = c(10, 50)) {
  check_pkgs("bayesnec")
  stopifnot(inherits(x, "analysis_fit"))
  inv <- x$funs$inv

  one <- function(label, expr) {
    val <- tryCatch(
      suppressWarnings(suppressMessages(expr)),
      error = function(e) {
        warning(
          label,
          " could not be estimated for sheet '",
          x$sheet$sheet,
          "': ",
          conditionMessage(e),
          call. = FALSE
        )
        c(NA_real_, NA_real_, NA_real_)
      }
    )
    data.frame(
      estimate = label,
      value = unname(val[1]),
      lower = unname(val[2]),
      upper = unname(val[3]),
      stringsAsFactors = FALSE
    )
  }

  rows <- list(one("N(S)EC", bayesnec::nec(x$fit, xform = inv)))
  for (e in ecx_vals) {
    rows[[length(rows) + 1]] <- one(
      paste0("EC", e),
      bayesnec::ecx(x$fit, ecx_val = e, xform = inv)
    )
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Diagnostics for a fitted model set
#'
#' Collects the checks that decide whether the estimates can be trusted: the
#' convergence statistic for every parameter of every retained equation, the
#' Bayesian R-squared of each, and, where the response is a count, a test for
#' over-dispersion.
#'
#' The over-dispersion test matters for a binomial response because the
#' binomial variance is fixed by the mean. Variation beyond that cannot be
#' absorbed by the fit and instead inflates the apparent precision of the
#' estimates, so a dispersion estimate whose interval excludes 1 is a reason to
#' refit with `family = brms::beta_binomial()`.
#'
#' The test is applied to each equation separately, and an equation fails it
#' when it fits the data badly, whether or not the data are over-dispersed:
#' residual variation the wrong curve cannot account for is counted as
#' dispersion. Such an equation is given almost no weight in the model average,
#' so it says nothing about the estimates that are reported. Over-dispersion is
#' therefore only worth acting on when an equation that carries weight shows
#' it, which is what the `warn` column marks.
#'
#' @param x An `analysis_fit` object from [fit_analysis_sheet()].
#' @param weight_threshold The stacking weight below which an equation is
#'   treated as making no contribution to the model average, and so not worth
#'   warning about. The default of 0.01 is one per cent of the weight.
#'
#' The same qualification applies to the convergence check. An equation the
#' sampler struggles with is usually one that suits the data badly, and it is
#' given almost no weight for the same reason, so its R-hat says nothing about
#' the model-averaged estimates. It is still reported, because a convergence
#' failure is evidence about the fit; but whether it bears on the estimates is
#' marked separately, in the same `warn` column.
#'
#' @return A list with elements `rhat` (models flagged for non-convergence),
#'   `r2` (Bayesian R-squared per model), `dispersion` and `rhat_flags` (data
#'   frames, or `NULL` where they do not apply). Both data frames are ordered
#'   by weight and carry a `weight` column, the raw result of the check, and a
#'   `warn` column that is `TRUE` only where the equation also carries weight.
#' @export
#' @examples
#' \dontrun{
#' workbook_diagnostics(fit)
#' }
workbook_diagnostics <- function(x, weight_threshold = 0.01) {
  check_pkgs("bayesnec", "brms")
  stopifnot(inherits(x, "analysis_fit"))
  fit <- x$fit
  summ <- suppressWarnings(suppressMessages(summary(fit)))

  rhat_out <- tryCatch(
    suppressWarnings(suppressMessages(brms::rhat(fit))),
    error = function(e) NULL
  )

  r2 <- tryCatch(
    {
      tab <- summ$bayesr2
      data.frame(
        model = rownames(tab),
        tab,
        row.names = NULL,
        stringsAsFactors = FALSE
      )
    },
    error = function(e) NULL
  )

  disp <- dispersion_table(summ$mod_weights, weight_threshold)

  list(
    rhat = rhat_out,
    r2 = r2,
    dispersion = disp,
    rhat_flags = rhat_flag_table(
      summ$rhat_issues,
      summ$mod_weights,
      weight_threshold
    ),
    rhat_issues = summ$rhat_issues,
    weights = summ$mod_weights,
    summary = summ
  )
}

## Build the over-dispersion table from the model weights that summary() has
## already computed.
##
## The estimates are taken from there rather than recomputed with
## dispersion(), which would mean a posterior_predict() draw for every equation
## in the set: for a set of twelve, minutes of work for numbers already to
## hand. The columns are present only for the families the test applies to.
##
## Kept separate from workbook_diagnostics() so that the rule deciding what is
## worth warning about can be tested without fitting a model.
dispersion_table <- function(w, weight_threshold = 0.01) {
  disp_cols <- c("dispersion_Estimate", "dispersion_Q2.5", "dispersion_Q97.5")
  if (is.null(w) || !all(disp_cols %in% colnames(w))) {
    return(NULL)
  }
  out <- data.frame(
    model = rownames(w),
    weight = if ("wi" %in% colnames(w)) unname(w[, "wi"]) else NA_real_,
    estimate = unname(w[, "dispersion_Estimate"]),
    lower = unname(w[, "dispersion_Q2.5"]),
    upper = unname(w[, "dispersion_Q97.5"]),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
  out$overdispersed <- out$lower > 1 | out$upper < 1

  ## An equation that fits badly fails the dispersion test whatever the data
  ## are doing, because the variation its curve cannot account for is counted
  ## as dispersion. Such an equation also carries almost none of the stacking
  ## weight, so it has no bearing on the estimates that are reported. Warning
  ## on the raw test therefore raises an alarm about the wrong thing: only an
  ## equation that contributes to the model average is worth acting on.
  ##
  ## Where the weights are unavailable the raw test is kept, so that a finding
  ## is over-reported rather than silently dropped.
  out$contributes <- if (all(is.na(out$weight))) {
    TRUE
  } else {
    !is.na(out$weight) & out$weight >= weight_threshold
  }
  out$warn <- out$overdispersed & out$contributes
  out <- out[order(-out$weight, out$model), ]
  rownames(out) <- NULL
  out
}

## Which equations the convergence check flagged, and whether that matters.
##
## Separated from the raw flags for the reason given in the documentation
## above: an equation the sampler cannot fit is usually one that suits the data
## badly, and carries no weight in the model average as a result.
rhat_flag_table <- function(issues, w, weight_threshold = 0.01) {
  if (is.null(issues) || length(issues) == 0) {
    return(NULL)
  }
  flagged <- unlist(issues)
  if (is.null(names(flagged))) {
    return(NULL)
  }
  out <- data.frame(
    model = names(flagged),
    flagged = as.logical(flagged),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
  out$weight <- if (!is.null(w) && "wi" %in% colnames(w)) {
    unname(w[match(out$model, rownames(w)), "wi"])
  } else {
    NA_real_
  }
  out$contributes <- if (all(is.na(out$weight))) {
    TRUE
  } else {
    !is.na(out$weight) & out$weight >= weight_threshold
  }
  out$warn <- out$flagged & out$contributes
  out <- out[order(-out$weight, out$model), ]
  rownames(out) <- NULL
  out
}
