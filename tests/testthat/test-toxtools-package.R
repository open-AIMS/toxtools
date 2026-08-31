# Placeholder so tests/testthat/ is tracked and test_check() has a file to run.
# Replace with real tests as functions are added to R/.
test_that("package can be loaded", {
  expect_true(requireNamespace("toxtools", quietly = TRUE))
})
