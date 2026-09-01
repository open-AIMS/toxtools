# Classify the sheets of a workbook

Examines every sheet in a workbook and decides which hold
concentration-response data that can be fitted, and which do not.

## Usage

``` r
classify_sheets(path)
```

## Arguments

- path:

  Path to the workbook.

## Value

A data frame with one row per sheet and the columns `sheet`, `analyse`
(whether the sheet holds fittable data), `reason` (why not, when
`analyse` is `FALSE`), `header_row` (the sheet row holding the column
names), `n_rows`, `n_levels` (distinct concentrations) and `response`
(the response layout found).

## Details

A sheet is treated as an analysis sheet when a row can be found that
names a concentration column and at least one response column, with
numeric data beneath it. The search is by column name rather than by
position, so the title block, blank rows and blank columns of a
laboratory form do not have to be counted or skipped. Columns holding
values derived from the response, such as per cent of control, replicate
means and standard deviations, are recognised and discarded: the fit
uses the recorded counts, not figures computed from them.

Two response layouts are recognised. A pair of count columns, such as
"No. Normal Development" and "No. Abnormal Development", gives a
binomial response whose number of trials is the row total. A single
response column, with an optional column of trial totals, gives either a
binomial response (when totals are supplied) or a continuous one.

## Examples

``` r
if (FALSE) { # \dontrun{
classify_sheets(find_workbook())
} # }
```
