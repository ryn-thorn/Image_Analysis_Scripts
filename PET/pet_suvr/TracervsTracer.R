# Load libraries
library(ggplot2)
library(dplyr)

# Input file
input_file <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_Summary_Files/pet/centiloid_project/centiloids_both_tracers.csv"

# Output folder (same as input folder)
output_folder <- dirname(input_file)

# Read CSV
data <- read.csv(input_file, stringsAsFactors = TRUE)
data$Tracer <- as.factor(data$Tracer)

# =========================
# 1. Violin plot with jittered points
# =========================
violin_file <- file.path(output_folder, "SUVR_violin_plot.png")

png(violin_file, width = 800, height = 600)
ggplot(data, aes(x = Tracer, y = MeanSUVR)) +
  geom_violin(fill = "white", color = "black", alpha = 0.6) +
  geom_jitter(width = 0.15, height = 0, size = 2, alpha = 0.8) +
  theme_minimal() +
  labs(title = "SUVR Distribution by Tracer",
       x = "Tracer",
       y = "Mean SUVR")
dev.off()

# =========================
# 2. Summary statistics per tracer
# =========================
summary_stats <- data %>%
  group_by(Tracer) %>%
  summarise(
    n = n(),
    mean_SUVR = mean(MeanSUVR, na.rm = TRUE),
    sd_SUVR = sd(MeanSUVR, na.rm = TRUE),
    median_SUVR = median(MeanSUVR, na.rm = TRUE),
    IQR_SUVR = IQR(MeanSUVR, na.rm = TRUE)
  )

print(summary_stats)

# Optional: save summary to CSV
summary_file <- file.path(output_folder, "SUVR_summary_stats.csv")
write.csv(summary_stats, summary_file, row.names = FALSE)
