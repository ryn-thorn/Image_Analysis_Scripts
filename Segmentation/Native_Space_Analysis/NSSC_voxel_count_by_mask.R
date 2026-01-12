# =========================
# Setup
# =========================
library(tidyverse)

# Input file
infile <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_Summary_Files/Segmentation/native_subcortical_roi_analysis_md-fa-mask/roi_voxel_counts_aim1_famd-mask_vs_csf-mask.csv"   # <-- change if needed

# Output directory
outdir <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_Summary_Files/Segmentation/native_subcortical_roi_analysis_md-fa-mask"
dir.create(outdir, showWarnings = FALSE)

# =========================
# Read data
# =========================
df <- read.csv(infile, stringsAsFactors = FALSE, check.names = FALSE)

# =========================
# Reshape to long format
# =========================
long <- df %>%
  pivot_longer(
    cols = matches("^(Left|Right)[.-]"),
    names_to = "Region",
    values_to = "Value"
  )

# =========================
# Wide format for comparisons
# =========================
wide <- long %>%
  pivot_wider(
    names_from = Mask,
    values_from = Value
  ) %>%
  mutate(
    Difference = FAMD - CSF,
    Percent_Diff = (FAMD - CSF) / CSF * 100
  )

# =========================
# Plot 1: FAMD vs CSF values
# =========================
p1 <- ggplot(long, aes(x = Region, y = Value, fill = Mask)) +
  geom_col(position = "dodge") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "FAMD vs CSF by Region",
    y = "Value",
    x = ""
  )

ggsave(
  filename = file.path(outdir, "FAMD_vs_CSF.png"),
  plot = p1,
  width = 8,
  height = 10,
  dpi = 300
)

# =========================
# Plot 2: Difference (FAMD − CSF)
# =========================
p2 <- ggplot(wide, aes(x = Region, y = Difference)) +
  geom_col(fill = "steelblue") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Difference (FAMD − CSF)",
    y = "Difference",
    x = ""
  )

ggsave(
  filename = file.path(outdir, "Difference_FAMD_minus_CSF.png"),
  plot = p2,
  width = 8,
  height = 10,
  dpi = 300
)

# =========================
# Plot 3: Percent difference
# =========================
p3 <- ggplot(wide, aes(x = Region, y = Percent_Diff)) +
  geom_col(fill = "darkorange") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Percent Difference (FAMD vs CSF)",
    y = "Percent difference (%)",
    x = ""
  )

ggsave(
  filename = file.path(outdir, "Percent_Difference.png"),
  plot = p3,
  width = 8,
  height = 10,
  dpi = 300
)

# =========================
# Optional: save computed table
# =========================
write.csv(
  wide,
  file = file.path(outdir, "FAMD_vs_CSF_differences.csv"),
  row.names = FALSE
)
