# Render the report for a completed run

Renders the Quarto report from the fits saved by
[`run_workbook()`](https://open-aims.github.io/toxtools/reference/run_workbook.md).
Use this to produce the report again, in a different format or after
editing the template, without refitting anything.

## Usage

``` r
render_workbook_report(manifest, format = "pdf", template = NULL)
```

## Arguments

- manifest:

  Path to the `manifest.rds` written by
  [`run_workbook()`](https://open-aims.github.io/toxtools/reference/run_workbook.md).

- format:

  Quarto output format, `"pdf"` or `"html"`.

- template:

  Path to the Quarto template. The default uses the one installed with
  the package.

## Value

Invisibly, the path to the rendered report.

## Examples

``` r
if (FALSE) { # \dontrun{
render_workbook_report("outputs/Test_data/manifest.rds")
} # }
```
