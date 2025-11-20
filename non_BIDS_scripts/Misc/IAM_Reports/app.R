library(shiny)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(DT)

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
    demo <- read.csv(input$demographics$datapath, stringsAsFactors = FALSE)
    
    demo <- demo %>%
      mutate(
        Wave = `Is this participant part of Wave 1 or Wave 2?`,
        Sex = case_when(`7. Subject's sex:` %in% c("1 Male","2 Male","Male") ~ "Male",
                        `7. Subject's sex:` %in% c("1 Female","2 Female","Female") ~ "Female",
                        TRUE ~ NA_character_),
        Race = case_when(
          Wave == "Wave 1" & `9. What does subject report as his or her race?` != "" ~ `9. What does subject report as his or her race?`,
          Wave == "Wave 2" ~ paste(
            c(`White`,`Black or African American`,`American Indian or Alaska Native (AIAN)`,
              `Native Hawaiian or other Pacific Islander`,`Asian`,`Hispanic`)[
                c(`White`,`Black or African American`,`American Indian or Alaska Native (AIAN)`,
                  `Native Hawaiian or other Pacific Islander`,`Asian`,`Hispanic`) == "Yes"
              ], collapse = ", "
          ),
          TRUE ~ NA_character_
        ),
        Race = ifelse(str_detect(Race, ","), "Multiracial", Race),
        Year = 0,
        Cognition = "Normal"   # Year 0 has no MCI data
      ) %>%
      select(StudyID = `Study ID`, Wave, Sex, Race, Year, Cognition)
    
    demo
  })
  
  # ---------- Clean Cognition Data ----------
  clean_dx <- reactive({
    req(input$dx_y2, input$dx_y4, input$dx_y6)
    
    process_dx <- function(file, year) {
      df <- read.csv(file$datapath, stringsAsFactors = FALSE)
      df <- df %>%
        mutate(
          StudyID = str_remove(`Record ID`, "[b-d]$"),
          Year = year,
          Cognition = case_when(
            `2. Does the subject have normal cognition (global CDR=0 and/or neuropsychological testing within normal range) and normal behavior (i.e., the subject does not exhibit behavior sufficient to diagnose MCI or dementia due to FTLD or LBD)?` %in% c("0 No","0 No   <b>(CONTINUE TO QUESTION 3)</b>") ~ "Normal",
            rowSums(select(., starts_with("5a"), starts_with("5b"), starts_with("5c"), starts_with("5d"), starts_with("5e")) == "1 Present", na.rm = TRUE) > 0 ~ "MCI",
            TRUE ~ NA_character_
          )
        ) %>%
        select(StudyID, Year, Cognition)
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
    full_join(demo, dx, by = c("StudyID","Year")) %>%
      group_by(StudyID) %>%
      fill(Wave, Sex, Race, .direction = "downup") %>%
      ungroup()
  })
  
  # ---------- Apply Filters ----------
  filtered_data <- reactive({
    df <- merged_data()
    if(input$filter_wave != "All") df <- df %>% filter(Wave == input$filter_wave)
    if(input$filter_sex != "All") df <- df %>% filter(Sex == input$filter_sex)
    if(input$filter_race != "All") df <- df %>% filter(Race == input$filter_race)
    df
  })
  
  # ---------- Summary Table ----------
  output$summary_table <- renderDT({
    df <- filtered_data()
    
    race_levels <- c("White","Black","Asian","Native Hawaiian/PI","AIAN","Hispanic","Multiracial")
    df <- df %>%
      mutate(Race = case_when(
        str_detect(Race, "White") ~ "White",
        str_detect(Race, "Black") ~ "Black",
        str_detect(Race, "Asian") ~ "Asian",
        str_detect(Race, "Native Hawaiian") ~ "Native Hawaiian/PI",
        str_detect(Race, "AIAN") ~ "AIAN",
        str_detect(Race, "Hispanic") ~ "Hispanic",
        Race == "Multiracial" ~ "Multiracial",
        TRUE ~ NA_character_
      ))
    
    summarize_wave <- function(wave_name, df_wave) {
      baseline <- df_wave %>%
        filter(Year == 0) %>%
        group_by(Sex, Race) %>%
        summarize(Total = n(), .groups = "drop") %>%
        complete(Sex = c("Male","Female"), Race = race_levels, fill = list(Total = 0))
      
      mci_years <- df_wave %>%
        filter(Cognition == "MCI") %>%
        group_by(Year, Sex, Race) %>%
        summarize(MCI = n(), .groups = "drop") %>%
        complete(Year = c(2,4,6), Sex = c("Male","Female"), Race = race_levels, fill = list(MCI = 0))
      
      total_mci <- mci_years %>%
        group_by(Sex, Race) %>%
        summarize(Total_MCI = sum(MCI, na.rm = TRUE), .groups = "drop")
      
      table_wave <- baseline %>%
        left_join(mci_years %>% pivot_wider(names_from = Year, values_from = MCI, names_prefix = "Y"), by = c("Sex","Race")) %>%
        left_join(total_mci, by = c("Sex","Race")) %>%
        arrange(Sex, factor(Race, levels = race_levels)) %>%
        mutate(Wave = wave_name) %>%
        select(Wave, Sex, Race, Total, Y2, Y4, Y6, Total_MCI)
      
      table_wave
    }
    
    wave1 <- summarize_wave("Wave 1", df %>% filter(Wave == "Wave 1"))
    wave2 <- summarize_wave("Wave 2", df %>% filter(Wave == "Wave 2"))
    all_waves <- summarize_wave("All Waves", df)
    
    final_table <- bind_rows(wave1, wave2, all_waves)
    
    datatable(final_table, options = list(pageLength = 50), rownames = FALSE)
  })
  
  # ---------- Demographics Plot ----------
  output$demo_plot <- renderPlot({
    df <- filtered_data() %>% filter(Year == 0)
    ggplot(df, aes(x = Race, fill = Sex)) +
      geom_bar(position = "dodge") +
      facet_wrap(~Wave) +
      labs(title = "Baseline Demographics by Sex and Race", y = "Count") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })
  
  # ---------- MCI Progression Plot ----------
  output$mci_plot <- renderPlot({
    df <- filtered_data() %>%
      filter(Cognition == "MCI") %>%
      group_by(Year, Sex, Race) %>%
      summarize(MCI_count = n(), .groups = "drop") %>%
      mutate(Race = factor(Race, levels = c("White","Black","Asian","Native Hawaiian/PI","AIAN","Hispanic","Multiracial")))
    
    ggplot(df, aes(x = Year, y = MCI_count, color = Sex, group = Sex)) +
      geom_line() +
      geom_point() +
      facet_wrap(~Race) +
      labs(title = "MCI Progression Over Time by Sex and Race", y = "MCI Count") +
      theme_minimal()
  })
  
}

shinyApp(ui, server)
