# ===============================
# Libraries
# ===============================
library(tidyverse)
library(gridExtra)

# ===============================
# Inputs
# ===============================
output_dir  <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_Summary_Files/PET/centiloids_mri-free"
output_file <- "MRF_Centiloids.pdf"

# Create directory if it doesn't exist
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

pdf_path <- file.path(output_dir, output_file)

# ===============================
# Load data
# ===============================
df <- read.csv("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_Summary_Files/PET/centiloids_mri-free/MRF_Centiloids.csv", stringsAsFactors = FALSE)
colnames(df)

# ===============================
# Helper function (updated)
# ===============================
make_scatter <- function(data, xvar, yvar, color, title, fix_scale = FALSE) {
  p <- ggplot(data, aes(x = {{ xvar }}, y = {{ yvar }})) +
    geom_point(color = color, alpha = 0.7) +
    geom_smooth(method = "lm", se = FALSE, color = color) +
    theme_bw() +
    labs(title = title, x = deparse(substitute(xvar)), y = deparse(substitute(yvar))) +
    theme(plot.title = element_text(hjust = 0.5))
  
  # Fix axis limits if requested
  if (fix_scale) {
    range_vals <- range(c(data[[deparse(substitute(xvar))]], data[[deparse(substitute(yvar))]]), na.rm = TRUE)
    p <- p + xlim(range_vals) + ylim(range_vals)
  }
  
  return(p)
}

# ===============================
# Split by tracer
# ===============================
df_fbb <- df %>% filter(Tracer == "FBB")
df_fbp <- df %>% filter(Tracer == "FBP")

# ===============================
# Open PDF
# ===============================
pdf(pdf_path, width = 14, height = 5)

# ------------------------------------------------
# Slide 1: FBB
# ------------------------------------------------
p1_fbb <- make_scatter(df_fbb, age, MRFCentiloid, "darkgreen",
                       "FBB: MRFCentiloid vs Age")

p2_fbb <- make_scatter(df_fbb, age, mSUVr, "darkgreen",
                       "FBB: mSUVr vs Age")

p3_fbb <- make_scatter(df_fbb, MRFCentiloid, OldCentiloid, "darkgreen",
                       "FBB: MRFCentiloid vs OldCentiloid", fix_scale = TRUE)

grid.arrange(p1_fbb, p2_fbb, p3_fbb, ncol = 3)

# ------------------------------------------------
# Slide 2: FBP
# ------------------------------------------------
p1_fbp <- make_scatter(df_fbp, age, MRFCentiloid, "blue",
                       "FBP: MRFCentiloid vs Age")

p2_fbp <- make_scatter(df_fbp, age, mSUVr, "blue",
                       "FBP: mSUVr vs Age")

p3_fbp <- make_scatter(df_fbp, MRFCentiloid, OldCentiloid, "blue",
                       "FBP: MRFCentiloid vs OldCentiloid", fix_scale = TRUE)

grid.arrange(p1_fbp, p2_fbp, p3_fbp, ncol = 3)

# ------------------------------------------------
# Slide 3: FBB + FBP
# ------------------------------------------------
# Define consistent colors
tracer_colors <- c("FBB" = "darkgreen", "FBP" = "blue")

# Compute axis limits for MRFCentiloid vs OldCentiloid
range_vals <- range(c(df$MRFCentiloid, df$OldCentiloid), na.rm = TRUE)

p1_both <- ggplot(df, aes(age, MRFCentiloid, color = Tracer)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = FALSE) +
  scale_color_manual(values = tracer_colors) +
  theme_bw() +
  labs(title = "MRFCentiloid vs Age")

p2_both <- ggplot(df, aes(age, mSUVr, color = Tracer)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = FALSE) +
  scale_color_manual(values = tracer_colors) +
  theme_bw() +
  labs(title = "mSUVr vs Age")

p3_both <- ggplot(df, aes(MRFCentiloid, OldCentiloid, color = Tracer)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = FALSE) +
  scale_color_manual(values = tracer_colors) +
  theme_bw() +
  labs(title = "MRFCentiloid vs OldCentiloid") +
  xlim(range_vals) + ylim(range_vals)

grid.arrange(p1_both, p2_both, p3_both, ncol = 3)

# ------------------------------------------------
# Slide 4: mSUVr vs MRFCentiloid (FBB + FBP)
# ------------------------------------------------
p_msuvr_vs_mrf <- ggplot(df, aes(mSUVr, MRFCentiloid, color = Tracer)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = FALSE) +
  scale_color_manual(values = tracer_colors) +
  theme_bw() +
  theme(
    aspect.ratio = 1,               # 👈 square panel, no unit warping
    plot.title = element_text(hjust = 0.5)
  ) +
  xlim(range(df$mSUVr, na.rm = TRUE)) +
  ylim(range(df$MRFCentiloid, na.rm = TRUE)) +
  labs(
    title = "MRFCentiloid vs mSUVr",
    x = "mSUVr",
    y = "MRFCentiloid"
  )

grid.arrange(p_msuvr_vs_mrf, ncol = 1)


# ===============================
# Close PDF
# ===============================
dev.off()

cat("PDF saved to:\n", pdf_path, "\n")
