# No-effect and effect concentrations

Extracts the model-averaged no-effect concentration and the effect
concentrations from a fit, returned in the units recorded on the sheet.

## Usage

``` r
workbook_estimates(x, ecx_vals = c(10, 50))
```

## Arguments

- x:

  An `analysis_fit` object from
  [`fit_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/fit_analysis_sheet.md).

- ecx_vals:

  Effect sizes, as percentages.

## Value

A data frame with the columns `estimate`, `value`, `lower` and `upper`,
where the interval is the 95% credible interval.

## Details

The estimates are back-transformed. The curve is fitted to transformed
concentration, so
[`bayesnec::nec()`](https://open-aims.github.io/bayesnec/reference/nec.html)
and
[`bayesnec::ecx()`](https://open-aims.github.io/bayesnec/reference/ecx.html)
report on that scale unless the inverse transformation is supplied; the
values here are square roots or logarithms of concentrations otherwise,
which are easy to mistake for concentrations.

For a model set holding both threshold and smooth equations, `nec()`
returns the model-averaged N(S)EC: the `nec` parameter of the threshold
equations combined with the no-significant-effect concentration of the
smooth ones.

## Examples

``` r
if (FALSE) { # \dontrun{
workbook_estimates(fit)
} # }
```
