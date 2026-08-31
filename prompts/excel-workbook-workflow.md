## Session: excel-workbook-workflow
Date: 2026-08-31
Model: Claude Opus 5 (claude-opus-5)

### Prompts and Responses

**User:** I need to create a workflow for people to run bayesnec that have very
limited ability to use R. Using the excel workbook in the data-raw/sea_urchin
folder as an example, let's: add a new folder called "inputs" — gitignored from
the get go, where users place a workbook to be analysed; place the example
workbook in it (duplicated, so the original is reproducible); write the
functions/code required to read in the workbook, examine each sheet to
determine which are analysis sheets, read in the analysis data, run the
analysis, and output the results via a qmd to pdf, including the bayesnec
summary, n(s)ec, ec10 and ec50, chain plots, other diagnostic tests, the
individual plots and the final model averaged plot, with log or sqrt x-scaling
for visual appeal.

**Claude:** Three decisions were put to the user before any code was written,
because each changed the shape of the work. The answers taken forward were:

1. **Code location and dependencies.** Exported package functions in `R/`, with
   `bayesnec`, `brms`, `readxl`, `ggplot2` and `quarto` declared in `Suggests`
   and checked at run time by a guard that names everything missing in one
   message. Rejected: `Imports`, which would make anyone installing `toxtools`
   for its data build `brms`; and standalone scripts, which would leave the
   user calling `source()` rather than one function.
2. **Sheet reader.** Signature-based, matching a header row by column name
   anywhere on the sheet, with a fallback for a plain rectangular table.
   Rejected: strict matching to the Form 149 layout, which would silently yield
   nothing for a differently laid-out workbook; and fully generic column
   matching, which would misread a summary block as data.
3. **Output.** One PDF per workbook with a section per analysis sheet.

#### What was added

- `inputs/` and `outputs/`, both excluded by `.gitignore`, with the negation
  `!/inputs/README.md` so the folder and its instructions survive a fresh
  clone while any workbook placed there does not. `data-raw/sea_urchin/Test
  data.xlsx` was copied to `inputs/` rather than moved.
- `R/read_workbook.R`: `find_workbook()`, `classify_sheets()`,
  `read_analysis_sheet()`, `read_workbook()` and their internals.
- `R/fit_workbook.R`: `fit_analysis_sheet()`, `workbook_estimates()`,
  `workbook_diagnostics()`.
- `R/plot_workbook.R`: `plot_workbook_fit()`, `plot_sheet_data()`.
- `R/run_workbook.R`: `run_workbook()`, `render_workbook_report()`.
- `R/utils.R`: the dependency guard and the predictor transformation functions.
- `inst/quarto/workbook_report.qmd`: the report, generated one section per
  sheet with `knitr::knit_child()`.
- `analysis/run_workbook.R`: a file a user can open and run without writing
  code, carrying the settings and their explanations at the bottom.
- Tests in `tests/testthat/test-read_workbook.R` and `test-fit_workbook.R`,
  with a fixture workbook written by `tests/testthat/helper-workbook.R`.

#### Decisions and their reasoning

**Sheets are found by column name, not by cell range.** `data-raw/sea_urchin.R`
takes the sheet by absolute range (`cell_limits(c(9, 2), c(26, 8))`) because it
was written by hand against one form. A workflow cannot do that. Each sheet is
read as text anchored at cell A1 — `read_excel()` trims leading empty rows and
columns when given no range, which renumbers everything — and every row is
tested as a candidate header. A row qualifies when it names a concentration
column and a response column with numeric data beneath it. The first
qualifying row from the top wins, because a laboratory form repeats its column
names in any summary block below the data. Reading stops at the first row whose
concentration cell is not a number, which is what ends the data on Form 149:
the "Average Control" block below it has no concentration.

**Derived columns are recognised so that they can be discarded.** A laboratory
form carries `% Normal Development`, `% Control`, `Mean` and `S.D.` beside the
counts they are computed from. Fitting to those rather than to the counts would
be wrong. Testing revealed a latent defect in the first implementation: header
text was normalised by removing every non-alphanumeric character, which turned
`% Normal Development` into the same string as `No. Normal Development`, so
which of the two was read depended only on which appeared first on the sheet.
The per cent sign is now spelled out before the strip, so the derived column
matches the ignore pattern.

**The response is fitted as counts, on the natural scale, with an identity
link.** All three follow the worked example in `analysis/fit_sea_urchin.R`.
The link is stated explicitly for every family because `bnec()` sets
`link = "identity"` only when it infers the family itself; a family passed in
keeps its own default, and `binomial()` defaults to logit. Counts are not
converted to per cent of control, because `ecx()` measures decline against the
fitted control value one posterior draw at a time and so keeps the uncertainty
in the control, which dividing by the observed control mean beforehand
discards.

**Concentration is square-root transformed by default.** These designs include
a zero control, so a logarithm would either drop the controls or require an
arbitrary offset. `"log"` and `"identity"` are available; `"log"` stops with an
explanation when a zero is present rather than dropping rows.

**The axis is spaced by the transformation but labelled in recorded units.**
This was got wrong first and corrected after inspecting the output. `bayesnec`
returns plot data on the recorded concentration scale even when the curve was
fitted to a transformed predictor, whereas its `nec()` and `ecx()` return
estimates on the fitted scale. Placing breaks at `sqrt(concentration)`
therefore crammed every label into the left sixth of the axis. The spacing is
now applied by `scale_x_continuous(transform = ...)` on natural-scale data, and
the estimates are back-transformed with the `xform` argument. The argument
naming the transformation was renamed from `trans` to `transform` in ggplot2
3.5.0, so the name this installation expects is chosen at run time.

**`bayesnec`'s own annotation is suppressed and replaced.** `autoplot()` labels
the plot with the no-effect concentration on the fitted scale. Shown beside the
back-transformed table it reads as a disagreement, so `nec = FALSE` is passed
and the value is drawn again in recorded units. The printed `summary()` still
carries the fitted-scale value, and the report now states that this is why the
two numbers differ — except where the transformation is the identity, in which
case there is no difference to explain and the sentence is not printed.

**Dispersion is taken from the model weights table.** `summary()` has already
computed it. Calling `dispersion()` again means a `posterior_predict()` draw for
every equation in the set, which for a set of twelve is minutes of work for
numbers already to hand. `dispersion()` also takes a single-model
`bayesnecfit` rather than a `bayesmanecfit`: called on a model average it
stops with "argument is not a valid model", which was confirmed against a
fitted object in this session. `analysis/fit_sea_urchin.R:122` calls it that
way and so cannot run to completion. That file was left unchanged, being
uncommitted and outside the scope of this work.

**Fits are cached, and the cache is keyed on the question asked.** Each fit is
saved as it completes so an interrupted run resumes, but a saved fit is reused
only when the model set and the predictor transformation match; either changes
the fitted model, so a mismatch means the object is stale rather than a cache
hit.

**Figure height for the individual-equation panels is computed from the number
of equations.** The panels are laid out in two columns. At the fixed height
first used, a set of three was stretched and, with figures held in place rather
than floated, LaTeX pushed the figure to the next page and left a blank one
behind.

#### Verification

- `testthat::test_dir()`: 69 tests pass, none skipped, on R 4.6.1 under WSL.
  Two of the failures that this suite found on its first run were real defects
  and are described above.
- The generic reader was checked against the shipped dataset: reading
  `Copper Ref (4)` from the workbook by column name reproduces
  `data/sea_urchin.rda` exactly in all four columns, that dataset having been
  extracted independently by absolute cell range in `data-raw/sea_urchin.R`.
- End to end: `run_workbook()` was run on `inputs/Test data.xlsx` over two
  sheets with a reduced model set (`nec3param`, `ecxexp`, `ecx4param`), two
  chains and 800 iterations, through the `cmdstanr` backend. It classified all
  five sheets correctly, fitted and cached both, wrote the estimates as CSV,
  and rendered a 19 page PDF through Quarto 1.10.18 and LuaLaTeX. Every page
  was inspected. This run does not cover the full `decline` set, the `"log"`
  or `"identity"` transformations, a non-binomial response, or rendering to
  HTML.
- `devtools::check(args = "--no-manual")` under R 4.6.1: `Status: OK`,
  0 errors, 0 warnings, 0 notes.
- `air format` was run on `R/`, `tests/testthat/` and
  `analysis/run_workbook.R`; `roxygen2::roxygenise()` regenerated `NAMESPACE`
  and `man/`.

---

## Session: excel-workbook-workflow (continued)
Date: 2026-08-31
Model: Claude Opus 5 (claude-opus-5)

### Prompts and Responses

**User:** is it possible to put a shiny over the top end for them to use?

**Claude:** Answered that it is, gave the design and the one constraint that
shapes it, and put the scope choice to the user. The answer taken forward was a
local app launched from R, rather than a minimal version or one built to be
deployed on a server.

The constraint is that a fit takes twenty to forty minutes per sheet. A Shiny
session that blocked for that long would appear to have frozen and would be
disconnected by any proxy in front of it, so the fitting has to run outside the
app. It was also recorded that Shiny removes the need to type R but not the
need to install R, `brms`, CmdStan and a C++ toolchain, which is the larger
barrier for the intended users; a server deployment moves that install to one
machine but brings long-running jobs, concurrency and CmdStan-on-the-server in
its place.

#### What was added

- `R/run_app.R`: the exported `run_app()`, and the internal `fit_job()` that
  the background process runs.
- `inst/shiny/app.R`: the app. Four tabs — Sheets, Progress, Results, Help —
  with the workbook, sheets and settings chosen in the sidebar.
- `tests/testthat/test-run_app.R`: a `shiny::testServer()` test of the server
  logic, using the same fixture workbook as the reader tests.
- `shiny`, `bslib`, `DT` and `callr` added to `Suggests`.

#### Decisions and their reasoning

**The app does no fitting.** `run_workbook()` is run by `callr::r_bg()` in a
separate R session, with `stderr = "2>&1"` so that the progress it already
writes with `message()` is captured, and `supervise = TRUE` so an orphaned
CmdStan job cannot be left holding several cores. The app polls that process
once a second. Everything that reads a file the other process is writing — the
log, the count of completed fits, the manifest — depends on a single counter
bumped by one timer, rather than each polling on its own.

**The job function has its environment replaced before it is sent.** `callr`
serialises the function together with its environment. Left as the `toxtools`
namespace, the child would try to load an installed `toxtools`, which during
development does not exist; the environment is set to the global environment
and the package is loaded in the child from the source directory instead. This
was verified by running the job through `callr` from a `pkgload`-loaded
session.

**Every path passed to the app is absolute.** This was found by the first
`testServer()` run, which failed at `req(file.exists(path))`.
`shiny::runApp()` changes the working directory to the app's own folder inside
the installed package, so a relative `"inputs"` is looked for there and not
where the user launched from. `run_app()` now normalises both folders and
passes the launching directory through as well, which is what the fitting
process runs in.

**Reactive values are written from an observer, not from a reactive.** The
first version polled inside a `reactive()` that also wrote to
`reactiveVal`s, which is a route to an invalidation loop. The poll is now an
`observe()` that reads with `isolate()` and writes the state, and the outputs
depend on what it writes.

**Uploads are copied into the input folder.** Shiny puts an upload in a
temporary file that is discarded when the session ends. Copying it into
`inputs/` under its own name means the workbook is still there for a later run,
and that the folder the app lists is the folder `run_workbook()` reads from.
The app lists every workbook in that folder and offers a choice, rather than
using `find_workbook()`, whose one-workbook rule suits a console call but would
make the app refuse to start whenever two were present.

**`plot_workbook_fit()` and the estimates are reused unchanged.** The Results
tab reads the saved fit and calls the same functions the report does, so the
figures on screen and the figures in the PDF cannot diverge.

#### Verification

- 75 tests pass, none skipped, on R 4.6.1 under WSL.
- The background job was run end to end through `callr::r_bg()` from a
  `pkgload`-loaded session, fitting `Copper Ref (2)` with a reduced model set
  and rendering to HTML: exit status 0, with the fit, the estimates CSV, the
  manifest and the report all written. This also covered the `format = "html"`
  path, which the earlier session had not exercised.
- `shiny::testServer()` was used to check the workbook listing, the sheet
  classification, the idle state, and that pressing Run with no sheets ticked
  starts no process. A second `testServer()` run against the completed fit
  above confirmed the Results tab wiring: manifest, estimates table, fitted
  object, both plots and the download file name.
- The app was started with `run_app(launch_browser = FALSE, port = 8123)` and
  the page fetched over HTTP: 200, 17,786 bytes, carrying the expected
  controls.
- Not covered: driving the browser interface itself (no `shinytest2` in this
  environment), the Stop button, and a full-length run through the app.

---

## Session: excel-workbook-workflow (continued)
Date: 2026-08-31
Model: Claude Opus 5 (claude-opus-5)

### Prompts and Responses

**User:** run the app on the real workbook

**Claude:** The app was run on `inputs/Test data.xlsx` through its own server
logic, using `shiny::testServer()` to set the inputs and press Run: the same
button handler, the same `callr` job and the same progress and results
reactives a browser exercises, with only the clicking simulated.

All four `Copper Ref` sheets were fitted with the full `decline` set, four
chains, four cores, `cmdstanr`, and rendered to PDF. `Sheet1` was skipped as
empty. Eleven of the fourteen decline equations were retained; `neclin`,
`ecxlin` and `ecxll5` were dropped by `bnec()` as invalid for a binomial
response with an identity link. Total elapsed time 39.4 minutes including the
render, roughly six minutes per sheet, on a 22 core machine; the twenty to
forty minutes per sheet quoted in the documentation was written for four cores.
The report is 71 pages.

Model-averaged estimates, micrograms per litre of copper, median and 95 per
cent credible interval:

| Sheet | N(S)EC | EC10 | EC50 |
|---|---|---|---|
| Copper Ref (4) | 2.84 (1.07-5.31) | 6.45 (5.13-8.25) | 15.4 (14.4-16.2) |
| Copper Ref (3) | 3.89 (1.78-5.48) | 8.29 (7.01-9.49) | 16.8 (16.1-17.6) |
| Copper Ref (2) | 2.94 (1.00-5.27) | 7.49 (6.09-9.13) | 17.7 (16.9-18.5) |
| Copper Ref | 6.43 (3.49-9.90) | 13.1 (11.6-15.1) | 22.8 (21.7-23.9) |

The convergence check flagged one equation on each of three sheets:
`nec4param` on Copper Ref (3) and Copper Ref (2), and `ecxll3` on Copper Ref.
All three carry negligible weight; see the entry below, where the same weight
qualification was applied to this check as to the dispersion test.

Two changes were made before the run, because the run is what made them
matter. `run_workbook()` now records the report format in the manifest, and the
app adopts a finished run when its workbook is selected: everything needed is
on disk, and without it the Results tab stayed empty until something was fitted
again, which for an analysis measured in hours is the wrong default. Both were
confirmed by opening the app fresh afterwards and reading the completed run
without refitting.

One defect was found, in the script driving the run rather than in the app. It
called `report_file()`, a helper defined at `app.R`'s top level, which is not
in scope inside `testServer()`'s evaluation environment. The analysis had
already completed with exit status 0 when it failed. The app's own code calls
that helper from inside the server function, where it resolves.

---

**User:** poor fitting models can fail the dispersion test, so we would only
warn if a model with essentially non-zero weight had overdispersion

**Claude:** Correct, and the run above demonstrates it. The dispersion test is
applied to each equation separately, and an equation that fits the data badly
fails it whatever the data are doing, because the residual variation its curve
cannot account for is counted as dispersion. That equation also receives almost
none of the stacking weight, for the same reason, so it has no bearing on the
estimates reported. The report as first written warned on the raw test and so
raised an alarm about the wrong thing.

#### The evidence

Weight against dispersion for every equation on all four sheets. Not one
equation carrying a weight of 0.01 or more fails the test:

| Sheet | Dominant equation (weight) | Its dispersion | Equations failing the test | Their combined weight |
|---|---|---|---|---|
| Copper Ref (4) | `ecxwb1` (0.81) | 1.05 (0.51-2.58) | nec3param, ecxsigm, nec4param, ecxexp, ecxwb1p3 | 0.008 |
| Copper Ref (3) | `ecxll3` (0.49) | 0.97 (0.46-2.45) | ecxwb1p3, nec3param, nec4param, ecxexp | 0.0001 |
| Copper Ref (2) | `ecxwb1p3` (0.79) | 0.80 (0.37-2.08) | nec3param, nec4param, ecxexp | under 0.0001 |
| Copper Ref | `ecxwb1p3` (0.79) | 0.61 (0.25-1.90) | ecxexp | under 0.0001 |

Three features of those numbers carry the argument.

Within each sheet the ordering is close to monotone: the higher the weight, the
nearer the dispersion is to 1. `ecxexp` sits between 30 and 41 on every sheet,
and its Bayesian R-squared is 0.54 where the others are above 0.96.

The same equation both passes and fails. `ecxwb1p3` is the dominant equation on
Copper Ref (2) and Copper Ref, with dispersion 0.80 and 0.61, and passes. On
Copper Ref (3) its weight is 0.0001 and its dispersion 2.74, and it fails.
Nothing about the data changed between those sheets in a way that would explain
it; how well that curve suited them did.

The threshold is not doing hidden work. The largest weight held by any failing
equation across the four sheets is `nec3param` at 0.0053, so any threshold
between roughly 0.006 and 0.05 gives the same answer on this run.

#### What was changed

`workbook_diagnostics()` gained a `weight_threshold` argument, default 0.01,
and the dispersion table now separates two things that were conflated:
`overdispersed`, the test itself, and `warn`, which additionally requires the
equation to carry at least that weight. The table is ordered by weight and
records it, so the reader can see the basis for the judgement rather than being
asked to take it.

The rule was extracted into `dispersion_table()`, an internal function taking
the model weights matrix, so that it can be tested without fitting a model. Six
tests cover it: a badly fitting equation with large dispersion and no weight
raises no warning; a weighted equation does; raising the threshold above a
contributing equation's weight silences it; ordering is by weight; a fit with
no dispersion columns returns nothing. Where the weights are unavailable the
raw test is kept, so a finding is over-reported rather than silently dropped.

The report now states one of three things above the table: over-dispersion is
present in named weighted equations and a beta-binomial refit is warranted; or
no weighted equation is over-dispersed, naming those that fail the test and the
share of weight they carry, with the reason a badly fitting curve fails it; or
nothing is over-dispersed. The "How to read this report" section states the
qualification rather than leaving it to be inferred.

#### The same argument applied to the convergence check

Reading the diagnostics for all four sheets, rather than the one sheet reported
first, showed the convergence check has the same defect. It flagged
`nec4param` on Copper Ref (3) and Copper Ref (2), and `ecxll3` on Copper Ref.
Their weights are 0.00000, 0.00000 and 0.00165. An equation the sampler
struggles with is usually one whose shape suits the data badly, which is also
why stacking gives it nothing, so an unqualified convergence warning names the
wrong thing for the same reason the dispersion warning did.

`workbook_diagnostics()` therefore also returns `rhat_flags`, built by
`rhat_flag_table()`, carrying the flag, the weight and the same `warn` column.
The report states either that the sampler did not converge for named equations
carrying weight, and that the estimates should not be relied on, or that it did
not converge for named equations carrying a stated and negligible share of the
weight, and that the estimates are unaffected.

The flag is qualified rather than suppressed. A non-converged fit's weight is
itself computed from a suspect posterior, so the equation is named either way
and only the interpretation changes. This extends what was asked for to an
adjacent check; it was recorded to the user as such, with the one-line reversal
noted.

#### Verification

- 91 tests pass, none skipped.
- `dispersion_table()` and `rhat_flag_table()` were run over the four saved
  fits from the run above. For dispersion, `warn` is FALSE throughout while
  `overdispersed` retains the raw result. For convergence, the three flagged
  equations are reported with weights 0.00000, 0.00000 and 0.00165, and `warn`
  is FALSE for each.
- The report was re-rendered from the saved fits to confirm the new wording of
  both sections. The first render showed the sentence naming a single equation
  read "nec4param, which between them carry"; the phrase is now built by a
  helper that reads correctly for one equation as well as for several, and both
  sentences format the weight the same way. Confirmed on all four sheets,
  including the singular case on Copper Ref.

---
