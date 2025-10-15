library(ggplot2)

df <- read.csv("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/centiloids_both_tracers.csv",
               header = TRUE, stringsAsFactors = FALSE)

# Combine tracer + amyloid to make a unique group
df$group <- paste(df$Tracer, df$amyloid, sep = "_")

# Define custom palette
palette <- c(
  "Florbetapir_Positive" = "#258A75", # dark version of blue
  "Florbetapir_Negative" = "#42C9AB", # medium blue
  "Florbetapir_Unknown"  = "#44F2CB", # light blue
  "Florbetaben_Positive" = "#87258A", # dark version of purple
  "Florbetaben_Negative" = "#BF35C4", # medium purple
  "Florbetaben_Unknown"  = "#FC7AFF"  # light purple
)

ggplot(df, aes(x = Centiloid, y = MeanSUVR, color = group)) +
  geom_point(size = 4) +    
  theme_minimal() +                
  labs(
    x = "Centiloid",
    y = "Mean SUVR",
    color = "Tracer + Amyloid",
    title = "Mean SUVR vs Centiloid"
  ) +
  scale_color_manual(values = palette) +
  scale_y_continuous(limits = c(0, NA)) +
  #scale_x_continuous(limits = c(-100, 100))
  theme(
    text = element_text(size = 14),
    plot.title = element_text(hjust = 0.5)
  ) 

ggsave("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Calibrated-Coefficients/centiloid_vs_msuvr.pdf",
       width = 8, height = 6)
