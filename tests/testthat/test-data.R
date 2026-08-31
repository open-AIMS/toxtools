test_that("sea_urchin has the expected structure", {
  expect_s3_class(sea_urchin, "data.frame")
  expect_identical(dim(sea_urchin), c(18L, 4L))
  expect_named(
    sea_urchin,
    c("concentration", "replicate", "n_normal", "n_abnormal")
  )
  expect_type(sea_urchin$concentration, "double")
  expect_type(sea_urchin$replicate, "integer")
  expect_type(sea_urchin$n_normal, "integer")
  expect_type(sea_urchin$n_abnormal, "integer")
  expect_false(anyNA(sea_urchin))
})

test_that("sea_urchin is a balanced design with non-negative counts", {
  expect_identical(
    sort(unique(sea_urchin$concentration)),
    c(0, 2.5, 5, 10, 20, 40)
  )
  expect_identical(sort(unique(sea_urchin$replicate)), 1:3)
  expect_true(all(table(sea_urchin$concentration) == 3))
  expect_true(all(sea_urchin$n_normal >= 0))
  expect_true(all(sea_urchin$n_abnormal >= 0))
  # every vessel scored at least one larva, so the proportion normal is defined
  expect_true(all(sea_urchin$n_normal + sea_urchin$n_abnormal > 0))
})

test_that("sea_urchin response decreases across the concentration series", {
  # a copper reference toxicant test that did not show this would indicate the
  # wrong rows or columns were extracted from the laboratory form
  prop <- with(
    sea_urchin,
    n_normal / (n_normal + n_abnormal)
  )
  group_mean <- tapply(prop, sea_urchin$concentration, mean)
  expect_gt(group_mean[["0"]], 0.9)
  expect_lt(group_mean[["40"]], 0.05)
  expect_true(group_mean[["0"]] > group_mean[["20"]])
})
