############################################
# Centiloid Comparisons Script (Axis + Age Update)
############################################

# ---------- Libraries ----------
library(tidyverse)
library(readr)
library(readxl)
library(ggpubr)

# ---------- File paths ----------
input_file <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free/MRF_Centiloids.csv"

output_dir <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Imaging/MRI/IAM_BIDS/derivatives/PET/centiloids_mri-free"

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# ---------- Load data ----------
df <- read_csv(input_file)
# If Excel instead:
# df <- read_excel(input_file)

############################################
# 1. MRF Centiloid vs Old Centiloid (FBB only)
############################################

df_fbb <- df %>%
  filter(
    Tracer == "FBB",
    `MRF Centiloid` != 0,
    `Old Centiloid` != 0
  )

min_cl <- min(c(df_fbb$`MRF Centiloid`, df_fbb$`Old Centiloid`), na.rm = TRUE)
max_cl <- max(c(df_fbb$`MRF Centiloid`, df_fbb$`Old Centiloid`), na.rm = TRUE)

print(
  cor.test(
    df_fbb$`MRF Centiloid`,
    df_fbb$`Old Centiloid`,
    method = "pearson"
  )
)

p1 <- ggplot(df_fbb, aes(x = `Old Centiloid`, y = `MRF Centiloid`)) +
  geom_point(size = 2) +
  geom_smooth(method = "lm", se = FALSE) +
  coord_cartesian(xlim = c(min_cl, max_cl), ylim = c(min_cl, max_cl)) +
  labs(
    title = "MRF Centiloid vs Old Centiloid (FBB)",
    x = "Old Centiloid",
    y = "MRF Centiloid"
  ) +
  theme_bw()

ggsave(
  file.path(output_dir, "MRF_vs_Old_Centiloid_FBB.png"),
  p1,
  width = 6,
  height = 5,
  dpi = 300
)

############################################
# 2. Old Centiloid: FBB vs FBP
############################################

df_tracers <- df %>%
  filter(
    Tracer %in% c("FBB", "FBP"),
    `Old Centiloid` != 0
  )

min_oldCL <- min(df_tracers$`Old Centiloid`, na.rm = TRUE)
max_oldCL <- max(df_tracers$`Old Centiloid`, na.rm = TRUE)

print(
  df_tracers %>%
    group_by(Tracer) %>%
    summarise(
      n = n(),
      mean_oldCL = mean(`Old Centiloid`, na.rm = TRUE),
      sd_oldCL = sd(`Old Centiloid`, na.rm = TRUE)
    )
)

print(wilcox.test(`Old Centiloid` ~ Tracer, data = df_tracers))

p2 <- ggplot(df_tracers, aes(x = Tracer, y = `Old Centiloid`, fill = Tracer)) +
  geom_boxplot(alpha = 0.6, outlier.shape = NA) +
  geom_jitter(width = 0.15, size = 2) +
  stat_compare_means(method = "wilcox.test") +
  coord_cartesian(ylim = c(min_oldCL, max_oldCL)) +
  labs(
    title = "Old Centiloid by Tracer",
    x = "Tracer",
    y = "Old Centiloid"
  ) +
  theme_bw() +
  theme(legend.position = "none")

ggsave(
  file.path(output_dir, "Old_Centiloid_by_Tracer.png"),
  p2,
  width = 6,
  height = 5,
  dpi = 300
)

############################################
# 3. mSUVr vs MRF Centiloid
############################################

df_msu <- df %>%
  filter(
    mSUVr != 0,
    `MRF Centiloid` != 0
  )

min_msu <- min(df_msu$mSUVr, na.rm = TRUE)
max_msu <- max(df_msu$mSUVr, na.rm = TRUE)

min_mrf <- min(df_msu$`MRF Centiloid`, na.rm = TRUE)
max_mrf <- max(df_msu$`MRF Centiloid`, na.rm = TRUE)

print(
  cor.test(
    df_msu$mSUVr,
    df_msu$`MRF Centiloid`,
    method = "pearson"
  )
)

p3 <- ggplot(df_msu, aes(x = mSUVr, y = `MRF Centiloid`, color = Tracer)) +
  geom_point(size = 2) +
  geom_smooth(method = "lm", se = FALSE) +
  stat_cor(
    aes(label = paste(..r.label.., ..p.label.., sep = "~`,`~")),
    method = "pearson"
  ) +
  coord_cartesian(xlim = c(min_msu, max_msu), ylim = c(min_mrf, max_mrf)) +
  labs(
    title = "mSUVr vs MRF Centiloid",
    x = "mSUVr",
    y = "MRF Centiloid"
  ) +
  theme_bw()

ggsave(
  file.path(output_dir, "mSUVr_vs_MRF_Centiloid.png"),
  p3,
  width = 6,
  height = 5,
  dpi = 300
)

############################################
# 4. MRF Centiloid vs Age
############################################

df_age <- df %>%
  filter(
    age != 0,
    `MRF Centiloid` != 0
  )

min_age <- min(df_age$age, na.rm = TRUE)
max_age <- max(df_age$age, na.rm = TRUE)

min_mrf_age <- min(df_age$`MRF Centiloid`, na.rm = TRUE)
max_mrf_age <- max(df_age$`MRF Centiloid`, na.rm = TRUE)

print(
  cor.test(
    df_age$age,
    df_age$`MRF Centiloid`,
    method = "pearson"
  )
)

p4 <- ggplot(df_age, aes(x = age, y = `MRF Centiloid`)) +
  geom_point(size = 2) +
  geom_smooth(method = "lm", se = FALSE) +
  stat_cor(method = "pearson") +
  coord_cartesian(
    xlim = c(min_age, max_age),
    ylim = c(min_mrf_age, max_mrf_age)
  ) +
  labs(
    title = "MRF Centiloid vs Age",
    x = "Age (years)",
    y = "MRF Centiloid"
  ) +
  theme_bw()

ggsave(
  file.path(output_dir, "MRF_Centiloid_vs_Age.png"),
  p4,
  width = 6,
  height = 5,
  dpi = 300
)

cat("All analyses complete. Plots saved to:", output_dir, "\n")
