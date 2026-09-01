# Fit the bayesnec model set to one analysis sheet

Fits a set of concentration-response curves to the data read from one
sheet and returns the model-averaged fit, together with the information
the report needs to describe it.

## Usage

``` r
fit_analysis_sheet(
  sheet,
  model = "decline",
  predictor_transform = c("sqrt", "log", "identity"),
  chains = 4,
  cores = chains,
  seed = 101,
  ...
)
```

## Arguments

- sheet:

  An `analysis_sheet` object from
  [`read_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/read_analysis_sheet.md).

- model:

  Model set passed to
  [`bayesnec::bnec()`](https://open-aims.github.io/bayesnec/reference/bnec.html).
  The default, `"decline"`, fits the equations that decrease
  monotonically with concentration. Use `"all"` to include the hormesis
  equations, which allow the response to rise before it falls.

- predictor_transform:

  One of `"sqrt"`, `"log"` or `"identity"`.

- chains, cores, seed:

  Passed to
  [`bayesnec::bnec()`](https://open-aims.github.io/bayesnec/reference/bnec.html).

- ...:

  Further arguments passed to
  [`bayesnec::bnec()`](https://open-aims.github.io/bayesnec/reference/bnec.html),
  and from there to
  [`brms::brm()`](https://paulbuerkner.com/brms/reference/brm.html); for
  example `iter`, `backend` or `control`.

## Value

An object of class `analysis_fit`: a list holding the fit (`fit`), the
`analysis_sheet` it was fitted to, the formula used and the
transformation functions.

## Details

Concentration is transformed before fitting, by default with a square
root. The square root is the default rather than a logarithm because
these designs include a zero control: a logarithm of zero is undefined,
so a log-scaled fit would either drop the controls or require an
arbitrary offset added to every concentration. The square root spreads
the low concentrations, where the curve turns, without either.

The response is fitted as recorded, not as a per cent of control.
[`bayesnec::ecx()`](https://open-aims.github.io/bayesnec/reference/ecx.html)
measures decline relative to the fitted control value one posterior draw
at a time, so it already accounts for uncertainty in the control;
dividing by the observed control mean beforehand discards that
uncertainty and biases the effect concentrations upwards.

## Examples

``` r
if (FALSE) { # \dontrun{
s <- read_analysis_sheet(find_workbook(), "Copper Ref (4)")
fit_analysis_sheet(s)
} # }
```
