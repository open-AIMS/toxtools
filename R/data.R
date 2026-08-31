#' Sea urchin larval development under copper exposure
#'
#' Counts of normally and abnormally developed larvae from a 72 hour sea urchin
#' development test, exposed to a dilution series of copper. The data are the
#' first of four copper reference-toxicant tests recorded on Laboratory
#' Form 149, and are provided as a worked example of a binomial
#' concentration-response dataset.
#'
#' Six copper concentrations were each run with three replicate vessels. Every
#' larva scored in a vessel is classified as either normal or abnormal, so
#' `n_normal + n_abnormal` is the number scored in that vessel. Vessel totals
#' are not constant, which is typical of these assays and is the reason the
#' response is held as counts rather than as a proportion.
#'
#' Only the counts recorded on the form are retained. The percent normal
#' development, percent of control, replicate means and standard deviations
#' that also appear on the form are all derived from the counts and are
#' recomputed rather than stored, so that they cannot fall out of step with
#' the values they are derived from.
#'
#' @format A data frame with 18 rows and 4 columns:
#' \describe{
#'   \item{concentration}{Copper concentration, in micrograms per litre. Six
#'     levels: 0, 2.5, 5, 10, 20 and 40.}
#'   \item{replicate}{Replicate vessel within a concentration, 1 to 3.}
#'   \item{n_normal}{Number of larvae scored as normally developed.}
#'   \item{n_abnormal}{Number of larvae scored as abnormally developed.}
#' }
#' @source Laboratory Form 149, 72 hr sea urchin development test, copper
#'   reference. Prepared by `data-raw/sea_urchin.R`. The source workbook is
#'   not distributed with the package.
#' @examples
#' # proportion developing normally in each vessel
#' with(sea_urchin, n_normal / (n_normal + n_abnormal))
"sea_urchin"
