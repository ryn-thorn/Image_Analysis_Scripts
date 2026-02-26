###R shiny application for demographics and recognition data of the IAM study 
###Yao & Ryn, 
###Dec




# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    https://shiny.posit.co/
#



library(shiny) 
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(DT)
library(janitor)


# Define dataset names for display
dataset_names <- list(
  y0 = "data_y0",
  y2 = "data_y2",
  y4 = "data_y4",
  y6 = "data_y6"
)



# source data cleaning code ------
source("cleaning.R")
# after sourcing, the environment will have a working dataset called data_clean,
 # and the dfs in dataset_names

 
colnames(data_clean)
# data_long %>% filter(Study.ID=="IAM_1001") %>% tibble() %>% as.data.frame() 


# ---------------------Define UI for application -----------
ui <- fluidPage (
  
  # 1. title 
  titlePanel("IAM Cohort Explorer") ,
  
  
  # 2. main content sections
  sidebarLayout(
    
    ## ------------INPUTS -------------#####
    # 2.1 sidebar panel 
    sidebarPanel(
      
      #### --- show loading data ----
      h4("Datasets loaded:"), # Main title for the panel
    
      # Use tagList to group multiple HTML elements together
      tagList(
        # The labels now use the descriptive name
        p(HTML(paste0("<b>Baseline:</b> ", dataset_names$y0))),
        p(HTML(paste0("<b>Year 2:</b> ", dataset_names$y2))),
        p(HTML(paste0("<b>Year 4:</b> ", dataset_names$y4))),
        p(HTML(paste0("<b>Year 6:</b> ", dataset_names$y6)))
      ),
    
      hr(),
      
      #### --- FILTER OPTIONS SECTION: CROSS-SECTIONAL -----
      h4("Filter Options - Demographics"), 
      checkboxGroupInput("filter_wave", "Select Wave of enrollment", 
                         choices = c("Wave 1" = "1", "Wave 2" = "2"),
                         selected = c("1", "2")),  # Default to all selected
      
      checkboxGroupInput("filter_sex", "Select Sex", 
                         choices = c("Male", "Female"), 
                         selected = c("Male", "Female")),
      
      checkboxGroupInput("filter_race", "Select Race", 
                         choices = c("White", "Black", "Asian", "Hispanic",
                                     "AIAN" = "AIAN", "NHPI" = "NHPI",
                                     "Multi-Race" = "Multi-Race", "Other" = "Other"), 
                         selected = c("White", "Black", "Asian", "Hispanic", 
                                      "AIAN", "NHPI", "Multi-Race", "Other"), 
                         inline = TRUE), #using inline saves some space
      
      hr(style = "border-top: 1px double #8c8b8b;"), # Stronger visual separator
      
      
      #### --- FILTER OPTIONS SECTION: LONGITUDINAL -----
      h4("Filter Options - Cognitive"),
      # data previewer 
      # hr(),
      # h4("Data Preview"),
      # tableOutput("previewTable"),
      
      # Single choice for outcome (defaults to the first one)
      selectInput("long_outcome", "Select Longitudinal Outcome",
                  choices = c(#"All", 
                    "Normal cognition"="Normal.cognition",
                    "Amnestic MCI, single domain"="aMCI.SD",   
                    "Amnestic MCI, multiple domain"="aMCI.MD" , 
                    "Non-amnestic MCI, single domain"="naMCI.SD",
                    "Non-amnestic MCI, multiple domain"="naMCI.MD",   
                    "Cognitively impaired"="Cognitively.impaired"), 
                  selected = "Normal cognition"),
      
      # include TBD?
      selectInput("TBD_include", "Include TBD",
                  choices = c(  
                    "Yes"="1",
                    "No"="0"), 
                  selected = "Yes"),
      
      ###  Multiple choice for Years/Waves - *leaving this out for now
      # checkboxGroupInput("long_years", "Select Years to Plot",
      #                    choices = c("Year 2" = 2, 
      #                                "Year 4" = 4, 
      #                                "Year 6" = 6),
      #                    selected = c(2, 4, 6)),
      
      width = 3 # Sidebar takes 3 out of 12 columns
    ),
  
    
    ## OUTPUTS #####
    ### The Main Content Panel -----
    mainPanel(
      tabsetPanel(
        #### table print tab -----
        tabPanel("Demographic Information", DTOutput("print_table")),
        
        #### enrollment and wave tab -----
        tabPanel("Enrollment and Follow-up (ALL subjects)", 
                 fluidRow(
                   column(12, 
                          # Title for the first table
                          div(style = "margin-top: 20px;", 
                              h4(strong("Enrollment & Follow-up Visits"))),
                          DTOutput("attrition_DT"),
                          
                          hr(style = "border-top: 1px solid #ccc; margin: 30px 0;"), # Visual divider
                          
                          # Title for the second table
                          div(h4(strong("Recorded Withdraws"))),
                          DTOutput("withdraw_DT"),
                          
                          # Optional: Extra space at the bottom
                          div(style = "margin-bottom: 30px;")
                   )
                 )
        ),
        
        #### descriptive plots tab -----
        tabPanel("Descriptive Plots",
                 # Row 1: One wide Age Histogram
                 fluidRow(
                   div(style = "margin-top: 20px;", 
                       h4(strong("For selected sub-sample"))),
                   column(12, plotOutput("age_hist", height = "300px"))
                 ),
                 
                 br(), # Spacing
                 
                 # Row 2: Sex and Race side-by-side
                 fluidRow(
                   column(6, plotOutput("sex_bar", height = "300px")),
                   column(6, plotOutput("race_bar", height = "300px"))
                 ),
                 
                 hr(), # Visual separator
                 
                 # Row 3: Enrollment and Withdrawal side-by-side
                 fluidRow(
                   column(6, plotOutput("enroll_wave_bar", height = "300px")) ,
                   column(6, plotOutput("follow_up_bar", height = "300px")) 
                 )
        ),
        
        #### categorical outcomes  -----
        tabPanel("Composite Outcome", 
                 plotOutput("category_bar", height = "500px")
        ),
        #### outcome progression tab -----
        tabPanel("Single Outcome progression", 
                 plotOutput("singular_bar", height = "500px") 
                 ) 
      )
    )
  )
)


outcome_list <- c(
  "Normal.cognition.",
  "aMCI.SD.",   
  "aMCI.MD." , 
  "naMCI.SD.",
  "naMCI.MD.",  
  "Cognitively.impaired."
)

# Define server ########
server <- function(input, output, session) {
  
  ## 1. Define the reactive DEMOGRAPHICS data -------
  # Use reactive({ ... }) so it updates when inputs change
  
  ### filtered_df: WIDE form working dataset -----
  filtered_df <- reactive({
    validate(
      need(input$filter_wave, "Please select at least one Wave of enrollment."),
      need(input$filter_sex, "Please select at least one Sex."),
      need(input$filter_race, "Please select at least one Race category.")
    )
    
    data_demographics %>%
      filter(
        # Use %in% for multi-select inputs
        Wave_enroll %in% as.numeric(input$filter_wave),
        Sex %in% input$filter_sex,
        Race %in% input$filter_race
      )
  })
  
  ### summary_df_followups -----
  summary_df_followups <- reactive({
    validate(
      need(input$filter_wave, "Please select at least one Wave of enrollment."),
      need(input$filter_sex, "Please select at least one Sex."),
      need(input$filter_race, "Please select at least one Race category.")
    )
    
    df <- data_clean %>%
      filter(
        Wave_enroll %in% as.numeric(input$filter_wave),
        Sex %in% input$filter_sex,
        Race %in% input$filter_race
      ) 
    
    df %>%
      summarise(
        "Year 2" = sum(!is.na(Composite.Category.2)),
        "Year 4" = sum(!is.na(Composite.Category.4)),
        "Year 6" = sum(!is.na(Composite.Category.6))
      ) %>%
      pivot_longer(cols = everything(), names_to = "Year", values_to = "Count") %>%
      mutate(Year = factor(Year, levels = c("Year 2", "Year 4", "Year 6")))
   
  })
  
  ### longitudinal_filtered_df: LONG form working dataset -----
  # 1. The Main Longitudinal Reactive
  longitudinal_filtered_df <- reactive({
    # Ensure baseline filter and year selection are not empty
    req(filtered_df())
    
    data_long %>%
      # Filter by IDs currently selected in the baseline/demographic tab
      filter(Study.ID %in% filtered_df()$Study.ID) %>%
      # Filter by years selected in the UI
      # filter(Wave %in% input$long_years) %>%
      # Drop rows where composites are NA
      filter(!is.na(Composite.Category))
  })
  
  ### longitudinal_filtered_df_no_TBD： "No TBD" Reactive (for Plots)------
  longitudinal_filtered_df_no_TBD <- reactive({
    df <- longitudinal_filtered_df()
    
    df %>%
        filter(Composite.Category != "TBD")
   
  })
  
  
  ## 2. FUNCTIONS FOR DEMOGRAPHICS ------- 
  
  ### fn 1 print demo table -----
  output$print_table <- renderDT({
    df_to_show <- req(filtered_df()) 
     
    datatable(
      df_to_show, 
      options = list(
        pageLength = 10, 
        scrollX = TRUE,
        autoWidth = TRUE
      ),
      selection = "single",
      class = 'cell-border stripe'
    )
  })
  
  ### fn 2a age_hist  -----
  output$age_hist <- renderPlot({
    df <- filtered_df() # Call the reactive
    
    # print(paste("Number of subjects: ", nrow(df)))
    
    ggplot(df, aes(x = Age)) + 
      geom_histogram(fill = "steelblue", color = "white") +
      annotate("label", x = Inf, y = Inf, 
               label = paste0("N = ", nrow(df)),size=9,
               hjust = 1.1, vjust = 1.1, fill = "white", alpha = 0.7) +
      labs(title = "Age Distribution", x = "Count", y = NULL) +
      theme_minimal() +
      theme(legend.position = "none", 
            title = element_text(size = 14, face = "bold"))
  })
  
  
  ### fn 2b sex_bar  -----
  output$sex_bar <- renderPlot({
    df <- filtered_df()
    
    data_counts_sex <- df %>%
      count(Sex) 
    
    ggplot(data_counts_sex, aes(x = n, y = fct_rev(Sex), 
                            fill = Sex)) +
      geom_col(
        width = 0.6 
      ) +
      # Add the actual values at the end of the bars
      geom_text(aes(label = n), 
                hjust = -0.2,         
                color = "black", 
                fontface = "bold") +
      scale_fill_brewer(palette = "PuBu", 
                        name = "Sex") +
      expand_limits(x = max(data_counts_sex$n) * 1.1) +
          # Leave room for the text
      labs(title = "Sex Composition", 
           x = "Count", y = NULL) +
      theme_minimal() +
      theme(legend.position = "none", 
            title = element_text(size = 14, face = "bold"))
    
  }    )
   
  
   ### fn 2c race_bar  -----
  
  output$race_bar <- renderPlot({
    df <- filtered_df()
    
    data_counts <- df %>%
      count(Race) # This creates a column named 'n'
    
    ggplot(data_counts, aes(x = n, y = fct_rev(Race), 
                            fill = Race)) +
      geom_col(
        width = 0.6 
      ) +
      # Add the actual values at the end of the bars
      geom_text(aes(label = n), 
                hjust = -0.2,          # Nudge text to the right of the bar
                color = "black", 
                fontface = "bold") +
      scale_fill_brewer(palette = "PuBu", 
                        name = "Race") +
      expand_limits(x = max(data_counts$n) * 1.1) + # Leave room for the text
      labs(title = "Racial Composition", x = "Count", y = NULL) +
      theme_minimal() +
      theme(legend.position = "none", 
            title = element_text(size = 14, face = "bold"))
    
    }    )
  
  
  ### fn 2d enrollment wave -----
  output$enroll_wave_bar <- renderPlot({
    df <- filtered_df()
    
    data_counts <- df %>%
      count(Wave_enroll) # This creates a column named 'n'
    
    ggplot(data_counts, aes(x = n, y = (factor(Wave_enroll)),
                            fill = factor(Wave_enroll))) +
      geom_col(
        width = 0.6 
      ) +
      # Add the actual values at the end of the bars
      geom_text(aes(label = n), 
                hjust = -0.2,         
                color = "black", 
                fontface = "bold") + 
      scale_fill_brewer(palette = "PuBu", 
                        name = "Enrollment Wave") +
      expand_limits(x = max(data_counts$n) * 1.1) + 
      labs(title = "Enrollment Wave", x = "Count", y = "Wave of Enrollment") +
      theme_minimal() +
      theme(legend.position = "none", 
            title = element_text(size = 14, face = "bold")
              )
  })
  
  ### fn 2e followups  -----
  output$follow_up_bar <- renderPlot({
    df_summary <- req(summary_df_followups())
     
    validate(
      need(sum(df_summary$Count) > 0, "No valid follow-up data found for these filters.")
    )
    
    ggplot(df_summary, aes(y = fct_rev(Year), x = Count, fill = Year)) +
      geom_col(
        width = 0.6,
        color = "white"
      ) +
      # Add the actual values at the end of the bars
      geom_text(aes(label = Count), 
                hjust = -0.2,           # Nudge text to the right of the bar
                color = "black", 
                fontface = "bold",
                size = 5) +
      scale_fill_brewer(palette = "PuBu") +
      expand_limits(x = max(df_summary$Count) * 1.2) + 
      theme_minimal() +
      labs(
        title = "Successful Follow-up Visits",
        caption = " 'Success' assumed if subject ID appeared in following years of data",
        x = "Number of Subjects",
        y = NULL
      ) +
      theme(
        legend.position = "none",
        panel.grid.major.y = element_blank() , 
        title = element_text(size = 14, face = "bold")
      )
    
  })

  
  
  ## 3. FUNCTIONS FOR cohort followups ----------
  ### fn 3a # of subjects in each wave -----
  # --- Enrollment & Withdrawal Table ---
  
  message_text <- paste0("Year-to-year retention is calculated by matching Subject IDs from baseline.",
  " Subjects are counted as 'present' if their ID appears in the follow-up data,",
  " regardless of their specific clinical or withdrawal status.")
  
  # --- Attrition & withdraw Tables ---
  output$attrition_DT <- renderDT({
    
    datatable(attrition_table, 
              caption = tags$caption(style = 'caption-side: bottom; color: grey;', 
                                      message_text),
              options = list(dom = 't', paging = FALSE, ordering = FALSE), 
              rownames = FALSE)
    
  })
  
  output$withdraw_DT <- renderDT({
    
    datatable(final_withdraw_report, 
              options = list(dom = 't', paging = FALSE, ordering = FALSE), 
              rownames = FALSE)
    
  })
  
  ## 4. FUNCTIONS FOR OUTCOMES ----------
  
  ### fn 4a composite outcome bar plot ----- 
    #for singular outcome type chosen, bar plot each year's 1s and 0s. 
  output$category_bar <- renderPlot({
     
    # 1. pull data as df_long based on TBD inclusion
    if (input$TBD_include == "1") {
      df_long <- longitudinal_filtered_df()
      mode_label <- "Includes TBD, "
    } else {
      df_long <- longitudinal_filtered_df_no_TBD()
      mode_label <- "No TBD, "
    }
    
    # 2. POP-UP NOTIFICATION (Optional: Shows in the app UI)
    message_1 <- paste(mode_label," N=",length(unique(df_long$Study.ID)))
      
    
    # 3. VALIDATE (Stops the plot if rows are 0)
    validate(
      need(!is.null(df_long) && nrow(df_long) > 0, 
           paste("No data found for", mode_label, "selection."))
    )
    
    # 4. RENDER PLOT
    ggplot(df_long, 
           aes(x = factor(Composite.Category), 
               fill = factor(Composite.Category))) + 
      geom_bar(color = "grey", position = "dodge") +
      geom_text(stat = "count", 
                aes(label = after_stat(count)), 
                vjust = -0.5, 
                size = 3.5,
                fontface = "bold") +    
      facet_wrap(~Wave,
                 labeller = as_labeller(
                   c("2" = "Year 2", "4" = "Year 4", "6" = "Year 6")
                 )) +
      scale_fill_brewer(palette = "PuBu", 
                        name = "Cognitive Status") +
      theme_minimal() +
      scale_y_continuous(expand = expansion(mult = c(0, 0.15))) + 
      labs(x = NULL, y = "Count",
           caption = message_1) +
      theme(axis.text.x = element_blank(),
            panel.grid.major.x = element_blank(),
            strip.background = element_rect(fill = "lightgrey", color = "grey"),
            strip.text = element_text(face = "bold", color = "grey30", size = 10) 
      )
  })
  
  ### fn 4b single outcome binary  --------
  output$singular_bar <- renderPlot({
    # 1. Use the 'No TBD' reactive so the lines only connect 0s and 1s
    df <- req(longitudinal_filtered_df_no_TBD())
    
    print(head(df))
    
    # 2. Ensure the outcome column is numeric for the y-axis
    # We convert "0"/"1" strings to numbers 0/1
    df_plot <- df %>%
      # Convert the selected string outcome to a numeric 0/1
      mutate(Outcome = as.numeric(as.character(.data[[input$long_outcome]]))) %>%
      # Remove NAs to ensure the bars represent a clean sample
      filter(!is.na(Outcome)) %>%
      # Convert to factor for better discrete coloring 
      mutate(Outcome_Factor = factor(Outcome, levels = c(0, 1), 
                                     labels = c("No", "Yes")))
    
    # 3. Validation check
    validate(
      need(nrow(df_plot) > 0, "No valid 0/1 data for this outcome.")
    )
    
    if(nrow(df_plot) > 0) {
      print("First few rows of Outcome:")
      print(head(df_plot$Outcome_Factor))
    }
    
    # CALCULATE VALUES FIRST
    # This creates a small table with one row per Wave
    df_summary <- df_plot %>%
      group_by(Wave) %>%
      summarise(
        Total_N = n(),
        # Calculate % of 'Yes' (Outcome == 1)
        Percent_Yes = paste0(round(100 * mean(Outcome), 1), "%"),
        .groups = "drop"
      )
    
    ggplot() +
      # Use the main data for the bars
      geom_bar(data = df_plot, 
               width = 0.6,
               aes(x = factor(Wave), fill = Outcome_Factor),
               position = "stack", color = "white", linewidth = 0.3) +
      
      # Use the SUMMARY data for the text labels
      geom_text(data = df_summary, 
                aes(x = factor(Wave), y = Total_N, label = Percent_Yes),
                vjust = -0.8,           # Position above the bar
                fontface = "bold", 
                color = "#0570B0",     # Match the 'Yes' color
                size = 4.5) +
      
      # Styling
      scale_fill_manual(values = c("No" = "#bdc3c7", "Yes" = "#0570B0"), 
                        name = "Outcome Present") +
      scale_x_discrete(labels = c("2" = "Year 2", "4" = "Year 4", "6" = "Year 6")) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.2))) + # Extra room for labels
      labs(
        title = paste("Outcome Progression of - ", input$long_outcome),
        subtitle = "Percentage values represent the conversion rate ('Yes') at each Wave",
        x = "Study Year",
        y = "Total Participants (n)",
        caption = "Data shown excludes TBD and NA values for clarity."
      ) +
      theme_minimal() +
      theme(
        subtitle = element_text(size = 14, color = "grey40"),
        subtitle = element_text(size = 10, color = "grey40"),
        panel.grid.major.x = element_blank(),
        strip.background = element_rect(fill = "lightgrey", 
                                        color = "grey"),
        strip.text = element_text(face = "bold")
      )
  })
 
  
} # closing the whole server Rfunction
 


# Run the application 
shinyApp(ui = ui, server = server)




#archive
# ### ARCHIVE: binary spaghetti -----
# output$longitudinal_spaghetti_line <- renderPlot({
#   # 1. Use the 'No TBD' reactive so the lines only connect 0s and 1s
#   df <- req(longitudinal_filtered_df_no_TBD())
#   
#   # 2. Ensure the outcome column is numeric for the y-axis
#   # We convert "0"/"1" strings to numbers 0/1
#   df_plot <- df %>%
#     mutate(y_value = as.numeric(as.character(.data[[input$long_outcome]]))) %>%
#     filter(!is.na(y_value)) # Remove any residual NAs
#   
#   # 3. Create the Plot
#   ggplot(df_plot, aes(x = Wave, y = y_value, group = Study.ID)) +
#     # Add the individual "spaghetti" lines
#     geom_line(alpha = 0.3, color = "steelblue", linewidth = 0.5) +
#     # Add points to show the actual data collection moments
#     geom_point(alpha = 0.5, color = "steelblue") +
#     # Add a bold "Mean Trend" line to show the overall trajectory
#     stat_summary(aes(group = 1), fun = mean, geom = "line", 
#                  color = "darkred", linewidth = 1.2) +
#     # Formatting
#     scale_y_continuous(breaks = c(0, 1), labels = c("No", "Yes"), limits = c(-0.1, 1.1)) +
#     labs(
#       title = paste("Trajectory of:", 
#                     "selected outcome"),
#       x = "Study Wave",
#       y = "Presence of Outcome",
#       caption = "Removing TBD and NA for clarity" 
#     ) +
#     theme_minimal()+
#     #caption
#     theme(
#       caption=element_text(hjust = 0, size = 8, color = "grey50")
#     )
# })
