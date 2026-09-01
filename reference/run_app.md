# Run the analysis through a point-and-click interface

Opens a small web page in the browser that drives the same workflow as
[`run_workbook()`](https://open-aims.github.io/toxtools/reference/run_workbook.md):
choose a workbook, see which of its sheets hold data that can be fitted,
choose the settings, start the analysis, watch it run, and download the
report. Nothing has to be typed.

## Usage

``` r
run_app(
  input_dir = "inputs",
  output_dir = "outputs",
  launch_browser = TRUE,
  ...
)
```

## Arguments

- input_dir:

  Folder holding the workbooks to choose between. Workbooks added
  through the page are copied into it.

- output_dir:

  Folder to write results into.

- launch_browser:

  Whether to open a browser window.

- ...:

  Further arguments passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Value

Called for its side effect. Returns nothing.

## Details

The page runs on the machine it is started from. The workbook is not
sent anywhere, and the results are written to the same `outputs/` folder
that
[`run_workbook()`](https://open-aims.github.io/toxtools/reference/run_workbook.md)
writes to.

Fitting is done in a separate R process, so the page stays responsive
for the twenty to forty minutes each sheet takes, and closing the
browser tab by accident does not stop the analysis. The process is
stopped when the app itself is stopped.

## Examples

``` r
if (FALSE) { # \dontrun{
run_app()
} # }
```
