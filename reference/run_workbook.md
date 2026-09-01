# Analyse every sheet in a workbook and write a report

The single call that runs the whole workflow. It finds the workbook,
decides which of its sheets hold concentration-response data, fits the
`bayesnec` model set to each of them, and renders one PDF holding the
results for every sheet.

## Usage

``` r
run_workbook(
  path = find_workbook(),
  output_dir = "outputs",
  sheets = NULL,
  model = "decline",
  predictor_transform = "sqrt",
  ecx_vals = c(10, 50),
  refit = FALSE,
  render = TRUE,
  format = "pdf",
  ...
)
```

## Arguments

- path:

  Path to the workbook. The default takes the single workbook in
  `inputs/`.

- output_dir:

  Folder to write results into. A sub-folder named after the workbook is
  created inside it.

- sheets:

  Optional character vector naming the sheets to analyse. The default
  analyses every sheet identified as holding fittable data.

- model, predictor_transform, ecx_vals:

  Passed to
  [`fit_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/fit_analysis_sheet.md)
  and
  [`workbook_estimates()`](https://open-aims.github.io/toxtools/reference/workbook_estimates.md).

- refit:

  If `TRUE`, refit sheets that already have a saved fit.

- render:

  If `FALSE`, fit and save but do not render the report.

- format:

  Report format, passed to Quarto. `"pdf"` by default; `"html"` needs no
  LaTeX installation.

- ...:

  Further arguments passed to
  [`fit_analysis_sheet()`](https://open-aims.github.io/toxtools/reference/fit_analysis_sheet.md),
  and from there to
  [`bayesnec::bnec()`](https://open-aims.github.io/bayesnec/reference/bnec.html)
  and [`brms::brm()`](https://paulbuerkner.com/brms/reference/brm.html);
  for example `backend = "cmdstanr"`, `iter` or `cores`.

## Value

Invisibly, the path to the manifest file describing the run.

## Details

Fitting is the slow step, taking roughly twenty to forty minutes per
sheet on four cores. Each fit is saved as it completes, and a fit that
is already saved is reused rather than repeated, so an interrupted run
can be restarted by calling the function again. A saved fit is reused
only when it was fitted with the same model set, the same predictor
transformation and the same sheet; changing any of them causes it to be
refitted.

A sheet that cannot be analysed does not stop the run. The reason is
reported, recorded in `sheet_classification.csv` and carried in the
manifest, and the remaining sheets are still fitted and reported; a run
stops only when no sheet at all could be analysed. A run covering
several sheets takes hours, and discarding the ones that worked because
a later one failed would waste them.

## Examples

``` r
if (FALSE) { # \dontrun{
run_workbook()
} # }
```
