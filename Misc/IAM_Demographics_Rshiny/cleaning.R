#################
##for cleaning the data of Y0-6 app.R for Rshiny App LabDataLookLook
## source this in app.R 
## revise this code when data has major changes in the future 

# rm(list=ls())
library(dplyr)
library(tidyr)
library(tidyverse)

# load datasets from the data folder under the same directory as this project
data_y0 <-read.csv("data/IAMDatabaseY0-IAMMeetingDemographi_DATA_LABELS_2025-11-20_1325.csv")
data_y2 <-read.csv("data/IAMDatabaseY2-IAMMeetingDemographi_DATA_LABELS_2025-11-20_1325.csv")
data_y4 <-read.csv("data/IAMDatabaseY4-IAMMeetingDemographi_DATA_LABELS_2025-11-20_1325.csv")
data_y6 <-read.csv("data/IAMDatabaseY6-IAMMeetingDemographi_DATA_LABELS_2025-11-20_1325.csv")


## question - are we considering adding more subjects to come later?
#hence - questions 12 will have values in the future? so far we will name them as "other"


# ! DEMOGRAPHICS CLEANING #########

data_demographics <- data_y0 %>% 
  ### renaming ----
  rename(
    # "Study.ID"=1
    Wave12 = 2,
    White = 3, 
    Black = 4,
    AIAN = 5,
    NHPI = 6,
    Asian = 7,
    Hispanic = 8,
    Self_reported_race = 9,
    Self_reported_ethnicity = 10,
    Additional_race = 11,
    Other_race = 12 ,
    Sex= 13,
    M = 14, F = 15,
    WITHDRAW = 16,
    # "AGE"=17
  ) %>%
  
  
  ### re-leveling ----
  mutate(
    Wave_enroll = ifelse(Wave12 == "Wave 1", 1,
                  ifelse(Wave12 == "Wave 2", 2, NA) ),
    # ! very important - force true NAs for "" 
    Self_reported_Hispanic = na_if(Self_reported_ethnicity,""), 
    Self_reported_Hispanic = factor(Self_reported_ethnicity, 
                                    levels = c("1 Yes" , 
                                               "0 No (If No, SKIP TO QUESTION 9)"),
                                    labels = c("Yes","No")),
    Self_reported_race = na_if(Self_reported_race,""), 
    Self_reported_race = factor(Self_reported_race, 
                                levels = c("1 White",
                                           "2 Black or African American",
                                           "5 Asian"),
                                labels = c("White","Black","Asian")),
    
    WITHDRAW = factor(WITHDRAW,
                      levels = c( 
                        "Yes, withdrew at Y0",
                        "Yes, withdrew at Y2",
                        "Yes, withdrew at Y4",
                        "Yes, withdrew at Y6",
                        "No (still enrolled)",
                        ""),
                      labels = c(
                        "Y0",
                        "Y2",
                        "Y4",
                        "Y6",
                        "No",
                        NA )
    ) ,
    M = na_if(M,""),
    F = na_if(F,""),
    Sex = na_if(Sex,""),
    M = factor (M,
                levels=c("","Yes","No"),
                labels=c(NA,"Yes","No") ),
    F = factor (F,
                levels=c("","Yes","No"),
                labels=c(NA,"Yes","No") ),
    Sex = factor(Sex,
                 levels=c("","1 Male","2 Female"),
                 labels=c(NA, "Male", "Female") )
    
  ) %>%
  
  
  ### binary race and sex variables ----
  mutate( 
    # 1. count how many race responses are "Yes"
    yes_count = rowSums( 
      select(., White, Black, AIAN, NHPI, Asian, Hispanic) == "Yes",  
      na.rm = TRUE 
    ),
    
    # 2. Use case_when() to define the new 'Race_Category' variable
    Race_Category = case_when(
      # Condition 1: If count is 0, mark as Missing (None Selected)
      yes_count == 0 ~ NA,
      
      # Condition 2: If count is greater than 1, mark as Multi-Race
      yes_count > 1 ~ "Multi-Race",
      
      # Condition 3: If count is exactly 1, determine which column was "Yes"
      yes_count == 1 & White    == "Yes" ~ "White",
      yes_count == 1 & Black    == "Yes" ~ "Black",
      yes_count == 1 & AIAN     == "Yes" ~ "AIAN",
      yes_count == 1 & NHPI     == "Yes" ~ "NHPI",
      yes_count == 1 & Asian    == "Yes" ~ "Asian",
      yes_count == 1 & Hispanic == "Yes" ~ "Hispanic",
      
      # Fallback for any unexpected cases (optional, but good practice)
      TRUE ~ "Unknown Error" 
    )
  )%>%
  
  
  ### merge race and sex  -----
  mutate(
    # Merge Race_Category and Self_reported_Hispanic/Self_reported_race
    Race_Category_Final = case_when( # Using a new column name to avoid confusion
      
      # 1.  # when Self_reported_Hispanic=="Yes" & !is.na(Self_reported_race), "Multi-Race;
      Self_reported_Hispanic == "Yes" & !is.na(Self_reported_race) ~ "Multi-Race",
      
      # 2. when Self_reported_Hispanic=="Yes" & is.na(Self_reported_race), "Hispanic";
      Self_reported_Hispanic == "Yes" & is.na(Self_reported_race) ~ "Hispanic",
      
      # 3. When Self_reported_Hispanic=="No"orNA, & !is.na(Self_reported_race), =Self_reported_race;
      Self_reported_Hispanic !="Yes" & !is.na(Self_reported_race) ~ Self_reported_race,
      
      # 4. When is.na(Self_reported_Hispanic) & !is.na(Self_reported_race), don't change value;
      TRUE ~ Race_Category 
    ),
    ,
    # make the Race_Category variable a factor variable -- and force levels
       ##@@@@ the enforcement of levels moved here 
    Race_Category_Final = factor(
      Race_Category_Final,
      levels = c(
        "White",
        "Black",
        "Asian",
        "Hispanic",
        "AIAN",
        "NHPI",
        "Multi-Race",
        "Other"
        # Note: We usually don't include NA in the levels list, 
        # and "Unknown Error" should be fixed/rare.
      )
    ) , 
    # Merge Sex variable in the same override logic 
    Sex_Final = case_when(
      # when Sex is not missing, use Sex, 
      !is.na(Sex) ~ Sex,
      # When Sex is missing and M=Yes, M; 
      is.na(Sex) & M=="Yes" ~ 'Male',
      # When Sex is missing and F=Yes, F; 
      is.na(Sex) & F=="Yes" ~ 'Female',
    ),
    Sex_Final = factor(Sex_Final,
                       levels = c("Male","Female", NA))
  ) %>%
  
  
  ### renaming and selecting -----
  
  select(Study.ID,
         Age, Sex_Final, Race_Category_Final,
         Wave_enroll, WITHDRAW
  ) %>%

  rename(
    Sex=Sex_Final,
    Race=Race_Category_Final
  ) 
  

data_demographics <- data_demographics %>%
  filter(!is.na(Age)|!is.na(Sex))

# # final check
# data_demographics  %>%
#   group_by(Sex, Race) %>%
#   summarise(n=n())
#   
# data_demographics %>% head()
# 
# table(data_demographics $ Race, useNA = "always")   
#   
# data_demographics %>% glimpse()
#   

colnames(data_y2) <-c(
  "Record.ID",
  "Normal.cognition.",
  "aMCI.SD.",  # amnestic + single-domain
  "aMCI.MD." , 
  "naMCI.SD.",
  "naMCI.MD.", # non-amnestic + multi-domain 
  "Cognitively.impaired."
) 


#print how answers of outcomes are logged in raw data
#(col 2:7 in data_y2 etc)
for (i in 2:7){
  cat(paste0("Column ", i, " unique values:\n"))
  cat(paste0("year2", "\n")) 
  print(unique(data_y2[[i]]))
  
  cat(paste0("year4", "\n"))
  print(unique(data_y4[[i]]))
  
  cat(paste0("year6", "\n"))
  print(unique(data_y6[[i]]))
  
  cat("\n")
}


# !RECODING Y2/4/6 ----- 

## recoding outcome variables ------------
process_wave_data <- function(df, wave_num) {
  
  ### 1. rename columns ----------
  colnames(df) <- c(
    "Record.ID",
    "Normal.cognition.",
    "aMCI.SD.",  # amnestic + single-domain
    "aMCI.MD." , 
    "naMCI.SD.",
    "naMCI.MD.", # non-amnestic + multi-domain 
    "Cognitively.impaired."
  )  
  
  # Validation: Ensure the data frame has exactly 7 columns
  if (ncol(df) != 7) {
    stop("The dataset must have exactly 7 columns.")
  }
  
  
  
  ### 2. releveling for 2~7 --------
  df_processed_1 <- df %>%
    mutate(across(2:7, 
                  ~ na_if(as.character(.), "")), #for col2-7, make "" to NA
           across(2:7, 
                  ~ na_if(as.character(.), "NA")), #for col2-7, make "" to NA 
           # recode "Yes"/"No" to 1/0 
           Normal.cognition. = ifelse(
             grepl("Yes", Normal.cognition., ignore.case = TRUE), 
             1, 
             ifelse(
               grepl("Yes",Normal.cognition., ignore.case = TRUE), 
               0, NA) ),
            # recode 1 present to 1
            aMCI.SD. = ifelse( grepl("Present", aMCI.SD., ignore.case = TRUE), 
                               1, NA),
            aMCI.MD. = ifelse(grepl("Present", aMCI.MD., ignore.case = TRUE), 
                              1, NA),
            naMCI.SD. = ifelse(grepl("Present", naMCI.SD., ignore.case = TRUE), 
                               1, NA),
            naMCI.MD. = ifelse(grepl("Present", naMCI.MD., ignore.case = TRUE), 
                               1, NA),
            Cognitively.impaired.= 
             ifelse(grepl("Present", Cognitively.impaired., ignore.case = TRUE), 
                    1, NA),
  
           # ensure all are character type
           across(2:7, ~ as.character(.))
     ) %>% 
  
  ### 3. Polish the outcome variables --------
    #if all outcomes are missing ,then this participant has not been discussed.
    mutate(num_missing = rowSums(is.na(select(., 2:7)))) %>%
    mutate(across(2:7, ~ case_when(
      num_missing == 6 ~ "TBD",          # If all 6 are missing, set to TBD
      is.na(.)         ~ "0",            # If row has some data but this col is NA, set to 0
      TRUE             ~ as.character(.) # Otherwise, keep the existing value 
    ))) %>%
    
    
  ### 4. create new composite outcome variable ------
    # create an aggregated categorical variable based on outcomes in col2-7
    mutate(
      Composite.Category. = case_when(
        num_missing == 6 ~ "TBD",
        
        # Column 2: Normal cognition
        Normal.cognition. == "1" ~ "Normal cognition",
        
        # Columns 3 thru 6: MCI group (any of them)
        aMCI.SD. == "1" | 
        aMCI.MD. == "1" |  
        naMCI.SD. == "1" | 
        naMCI.MD.== "1"  ~ "MCI",
        
        # Column 7: Cognitively impaired
        Cognitively.impaired. == "1" ~ "Cognitively impaired",
        
        TRUE ~ NA_character_
      ) # end of case when
    )  %>%# end of mutate 
  mutate(Composite.Category. = factor(Composite.Category.,
           levels = c("Normal cognition","MCI","Cognitively impaired","TBD"))
         )
  
  ### 4. unify subject ID, rename column names with wave number
  cols_to_rename <- c(colnames(df)[-1],
                      "Composite.Category.") # all except Record.ID
  
  df_processed_2 <- df_processed_1 %>%
    # Create Subject.ID by removing the last character of Record.ID
    # . is the placeholder for the value; -1 removes the last character
    mutate(Study.ID = str_sub(Record.ID, 1, -2),  # substring from 1 to 2nd last 
           .after = Record.ID) %>%
    
    # Rename columns 2 through 7 by appending the wave number
    rename_with(
      .fn = ~ paste0(.,wave_num, sep=""), # add _Y indicating Year x
      .cols = all_of(cols_to_rename)
    )  %>%
  select(-Record.ID, -num_missing)
  
  return(df_processed_2)
}

data_y2_clean <- process_wave_data(data_y2, 2)
data_y4_clean <- process_wave_data(data_y4, 4)
data_y6_clean <- process_wave_data(data_y6, 6)

table(data_y2_clean$num_missing)
table(data_y2_clean$Composite.Category.2, useNA = "always")
table(data_y4_clean$Composite.Category.4, useNA = "always")
table(data_y6_clean$Composite.Category.6, useNA = "always")

## inspecting missings in outcomes ----------
# true NA vs. fake NA 
# does Y2 Y4 Y6 data have missing outcomes? 
# data_demographics %>%
#   mutate(num_missing = rowSums(is.na(select(., 1:6)))) %>%
#   count(num_missing)
# 
# glimpse(data_y2_clean)
# 
data_y2_clean %>%
  filter(rowSums(is.na(select(., 2:7))) == 6) %>%
  nrow()
# 
# data_y2_clean %>%
#   # 1. Count how many NAs exist in columns 2 through 7 for EVERY row
#   mutate(num_missing = rowSums(is.na(select(., 2:7)))) %>%
#   # 2. Count the frequency of each missingness level
#   count(num_missing)
# 
# data_y4_clean %>%
#   mutate(num_missing = rowSums(is.na(select(., 2:7)))) %>%
#   count(num_missing)
# 
# data_y6_clean %>%
#   mutate(num_missing = rowSums(is.na(select(., 2:7)))) %>%
#   count(num_missing)
# 
# table(data_y2_clean$Composite.Category.2, useNA = "always")
 


# Merge demo with Y2-6 ---------
data_clean <- data_demographics %>%
  left_join(data_y2_clean, by = "Study.ID") %>%
  left_join(data_y4_clean, by = "Study.ID") %>%
  left_join(data_y6_clean, by = "Study.ID")
 

# Make a long version of data_clean ---------
data_long <- data_clean %>%
  pivot_longer(
    # 1. Select all columns that end in a dot followed by a digit
    cols = matches("\\.\\d$"),  # using Use regex 
    
    # 2. 
    # (.*) : variable name
    # \\. : the literal dot
    # (\\d) : wave number
    # $: ensure to look at the end of string
    names_to = c(".value", "Wave"),
    names_pattern = "(.*)\\.(\\d)$"
  ) %>%
  # 3. Convert Wave to numeric
  mutate(Wave = as.numeric(Wave))

# check first participant
# data_long %>% filter(Study.ID=="IAM_1001") %>% tibble() %>% as.data.frame() 


# WITHDRAW PATTERN ----- 

# 1. Generate the summary grouped by Wave
enrollment_summary <- data_clean %>%
  group_by(Wave_enroll) %>%
  summarise(
    Total_Enrolled = n(),
    Withdrawn_Y0   = sum(WITHDRAW == "Y0", na.rm = TRUE),
    Withdrawn_Y2   = sum(WITHDRAW == "Y2", na.rm = TRUE),
    Withdrawn_Y4   = sum(WITHDRAW == "Y4", na.rm = TRUE),
    Withdrawn_Y6   = sum(WITHDRAW == "Y6", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(Wave_enroll = as.character(Wave_enroll))

# 2. Calculate the "Grand Total" row
total_row <- enrollment_summary %>%
  summarise(
    Wave_enroll    = "Total", # Label for the first column
    Total_Enrolled = sum(Total_Enrolled),
    Withdrawn_Y0   = sum(Withdrawn_Y0),
    Withdrawn_Y2   = sum(Withdrawn_Y2),
    Withdrawn_Y4   = sum(Withdrawn_Y4),
    Withdrawn_Y6   = sum(Withdrawn_Y6)
  )

# 3. Combine them and convert to a clean tibble
final_withdraw_report <- bind_rows(enrollment_summary, total_row) 

print(as_tibble(final_withdraw_report))



# ATTRITION PATTERN ----- 
# --- 1. Define the ID sets for Baseline groups ---
ids_total  <- data_demographics$Study.ID
ids_wave1  <- data_demographics[data_demographics$Wave_enroll == 1,]$Study.ID
ids_wave2  <- data_demographics[data_demographics$Wave_enroll == 2,]$Study.ID

# --- 2. Create the Table ---
attrition_table <- data.frame(
  Group = c("Total Enrolled", "Wave 1 Enrollment", "Wave 2 Enrollment")
) %>%
  mutate(
    # Year 0: Baseline counts
    Baseline = c(length(ids_total), 
                 length(ids_wave1), 
                 length(ids_wave2)),
    
    # Year 2: Sum the logical matches
    Year2 = c(sum(ids_total %in% data_y2_clean$Study.ID),
              sum(ids_wave1 %in% data_y2_clean$Study.ID),
              sum(ids_wave2 %in% data_y2_clean$Study.ID)),
    
    # Year 4: Sum the logical matches
    Year4 = c(sum(ids_total %in% data_y4_clean$Study.ID),
              sum(ids_wave1 %in% data_y4_clean$Study.ID),
              sum(ids_wave2 %in% data_y4_clean$Study.ID)),
    
    # Year 6: Sum the logical matches
    Year6 = c(sum(ids_total %in% data_y6_clean$Study.ID),
              sum(ids_wave1 %in% data_y6_clean$Study.ID),
              sum(ids_wave2 %in% data_y6_clean$Study.ID))
  )

# View the result
print(attrition_table)



# MISSING OUTCOME PATTERN in final data wide form----- 
wide_NA_examine <-
  data_clean %>%
  select(Study.ID, 
         Composite.Category.2,
         Composite.Category.4,
         Composite.Category.6) %>%
  mutate(pattern = paste0(
    as.integer(!is.na(Composite.Category.2)), # 1 if has data, 0 if NA
    as.integer(!is.na(Composite.Category.4)),
    as.integer(!is.na(Composite.Category.6))
  ))

unique(wide_NA_examine$pattern)
table(wide_NA_examine$pattern, useNA="ifany")

#subject IDs with pattern 000
df_000 <- wide_NA_examine %>%
  filter(pattern=="000") 

df_000_full <- data_clean %>%
  filter(Study.ID %in% df_000$Study.ID) %>%
  tibble() %>%
  as.data.frame()  


df_000_full %>%
  mutate(num_missing_comp = rowSums(is.na(select(., 
                                                 c("Composite.Category.2", 
                                                   "Composite.Category.4", 
                                                   "Composite.Category.6"))))) %>%
  # 2. Select the ID, the source variables (columns 7 to 27), and your count
  select(Study.ID, 7:27, num_missing_comp) %>%
  mutate(across(everything(), ~ nchar(as.character(.)),
                .names = "len_{.col}") )%>%
  head(10)


df_000_full$WITHDRAW

table(data_clean$WITHDRAW)



# FINAL remaining objects for use in app.R ============
# remove unnecessary objects

dataset_names <- list(
  y0 = "data_y0",
  y2 = "data_y2",
  y4 = "data_y4",
  y6 = "data_y6"
)

# remove all objects, ONLY KEEP :
rm(  list = setdiff(ls(), 
                    #objects we are keeping
                    c("data_clean",
                      "data_long",
                      "data_demographics", 
                      dataset_names,
                      "data_y2_clean",
                      "data_y4_clean",
                      "data_y6_clean",
                      "attrition_table",
                      "final_withdraw_report") 
) 
)





# -------ARCHIVE------- #########
