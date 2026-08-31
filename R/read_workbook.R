#' Locate the workbook to be analysed
#'
#' Finds the single Excel workbook held in a folder, by default `inputs/`.
#' This is the entry point for users who place one workbook in that folder and
#' do not want to type a file path.
#'
#' Temporary lock files that Excel creates while a workbook is open (names
#' beginning `~$`) are ignored, as are files beginning with a dot.
#'
#' @param dir Folder to search. Defaults to `"inputs"`, relative to the working
#'   directory.
#'
#' @return A single file path.
#' @export
#' @examples
#' \dontrun{
#' find_workbook()
#' }
find_workbook <- function(dir = "inputs") {
  if (!dir.exists(dir)) {
    stop(
      "the folder '",
      dir,
      "' does not exist. Create it and place the ",
      "workbook to be analysed inside it.",
      call. = FALSE
    )
  }
  files <- list.files(dir, pattern = "\\.xlsx?$", full.names = TRUE)
  files <- files[!grepl("^(~\\$|\\.)", basename(files))]
  if (length(files) == 0) {
    stop(
      "no Excel workbook found in '",
      dir,
      "'. Place one .xlsx file there.",
      call. = FALSE
    )
  }
  if (length(files) > 1) {
    stop(
      "more than one Excel workbook found in '",
      dir,
      "': ",
      paste(basename(files), collapse = ", "),
      ". Leave only the one to be analysed, or name it explicitly.",
      call. = FALSE
    )
  }
  files
}

## Column roles recognised in a header row. Order matters: the first pattern
## that matches a header decides its role, so "No. Abnormal Development" must
## be tested against the abnormal pattern before the normal one.
##
## Patterns are matched against the header text lowercased with all
## non-alphanumeric characters removed, so "S.D.", "% Control" and "No. Normal
## Development" become "sd", "control" and "nonormaldevelopment".
role_patterns <- function() {
  list(
    ## Derived and summary columns are recognised only so that they can be
    ## discarded. A laboratory form carries percentages, replicate means and
    ## standard deviations alongside the counts they are computed from; fitting
    ## to those instead of to the counts would be wrong, and "% Normal
    ## Development" would otherwise match the normal-count pattern below.
    ignore = paste(
      "^percent",
      "^pct",
      "^mean",
      "^sd$",
      "^stdev",
      "^se$",
      "^stderr",
      "^control$",
      "^averagecontrol",
      "^cv$",
      sep = "|"
    ),
    x = paste(
      "conc",
      "dose",
      "reference",
      "treatment",
      "nominal",
      "measured",
      "ugl$",
      "mgl$",
      "ugl1",
      "mgl1",
      sep = "|"
    ),
    replicate = "^rep|replicate|vessel|^tank|^beaker|^dish",
    trials = "^total|scored|^trials|^ntotal|^nscored",
    failures = "abnormal|dead|mortal|deformed|affected",
    successes = "normal|surviv|alive|^live|hatched|settled|^success"
  )
}

## Normalise a header for pattern matching: lowercase, with everything that is
## not a letter or digit removed.
##
## The per cent sign is spelled out first rather than dropped. Removing it
## turns "% Normal Development" into the same text as "No. Normal Development",
## so the derived percentage column would be matched as a count column. Which
## of the two was then used depended only on which came first on the sheet.
normalise_header <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("%", "percent", x, fixed = TRUE)
  gsub("[^a-z0-9]", "", x)
}

## Assign a role to each cell of a candidate header row. Returns a character
## vector the same length as the row, with NA where no role applies.
header_roles <- function(cells) {
  key <- normalise_header(cells)
  pat <- role_patterns()
  out <- rep(NA_character_, length(key))
  for (i in seq_along(key)) {
    if (is.na(key[i]) || !nzchar(key[i])) {
      next
    }
    if (grepl(pat$ignore, key[i])) {
      next
    }
    role <- NA_character_
    for (nm in c("x", "replicate", "trials", "failures", "successes")) {
      if (grepl(pat[[nm]], key[i])) {
        role <- nm
        break
      }
    }
    out[i] <- role
  }
  out
}

## Read the whole sheet as text, anchored at cell A1.
##
## read_excel() trims leading empty rows and columns when no range is given,
## which renumbers everything and makes any row or column reference wrong by an
## unpredictable amount. Anchoring the range at A1 keeps the sheet coordinates
## the user sees in Excel, so a reported header row number is the one they can
## navigate to. Everything is read as text and converted here, so that a column
## Excel has stored as text does not silently become NA.
sheet_grid <- function(path, sheet) {
  out <- suppressMessages(readxl::read_excel(
    path = path,
    sheet = sheet,
    range = readxl::cell_limits(c(1, 1), c(NA, NA)),
    col_names = FALSE,
    col_types = "text",
    .name_repair = "minimal",
    progress = FALSE
  ))
  as.data.frame(out, stringsAsFactors = FALSE)
}

as_number <- function(x) {
  suppressWarnings(as.numeric(trimws(as.character(x))))
}

#' Classify the sheets of a workbook
#'
#' Examines every sheet in a workbook and decides which hold
#' concentration-response data that can be fitted, and which do not.
#'
#' A sheet is treated as an analysis sheet when a row can be found that names a
#' concentration column and at least one response column, with numeric data
#' beneath it. The search is by column name rather than by position, so the
#' title block, blank rows and blank columns of a laboratory form do not have
#' to be counted or skipped. Columns holding values derived from the response,
#' such as per cent of control, replicate means and standard deviations, are
#' recognised and discarded: the fit uses the recorded counts, not figures
#' computed from them.
#'
#' Two response layouts are recognised. A pair of count columns, such as
#' "No. Normal Development" and "No. Abnormal Development", gives a binomial
#' response whose number of trials is the row total. A single response column,
#' with an optional column of trial totals, gives either a binomial response
#' (when totals are supplied) or a continuous one.
#'
#' @param path Path to the workbook.
#'
#' @return A data frame with one row per sheet and the columns `sheet`,
#'   `analyse` (whether the sheet holds fittable data), `reason` (why not, when
#'   `analyse` is `FALSE`), `header_row` (the sheet row holding the column
#'   names), `n_rows`, `n_levels` (distinct concentrations) and `response`
#'   (the response layout found).
#' @export
#' @examples
#' \dontrun{
#' classify_sheets(find_workbook())
#' }
classify_sheets <- function(path) {
  check_pkgs("readxl")
  sheets <- readxl::excel_sheets(path)
  rows <- lapply(sheets, function(s) {
    spec <- try(sheet_spec(path, s), silent = TRUE)
    if (inherits(spec, "try-error")) {
      return(data.frame(
        sheet = s,
        analyse = FALSE,
        reason = trimws(sub("^Error[^:]*:", "", as.character(spec))),
        header_row = NA_integer_,
        n_rows = NA_integer_,
        n_levels = NA_integer_,
        response = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
    data.frame(
      sheet = s,
      analyse = spec$analyse,
      reason = spec$reason,
      header_row = spec$header_row,
      n_rows = spec$n_rows,
      n_levels = spec$n_levels,
      response = spec$response,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

## Work out what a single sheet holds. Returns the classification and, when the
## sheet is fittable, everything read_analysis_sheet() needs to extract it.
sheet_spec <- function(path, sheet) {
  no <- function(reason) {
    list(
      analyse = FALSE,
      reason = reason,
      header_row = NA_integer_,
      n_rows = NA_integer_,
      n_levels = NA_integer_,
      response = NA_character_
    )
  }
  grid <- sheet_grid(path, sheet)
  if (nrow(grid) == 0 || ncol(grid) == 0) {
    return(no("sheet is empty"))
  }

  ## Candidate header rows, best first. A row qualifies when it names a
  ## concentration column and at least one response column; the first such row
  ## from the top wins, because a laboratory form repeats its column names in
  ## any summary block that follows the data.
  best <- NULL
  for (r in seq_len(nrow(grid))) {
    roles <- header_roles(unlist(grid[r, ], use.names = FALSE))
    has_x <- any(roles %in% "x", na.rm = TRUE)
    has_y <- any(roles %in% c("successes", "failures"), na.rm = TRUE)
    if (!(has_x && has_y)) {
      ## Fall back to an unnamed response: a concentration column with a
      ## numeric column beside it that carries no recognised role and is not a
      ## derived summary. This is what catches a workbook that is not laid out
      ## as Form 149.
      if (!has_x) {
        next
      }
      cand <- unnamed_response(grid, r, roles)
      if (is.null(cand)) {
        next
      }
      roles <- cand
    }
    block <- data_block(grid, r, roles)
    if (is.null(block)) {
      next
    }
    best <- list(header_row = r, roles = roles, block = block)
    break
  }
  if (is.null(best)) {
    return(no(paste(
      "no row of column names was found naming a concentration column and a",
      "response column with numeric data beneath it"
    )))
  }

  d <- best$block
  n_levels <- length(unique(d$concentration))
  if (n_levels < 4) {
    return(no(paste0(
      "only ",
      n_levels,
      " distinct concentration(s); at least 4 are needed ",
      "to fit a concentration-response curve"
    )))
  }
  if (nrow(d) < 5) {
    return(no(paste0("only ", nrow(d), " data rows; at least 5 are needed")))
  }

  c(
    list(
      analyse = TRUE,
      reason = NA_character_,
      header_row = best$header_row,
      n_rows = nrow(d),
      n_levels = n_levels,
      sheet = sheet,
      path = path,
      roles = best$roles,
      labels = header_labels(grid, best$header_row, best$roles),
      data = d
    ),
    response_spec(d)
  )
}

## A column with no recognised role that holds numbers under the candidate
## header row, used as the response when no named response column is present.
unnamed_response <- function(grid, r, roles) {
  if (r >= nrow(grid)) {
    return(NULL)
  }
  below <- grid[seq(r + 1, nrow(grid)), , drop = FALSE]
  numeric_frac <- vapply(
    seq_len(ncol(below)),
    function(j) {
      v <- as_number(below[[j]])
      mean(!is.na(v))
    },
    numeric(1)
  )
  named <- !is.na(roles)
  header_txt <- normalise_header(unlist(grid[r, ], use.names = FALSE))
  ## Requires a name: an unlabelled column is more often a stray note than a
  ## response, and naming it is a reasonable thing to ask of the user.
  cand <- which(
    !named & nzchar(header_txt) & !is.na(header_txt) & numeric_frac > 0.5
  )
  if (length(cand) != 1) {
    return(NULL)
  }
  roles[cand] <- "response"
  roles
}

## Extract the rectangular block of data beneath a header row. Reading stops at
## the first row whose concentration cell is not a number, which is what ends
## the data on a laboratory form: the "Average Control" summary block below the
## counts has an empty concentration cell.
data_block <- function(grid, header_row, roles) {
  col_of <- function(role) which(roles %in% role)
  x_col <- col_of("x")[1]
  if (is.na(x_col)) {
    return(NULL)
  }
  start <- header_row + 1
  if (start > nrow(grid)) {
    return(NULL)
  }
  x_all <- as_number(grid[[x_col]])
  keep <- integer(0)
  for (i in seq(start, nrow(grid))) {
    if (is.na(x_all[i])) {
      break
    }
    keep <- c(keep, i)
  }
  if (length(keep) == 0) {
    return(NULL)
  }

  take <- function(role) {
    j <- col_of(role)
    if (length(j) == 0) {
      return(NULL)
    }
    as_number(grid[[j[1]]])[keep]
  }
  out <- data.frame(concentration = x_all[keep])
  succ <- take("successes")
  fail <- take("failures")
  resp <- take("response")
  trials <- take("trials")
  rep_col <- take("replicate")
  if (!is.null(succ)) {
    out$successes <- succ
  }
  if (!is.null(fail)) {
    out$failures <- fail
  }
  if (!is.null(resp)) {
    out$response <- resp
  }
  if (!is.null(trials)) {
    out$trials <- trials
  }
  if (!is.null(rep_col)) {
    out$replicate <- rep_col
  }

  ## Drop rows where any retained column is missing. A partly filled row is a
  ## data entry that was never completed, not an observation.
  complete <- stats::complete.cases(out)
  out <- out[complete, , drop = FALSE]
  if (nrow(out) == 0) {
    return(NULL)
  }
  if (is.null(out$replicate)) {
    ## Replicate is recorded only for reporting; it is not a term in the model.
    out$replicate <- stats::ave(
      out$concentration,
      out$concentration,
      FUN = seq_along
    )
  }
  out$replicate <- as.integer(out$replicate)
  rownames(out) <- NULL
  out
}

## The header text actually used, for labelling the report axes.
header_labels <- function(grid, header_row, roles) {
  cells <- as.character(unlist(grid[header_row, ], use.names = FALSE))
  lab <- function(role) {
    j <- which(roles %in% role)
    if (length(j) == 0) NA_character_ else trimws(cells[j[1]])
  }
  list(
    x = lab("x"),
    successes = lab("successes"),
    failures = lab("failures"),
    response = lab("response"),
    trials = lab("trials")
  )
}

## Decide the response layout, the response variable and the family, from the
## columns that were found.
##
## The link is always stated explicitly. bnec() sets link = "identity" when it
## infers the family itself, but a family object passed in keeps whatever link
## that family defaults to, and both binomial() and Beta() default to logit.
## With a logit link the curve is fitted to the logit of the mean rather than
## to the mean, so top, bot and nec stop being readable on the response scale.
response_spec <- function(d) {
  if (!is.null(d$successes) && !is.null(d$failures)) {
    return(list(
      response = "counts (successes and failures)",
      y_var = "successes",
      trials_var = "trials_total",
      family_call = "binomial(link = \"identity\")"
    ))
  }
  if (!is.null(d$successes) && !is.null(d$trials)) {
    return(list(
      response = "counts with supplied totals",
      y_var = "successes",
      trials_var = "trials",
      family_call = "binomial(link = \"identity\")"
    ))
  }
  y <- if (!is.null(d$response)) d$response else d$successes
  if (is.null(y)) {
    return(list(
      response = NA_character_,
      y_var = NA_character_,
      trials_var = NA_character_,
      family_call = NA_character_
    ))
  }
  y_name <- if (!is.null(d$response)) "response" else "successes"
  if (all(y >= 0 & y <= 1)) {
    list(
      response = "proportion",
      y_var = y_name,
      trials_var = NA_character_,
      family_call = "Beta(link = \"identity\")"
    )
  } else {
    list(
      response = "continuous",
      y_var = y_name,
      trials_var = NA_character_,
      family_call = "gaussian()"
    )
  }
}

#' Read one analysis sheet
#'
#' Reads the concentration-response data from a single sheet, together with
#' everything needed to fit it: the response variable, the number of trials
#' where the response is a count, and the family.
#'
#' @param path Path to the workbook.
#' @param sheet Sheet name.
#'
#' @return An object of class `analysis_sheet`: a list holding the data frame
#'   (`data`), the sheet name, the variable names, the family call and the
#'   column headings read from the sheet.
#' @export
#' @examples
#' \dontrun{
#' read_analysis_sheet(find_workbook(), "Copper Ref (4)")
#' }
read_analysis_sheet <- function(path, sheet) {
  check_pkgs("readxl")
  spec <- sheet_spec(path, sheet)
  if (!isTRUE(spec$analyse)) {
    stop(
      "sheet '",
      sheet,
      "' does not hold fittable data: ",
      spec$reason,
      call. = FALSE
    )
  }
  d <- spec$data

  ## Every larva scored in a vessel is either a success or a failure, so the
  ## vessel total is the number of trials. Vessel totals are not constant in
  ## these assays, which is why the response is modelled as counts rather than
  ## as a proportion: a proportion discards how many animals it was computed
  ## from.
  if (identical(spec$trials_var, "trials_total")) {
    d$trials_total <- d$successes + d$failures
    spec$trials_var <- "trials_total"
  }

  notes <- character(0)
  if (grepl("binomial", spec$family_call, fixed = TRUE)) {
    if (any(d[[spec$trials_var]] <= 0)) {
      stop(
        "sheet '",
        sheet,
        "' has rows where no animals were scored.",
        call. = FALSE
      )
    }
    for (v in intersect(
      c(spec$y_var, spec$trials_var, "successes", "failures"),
      names(d)
    )) {
      d[[v]] <- as.integer(round(d[[v]]))
    }
  }
  if (grepl("Beta", spec$family_call, fixed = TRUE)) {
    ## A beta response is defined on the open interval, so exact 0 and 1 cannot
    ## be fitted. They are squeezed towards the interior by the standard
    ## transformation of Smithson and Verkuilen (2006). This is a change to the
    ## data, so it is recorded and reported rather than done silently. Where
    ## the underlying counts are available, supplying them instead avoids the
    ## problem entirely and is preferred.
    y <- d[[spec$y_var]]
    if (any(y <= 0 | y >= 1)) {
      n <- length(y)
      d[[spec$y_var]] <- (y * (n - 1) + 0.5) / n
      notes <- c(
        notes,
        paste(
          "the response contains exact 0 or 1 values, which a beta response",
          "cannot take; values were squeezed towards the interior using",
          "(y * (n - 1) + 0.5) / n"
        )
      )
    }
  }

  structure(
    list(
      data = d,
      sheet = sheet,
      path = path,
      header_row = spec$header_row,
      x_var = "concentration",
      y_var = spec$y_var,
      trials_var = spec$trials_var,
      family_call = spec$family_call,
      response = spec$response,
      labels = spec$labels,
      notes = notes
    ),
    class = "analysis_sheet"
  )
}

#' @export
print.analysis_sheet <- function(x, ...) {
  cat("Analysis sheet: ", x$sheet, "\n", sep = "")
  cat("  workbook:    ", basename(x$path), "\n", sep = "")
  cat("  column names on sheet row ", x$header_row, "\n", sep = "")
  cat("  response:    ", x$response, "\n", sep = "")
  cat("  family:      ", x$family_call, "\n", sep = "")
  cat(
    "  data:        ",
    nrow(x$data),
    " rows, ",
    length(unique(x$data$concentration)),
    " concentrations (",
    paste(sort(unique(x$data$concentration)), collapse = ", "),
    ")\n",
    sep = ""
  )
  for (n in x$notes) {
    cat("  note:        ", n, "\n", sep = "")
  }
  invisible(x)
}

#' Read every analysis sheet in a workbook
#'
#' @param path Path to the workbook. Defaults to the single workbook found by
#'   [find_workbook()].
#' @param sheets Optional character vector naming the sheets to read. The
#'   default reads every sheet [classify_sheets()] identifies as holding
#'   fittable data.
#'
#' @return A named list of `analysis_sheet` objects.
#' @export
#' @examples
#' \dontrun{
#' read_workbook()
#' }
read_workbook <- function(path = find_workbook(), sheets = NULL) {
  if (is.null(sheets)) {
    cls <- classify_sheets(path)
    sheets <- cls$sheet[cls$analyse]
  }
  if (length(sheets) == 0) {
    stop(
      "no sheet in '",
      basename(path),
      "' holds fittable data. Run ",
      "classify_sheets() on it to see why each sheet was skipped.",
      call. = FALSE
    )
  }
  out <- lapply(sheets, function(s) read_analysis_sheet(path, s))
  names(out) <- sheets
  out
}
