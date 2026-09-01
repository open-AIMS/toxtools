## Turn a column heading from the sheet into an axis label.
## "No. Normal Development" is the count; the quantity plotted for a binomial
## response is the proportion, so the label is built from the heading rather
## than used as it stands.
axis_label_y <- function(sheet) {
  lab <- sheet$labels$successes
  if (is.na(lab)) {
    lab <- sheet$labels$response
  }
  if (is.na(lab)) {
    return("Response")
  }
  ## \\s+ rather than \\s*: the count prefix has to be a separate word.
  ## Without the space required, the alternation strips the first letters of a
  ## heading that merely begins with them, turning "Normal Development" into
  ## "rmal Development" and "Nauplii alive" into "auplii alive".
  lab <- trimws(sub("^(no\\.?|number of|n)\\s+", "", lab, ignore.case = TRUE))
  if (grepl("binomial", sheet$family_call, fixed = TRUE)) {
    paste0("Proportion ", tolower(lab))
  } else {
    lab
  }
}

axis_label_x <- function(sheet) {
  lab <- sheet$labels$x
  if (is.na(lab)) "Concentration" else lab
}

#' Plot a fitted model set
#'
#' Draws the model-averaged fit, or the individual equations that make it up,
#' with the concentration axis spaced on the scale the curve was fitted on and
#' labelled in the units recorded on the sheet.
#'
#' The axis is spaced by the square root (or logarithm) of concentration,
#' which is the scale the curve was fitted on and which spreads out the low
#' concentrations where the response turns. Only the spacing is transformed:
#' the ticks are labelled with the concentrations themselves, so the axis can
#' be read in the units on the sheet.
#'
#' `bayesnec` returns plot data on the recorded concentration scale even when
#' the curve was fitted to a transformed predictor, so the spacing is applied
#' by the scale rather than by transforming the data. Its `nec()` and `ecx()`
#' estimates, by contrast, come back on the fitted scale; [workbook_estimates()]
#' back-transforms those, which is why the value annotated here needs no
#' further conversion.
#'
#' @param x An `analysis_fit` object from [fit_analysis_sheet()].
#' @param estimates Optional data frame from [workbook_estimates()]. When
#'   supplied and `all_models` is `FALSE`, the no-effect concentration and its
#'   credible interval are drawn on the plot and labelled in the recorded
#'   units.
#' @param all_models If `TRUE`, one panel per retained equation instead of the
#'   model-averaged curve.
#' @param title Plot title. `NULL` uses the sheet name.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \dontrun{
#' plot_workbook_fit(fit, workbook_estimates(fit))
#' }
plot_workbook_fit <- function(
  x,
  estimates = NULL,
  all_models = FALSE,
  title = NULL
) {
  check_pkgs("bayesnec", "ggplot2")
  stopifnot(inherits(x, "analysis_fit"))
  sheet <- x$sheet
  funs <- x$funs

  ## nec = FALSE suppresses bayesnec's own annotation, which reports the
  ## no-effect concentration on the transformed scale. The value is added back
  ## below in the units the user recorded; the two side by side would be read
  ## as a disagreement.
  p <- suppressWarnings(suppressMessages(
    ggplot2::autoplot(
      x$fit,
      nec = FALSE,
      ecx = FALSE,
      all_models = all_models
    )
  ))

  brks <- axis_breaks(sheet$data[[sheet$x_var]], funs)

  if (!all_models && !is.null(estimates)) {
    nsec <- estimates[estimates$estimate == "N(S)EC", , drop = FALSE]
    if (nrow(nsec) == 1 && is.finite(nsec$value)) {
      vals <- c(nsec$value, nsec$lower, nsec$upper)
      p <- p +
        ggplot2::geom_vline(
          xintercept = vals,
          linetype = c(1, 2, 2),
          colour = "grey50",
          linewidth = c(0.5, 0.2, 0.2)
        ) +
        ggplot2::annotate(
          "text",
          x = Inf,
          y = Inf,
          hjust = 1.1,
          vjust = 1.5,
          size = 3,
          colour = "grey50",
          label = sprintf(
            "N(S)EC: %s (%s-%s)",
            format_breaks(signif(nsec$value, 3)),
            format_breaks(signif(nsec$lower, 3)),
            format_breaks(signif(nsec$upper, 3))
          )
        )
    }
  }

  ## suppressMessages(): replacing bayesnec's own x scale is deliberate, and
  ## ggplot2 reports every replacement.
  suppressMessages(
    p +
      spaced_x_scale(funs, brks, axis_label_x(sheet)) +
      ggplot2::labs(
        y = axis_label_y(sheet),
        title = title %||% sheet$sheet,
        caption = paste0(
          "Concentration axis spaced on the ",
          funs$note,
          " scale, labelled in recorded units."
        )
      )
  )
}

## Build the concentration scale: values stay in recorded units, spacing
## follows the transformation the curve was fitted on.
##
## The argument naming the transformation was renamed from `trans` to
## `transform` in ggplot2 3.5.0, and the old name now warns. Both are still
## accepted, so the one this installation expects is chosen here rather than
## pinning a ggplot2 version.
spaced_x_scale <- function(funs, breaks, name) {
  args <- list(
    name = name,
    breaks = breaks,
    labels = format_breaks(breaks)
  )
  arg <- if ("transform" %in% names(formals(ggplot2::scale_x_continuous))) {
    "transform"
  } else {
    "trans"
  }
  args[[arg]] <- funs$name
  do.call(ggplot2::scale_x_continuous, args)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Plot the observed data
#'
#' Draws the recorded response against concentration, with no model fitted.
#' This is the check that the right rows and columns were read from the sheet:
#' the points should reproduce what is on the laboratory form.
#'
#' @param sheet An `analysis_sheet` object from [read_analysis_sheet()].
#' @param transform Concentration axis spacing, one of `"sqrt"`, `"log"` or
#'   `"identity"`. Match this to the transformation used for the fit.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \dontrun{
#' plot_sheet_data(read_analysis_sheet(find_workbook(), "Copper Ref (4)"))
#' }
plot_sheet_data <- function(sheet, transform = "sqrt") {
  check_pkgs("ggplot2")
  stopifnot(inherits(sheet, "analysis_sheet"))
  funs <- predictor_funs(transform)
  d <- sheet$data
  y <- if (!is.na(sheet$trials_var)) {
    d[[sheet$y_var]] / d[[sheet$trials_var]]
  } else {
    d[[sheet$y_var]]
  }
  brks <- axis_breaks(d[[sheet$x_var]], funs)
  ggplot2::ggplot(
    data.frame(x = d[[sheet$x_var]], y = y),
    ggplot2::aes(x = x, y = y)
  ) +
    ggplot2::geom_point(shape = 21, fill = "grey30") +
    spaced_x_scale(funs, brks, axis_label_x(sheet)) +
    ggplot2::labs(y = axis_label_y(sheet)) +
    ggplot2::theme_classic()
}
