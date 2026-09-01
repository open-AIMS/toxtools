# Plot a fitted model set

Draws the model-averaged fit, or the individual equations that make it
up, with the concentration axis spaced on the scale the curve was fitted
on and labelled in the units recorded on the sheet.

## Usage

``` r
plot_workbook_fit(x, estimates = NULL, all_models = FALSE, title = NULL)
```

## Arguments

- x:

  An `analysis_fit` object from
  [`fit_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/fit_analysis_sheet.md).

- estimates:

  Optional data frame from
  [`workbook_estimates()`](https://open-aims.github.io/toxtools/reference/workbook_estimates.md).
  When supplied and `all_models` is `FALSE`, the no-effect concentration
  and its credible interval are drawn on the plot and labelled in the
  recorded units.

- all_models:

  If `TRUE`, one panel per retained equation instead of the
  model-averaged curve.

- title:

  Plot title. `NULL` uses the sheet name.

## Value

A `ggplot` object.

## Details

The axis is spaced by the square root (or logarithm) of concentration,
which is the scale the curve was fitted on and which spreads out the low
concentrations where the response turns. Only the spacing is
transformed: the ticks are labelled with the concentrations themselves,
so the axis can be read in the units on the sheet.

`bayesnec` returns plot data on the recorded concentration scale even
when the curve was fitted to a transformed predictor, so the spacing is
applied by the scale rather than by transforming the data. Its `nec()`
and `ecx()` estimates, by contrast, come back on the fitted scale;
[`workbook_estimates()`](https://open-aims.github.io/toxtools/reference/workbook_estimates.md)
back-transforms those, which is why the value annotated here needs no
further conversion.

## Examples

``` r
if (FALSE) { # \dontrun{
plot_workbook_fit(fit, workbook_estimates(fit))
} # }
```
