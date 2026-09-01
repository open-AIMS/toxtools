## Folder and file names are built from sheet and workbook names, which are
## whatever the laboratory typed. Spaces, brackets and slashes are all legal in
## an Excel sheet name and none of them is safe in a file path, a LaTeX label
## or a shell argument, so they are replaced here.
safe_name <- function(x) {
  x <- gsub("[^A-Za-z0-9._-]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  ifelse(nzchar(x), x, "sheet")
}

## Whether a saved fit answers the question being asked now.
##
## Model set and predictor transformation both change the fitted model, so a
## saved object that used different ones is stale rather than a cache hit. The
## sheet name is checked as well, because the file name is safe_name(sheet) and
## that is not one-to-one: "Test (1)" and "Test 1" both give Test_1. Without
## the check the second sheet would silently be reported using the first
## sheet's fit.
cached_fit_usable <- function(obj, model, predictor_transform, sheet) {
  inherits(obj, "analysis_fit") &&
    identical(obj$model_set, model) &&
    identical(obj$transform, predictor_transform) &&
    identical(obj$sheet$sheet, sheet)
}

## Read, fit and summarise one sheet, reusing a saved fit where there is a
## usable one. Extracted from run_workbook()'s loop so that the loop can catch
## a failure on one sheet without the recovery logic obscuring the work.
analyse_one_sheet <- function(
  path,
  sheet_name,
  fit_dir,
  run_dir,
  model,
  predictor_transform,
  ecx_vals,
  refit,
  ...
) {
  sheet <- read_analysis_sheet(path, sheet_name)
  for (n in sheet$notes) {
    message("  note: ", n)
  }

  fit_file <- file.path(fit_dir, paste0(safe_name(sheet_name), ".rds"))
  obj <- NULL
  if (file.exists(fit_file) && !refit) {
    obj <- tryCatch(readRDS(fit_file), error = function(e) NULL)
    if (cached_fit_usable(obj, model, predictor_transform, sheet_name)) {
      message("  using the saved fit in ", fit_file)
    } else {
      obj <- NULL
    }
  }
  if (is.null(obj)) {
    message(
      "  fitting the ",
      paste(model, collapse = ", "),
      " model set; this takes some time"
    )
    obj <- fit_analysis_sheet(
      sheet,
      model = model,
      predictor_transform = predictor_transform,
      ...
    )
    saveRDS(obj, fit_file)
    message("  fit saved to ", fit_file)
  }

  est <- workbook_estimates(obj, ecx_vals = ecx_vals)
  utils::write.csv(
    est,
    file.path(run_dir, paste0(safe_name(sheet_name), "_estimates.csv")),
    row.names = FALSE
  )
  print(est)

  list(
    sheet = sheet_name,
    fit_file = normalizePath(fit_file, winslash = "/"),
    estimates = est
  )
}

#' Analyse every sheet in a workbook and write a report
#'
#' The single call that runs the whole workflow. It finds the workbook, decides
#' which of its sheets hold concentration-response data, fits the `bayesnec`
#' model set to each of them, and renders one PDF holding the results for every
#' sheet.
#'
#' Fitting is the slow step, taking roughly twenty to forty minutes per sheet
#' on four cores. Each fit is saved as it completes, and a fit that is already
#' saved is reused rather than repeated, so an interrupted run can be restarted
#' by calling the function again. A saved fit is reused only when it was fitted
#' with the same model set, the same predictor transformation and the same
#' sheet; changing any of them causes it to be refitted.
#'
#' A sheet that cannot be analysed does not stop the run. The reason is
#' reported, recorded in `sheet_classification.csv` and carried in the
#' manifest, and the remaining sheets are still fitted and reported; a run
#' stops only when no sheet at all could be analysed. A run covering several
#' sheets takes hours, and discarding the ones that worked because a later one
#' failed would waste them.
#'
#' @param path Path to the workbook. The default takes the single workbook in
#'   `inputs/`.
#' @param output_dir Folder to write results into. A sub-folder named after the
#'   workbook is created inside it.
#' @param sheets Optional character vector naming the sheets to analyse. The
#'   default analyses every sheet identified as holding fittable data.
#' @param model,predictor_transform,ecx_vals Passed to [fit_analysis_sheet()]
#'   and [workbook_estimates()].
#' @param refit If `TRUE`, refit sheets that already have a saved fit.
#' @param render If `FALSE`, fit and save but do not render the report.
#' @param format Report format, passed to Quarto. `"pdf"` by default;
#'   `"html"` needs no LaTeX installation.
#' @param ... Further arguments passed to [fit_analysis_sheet()], and from
#'   there to [bayesnec::bnec()] and [brms::brm()]; for example
#'   `backend = "cmdstanr"`, `iter` or `cores`.
#'
#' @return Invisibly, the path to the manifest file describing the run.
#' @export
#' @examples
#' \dontrun{
#' run_workbook()
#' }
run_workbook <- function(
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
) {
  check_pkgs("readxl", "bayesnec", "brms", "ggplot2")
  if (render) {
    ## Every package the render needs is checked here, before the fitting,
    ## rather than being discovered by Quarto afterwards. Fitting is the part
    ## that takes hours; finding out at the end of it that knitr is missing
    ## wastes all of it.
    check_pkgs("quarto", "knitr", "rmarkdown", "ragg")
    if (identical(format, "pdf")) {
      warn_no_latex()
    }
  }
  if (!file.exists(path)) {
    stop("workbook not found: ", path, call. = FALSE)
  }

  run_dir <- file.path(
    output_dir,
    safe_name(tools::file_path_sans_ext(basename(path)))
  )
  fit_dir <- file.path(run_dir, "fits")
  dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)

  message("Workbook: ", basename(path))
  cls <- classify_sheets(path)
  utils::write.csv(
    cls,
    file.path(run_dir, "sheet_classification.csv"),
    row.names = FALSE
  )
  for (i in seq_len(nrow(cls))) {
    if (cls$analyse[i]) {
      message(sprintf(
        "  [analyse] %-20s %s rows, %s concentrations, %s",
        cls$sheet[i],
        cls$n_rows[i],
        cls$n_levels[i],
        cls$response[i]
      ))
    } else {
      message(sprintf("  [skip]    %-20s %s", cls$sheet[i], cls$reason[i]))
    }
  }

  if (is.null(sheets)) {
    sheets <- cls$sheet[cls$analyse]
  }
  if (length(sheets) == 0) {
    stop(
      "no sheet in this workbook holds fittable data; nothing to analyse. ",
      "The reasons for each sheet are in ",
      file.path(run_dir, "sheet_classification.csv"),
      call. = FALSE
    )
  }

  ## Each sheet is attempted on its own. A run covers several sheets and takes
  ## hours; letting one sheet's failure abort the loop would discard the fits
  ## that had not yet been reached and produce no report at all, when the
  ## sheets that did work are still worth having. What failed is recorded and
  ## reported rather than passed over.
  entries <- list()
  failures <- list()
  for (i in seq_along(sheets)) {
    s <- sheets[i]
    message(sprintf("\n[%d/%d] %s", i, length(sheets), s))
    entry <- tryCatch(
      analyse_one_sheet(
        path = path,
        sheet_name = s,
        fit_dir = fit_dir,
        run_dir = run_dir,
        model = model,
        predictor_transform = predictor_transform,
        ecx_vals = ecx_vals,
        refit = refit,
        ...
      ),
      error = function(e) {
        message("  this sheet was not analysed: ", conditionMessage(e))
        structure(conditionMessage(e), class = "sheet_failure")
      }
    )
    if (inherits(entry, "sheet_failure")) {
      failures[[s]] <- as.character(entry)
    } else {
      entries[[length(entries) + 1]] <- entry
    }
  }

  ## Which sheets were actually analysed is not the same question as which
  ## could be: the caller can name a subset, and a sheet can fail. The report
  ## needs all three, so that a sheet that was fittable but was not asked for
  ## is not reported as unfittable.
  ##
  ## This is recorded and written out before the run is allowed to fail.
  ## Stopping first would leave the file the error message sends the user to
  ## holding no reason at all.
  cls$analysed <- cls$sheet %in%
    vapply(entries, function(e) e$sheet, character(1))
  cls$reason[cls$analyse & !cls$analysed] <- "not requested in this run"
  for (s in names(failures)) {
    cls$reason[cls$sheet == s] <- failures[[s]]
  }
  utils::write.csv(
    cls,
    file.path(run_dir, "sheet_classification.csv"),
    row.names = FALSE
  )

  if (length(entries) == 0) {
    stop(
      "no sheet could be analysed. The reason for each is above, and in ",
      file.path(run_dir, "sheet_classification.csv"),
      call. = FALSE
    )
  }
  if (length(failures) > 0) {
    message(
      "\n",
      length(failures),
      " of ",
      length(sheets),
      " sheets were not analysed: ",
      paste(names(failures), collapse = ", ")
    )
  }

  manifest <- list(
    workbook = basename(path),
    path = normalizePath(path, winslash = "/"),
    run_dir = normalizePath(run_dir, winslash = "/"),
    classification = cls,
    entries = entries,
    failures = failures,
    model_set = model,
    predictor_transform = predictor_transform,
    ecx_vals = ecx_vals,
    ## Recorded so that a later session can find the report this run wrote
    ## without being told which format was asked for.
    format = if (render) format else NA_character_,
    created = Sys.time(),
    bayesnec_version = as.character(utils::packageVersion("bayesnec"))
  )
  manifest_file <- file.path(run_dir, "manifest.rds")
  saveRDS(manifest, manifest_file)

  if (render) {
    report <- render_workbook_report(manifest_file, format = format)
    message("\nReport written to ", report)
  }

  invisible(normalizePath(manifest_file, winslash = "/"))
}

#' Render the report for a completed run
#'
#' Renders the Quarto report from the fits saved by [run_workbook()]. Use this
#' to produce the report again, in a different format or after editing the
#' template, without refitting anything.
#'
#' @param manifest Path to the `manifest.rds` written by [run_workbook()].
#' @param format Quarto output format, `"pdf"` or `"html"`.
#' @param template Path to the Quarto template. The default uses the one
#'   installed with the package.
#'
#' @return Invisibly, the path to the rendered report.
#' @export
#' @examples
#' \dontrun{
#' render_workbook_report("outputs/Test_data/manifest.rds")
#' }
render_workbook_report <- function(manifest, format = "pdf", template = NULL) {
  check_pkgs("quarto")
  manifest <- normalizePath(manifest, winslash = "/", mustWork = TRUE)
  m <- readRDS(manifest)
  if (is.null(template)) {
    template <- system.file(
      "quarto",
      "workbook_report.qmd",
      package = "toxtools"
    )
  }
  if (!nzchar(template) || !file.exists(template)) {
    stop(
      "the report template could not be found. Reinstall toxtools, or pass ",
      "the path to workbook_report.qmd as `template`.",
      call. = FALSE
    )
  }

  ## The template is copied beside the results and rendered there, so that
  ## Quarto's intermediate files and the report itself land in the output
  ## folder rather than in the installed package or the working directory.
  dest <- file.path(m$run_dir, "workbook_report.qmd")
  file.copy(template, dest, overwrite = TRUE)

  ## When toxtools is being developed rather than installed, the rendering
  ## session cannot load it by name. The source directory is passed through so
  ## the report can load it with pkgload instead.
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

  quarto::quarto_render(
    input = dest,
    output_format = format,
    execute_params = list(
      manifest = manifest,
      dev_package_dir = dev_dir
    ),
    quiet = FALSE
  )

  out <- file.path(
    m$run_dir,
    paste0("workbook_report.", if (format == "html") "html" else format)
  )
  invisible(out)
}
