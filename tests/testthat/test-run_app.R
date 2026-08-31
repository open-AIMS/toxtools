test_that("the app classifies a workbook and will not start an empty run", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("DT")
  skip_if_not_installed("callr")

  fixture <- make_test_workbook()
  ## A folder of its own: the app lists every workbook in the folder it is
  ## given, and the session temp directory holds other files.
  in_dir <- withr::local_tempdir()
  out_dir <- withr::local_tempdir()
  file.copy(fixture, file.path(in_dir, "example.xlsx"))

  app_dir <- system.file("shiny", package = "toxtools")
  skip_if(!nzchar(app_dir) || !file.exists(file.path(app_dir, "app.R")))

  shiny::shinyOptions(
    toxtools_config = list(
      input_dir = in_dir,
      output_dir = out_dir,
      wd = getwd(),
      dev_dir = NULL
    )
  )

  shiny::testServer(shiny::shinyAppDir(app_dir), {
    session$setInputs(workbook = "example.xlsx")

    cls <- classification()
    expect_identical(cls$sheet, c("Form", "Empty", "TooFew", "Plain"))
    expect_identical(sum(cls$analyse), 2L)

    expect_identical(state(), "idle")
    expect_identical(n_done(), 0L)
    expect_null(manifest())

    # pressing Run with nothing ticked must not start a fitting process
    session$setInputs(sheets = character(0), run = 1)
    expect_null(job())
  })
})
