## Guard against a missing suggested package.
##
## The workflow functions depend on bayesnec, brms, readxl, ggplot2 and quarto,
## none of which is needed to use the datasets and helpers in this package.
## They are declared in Suggests and checked here, so that a user who installs
## toxtools for its data is not made to build brms, and a user who runs the
## workflow without them gets one instruction naming everything that is
## missing rather than a sequence of namespace errors.
check_pkgs <- function(...) {
  pkgs <- c(...)
  missing <- pkgs[
    !vapply(
      pkgs,
      requireNamespace,
      logical(1),
      quietly = TRUE
    )
  ]
  if (length(missing) > 0) {
    stop(
      "the following package(s) are needed for this and are not installed: ",
      paste(missing, collapse = ", "),
      ".\nInstall them with:\n",
      "  install.packages(c(",
      paste0("\"", missing, "\"", collapse = ", "),
      "))",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

## Transformation applied to concentration before fitting, and its inverse.
##
## The predictor is transformed rather than the axis alone, because the model
## is fitted to the transformed predictor: a curve that is a poor shape against
## raw concentration is often a good one against its square root. The inverse
## is needed to return the no-effect and effect concentrations to the units the
## user recorded, and to label the plot axes.
predictor_funs <- function(transform = c("sqrt", "log", "identity")) {
  transform <- match.arg(transform)
  switch(
    transform,
    sqrt = list(
      name = "sqrt",
      term = function(v) paste0("sqrt(", v, ")"),
      fwd = sqrt,
      inv = function(x) x^2,
      note = "square-root"
    ),
    log = list(
      name = "log",
      term = function(v) paste0("log(", v, ")"),
      fwd = log,
      inv = exp,
      note = "natural-log"
    ),
    identity = list(
      name = "identity",
      term = function(v) v,
      fwd = identity,
      inv = identity,
      note = "untransformed"
    )
  )
}

## Axis breaks in the units the user recorded. The tested concentrations are
## used directly when there are few enough of them, because they are the values
## the reader wants to locate on the axis; otherwise breaks are chosen evenly
## on the transformed scale so that they are evenly spaced in the plot.
axis_breaks <- function(x, funs, n = 6) {
  u <- sort(unique(x[is.finite(x)]))
  if (length(u) <= 8) {
    return(u)
  }
  tb <- pretty(funs$fwd(range(u)), n = n)
  tb <- tb[tb >= min(funs$fwd(u)) & tb <= max(funs$fwd(u))]
  signif(funs$inv(tb), 3)
}

format_breaks <- function(x) {
  formatC(x, format = "g", digits = 4, drop0trailing = TRUE)
}

## Column names used inside ggplot2::aes(), which R CMD check cannot see are
## data columns rather than undefined objects. Declared here rather than using
## the .data pronoun, because ggplot2 is a suggested package and the pronoun
## would have to be imported from it.
utils::globalVariables(c("x", "y"))
