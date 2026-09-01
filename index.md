## Overview

`toxtools` is an R package providing utility functions for
ecotoxicological workflows, including data preparation, summarisation
and helpers shared across concentration-response and species sensitivity
distribution analyses.

The package is at an early stage; the function set is not yet stable.

## Installation

The current development version can be installed from GitHub via

``` r

if (!requireNamespace("remotes")) {
  install.packages("remotes")
}
remotes::install_github("open-AIMS/toxtools")
```

## Usage

Documentation is available on the [project
page](https://open-aims.github.io/toxtools/) and the [reference
page](https://open-aims.github.io/toxtools/reference/).

## Analysing a workbook of concentration-response data

`toxtools` can take an Excel workbook of toxicity test results, work out
which of its sheets hold data that can be fitted, fit the `bayesnec`
model set to each of them, and write a single PDF report. It is intended
to be usable without writing R code.

Put the workbook in the `inputs` folder, then run

``` r

toxtools::run_app()
```

which opens a page in the browser: choose the workbook, tick the sheets
to analyse, press Run, watch the progress, and download the report when
it finishes. Nothing has to be typed, and the analysis runs on the
machine it is started from. The fitting is done in a separate R process,
so the page stays responsive and closing the browser tab does not stop
it.

The same workflow can be run from the console with

``` r

toxtools::run_workbook()
```

or by opening `analysis/run_workbook.R` and running the whole file.
Results are written to `outputs/`, one folder per workbook, holding the
report, the fitted objects and the estimates as CSV files. Both
`inputs/` and `outputs/` are excluded from version control, so a
laboratory workbook placed in `inputs/` is never committed.

Each sheet is searched for a row of column names giving a concentration
column and a response column, so the title block, blank rows and blank
columns of a laboratory form do not have to be counted or skipped, and
columns holding values derived from the response are ignored. Sheets
with no such block are skipped, and the report says why.
`inputs/README.md` describes what a sheet needs to contain.

The report gives, for each sheet: the data as they were read; the
equations fitted and their model weights; the model-averaged N(S)EC,
EC10 and EC50 with credible intervals, in the units recorded on the
sheet; the model-averaged curve and the individual equations behind it;
and the diagnostics, being R-hat, Bayesian R-squared, an over-dispersion
test and the chain traces.

Fitting takes roughly twenty to forty minutes per sheet. Each fit is
saved as it completes and reused on a later run, so an interrupted run
is resumed by calling
[`run_workbook()`](https://open-aims.github.io/toxtools/reference/run_workbook.md)
again. A sheet that cannot be analysed does not stop the run: the reason
is reported and the remaining sheets are still fitted.

The functions can also be used one step at a time:

``` r

path <- toxtools::find_workbook()
toxtools::classify_sheets(path)
sheet <- toxtools::read_analysis_sheet(path, "Copper Ref (4)")
fit <- toxtools::fit_analysis_sheet(sheet)
toxtools::workbook_estimates(fit)
toxtools::plot_workbook_fit(fit)
```

`bayesnec`, `brms` and `readxl` are needed to fit, `ggplot2`, `quarto`,
`knitr`, `rmarkdown` and `ragg` to report, and `shiny`, `bslib`, `DT`
and `callr` for the app. All are declared in `Suggests`, so installing
`toxtools` does not install them, and all are checked before any fitting
starts rather than after it. The PDF report also needs a LaTeX
installation;
[`tinytex::install_tinytex()`](https://rdrr.io/pkg/tinytex/man/install_tinytex.html)
provides one, or choose the web page format instead.

## Further Information

`toxtools` is provided by the [Australian Institute of Marine
Science](https://www.aims.gov.au).

Copyright 2026 Australian Institute of Marine Science.

Released under the [GPL (\>= 3)
License](https://www.gnu.org/licenses/gpl-3.0.html).
