# Input workbooks

Put the Excel workbook to be analysed in this folder, then run

```r
toxtools::run_app()
```

which opens a page in the browser where the workbook, the sheets and the
settings are chosen by pointing and clicking. The page can also add a workbook
to this folder for you, so copying one here by hand is optional.

To run it from the console instead:

```r
toxtools::run_workbook()
```

or open `analysis/run_workbook.R` and run the whole file. Those two read the
single workbook in this folder, so leave only one here when using them; the
app lists them all and lets you choose.

Everything in this folder except this file is ignored by git, so a workbook
placed here is never committed to the repository or shared. Results are
written to `outputs/`, which is also ignored.

`Test data.xlsx` is a copy of the worked example described in
`data-raw/sea_urchin.R`. It is safe to delete once you have your own workbook
to analyse.

## What the workbook needs to contain

Each sheet holding data to be analysed needs a row of column names giving:

- a concentration column, named so that it contains one of `concentration`,
  `dose`, `reference`, `treatment`, `nominal` or `measured`, or ending in a
  concentration unit such as `(ug/L)`;
- either a pair of count columns, one naming the animals that responded
  normally (`normal`, `survived`, `alive`, `hatched`, `settled`) and one
  naming those that did not (`abnormal`, `dead`, `deformed`, `affected`), or
  a single response column.

The row of column names does not have to be the first row of the sheet, and
the block of data does not have to start in column A: a title block, blank
rows and blank columns above and to the left are all found and skipped.
Reading stops at the first row with no concentration in it, so any summary
block placed below the data is left out.

Columns holding values worked out from the response, such as `% Normal
Development`, `% Control`, `Mean` and `S.D.`, are recognised and ignored. The
fit uses the recorded counts.

Sheets that have no such block, including empty sheets, are skipped, and the
report lists each one with the reason.
