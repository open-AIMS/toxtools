## Point-and-click front end for the workbook analysis workflow.
##
## Started by toxtools::run_app(), which passes the folders to use and, during
## development, the source directory the fitting process should load the
## package from.
##
## The app itself does no fitting. run_workbook() is run in a separate R
## process through callr, and this session polls that process for its progress
## and reads the files it writes. A fit takes twenty to forty minutes per
## sheet, and a Shiny session that blocked for that long would appear to have
## frozen and would be disconnected by any proxy in front of it.

library(shiny)
library(bslib)

if (!"package:toxtools" %in% search()) {
  library(toxtools)
}

## run_app() supplies this, with every path already absolute. The fallback is
## only reached when app.R is opened and run directly, which is a development
## convenience rather than the supported way in.
config <- getShinyOption(
  "toxtools_config",
  default = list(
    input_dir = normalizePath("inputs", winslash = "/", mustWork = FALSE),
    output_dir = normalizePath("outputs", winslash = "/", mustWork = FALSE),
    wd = normalizePath(getwd(), winslash = "/"),
    dev_dir = NULL
  )
)

## Laboratory workbooks are small, but the 5 MB default refuses files that are
## merely large by spreadsheet standards.
options(shiny.maxRequestSize = 100 * 1024^2)

## detectCores() returns NA on a machine it cannot interrogate, which would
## otherwise propagate into the cores setting and stop the fit.
n_cores <- suppressWarnings(parallel::detectCores(logical = FALSE))
if (!is.finite(n_cores)) {
  n_cores <- 2L
}
default_cores <- max(1L, min(4L, n_cores))

## The job function is taken from the package but has its environment replaced
## before it is sent to the other process. callr serialises the function
## together with its environment; left as the toxtools namespace, the child
## would try to load an installed toxtools, which during development does not
## exist.
job_fun <- getFromNamespace("fit_job", "toxtools")
environment(job_fun) <- globalenv()
safe_name <- getFromNamespace("safe_name", "toxtools")

model_sets <- c(
  "Declining curves only (recommended)" = "decline",
  "All curves, including hormesis" = "all",
  "Threshold (NEC) curves only" = "nec",
  "Smooth (ECx) curves only" = "ecx"
)

transforms <- c(
  "Square root (keeps a zero control)" = "sqrt",
  "Logarithm (no zero concentration allowed)" = "log",
  "None" = "identity"
)

list_workbooks <- function(dir) {
  f <- list.files(dir, pattern = "\\.xlsx?$")
  f[!grepl("^(~\\$|\\.)", f)]
}

report_file <- function(run_dir, format) {
  file.path(
    run_dir,
    paste0("workbook_report.", if (identical(format, "html")) "html" else "pdf")
  )
}

ui <- page_sidebar(
  title = "Concentration-response analysis",
  sidebar = sidebar(
    width = 340,
    open = "open",
    h5("1. Choose a workbook"),
    selectInput("workbook", NULL, choices = character(0)),
    fileInput(
      "upload",
      "Add a workbook",
      accept = c(".xlsx", ".xls"),
      buttonLabel = "Browse",
      placeholder = ""
    ),
    h5("2. Choose the sheets"),
    uiOutput("sheet_picker"),
    h5("3. Settings"),
    accordion(
      open = FALSE,
      accordion_panel(
        "Analysis",
        selectInput("model", "Curves to fit", choices = model_sets),
        selectInput("transform", "Concentration scale", choices = transforms),
        checkboxGroupInput(
          "ecx_vals",
          "Effect concentrations to report",
          choices = c("EC10" = 10, "EC20" = 20, "EC50" = 50),
          selected = c(10, 50),
          inline = TRUE
        )
      ),
      accordion_panel(
        "Report",
        radioButtons(
          "format",
          "Report format",
          choices = c("PDF" = "pdf", "Web page (no LaTeX needed)" = "html"),
          selected = "pdf"
        )
      ),
      accordion_panel(
        "Advanced",
        radioButtons(
          "backend",
          "Sampler",
          choices = c("CmdStan (faster)" = "cmdstanr", "rstan" = "rstan"),
          selected = "cmdstanr"
        ),
        numericInput("chains", "Sampling chains", 4, min = 2, max = 8),
        numericInput("cores", "Cores to use", default_cores, min = 1),
        checkboxInput("refit", "Fit again even if a saved fit exists", FALSE)
      )
    ),
    hr(),
    actionButton(
      "run",
      "Run analysis",
      icon = icon("play"),
      class = "btn-primary"
    ),
    actionButton("stop", "Stop", class = "btn-outline-danger"),
    hr(),
    uiOutput("status")
  ),
  navset_card_tab(
    id = "tabs",
    nav_panel(
      "Sheets",
      card_body(
        markdown(paste(
          "Each sheet is searched for a row of column names giving a",
          "concentration column and a response column, with numeric data",
          "beneath it. Sheets with no such block are skipped, and the reason",
          "is given here. Columns holding values worked out from the response,",
          "such as per cent of control, are ignored: the fit uses the recorded",
          "counts."
        )),
        DT::DTOutput("classification")
      )
    ),
    nav_panel(
      "Progress",
      card_body(
        uiOutput("progress_note"),
        verbatimTextOutput("log")
      )
    ),
    nav_panel("Results", card_body(uiOutput("results_ui"))),
    nav_panel(
      "Help",
      card_body(markdown(paste(
        "### What this does\n\n",
        "It fits a set of concentration-response curves to each sheet of data",
        "in the workbook, combines them into one model-averaged curve, and",
        "writes a report holding the no-effect concentration (N(S)EC), the",
        "effect concentrations, the curves and the diagnostic checks.\n\n",
        "### How long it takes\n\n",
        "Roughly twenty to forty minutes for each sheet. Each sheet is saved",
        "as it finishes, so if the run is interrupted, starting it again",
        "continues from where it stopped rather than beginning afresh. Tick",
        "*Fit again even if a saved fit exists* to override that.\n\n",
        "### Where the results go\n\n",
        "Into a folder named after the workbook, inside `outputs`. It holds",
        "the report, the estimates as CSV files, and the fitted objects.",
        "Nothing is sent anywhere: the analysis runs on this machine.\n\n",
        "### If the PDF fails\n\n",
        "A PDF report needs a LaTeX installation. If there is none, choose",
        "*Web page* as the report format instead, or install one by running",
        "`tinytex::install_tinytex()` once."
      )))
    )
  ),
  tags$head(tags$style(HTML(
    "#log { height: 460px; overflow-y: scroll; font-size: 0.78rem; }"
  )))
)

server <- function(input, output, session) {
  job <- reactiveVal(NULL)
  log_file <- reactiveVal(NULL)
  run_dir <- reactiveVal(NULL)
  run_format <- reactiveVal("pdf")
  n_requested <- reactiveVal(0L)
  state <- reactiveVal("idle")
  exit_status <- reactiveVal(NULL)
  ## Bumped once a second while a fit is running. Everything that reads a file
  ## the other process is writing depends on this rather than polling
  ## independently, so there is one timer rather than four.
  tick <- reactiveVal(0)
  wb_trigger <- reactiveVal(0)

  ## ---- Workbook selection --------------------------------------------------

  observe({
    wb_trigger()
    files <- list_workbooks(config$input_dir)
    keep <- isolate(input$workbook)
    updateSelectInput(
      session,
      "workbook",
      choices = files,
      selected = if (length(files) == 0) {
        character(0)
      } else if (isTruthy(keep) && keep %in% files) {
        keep
      } else {
        files[1]
      }
    )
  })

  observeEvent(input$upload, {
    ## The upload is copied into the input folder under its own name rather
    ## than left in the temporary file Shiny gives it, so that it is still
    ## there for a later run and so that the folder the app lists is the same
    ## folder run_workbook() reads from.
    dest <- file.path(config$input_dir, input$upload$name)
    if (!file.copy(input$upload$datapath, dest, overwrite = TRUE)) {
      showNotification("The workbook could not be copied.", type = "error")
      return()
    }
    wb_trigger(wb_trigger() + 1)
    updateSelectInput(session, "workbook", selected = input$upload$name)
    showNotification(paste0("Added ", input$upload$name), type = "message")
  })

  workbook_path <- reactive({
    req(input$workbook)
    file.path(config$input_dir, input$workbook)
  })

  ## Adopt the results of a previous run of the selected workbook, if there are
  ## any. Everything needed is on disk, and without this the Results tab is
  ## empty until something is fitted again, which for an analysis measured in
  ## hours is the wrong default.
  observeEvent(input$workbook, {
    if (identical(state(), "running")) {
      return()
    }
    dir <- file.path(
      config$output_dir,
      safe_name(tools::file_path_sans_ext(basename(input$workbook)))
    )
    f <- file.path(dir, "manifest.rds")
    if (!file.exists(f)) {
      run_dir(NULL)
      return()
    }
    m <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(m)) {
      run_dir(NULL)
      return()
    }
    run_dir(dir)
    run_format(if (is.null(m$format) || is.na(m$format)) "pdf" else m$format)
    tick(isolate(tick()) + 1)
  })

  classification <- reactive({
    path <- workbook_path()
    req(file.exists(path))
    tryCatch(
      toxtools::classify_sheets(path),
      error = function(e) {
        showNotification(
          paste("The workbook could not be read:", conditionMessage(e)),
          type = "error",
          duration = NULL
        )
        NULL
      }
    )
  })

  output$classification <- DT::renderDT({
    cls <- classification()
    req(cls)
    DT::datatable(
      data.frame(
        Sheet = cls$sheet,
        `Can be fitted` = ifelse(cls$analyse, "yes", "no"),
        `Names on row` = cls$header_row,
        Rows = cls$n_rows,
        Concentrations = cls$n_levels,
        Response = cls$response,
        `Reason skipped` = ifelse(is.na(cls$reason), "", cls$reason),
        check.names = FALSE
      ),
      rownames = FALSE,
      selection = "none",
      options = list(dom = "t", paging = FALSE, ordering = FALSE)
    )
  })

  output$sheet_picker <- renderUI({
    cls <- classification()
    if (is.null(cls)) {
      return(helpText("Choose a workbook."))
    }
    fittable <- cls$sheet[cls$analyse]
    if (length(fittable) == 0) {
      return(div(
        class = "text-danger",
        paste(
          "No sheet in this workbook holds data that can be fitted.",
          "The Sheets tab gives the reason for each."
        )
      ))
    }
    checkboxGroupInput("sheets", NULL, choices = fittable, selected = fittable)
  })

  ## ---- Running -------------------------------------------------------------

  observeEvent(input$run, {
    p <- job()
    if (!is.null(p) && p$is_alive()) {
      showNotification("An analysis is already running.", type = "warning")
      return()
    }
    if (!isTruthy(input$sheets)) {
      showNotification("Choose at least one sheet.", type = "warning")
      return()
    }
    ## A numeric input that has been cleared reads as NA, which would reach
    ## brms and fail there rather than here.
    if (!isTruthy(input$cores) || input$cores < 1) {
      showNotification("Cores must be at least 1.", type = "warning")
      return()
    }
    if (!isTruthy(input$chains) || input$chains < 2) {
      showNotification(
        "At least 2 sampling chains are needed.",
        type = "warning"
      )
      return()
    }

    path <- normalizePath(workbook_path(), winslash = "/")
    logf <- tempfile("toxtools_run_", fileext = ".log")
    dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
    dir <- file.path(
      config$output_dir,
      safe_name(tools::file_path_sans_ext(basename(path)))
    )

    call_args <- list(
      path = path,
      output_dir = normalizePath(config$output_dir, winslash = "/"),
      sheets = input$sheets,
      model = input$model,
      predictor_transform = input$transform,
      ecx_vals = as.numeric(input$ecx_vals),
      refit = isTRUE(input$refit),
      render = TRUE,
      format = input$format,
      backend = input$backend,
      chains = input$chains,
      cores = input$cores,
      refresh = 0
    )

    ## supervise = TRUE so that the fitting process is stopped if this R
    ## session exits without the Stop button having been used; an orphaned
    ## CmdStan job would otherwise keep several cores busy indefinitely.
    ## stderr is folded into stdout because message() writes there, and the
    ## progress shown here is written with message().
    proc <- tryCatch(
      callr::r_bg(
        func = job_fun,
        args = list(
          args = list(
            dev_dir = config$dev_dir,
            call_args = call_args
          )
        ),
        stdout = logf,
        stderr = "2>&1",
        wd = config$wd,
        supervise = TRUE
      ),
      error = function(e) {
        showNotification(
          paste("The analysis could not be started:", conditionMessage(e)),
          type = "error",
          duration = NULL
        )
        NULL
      }
    )
    req(proc)

    job(proc)
    log_file(logf)
    run_dir(dir)
    run_format(input$format)
    n_requested(length(input$sheets))
    exit_status(NULL)
    state("running")
    nav_select("tabs", "Progress")
  })

  observeEvent(input$stop, {
    p <- job()
    if (!is.null(p) && p$is_alive()) {
      p$kill()
      showNotification("The analysis was stopped.", type = "warning")
    }
  })

  ## One second is frequent enough for a job measured in tens of minutes, and
  ## cheap: it reads one small text file and lists one directory.
  observe({
    ## Nothing to poll before a run starts, and nothing once one has finished.
    ## Without the second case the observer re-arms its timer on the
    ## transition to "done" and then ticks once a second for the life of the
    ## session.
    if (identical(state(), "idle") || identical(state(), "done")) {
      return()
    }
    invalidateLater(1000, session)
    p <- isolate(job())
    if (is.null(p)) {
      return()
    }
    if (p$is_alive()) {
      tick(isolate(tick()) + 1)
      return()
    }
    if (is.null(isolate(exit_status()))) {
      exit_status(tryCatch(p$get_exit_status(), error = function(e) {
        NA_integer_
      }))
      state("done")
      tick(isolate(tick()) + 1)
      if (isTRUE(isolate(exit_status()) == 0)) {
        nav_select("tabs", "Results")
      }
    }
  })

  output$log <- renderText({
    tick()
    f <- log_file()
    if (is.null(f) || !file.exists(f)) {
      return("")
    }
    paste(utils::tail(readLines(f, warn = FALSE), 400), collapse = "\n")
  })

  n_done <- reactive({
    tick()
    d <- run_dir()
    if (is.null(d)) {
      return(0L)
    }
    length(list.files(file.path(d, "fits"), pattern = "\\.rds$"))
  })

  output$status <- renderUI({
    st <- state()
    if (identical(st, "idle")) {
      return(div(class = "text-muted", "Not started."))
    }
    if (identical(st, "running")) {
      return(tagList(
        div(
          class = "text-primary",
          sprintf("Running: %d of %d sheets fitted.", n_done(), n_requested())
        ),
        div(
          class = "text-muted small",
          paste(
            "This takes twenty to forty minutes per sheet.",
            "The page can be left open."
          )
        )
      ))
    }
    if (isTRUE(exit_status() == 0)) {
      ## A run that skipped a sheet still exits cleanly, so "Finished" on its
      ## own would be misleading. The reasons are in the Progress log and in
      ## the report's first table.
      failed <- tryCatch(names(manifest()$failures), error = function(e) NULL)
      if (length(failed) > 0) {
        tagList(
          div(class = "text-success", "Finished."),
          div(
            class = "text-warning small",
            paste0(
              length(failed),
              " sheet(s) were not analysed: ",
              paste(failed, collapse = ", "),
              ". The Progress tab gives the reason."
            )
          )
        )
      } else {
        div(class = "text-success", "Finished.")
      }
    } else {
      div(
        class = "text-danger",
        "Stopped before finishing. The Progress tab holds the messages."
      )
    }
  })

  output$progress_note <- renderUI({
    if (identical(state(), "idle")) {
      helpText("Messages from the analysis appear here once it is started.")
    } else {
      helpText(paste(
        "Messages from the analysis. Warnings about pareto_k and p_waic come",
        "from the model comparison and are usual on a small dataset."
      ))
    }
  })

  ## ---- Results -------------------------------------------------------------

  manifest <- reactive({
    tick()
    d <- run_dir()
    if (is.null(d)) {
      return(NULL)
    }
    f <- file.path(d, "manifest.rds")
    if (!file.exists(f)) {
      return(NULL)
    }
    tryCatch(readRDS(f), error = function(e) NULL)
  })

  output$results_ui <- renderUI({
    m <- manifest()
    if (is.null(m)) {
      return(helpText("Results appear here when the analysis has finished."))
    }
    report <- report_file(m$run_dir, run_format())
    tagList(
      if (file.exists(report)) {
        downloadButton("download", "Download the report", class = "btn-primary")
      } else {
        helpText("The report has not been written yet.")
      },
      hr(),
      selectInput(
        "result_sheet",
        "Sheet",
        choices = vapply(m$entries, function(e) e$sheet, character(1))
      ),
      h5("Estimates"),
      DT::DTOutput("result_estimates"),
      h5("Model-averaged fit"),
      plotOutput("result_plot", height = "420px"),
      h5("Individual equations"),
      plotOutput("result_all", height = "620px")
    )
  })

  entry <- reactive({
    m <- manifest()
    req(m, input$result_sheet)
    hit <- Filter(function(e) identical(e$sheet, input$result_sheet), m$entries)
    req(length(hit) == 1)
    hit[[1]]
  })

  ## A reactive holds its value until its dependencies change, so the fitted
  ## object is read from disk once per change of sheet rather than once per
  ## plot.
  fit_obj <- reactive({
    e <- entry()
    req(file.exists(e$fit_file))
    readRDS(e$fit_file)
  })

  output$result_estimates <- DT::renderDT({
    est <- entry()$estimates
    DT::datatable(
      data.frame(
        Estimate = est$estimate,
        Median = signif(est$value, 3),
        `Lower 95%` = signif(est$lower, 3),
        `Upper 95%` = signif(est$upper, 3),
        check.names = FALSE
      ),
      rownames = FALSE,
      selection = "none",
      options = list(dom = "t", paging = FALSE, ordering = FALSE)
    )
  })

  output$result_plot <- renderPlot({
    toxtools::plot_workbook_fit(fit_obj(), estimates = entry()$estimates)
  })

  output$result_all <- renderPlot({
    toxtools::plot_workbook_fit(fit_obj(), all_models = TRUE)
  })

  output$download <- downloadHandler(
    filename = function() {
      paste0(
        tools::file_path_sans_ext(manifest()$workbook),
        "_report.",
        if (identical(run_format(), "html")) "html" else "pdf"
      )
    },
    content = function(file) {
      file.copy(
        report_file(manifest()$run_dir, run_format()),
        file,
        overwrite = TRUE
      )
    }
  )

  ## Stopping the app stops the fit. Closing the browser tab does not: the
  ## session ends but the app, and so the process it supervises, keeps going.
  onStop(function() {
    p <- isolate(job())
    if (!is.null(p) && p$is_alive()) {
      p$kill()
    }
  })
}

shinyApp(ui, server)
