# Read every analysis sheet in a workbook

Read every analysis sheet in a workbook

## Usage

``` r
read_workbook(path = find_workbook(), sheets = NULL)
```

## Arguments

- path:

  Path to the workbook. Defaults to the single workbook found by
  [`find_workbook()`](https://open-aims.github.io/toxtools/reference/find_workbook.md).

- sheets:

  Optional character vector naming the sheets to read. The default reads
  every sheet
  [`classify_sheets()`](https://open-aims.github.io/toxtools/reference/classify_sheets.md)
  identifies as holding fittable data.

## Value

A named list of `analysis_sheet` objects.

## Examples

``` r
if (FALSE) { # \dontrun{
read_workbook()
} # }
```
