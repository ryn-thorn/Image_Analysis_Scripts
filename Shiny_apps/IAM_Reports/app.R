library(shiny)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(DT)
library(janitor)

ui <- fluidPage(
  titlePanel("Demographics & Cognition Explorer"),
  
  sidebarLayout(
    sidebarPanel(
      fileInput("demographics", "Upload Y0 Demographics CSV"),
      fileInput("dx_y2", "Upload Cognition Y2 CSV"),
      fileInput("dx_y4", "Upload Cognition Y4 CSV"),
      fileInput("dx_y6", "Upload Cognition Y6 CSV"),
      
      hr(),
      h4("Filter Options"),
      selectInput("filter_wave", "Select Wave", choices = c("All","Wave 1","Wave 2"), selected = "All"),
      selectInput("filter_sex", "Select Sex", choices = c("All","Male","Female"), selected = "All"),
      selectInput("filter_race", "Select Race", choices = c("All","White","Black","Asian","Native Hawaiian/PI","AIAN","Hispanic","Multiracial"), selected = "All"),
      
      width = 3
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Summary Table", DTOutput("summary_table")),
        tabPanel("Demographics Plot", plotOutput("demo_plot")),
        tabPanel("MCI Progression Plot", plotOutput("mci_plot"))
      )
    )
  )
)

server <- function(input, output, session) {
  
  # ---------- Clean Demographics ----------
  clean_demographics <- reactive({
    req(input$demographics)
    demo <- read.csv(input$demographics$datapath, stringsAsFactors = FALSE) %>%
      janitor::clean_names()
    
    # Standardize ID column
    if ("study_id" %in% names(demo)) {
      demo$study_id <- demo$study_id
    } else if ("record_id" %in% names(demo)) {
      demo$study_id <- demo$record_id
    }
    
    # Determine sex
    demo <- demo %>%
      mutate(
        wave = is_this_participant_part_of_wave_1_or_wave_2,
        sex = case_when(
          x7_subject_s_sex %in% c("1 Male","2 Male","Male","1","1 male") ~ "Male",
          x7_subject_s_sex %in% c("1 Female","2 Female","Female","2","2 female") ~ "Female",
          TRUE ~ NA_character_
        ),
        # Race logic
        race = case_when(
          wave == "Wave 1" & x9_what_does_subject_report_as_his_or_her_race != "" ~ x9_what_does_subject_report_as_his_or_her_race,
          wave == "Wave 2" ~ paste(
            c(white, black_or_african_american, american_indian_or_alaska_native_aian,
              native_hawaiian_or_other_pacific_islander, asian, hispanic)[
                c(white, black_or_african_american, american_indian_or_alaska_native_aian,
                  native_hawaiian_or_other_pacific_islander, asian, hispanic) == "Yes"
              ], collapse = ", "
          ),
          TRUE ~ NA_character_
        ),
        race = ifelse(str_detect(race, ","), "Multiracial", race),
        year = 0,
        cognition = "Normal"
      ) %>%
      select(study_id, wave, sex, race, year, cognition)
    
    demo
  })
  
  # ---------- Clean Cognition Data ----------
  clean_dx <- reactive({
    req(input$dx_y2, input$dx_y4, input$dx_y6)
    
    process_dx <- function(file, year) {
      df <- read.csv(file$datapath, stringsAsFactors = FALSE) %>%
        janitor::clean_names()
      
      # Standardize ID column
      if ("record_id" %in% names(df)) {
        df$study_id <- df$record_id
      } else if ("study_id" %in% names(df)) {
        df$study_id <- df$study_id
      }
      
      # Cognition column detection
      normal_col <- names(df)[str_detect(names(df), "does_the_subject_have_normal_cognition")]
      mci_cols <- names(df)[str_detect(names(df), "^x5[a-e]")]
      
      df <- df %>%
        mutate(
          year = year,
          cognition = case_when(
            !!sym(normal_col) %in% c("0 No", "No") ~ "Normal",
            rowSums(select(., all_of(mci_cols)) == "1 Present", na.rm = TRUE) > 0 ~ "MCI",
            TRUE ~ NA_character_
          )
        ) %>%
        select(study_id, year, cognition)
      df
    }
    
    bind_rows(
      process_dx(input$dx_y2, 2),
      process_dx(input$dx_y4, 4),
      process_dx(input$dx_y6, 6)
    )
  })
  
  # ---------- Merge Data ----------
  merged_data <- reactive({
    demo <- clean_demographics()
    dx <- clean_dx()
    full_join(demo, dx, by = c("study_id","year")) %>%
      group_by(study_id) %>%
      fill(wave, sex, race, .direction = "downup") %>%
      ungroup()
  })
  
  # ---------- Apply Filters ----------
  filtered_data <- reactive({
    df <- merged_data()
    if(input$filter_wave != "All") df <- df %>% filter(wave == input$filter_wave)
    if(input$filter_sex != "All") df <- df %>% filter(sex == input$filter_sex)
    if(input$filter_race != "All") df <- df %>% filter(race == input$filter_race)
    df
  })
  
  # ---------- Summary Table ----------
  output$summary_table <- renderDT({
    df <- filtered_data()
    
    race_levels <- c("White","Black","Asian","Native Hawaiian/PI","AIAN","Hispanic","Multiracial")
    df <- df %>%
      mutate(race = case_when(
        str_detect(race, "White") ~ "White",
        str_detect(race, "Black") ~ "Black",
        str_detect(race, "Asian") ~ "Asian",
        str_detect(race, "Native Hawaiian") ~ "Native Hawaiian/PI",
        str_detect(race, "AIAN") ~ "AIAN",
        str_detect(race, "Hispanic") ~ "Hispanic",
        race == "Multiracial" ~ "Multiracial",
        TRUE ~ NA_character_
      ))
    
    summarize_wave <- function(wave_name, df_wave) {
      # Ensure cognition column exists
      if(!"cognition" %in% names(df_wave)) {
        df_wave <- df_wave %>% mutate(cognition = NA_character_)
      }
      
      race_levels <- c("White","Black","Asian","Native Hawaiian/PI","AIAN","Hispanic","Multiracial")
      
      # Baseline counts
      baseline <- df_wave %>%
        filter(year == 0) %>%
        group_by(sex, race) %>%
        summarize(Total = n(), .groups = "drop") %>%
        complete(sex = c("Male","Female"), race = race_levels, fill = list(Total = 0))
      
      # MCI counts
      mci_years <- df_wave %>%
        filter(!is.na(cognition) & cognition == "MCI") %>%
        group_by(year, sex, race) %>%
        summarize(MCI = n(), .groups = "drop") %>%
        complete(year = c(2,4,6), sex = c("Male","Female"), race = race_levels, fill = list(MCI = 0))
      
      total_mci <- mci_years %>%
        group_by(sex, race) %>%
        summarize(Total_MCI = sum(MCI, na.rm = TRUE), .groups = "drop")
      
      table_wave <- baseline %>%
        left_join(mci_years %>% pivot_wider(names_from = year, values_from = MCI, names_prefix = "Y"), by = c("sex","race")) %>%
        left_join(total_mci, by = c("sex","race")) %>%
        arrange(sex, factor(race, levels = race_levels)) %>%
        mutate(Wave = wave_name) %>%
        select(Wave, sex, race, Total, Y2, Y4, Y6, Total_MCI)
      
      table_wave
    }
    
    
    wave1 <- summarize_wave("Wave 1", df %>% filter(wave == "Wave 1"))
    wave2 <- summarize_wave("Wave 2", df %>% filter(wave == "Wave 2"))
    all_waves <- summarize_wave("All Waves", df)
    
    final_table <- bind_rows(wave1, wave2, all_waves)
    
    datatable(final_table, options = list(pageLength = 50), rownames = FALSE)
  })
  
  # ---------- Demographics Plot ----------
  output$demo_plot <- renderPlot({
    df <- filtered_data() %>% filter(year == 0)
    ggplot(df, aes(x = race, fill = sex)) +
      geom_bar(position = "dodge") +
      facet_wrap(~wave) +
      labs(title = "Baseline Demographics by Sex and Race", y = "Count") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })
  
  # ---------- MCI Progression Plot ----------
  output$mci_plot <- renderPlot({
    df <- filtered_data() %>%
      filter(cognition == "MCI") %>%
      group_by(year, sex, race) %>%
      summarize(MCI_count = n(), .groups = "drop") %>%
      mutate(race = factor(race, levels = c("White","Black","Asian","Native Hawaiian/PI","AIAN","Hispanic","Multiracial")))
    
    ggplot(df, aes(x = year, y = MCI_count, color = sex, group = sex)) +
      geom_line() +
      geom_point() +
      facet_wrap(~race) +
      labs(title = "MCI Progression Over Time by Sex and Race", y = "MCI Count") +
      theme_minimal()
  })
  
}

shinyApp(ui, server)
