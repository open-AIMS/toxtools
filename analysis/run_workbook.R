## Analyse an Excel workbook of concentration-response data.
##
## HOW TO USE THIS FILE
##
##   1. Put your Excel workbook in the `inputs` folder. Only one workbook
##      should be in that folder at a time.
##   2. Open this file and run all of it. In RStudio or Positron that is the
##      "Source" button, or Ctrl+Shift+S. From a terminal it is
##      `Rscript analysis/run_workbook.R`.
##   3. Wait. Fitting takes roughly twenty to forty minutes for each sheet of
##      data, and the workbook may hold several. Progress is printed as it
##      goes.
##   4. Open the PDF that is written into the `outputs` folder.
##
## There is also a point-and-click version of all of this. Run
## `toxtools::run_app()` to open it in a browser; it does the same work and
## needs nothing typed.
##
## Nothing below needs to be edited to run the analysis as it stands. The
## settings that can be changed are gathered together and explained at the
## bottom of the file.
##
## If the run is interrupted, run the file again: each sheet that finished is
## saved as it completes and is not fitted a second time.

## ---- Packages ---------------------------------------------------------------

## These are not installed with toxtools, because they are only needed to run
## an analysis and not to use the package. This stops with one instruction
## naming everything missing, rather than failing part way through a fit.
needed <- c(
  "bayesnec",
  "brms",
  "ggplot2",
  "knitr",
  "quarto",
  "ragg",
  "readxl",
  "rmarkdown"
)
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop(
    "Install these packages first, then run this file again:\n",
    "  install.packages(c(",
    paste0("\"", missing, "\"", collapse = ", "),
    "))",
    call. = FALSE
  )
}

## The report is written as a PDF, which needs a LaTeX installation. TinyTeX is
## the smallest one that works and installs without administrator rights. If
## there is no LaTeX and none can be installed, change `format` at the bottom
## of this file to "html" instead.
if (
  !nzchar(Sys.which("pdflatex")) &&
    !(requireNamespace("tinytex", quietly = TRUE) && tinytex::is_tinytex())
) {
  message(
    "No LaTeX installation was found, so the PDF report cannot be made.\n",
    "Either install one with:\n",
    "  install.packages(\"tinytex\"); tinytex::install_tinytex()\n",
    "or change format = \"pdf\" to format = \"html\" at the bottom of this file."
  )
}

## ---- The package ------------------------------------------------------------

## Loads toxtools when it is installed, and from this repository when it is
## not, so the file works either way without being edited.
if (requireNamespace("toxtools", quietly = TRUE)) {
  library(toxtools)
} else if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  stop(
    "toxtools is not installed. Install it with:\n",
    "  install.packages(\"pak\"); pak::pak(\"open-AIMS/toxtools\")",
    call. = FALSE
  )
}

## ---- Run --------------------------------------------------------------------

## Settings that can be changed:
##
##   model                 which set of curves to fit. "decline" fits the
##                         equations that only decrease as concentration rises,
##                         which suits a toxicity test. Use "all" to include
##                         the hormesis equations, which allow the response to
##                         rise at low concentrations before it falls.
##   predictor_transform   "sqrt" or "log" or "identity". "sqrt" is the default
##                         because these designs include a zero control and the
##                         logarithm of zero does not exist.
##   ecx_vals              which effect concentrations to report, as
##                         percentages.
##   format                "pdf" or "html".
##   backend               "cmdstanr" compiles the models through CmdStan,
##                         which is faster than the default. Change it to
##                         "rstan" if CmdStan is not installed.
##   chains, cores         number of sampling chains, and how many to run at
##                         once. Do not set cores above the number of cores the
##                         computer has.
##   refit                 TRUE forces every sheet to be fitted again, ignoring
##                         any saved fit.

run_workbook(
  model = "decline",
  predictor_transform = "sqrt",
  ecx_vals = c(10, 50),
  format = "pdf",
  backend = "cmdstanr",
  chains = 4,
  cores = 4,
  seed = 101,
  refit = FALSE
)
