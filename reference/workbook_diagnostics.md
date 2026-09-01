# Diagnostics for a fitted model set

Collects the checks that decide whether the estimates can be trusted:
the convergence statistic for every parameter of every retained
equation, the Bayesian R-squared of each, and, where the response is a
count, a test for over-dispersion.

## Usage

``` r
workbook_diagnostics(x, weight_threshold = 0.01)
```

## Arguments

- x:

  An `analysis_fit` object from
  [`fit_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/fit_analysis_sheet.md).

- weight_threshold:

  The stacking weight below which an equation is treated as making no
  contribution to the model average, and so not worth warning about. The
  default of 0.01 is one per cent of the weight.

  The same qualification applies to the convergence check. An equation
  the sampler struggles with is usually one that suits the data badly,
  and it is given almost no weight for the same reason, so its R-hat
  says nothing about the model-averaged estimates. It is still reported,
  because a convergence failure is evidence about the fit; but whether
  it bears on the estimates is marked separately, in the same `warn`
  column.

## Value

A list with elements `rhat` (models flagged for non-convergence), `r2`
(Bayesian R-squared per model), `dispersion` and `rhat_flags` (data
frames, or `NULL` where they do not apply). Both data frames are ordered
by weight and carry a `weight` column, the raw result of the check, and
a `warn` column that is `TRUE` only where the equation also carries
weight.

## Details

The over-dispersion test matters for a binomial response because the
binomial variance is fixed by the mean. Variation beyond that cannot be
absorbed by the fit and instead inflates the apparent precision of the
estimates, so a dispersion estimate whose interval excludes 1 is a
reason to refit with `family = brms::beta_binomial()`.

The test is applied to each equation separately, and an equation fails
it when it fits the data badly, whether or not the data are
over-dispersed: residual variation the wrong curve cannot account for is
counted as dispersion. Such an equation is given almost no weight in the
model average, so it says nothing about the estimates that are reported.
Over-dispersion is therefore only worth acting on when an equation that
carries weight shows it, which is what the `warn` column marks.

## Examples

``` r
if (FALSE) { # \dontrun{
workbook_diagnostics(fit)
} # }
```
