#-----------------------
# IAM Pantry (v2.1)
#-----------------------
library(shiny)
library(dplyr)
library(tidyr)
library(DT)
library(ggplot2)
library(readr)

# --- Preferred labels ---
label_map <- c(
  wave = "Wave",
  age = "Age",
  ivp_a2_coparticipant_demographics_complete = "Co-P Demographics",
  ivp_a3_subject_family_history_complete = "Family History",
  ivp_a4_subject_medications_complete = "Medications",
  ivp_a5_subject_health_history_complete = "Health History",
  promis_sf_v10_physical_function_short_form_12a_complete = "Physical Fx",
  promis_sf_v20_ability_to_participate_social_8_e552_complete = "Ability to Participate Social",
  ecog_1 = "Ecog",
  c19diag = "COVID-19 Survey",
  nex_vit = "Vitals",
  apoe_collectiondate = "APOE",
  topf = "TOPF",
  det_ss = "DET",
  cdrglob = "CDR",
  qdrs_total = "QDRS",
  npiqinf = "NPI",
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

# --- UI ---
ui <- fluidPage(
  titlePanel("Data Completeness Dashboard"),
  
  sidebarLayout(
    sidebarPanel(
      fileInput("datafile", "Upload CSV", accept = ".csv"),
      checkboxGroupInput("waves", "Select Waves", choices = c(1,2), selected = c(1,2)),
      uiOutput("age_slider_ui"),
      checkboxInput("show_percent", "Show Percent Instead of Counts", FALSE),
      selectInput("var_to_plot", "Select Variable for Age Distribution", choices = NULL),
      downloadButton("downloadTable", "Download Table")
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Summary Table", DTOutput("summaryTable")),
        tabPanel("Bar Plot", plotOutput("completenessBarPlot", height = "600px")),
        tabPanel("Age Distribution", plotOutput("ageDistribution", height = "600px"))
      )
    )
  )
)

# --- Server ---
server <- function(input, output, session) {
  
  # --- Load and rename data safely ---
  data <- reactive({
    req(input$datafile)
    df <- read_csv(input$datafile$datapath, show_col_types = FALSE)
    
    # Standardize column names
    names(df) <- tolower(gsub("\\s+", "_", names(df)))
    
    # Safe rename using label_map
    existing_cols <- intersect(names(label_map), names(df))
    if(length(existing_cols) > 0){
      rename_vec <- setNames(existing_cols, label_map[existing_cols])
      df <- df %>% rename(!!!rename_vec)
    }
    
    # Ensure Wave and Age exist
    if(!("Wave" %in% names(df))) df$Wave <- NA
    if(!("Age" %in% names(df))) df$Age <- NA_real_
    
    df
  })
  
  # --- Dynamic age slider ---
  output$age_slider_ui <- renderUI({
    df <- data()
    req("Age" %in% names(df), any(!is.na(df$Age)))
    sliderInput("age_filter", "Select Age Range",
                min = floor(min(df$Age, na.rm = TRUE)),
                max = ceiling(max(df$Age, na.rm = TRUE)),
                value = c(floor(min(df$Age, na.rm = TRUE)), ceiling(max(df$Age, na.rm = TRUE))))
  })
  
  # --- Update variable selector ---
  observeEvent(data(), {
    df <- data()
    vars <- setdiff(names(df), c("Wave", "Age"))
    updateSelectInput(session, "var_to_plot", choices = vars)
  })
  
  # --- Filtered data ---
  filtered_data <- reactive({
    df <- data()
    req("Wave" %in% names(df), "Age" %in% names(df))
    df %>% filter(Wave %in% input$waves,
                  Age >= input$age_filter[1],
                  Age <= input$age_filter[2])
  })
  
  # --- Completeness calculation ---
  completeness <- reactive({
    df <- filtered_data()
    n_total <- nrow(df)
    
    df_summary <- df %>%
      summarise(across(everything(), ~{
        colname <- cur_column()
        if(colname %in% c("Wave", "Age")) return(NA)
        else if(grepl("mri_sequences", colname, ignore.case = TRUE)) {
          sum(. == 1, na.rm = TRUE)
        } else {
          sum(!is.na(as.character(.)) & trimws(as.character(.)) != "", na.rm = TRUE)
        }
      }))
    
    df_summary_long <- df_summary %>%
      pivot_longer(everything(), names_to = "Variable", values_to = "N_available") %>%
      mutate(Percent = N_available / n_total * 100)
    
    df_summary_long
  })
  
  # --- Outputs ---
  output$summaryTable <- renderDT({
    datatable(completeness(), rownames = FALSE, options = list(pageLength = 20))
  })
  
  output$completenessBarPlot <- renderPlot({
    df <- completeness()
    metric <- if(input$show_percent) "Percent" else "N_available"
    y_label <- if(input$show_percent) "% Complete" else "Number Available"
    
    ggplot(df, aes(x = reorder(Variable, .data[[metric]]), y = .data[[metric]])) +
      geom_col(fill = "#eb851e") +
      coord_flip() +
      theme_minimal(base_size = 14) +
      labs(title = "Data Completeness by Measure",
           x = "Data Type", y = y_label)
  })
  
  output$ageDistribution <- renderPlot({
    req(input$var_to_plot)
    df <- filtered_data()
    var <- input$var_to_plot
    
    df$has_data <- !is.na(as.character(df[[var]])) & trimws(as.character(df[[var]])) != ""
    
    ggplot(df, aes(x = Age, fill = has_data)) +
      geom_histogram(position = "identity", alpha = 0.6, bins = 25) +
      scale_fill_manual(values = c("#00447b", "#eb851e"),
                        labels = c("Missing", "Available")) +
      theme_minimal(base_size = 14) +
      labs(title = paste("Age Distribution by", var, "Completeness"),
           x = "Age", y = "Count", fill = "Data Status")
  })
  
  # --- Download Table ---
  output$downloadTable <- downloadHandler(
    filename = function() {"data_completeness.csv"},
    content = function(file) {
      write.csv(completeness(), file, row.names = FALSE)
    }
  )
}

# --- Run App ---
shinyApp(ui, server)
