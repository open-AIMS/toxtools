# Plot the observed data

Draws the recorded response against concentration, with no model fitted.
This is the check that the right rows and columns were read from the
sheet: the points should reproduce what is on the laboratory form.

## Usage

``` r
plot_sheet_data(sheet, transform = "sqrt")
```

## Arguments

- sheet:

  An `analysis_sheet` object from
  [`read_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/read_analysis_sheet.md).

- transform:

  Concentration axis spacing, one of `"sqrt"`, `"log"` or `"identity"`.
  Match this to the transformation used for the fit.

## Value

A `ggplot` object.

## Examples

``` r
if (FALSE) { # \dontrun{
plot_sheet_data(read_analysis_sheet(find_workbook(), "Copper Ref (4)"))
} # }
```
