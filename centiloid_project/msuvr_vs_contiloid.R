library(ggplot2)

df <- read.csv("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/centiloid_results_both_tracers.csv",
               header = TRUE, stringsAsFactors = FALSE)

ggplot(df, aes(x = Centiloid, y = MeanSUVR, color = Tracer, shape = amyloid)) +
  geom_point(size = 4) +            
  theme_minimal() +                
  labs(
    x = "Centiloid",
    y = "Mean SUVR",
    color = "Tracer",
    shape = "Amyloid Status",
    title = "Mean SUVR vs Centiloid"
  ) +
  scale_shape_manual(
    values = c(
      "Positive" = 8,  # star
      "Negative" = 16, # circle
      "Unknown"  = 17  # triangle
    )
  ) +
  theme(
    text = element_text(size = 14),
    plot.title = element_text(hjust = 0.5)
  )

ggsave("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/centiloid_vs_msuvr.pdf",
       width = 8, height = 6)