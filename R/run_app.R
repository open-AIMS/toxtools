#' Run the analysis through a point-and-click interface
#'
#' Opens a small web page in the browser that drives the same workflow as
#' [run_workbook()]: choose a workbook, see which of its sheets hold data that
#' can be fitted, choose the settings, start the analysis, watch it run, and
#' download the report. Nothing has to be typed.
#'
#' The page runs on the machine it is started from. The workbook is not sent
#' anywhere, and the results are written to the same `outputs/` folder that
#' [run_workbook()] writes to.
#'
#' Fitting is done in a separate R process, so the page stays responsive for
#' the twenty to forty minutes each sheet takes, and closing the browser tab by
#' accident does not stop the analysis. The process is stopped when the app
#' itself is stopped.
#'
#' @param input_dir Folder holding the workbooks to choose between. Workbooks
#'   added through the page are copied into it.
#' @param output_dir Folder to write results into.
#' @param launch_browser Whether to open a browser window.
#' @param ... Further arguments passed to [shiny::runApp()].
#'
#' @return Called for its side effect. Returns nothing.
#' @export
#' @examples
#' \dontrun{
#' run_app()
#' }
run_app <- function(
  input_dir = "inputs",
  output_dir = "outputs",
  launch_browser = TRUE,
  ...
) {
  ## Everything the app and the process it starts will need, named in one
  ## message at the point the user asks for the app, rather than found one at
  ## a time in a background log after a fit has run.
  check_pkgs(
    "shiny",
    "bslib",
    "DT",
    "callr",
    "readxl",
    "bayesnec",
    "brms",
    "ggplot2",
    "quarto",
    "knitr",
    "rmarkdown",
    "ragg"
  )

  ## Both folders are made absolute before the app starts. shiny::runApp()
  ## changes the working directory to the app's own folder inside the
  ## installed package, so a relative "inputs" would be looked for there. The
  ## directory the user launched from is passed through as well, because it is
  ## where the fitting process should run.
  for (d in c(input_dir, output_dir)) {
    if (!dir.exists(d)) {
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
  }

  ## The fitting process is a fresh R session, which can load toxtools by name
  ## only when it is installed. During development the source directory is
  ## passed through instead, so the app works from a clone without an install
  ## step first.
  dev_dir <- NULL
  if (
    requireNamespace("pkgload", quietly = TRUE) &&
      isTRUE(pkgload::is_dev_package("toxtools"))
  ) {
    dev_dir <- normalizePath(
      pkgload::pkg_path(system.file(package = "toxtools")),
      winslash = "/"
    )
  }

  app_dir <- system.file("shiny", package = "toxtools")
  if (!nzchar(app_dir) || !file.exists(file.path(app_dir, "app.R"))) {
    stop(
      "the app could not be found. Reinstall toxtools.",
      call. = FALSE
    )
  }

  ## shinyOptions() is how configuration reaches app.R, which shiny sources in
  ## its own environment and so cannot see this function's arguments.
  shiny::shinyOptions(
    toxtools_config = list(
      input_dir = normalizePath(input_dir, winslash = "/"),
      output_dir = normalizePath(output_dir, winslash = "/"),
      wd = normalizePath(getwd(), winslash = "/"),
      dev_dir = dev_dir
    )
  )

  shiny::runApp(app_dir, launch.browser = launch_browser, ...)
}

## The call the background process runs. Kept here rather than written inline
## in the app so that it is formatted, checked and testable with the rest of
## the package.
##
## Everything the child needs is passed as an argument: it is a new R session
## and shares nothing with the app.
fit_job <- function(args) {
  if (!is.null(args$dev_dir)) {
    pkgload::load_all(args$dev_dir, quiet = TRUE)
  } else {
    library(toxtools)
  }
  do.call(toxtools::run_workbook, args$call_args)
}
