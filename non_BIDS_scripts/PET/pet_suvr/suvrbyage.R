# Load libraries
library(ggplot2)
library(dplyr)

# Input file
input_file <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_Summary_Files/pet/centiloid_project/centiloids_both_tracers.csv"
output_folder <- dirname(input_file)

# Read CSV
data <- read.csv(input_file, stringsAsFactors = TRUE)
data$Tracer <- as.factor(data$Tracer)
data$amyloid <- as.factor(data$amyloid)  # Ensure it's treated as factor

# =========================
# Statistical comparison
# =========================
# Mann-Whitney U test
test <- wilcox.test(MeanSUVR ~ Tracer, data = data)
p_val <- signif(test$p.value, 3)

# =========================
# Scatter plot: MeanSUVR by Age
# rigid lines, shape by tracer, color by amyloid status
# =========================
plot_file <- file.path(output_folder, "SUVR_by_Age_with_pval.png")

png(plot_file, width = 800, height = 600)
ggplot(data, aes(x = Age, y = MeanSUVR,
                 color = amyloid,
                 shape = Tracer)) +
  geom_point(size = 3, alpha = 0.8) +
  geom_smooth(aes(group = Tracer),
              method = "lm",      # rigid (linear) lines
              se = FALSE,
              linetype = "dashed",
              color = "black") +  # keep line neutral or adjust
  scale_color_manual(
    values = c(
      "Positive" = "#d73027",   # red
      "Negative" = "#1a9850",   # green
      "Unknown"  = "darkgrey"   # dark grey
    )
  ) +
  theme_minimal() +
  labs(title = paste0("Mean SUVR by Age\nMann-Whitney p = ", p_val),
       x = "Age (years)",
       y = "Mean SUVR",
       color = "Amyloid Status",
       shape = "Tracer") +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold"),
    legend.position = "right"
  )
dev.off()
