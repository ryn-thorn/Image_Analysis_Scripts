# ==============================
# IAM Recruitment and Retention (v1.7)
# rsconnect::deployApp(
#  appDir = "/Volumes/helpern_share/Image_Analysis_Scripts/Misc/IAM_Reports_app",
#  appName = "iam_reports_app"
#)
# ==============================

library(shiny)
library(dplyr)
library(ggplot2)
library(DT)
library(stringr)
library(readr)
library(janitor)
library(tidyr)
library(ggmosaic)
library(plotly)

# --- UI ---
ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body { font-size: 18px; }
      .shiny-input-container { font-size: 16px; }
      h2, h3, h4 { font-weight: 600; margin-top: 20px; }
      .dataTables_wrapper { font-size: 16px; }
    "))
  ),
  
  titlePanel("IAM Recruitment and Retention"),
  
  sidebarLayout(
    sidebarPanel(
      fileInput("datafile", "Upload REDCap Export (CSV)", accept = ".csv"),
      selectInput("wave", "Select Wave", choices = c("All", "Wave 1", "Wave 2")),
      selectInput("plot_type", "Plot Type", 
                  choices = c("Race by Wave", "Sex by Wave", "Withdrawals by Year",
                              "Age Boxplot/Violin", "Age Histogram", "Mosaic Plot")),
      checkboxInput("show_crosstabs", "Show Cross Tabs", value = FALSE),
      sliderInput("age_filter", "Age Range", min = 0, max = 100, value = c(0, 100)),
      downloadButton("download_summary", "Download Summary (CSV)")
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Summary Table", 
                 h3("Demographic Summary"),
                 DTOutput("summaryTable"),
                 h3("Plot"),
                 plotlyOutput("plot")),
        
        tabPanel("Cross Tabs", 
                 conditionalPanel(
                   condition = "input.show_crosstabs == true",
                   h3("Cross Tabulation Table"),
                   DTOutput("crossTable"),
                   
                   h3("Cross Tabulation Plot: Race × Sex"),
                   plotlyOutput("crossPlot"),
                   
                   h3("Cross Tabulation Plot: Race × Withdraw Year"),
                   plotlyOutput("crossPlot2")
                 ),
                 conditionalPanel(
                   condition = "input.show_crosstabs == false",
                   h4("Enable 'Show Cross Tabs' in the sidebar to view these results.")
                 )
        )
      )
    )
  )
)

# --- SERVER ---
server <- function(input, output) {
  
  # Load and clean data
  data <- reactive({
    req(input$datafile)
    df <- read_csv(input$datafile$datapath, show_col_types = FALSE)
    df <- df %>% clean_names()
    df <- df %>% rename(wave = is_this_participant_part_of_wave_1_or_wave_2)
    
    # Harmonize columns across waves and normalize race
    df <- df %>%
      mutate(
        # Detect multiple races
        multi_race = case_when(
          wave == "Wave 2" ~ (
            rowSums(across(
              c(white, black_or_african_american, asian,
                american_indian_or_alaska_native_aian,
                native_hawaiian_or_other_pacific_islander),
              ~ .x == "Yes"
            ), na.rm = TRUE) > 1
          ),
          wave == "Wave 1" ~ str_detect(x9_what_does_subject_report_as_his_or_her_race, ";|,| and "),
          TRUE ~ FALSE
        ),
        
        # Assign race
        race = case_when(
          multi_race ~ "More Than One Race",
          wave == "Wave 1" ~ x9_what_does_subject_report_as_his_or_her_race,
          wave == "Wave 2" ~ case_when(
            white == "Yes" ~ "White",
            black_or_african_american == "Yes" ~ "Black or African American",
            asian == "Yes" ~ "Asian",
            american_indian_or_alaska_native_aian == "Yes" ~ "American Indian or Alaska Native",
            native_hawaiian_or_other_pacific_islander == "Yes" ~ "Native Hawaiian or Pacific Islander",
            TRUE ~ "Other/Unknown"
          ),
          TRUE ~ NA_character_
        ),
        
        # Normalize race labels and account for Hispanic fields
        race = case_when(
          race %in% c("1 White", "White") ~ "White",
          race %in% c("2 Black or African American", "Black or African American") ~ "Black or African American",
          race %in% c("5 Asian", "Asian") ~ "Asian",
          race %in% c("American Indian or Alaska Native", "3 American Indian or Alaska Native") ~ "American Indian or Alaska Native",
          race %in% c("Native Hawaiian or Pacific Islander", "4 Native Hawaiian or other Pacific Islander") ~ "Native Hawaiian or Pacific Islander",
          
          # Hispanic from either column
          hispanic == "1" | hispanic == "Yes" ~ "Hispanic",
          x8_does_the_subject_report_being_of_hispanic_latino_ethnicity_i_e_having_origins_from_a_mainly_spanish_speaking_latin_american_country_regardless_of_race == "1 Yes" ~ "Hispanic",
          
          TRUE ~ race
        ),
        
        sex = case_when(
          wave == "Wave 1" ~ case_when(
            str_detect(x7_subjects_sex, "1") ~ "Male",
            str_detect(x7_subjects_sex, "2") ~ "Female",
            TRUE ~ NA_character_
          ),
          wave == "Wave 2" ~ case_when(
            man == "Yes" ~ "Male",
            woman == "Yes" ~ "Female",
            TRUE ~ NA_character_
          ),
          TRUE ~ NA_character_
        ),
        
        withdraw_year = str_extract(
          did_the_participant_withdraw_withdraw_participant_no_longer_wants_to_be_part_of_the_iam_study,
          "Y[0-9]"
        ),
        
        age = as.numeric(age)
      )
    
    # Filter by wave
    if (input$wave != "All") df <- df %>% filter(wave == input$wave)
    
    # Filter by age range
    df <- df %>% filter(age >= input$age_filter[1], age <= input$age_filter[2])
    
    df
  })
  
  # --- Summary Table ---
  output$summaryTable <- renderDT({
    data() %>%
      count(wave, sex, race, withdraw_year, name = "Count") %>%
      datatable(options = list(pageLength = 10))
  })
  
  # --- Main Plot ---
  output$plot <- renderPlotly({
    df <- data()
    
    p <- switch(input$plot_type,
                "Race by Wave" = ggplot(df %>% filter(!is.na(race)), aes(x = race, fill = wave)) +
                  geom_bar(position = "dodge") + coord_flip() +
                  theme_minimal(base_size = 16) +
                  labs(x = "Race", y = "Count", title = "Race by Wave"),
                
                "Sex by Wave" = ggplot(df %>% filter(!is.na(sex)), aes(x = sex, fill = wave)) +
                  geom_bar(position = "dodge") +
                  theme_minimal(base_size = 16) +
                  labs(x = "Sex", y = "Count", title = "Sex by Wave"),
                
                "Withdrawals by Year" = ggplot(df %>% filter(!is.na(withdraw_year)), aes(x = withdraw_year, fill = wave)) +
                  geom_bar(position = "dodge") +
                  theme_minimal(base_size = 16) +
                  labs(x = "Withdrawal Year", y = "Count", title = "Withdrawals by Year"),
                
                "Age Boxplot/Violin" = ggplot(df %>% filter(!is.na(age)), aes(x = wave, y = age, fill = wave)) +
                  geom_violin(alpha = 0.4) +
                  geom_boxplot(width = 0.1, fill = "white", outlier.shape = 1) +
                  theme_minimal(base_size = 16) +
                  labs(x = "Wave", y = "Age", title = "Age Distribution by Wave"),
                
                "Age Histogram" = ggplot(df %>% filter(!is.na(age)), aes(x = age, fill = wave)) +
                  geom_histogram(position = "identity", alpha = 0.6, bins = 20) +
                  theme_minimal(base_size = 16) +
                  labs(x = "Age", y = "Count", title = "Histogram of Age"),
                
                "Mosaic Plot" = {
                  df_mosaic <- df %>% filter(!is.na(race), !is.na(sex), !is.na(withdraw_year))
                  ggplot(df_mosaic) +
                    geom_mosaic(aes(weight = 1, x = product(race, sex), fill = withdraw_year)) +
                    theme_minimal(base_size = 16) +
                    labs(x = "Race × Sex", y = "Proportion", fill = "Withdraw Year", title = "Mosaic Plot: Race × Sex × Withdraw Year")
                }
    )
    
    ggplotly(p, tooltip = "y") # Make interactive
  })
  
  # --- Cross Tabs ---
  output$crossTable <- renderDT({
    req(input$show_crosstabs)
    data() %>%
      count(wave, sex, race, withdraw_year, name = "Count") %>%
      pivot_wider(names_from = withdraw_year, values_from = Count, values_fill = 0) %>%
      datatable(options = list(pageLength = 10))
  })
  
  output$crossPlot <- renderPlotly({
    req(input$show_crosstabs)
    df <- data()
    p <- ggplot(df %>% filter(!is.na(sex), !is.na(race)), aes(x = race, fill = sex)) +
      geom_bar(position = "dodge") +
      facet_wrap(~ wave) +
      theme_minimal(base_size = 16) +
      coord_flip() +
      labs(x = "Race", y = "Count", fill = "Sex", title = "Cross Tab: Race × Sex by Wave")
    ggplotly(p, tooltip = "y")
  })
  
  output$crossPlot2 <- renderPlotly({
    req(input$show_crosstabs)
    df <- data()
    df_plot <- df %>% filter(!is.na(race), !is.na(withdraw_year))
    p <- ggplot(df_plot, aes(x = race, fill = withdraw_year)) +
      geom_bar(position = "dodge") +
      facet_wrap(~ wave) +
      theme_minimal(base_size = 16) +
      coord_flip() +
      labs(x = "Race", y = "Count", fill = "Withdrawal Year", title = "Cross Tab: Race × Withdraw Year by Wave")
    ggplotly(p, tooltip = "y")
  })
  
  # --- Download Button ---
  output$download_summary <- downloadHandler(
    filename = function() {
      paste0("IAM_Demographics_Summary_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write_csv(data() %>% count(wave, sex, race, withdraw_year, age, name = "Count"), file)
    }
  )
}

# --- Run App ---
shinyApp(ui, server)
