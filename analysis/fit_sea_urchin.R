## Concentration-response fit for the sea urchin copper reference test.
##
## Fits the bayesnec "decline" model set (14 equations) to the `sea_urchin`
## dataset and extracts the model-averaged no-effect and effect concentration
## estimates. Run from the repository root:
##
##   Rscript analysis/fit_sea_urchin.R
##
## Expect roughly 20-40 minutes with four cores. Outputs are written to
## analysis/output/, which is excluded from version control because a fitted
## brms object is large and is reproducible from this script.
##
## bayesnec, brms and ggplot2 are required. None is declared in DESCRIPTION:
## analysis/ is excluded from the package build (.Rbuildignore), so a user
## installing toxtools never needs them.

set.seed(101)

library(bayesnec)
library(ggplot2)

out_dir <- file.path("analysis", "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Data -------------------------------------------------------------------

## The dataset ships with the package. Loading the saved object directly when
## toxtools is not installed lets the script run from a fresh clone without an
## install step first.
if (requireNamespace("toxtools", quietly = TRUE)) {
  data("sea_urchin", package = "toxtools", envir = environment())
} else {
  load(file.path("data", "sea_urchin.rda"))
}

## Each vessel contributes a count of normally developed larvae out of the
## number scored, so the response is binomial and the vessel total is the
## number of trials. Vessel totals are not constant, which is why the response
## is modelled as counts rather than as a proportion.
sea_urchin$total <- sea_urchin$n_normal + sea_urchin$n_abnormal

stopifnot(
  nrow(sea_urchin) == 18L,
  all(sea_urchin$total > 0)
)

# ---- Fit --------------------------------------------------------------------

## Concentration is used on its natural scale. The series includes a zero
## control, so a log or square-root transformation of x would either drop the
## controls or require an arbitrary offset added to every concentration.
##
## The response is supplied as the measured counts, not as percent of control.
## bnec()'s ecx(type = "absolute") default already measures decline relative to
## the fitted control value one posterior draw at a time; normalising to the
## control beforehand instead discards the uncertainty in the divisor and
## biases effective doses upwards.
##
## family is stated explicitly rather than left to bnec()'s guess. Note that
## bnec() sets link = "identity" for every family it accepts, so `top`, `bot`
## and `nec` are returned on the proportion scale and are directly readable as
## proportions developing normally.
fit <- bnec(
  n_normal | trials(total) ~ crf(concentration, model = "decline"),
  data = sea_urchin,
  family = binomial(),
  seed = 101,
  chains = 4,
  cores = 4
)

saveRDS(fit, file.path(out_dir, "sea_urchin_decline_fit.rds"))

# ---- Diagnostics ------------------------------------------------------------

## check_chains() writes a multi-page trace plot; inspect before trusting any
## estimate below. summary() reports which of the 14 equations were retained
## and their model weights.
pdf(file.path(out_dir, "sea_urchin_chains.pdf"), width = 8, height = 10)
check_chains(fit)
dev.off()

fit_summary <- summary(fit)
print(fit_summary)

capture.output(
  print(fit_summary),
  file = file.path(out_dir, "sea_urchin_summary.txt")
)

## The binomial variance is fixed by the mean, so over-dispersion cannot be
## absorbed by the fit and instead inflates apparent precision. dispersion()
## tests for it. If the estimate excludes 1, refit with
## family = beta_binomial().
print(dispersion(fit, summary = TRUE))

# ---- Estimates --------------------------------------------------------------

## For a model set containing both NEC and ECx equations, nec() returns the
## model-averaged N(S)EC: the NEC parameter from the threshold equations
## combined with the NSEC from the smooth ones.
nsec_est <- nec(fit)
ec10_est <- ecx(fit, ecx_val = 10)
ec50_est <- ecx(fit, ecx_val = 50)

estimates <- rbind(
  `N(S)EC` = nsec_est,
  EC10 = ec10_est,
  EC50 = ec50_est
)
print(estimates)

write.csv(
  estimates,
  file.path(out_dir, "sea_urchin_estimates.csv"),
  row.names = TRUE
)

# ---- Plot -------------------------------------------------------------------

p <- autoplot(fit) +
  labs(
    x = expression("Copper (" * mu * "g L"^-1 * ")"),
    y = "Proportion developing normally",
    title = "Sea urchin 72 h development, copper reference test"
  ) +
  theme_classic()

ggsave(
  file.path(out_dir, "sea_urchin_fit.png"),
  plot = p,
  width = 6,
  height = 4.5,
  dpi = 300
)
