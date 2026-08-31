## Script to prepare datasets shipped in data/.
##
## One block per dataset. Read the source file, do any cleaning here rather
## than in package code so the shipped object is the analysis-ready version,
## then write it with usethis::use_data(). Document the result in R/data.R.

# set.seed(101)  # only if any step is stochastic

# my_dataset <- readr::read_csv("data-raw/my_dataset.csv")
# usethis::use_data(my_dataset, overwrite = TRUE)
