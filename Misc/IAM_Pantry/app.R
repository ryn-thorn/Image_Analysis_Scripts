#-----------------------
# IAM Pantry (v3.7)
# Multi-timepoint, crash-proof with Preferred Labels
#-----------------------
library(shiny)
library(dplyr)
library(tidyr)
library(DT)
library(ggplot2)
library(readr)
library(stringr)

# --- Preferred labels ---
label_map <- c(
  wave = "Wave",
  age = "Age",
  ivp_a2_coparticipant_demographics_complete = "Co-P Demographics",
  fvp_a2_coparticipant_demographics_complete = "Co-P Demographics",
  ivp_a3_subject_family_history_complete = "Family History",
  fvp_a3_subject_family_history_complete = "Family History",
  ivp_a4_subject_medications_complete = "Medications",
  ivp_a5_subject_health_history_complete = "Health History",
  promis_sf_v10_physical_function_short_form_12a_complete = "Physical Fx",
  promis_sf_v20_ability_to_participate_social_8_e552_complete = "Ability to Participate Social",
  promis_sf_v20_ability_to_participate_social_8a_complete = "Ability to Participate Social",
  ecog_1 = "Ecog",
  c19diag = "COVID-19 Survey",
  cov_1 = "COVID-19 Survey",
  nex_vit = "Vitals",
  apoe_collectiondate = "APOE",
  topf = "TOPF",
  det_ss = "DET",
  cdrglob = "CDR",
  qdrs_total = "QDRS",
  npiqinf = "NPI",
  npiq_complete = "NPI",
  gds_1 = "GDS",
  faq_1 = "FAQ",
  date_pet = "PET",
  date_mri_read = "MRI Reads",
  date_mri = "MRI",
  mri_sequences___1 = "T2",
  mri_sequences___2 = "DKI BIPOLAR 64dir",
  mri_sequences___3 = "DKI BIPOLAR 64dir TOPUP",
  mri_sequences___4 = "FBI B6000",
  mri_sequences___5 = "DKI MONOPOLAR 30dir",
  mri_sequences___6 = "DKI MONOPOLAR 30dir TOPUP",
  mri_sequences___7 = "T1 MPRAGE",
  mri_sequences___8 = "ViSTa",
  mri_sequences___9 = "ViSTa REF",
  mri_sequences___10 = "SVS 2cm PC",
  mri_sequences___11 = "SVS water off 2cm PC",
  mri_sequences___12 = "SVS 2cm hippocampus",
  mri_sequences___13 = "SVS water off 2cm hippocampus",
  mri_sequences___14 = "fMRI task",
  mri_sequences___15 = "fMRI Resting State 1",
  mri_sequences___16 = "fMRI Resting State 2"
)

# --- Helper to get preferred label safely ---
get_label <- function(var) {
  if (var %in% names(label_map)) label_map[[var]] else var
}

# --- UI ---
ui <- fluidPage(
  titlePanel("IAM Pantry — Multi-Timepoint"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Upload Data by Timepoint"),
      fileInput("data_y0", "Upload Y0 CSV", accept = ".csv"),
      fileInput("data_y2", "Upload Y2 CSV", accept = ".csv"),
      fileInput("data_y4", "Upload Y4 CSV", accept = ".csv"),
      fileInput("data_y6", "Upload Y6 CSV", accept = ".csv"),
      
      checkboxGroupInput("timepoints", "Select Timepoints",
                         choices = c("Y0", "Y2", "Y4", "Y6"),
                         selected = c("Y0", "Y2", "Y4", "Y6")),
      uiOutput("age_slider_ui"),
      checkboxInput("show_percent", "Show Percent Instead of Counts", FALSE),
      selectInput("var_to_plot", "Select Variable for Age Distribution", choices = NULL),
      downloadButton("downloadTable", "Download Table")
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Summary Table", DTOutput("summaryTable")),
        tabPanel("Bar Plot", plotOutput("completenessBarPlot", height = "600px")),
        tabPanel("Age Distribution", plotOutput("ageDistribution", height = "600px")),
        tabPanel("Completeness Over Time", plotOutput("trendPlot", height = "600px"))
      )
    )
  )
)

# --- Server ---
server <- function(input, output, session) {
  options(shiny.sanitize.errors = TRUE)
  
  # --- Safe CSV loader ---
  safe_read_csv <- function(file, tp_label) {
    if (is.null(file)) return(NULL)
    df <- tryCatch({
      read_csv(file$datapath, show_col_types = FALSE)
    }, error = function(e) {
      showNotification(paste("Error reading", tp_label, ":", e$message), type = "error")
      return(NULL)
    })
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    names(df) <- tolower(gsub("\\s+", "_", names(df)))
    
    if (!("studyid" %in% names(df))) {
      if ("record_id" %in% names(df)) df <- df %>% rename(studyid = record_id)
      else df$studyid <- NA
    }
    if (!("age" %in% names(df))) df$age <- NA_real_
    else df$age <- suppressWarnings(as.numeric(df$age))
    if (!("wave" %in% names(df))) df$wave <- NA
    
    df$timepoint <- tp_label
    df
  }
  
  # --- Harmonize columns ---
  harmonize_dfs <- function(dfs) {
    all_cols <- unique(unlist(lapply(dfs, names)))
    dfs <- lapply(dfs, function(df) {
      missing <- setdiff(all_cols, names(df))
      if (length(missing) > 0) df[missing] <- NA_character_
      df <- df %>%
        mutate(across(setdiff(names(df), c("age", "wave", "timepoint", "studyid")), as.character))
      if ("age" %in% names(df)) df$age <- suppressWarnings(as.numeric(df$age))
      if ("wave" %in% names(df)) df$wave <- suppressWarnings(as.numeric(df$wave))
      df[all_cols]
    })
    bind_rows(dfs)
  }
  
  # --- Combine CSVs ---
  data_all <- reactive({
    dfs <- list(
      Y0 = safe_read_csv(input$data_y0, "Y0"),
      Y2 = safe_read_csv(input$data_y2, "Y2"),
      Y4 = safe_read_csv(input$data_y4, "Y4"),
      Y6 = safe_read_csv(input$data_y6, "Y6")
    )
    dfs <- dfs[!sapply(dfs, is.null)]
    validate(need(length(dfs) > 0, "Please upload at least one CSV."))
    harmonize_dfs(dfs)
  })
  
  # --- Age slider ---
  output$age_slider_ui <- renderUI({
    df <- data_all()
    validate(need("age" %in% names(df), "No Age column found"))
    age_vals <- suppressWarnings(as.numeric(df$age))
    if (all(is.na(age_vals))) return(helpText("No valid ages found in uploaded data."))
    sliderInput("age_filter", "Select Age Range",
                min = floor(min(age_vals, na.rm = TRUE)),
                max = ceiling(max(age_vals, na.rm = TRUE)),
                value = c(floor(min(age_vals, na.rm = TRUE)), ceiling(max(age_vals, na.rm = TRUE))))
  })
  
  # --- Variable selector ---
  observeEvent(data_all(), {
    df <- data_all()
    vars <- setdiff(names(df), c("wave", "age", "timepoint", "studyid"))
    updateSelectInput(session, "var_to_plot",
                      choices = setNames(vars, sapply(vars, get_label)))
  })
  
  # --- Filtered data ---
  filtered_data <- reactive({
    df <- data_all()
    validate(need(nrow(df) > 0, "No data available"))
    df <- df %>% filter(timepoint %in% input$timepoints)
    if ("age" %in% names(df) && !all(is.na(df$age))) {
      df <- df %>% filter(age >= input$age_filter[1], age <= input$age_filter[2])
    }
    df
  })
  
  # --- Safe completeness ---
  safe_completeness <- function(df) {
    df_summary <- df %>%
      group_by(timepoint) %>%
      summarise(across(everything(), ~{
        col <- cur_column()
        if (col %in% c("wave", "age", "studyid", "timepoint")) return(NA_real_)
        vec <- df[[col]]
        sum(!is.na(vec) & trimws(as.character(vec)) != "", na.rm = TRUE)
      }))
    
    df_long <- df_summary %>%
      pivot_longer(-timepoint, names_to = "Variable", values_to = "N_available") %>%
      group_by(timepoint) %>%
      mutate(Total = max(N_available, na.rm = TRUE),
             Percent = ifelse(Total > 0, 100 * N_available / Total, 0))
    
    df_combined <- df %>%
      summarise(across(everything(), ~{
        col <- cur_column()
        if (col %in% c("wave", "age", "studyid", "timepoint")) return(NA_real_)
        vec <- df[[col]]
        sum(!is.na(vec) & trimws(as.character(vec)) != "", na.rm = TRUE)
      })) %>%
      pivot_longer(everything(), names_to = "Variable", values_to = "N_available") %>%
      mutate(timepoint = "Combined",
             Total = max(N_available, na.rm = TRUE),
             Percent = ifelse(Total > 0, 100 * N_available / Total, 0))
    
    df_out <- bind_rows(df_long, df_combined)
    df_out$Label <- sapply(df_out$Variable, get_label)
    df_out
  }
  
  completeness <- reactive({
    df <- filtered_data()
    safe_completeness(df)
  })
  
  # --- Outputs ---
  output$summaryTable <- renderDT({
    df <- completeness()
    df_display <- df %>% select(timepoint, Label, N_available, Percent)
    datatable(df_display, rownames = FALSE, options = list(pageLength = 20))
  })
  
  output$completenessBarPlot <- renderPlot({
    df <- completeness()
    metric <- if (input$show_percent) "Percent" else "N_available"
    y_label <- if (input$show_percent) "% Complete" else "Number Available"
    ggplot(df, aes(x = reorder(Label, .data[[metric]]), y = .data[[metric]], fill = timepoint)) +
      geom_col(position = "dodge") +
      coord_flip() +
      theme_minimal(base_size = 14) +
      labs(title = "Data Completeness by Measure and Timepoint",
           x = "Data Type", y = y_label)
  })
  
  output$ageDistribution <- renderPlot({
    req(input$var_to_plot)
    df <- filtered_data()
    var <- input$var_to_plot
    label <- get_label(var)
    df$has_data <- !is.na(as.character(df[[var]])) & trimws(as.character(df[[var]])) != ""
    ggplot(df, aes(x = age, fill = has_data)) +
      geom_histogram(position = "identity", alpha = 0.6, bins = 25) +
      scale_fill_manual(values = c("#00447b", "#eb851e"), labels = c("Missing", "Available")) +
      facet_wrap(~ timepoint) +
      theme_minimal(base_size = 14) +
      labs(title = paste("Age Distribution by", label, "Completeness"),
           x = "Age", y = "Count", fill = "Data Status")
  })
  
  output$trendPlot <- renderPlot({
    df <- completeness()
    ggplot(df, aes(x = timepoint, y = Percent, group = Label, color = Label)) +
      geom_line(alpha = 0.5) +
      geom_point() +
      theme_minimal(base_size = 14) +
      labs(title = "Completeness Trends Over Time",
           x = "Timepoint", y = "% Complete", color = "Measure")
  })
  
  output$downloadTable <- downloadHandler(
    filename = function() { "data_completeness.csv" },
    content = function(file) {
      write.csv(completeness(), file, row.names = FALSE)
    }
  )
}

# --- Run App ---
shinyApp(ui, server)
