library(ggplot2)
library(ggpubr)
library(dplyr)
library(patchwork)

# -----------------------------
# 1. Load your data
# -----------------------------
data_file <- "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/centiloid_results_both_tracers.csv"
df <- read.csv(data_file, stringsAsFactors = TRUE)

# -----------------------------
# 2. Decide test type function
# -----------------------------
choose_test <- function(df, value_col, group_col){
  groups <- unique(df[[group_col]])
  normal <- sapply(groups, function(g){
    shapiro.test(df[[value_col]][df[[group_col]] == g])$p.value > 0.05
  })
  if(all(normal)){
    return("t.test")
  } else {
    return("wilcox.test")
  }
}

# -----------------------------
# 3. Compute p-value and label
# -----------------------------
get_p_label <- function(df, value_col, group_col){
  test_method <- choose_test(df, value_col, group_col)
  cm <- compare_means(as.formula(paste(value_col, "~", group_col)), data=df, method=test_method)
  pval <- cm$p
  p_text <- ifelse(pval < 0.001, "p < 0.001", paste0("p = ", round(pval,3)))
  label <- paste0(p_text, " (", test_method, ")")
  return(label)
}

p_label_suvr <- get_p_label(df, "MeanSUVR", "Tracer")
p_label_cent <- get_p_label(df, "Centiloid", "Tracer")

# -----------------------------
# 4. Summary stats
# -----------------------------
summary_stats <- df %>%
  group_by(Tracer) %>%
  summarise(
    mean_SUVR = mean(MeanSUVR),
    sd_SUVR   = sd(MeanSUVR),
    mean_Cent = mean(Centiloid),
    sd_Cent   = sd(Centiloid)
  )

# -----------------------------
# 5. Plot MeanSUVR
# -----------------------------
y_max_suvr <- max(df$MeanSUVR, na.rm=TRUE)  # dynamic y-axis for label
p1 <- ggplot(df, aes(x=Tracer, y=MeanSUVR, color=Tracer)) +
  geom_boxplot(outlier.shape = NA, alpha=0.3) +
  geom_jitter(width=0.15, size=2) +
  annotate("text", x=1.5, y=y_max_suvr + 0.05*y_max_suvr, label=p_label_suvr, size=5) +
  geom_text(
    data = summary_stats, 
    aes(x=Tracer, y=mean_SUVR + sd_SUVR + 0.05*y_max_suvr, 
        label = paste0("Mean±SD: ", round(mean_SUVR,2), "±", round(sd_SUVR,2))),
    inherit.aes = FALSE,
    size=5
  ) +
  theme_minimal(base_size = 16) +
  labs(title="MeanSUVR by Tracer", y="Mean SUV Ratio", x="Tracer") +
  theme(legend.position = "none",
        plot.title = element_text(size=18, face="bold"),
        axis.title = element_text(size=16),
        axis.text = element_text(size=14))

# -----------------------------
# 6. Plot Centiloid
# -----------------------------
y_max_cent <- max(df$Centiloid, na.rm=TRUE)
p2 <- ggplot(df, aes(x=Tracer, y=Centiloid, color=Tracer)) +
  geom_boxplot(outlier.shape = NA, alpha=0.3) +
  geom_jitter(width=0.15, size=2) +
  annotate("text", x=1.5, y=y_max_cent + 0.05*y_max_cent, label=p_label_cent, size=5) +
  geom_text(
    data = summary_stats, 
    aes(x=Tracer, y=mean_Cent + sd_Cent + 0.05*y_max_cent, 
        label = paste0("Mean±SD: ", round(mean_Cent,1), "±", round(sd_Cent,1))),
    inherit.aes = FALSE,
    size=5
  ) +
  theme_minimal(base_size = 16) +
  labs(title="Centiloid by Tracer", y="Centiloid", x="Tracer") +
  theme(legend.position = "none",
        plot.title = element_text(size=18, face="bold"),
        axis.title = element_text(size=16),
        axis.text = element_text(size=14))

# -----------------------------
# 7. Combine and save
# -----------------------------
combined_plot <- p1 + p2 + plot_layout(ncol=2)
print(combined_plot)

ggsave("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/MeanSUVR_by_Tracer.pdf", p1, width=6, height=5)
ggsave("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Centiloid_by_Tracer.pdf", p2, width=6, height=5)
ggsave("/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/centiloid_project/Combined_SUVR_Centiloid.pdf", combined_plot, width=12, height=5)
