library(ggplot2)

# ---- Input your CSV path here ----
csv_path <- "/Users/kayti/Desktop/Projects/IAM/Centiloids/FBB_centiloids.csv"   # change this to your actual file
df <- read.csv(csv_path)

# ---- Plot 1: Centiloid vs Age ----
p1 <- ggplot(df, aes(x=Age, y=Centiloid, color=amyloid)) +
  geom_point(size=3) +
  geom_smooth(method="lm", se=FALSE) +
  theme_minimal() +
  labs(title="Centiloid vs Age", y="Centiloid")

ggsave("/Users/kayti/Desktop/Projects/IAM/Centiloids/Centiloid_vs_Age.pdf", plot=p1, width=6, height=5)

# ---- Plot 2: MeanSUVR vs Age ----
p2 <- ggplot(df, aes(x=Age, y=MeanSUVR, color=amyloid)) +
  geom_point(size=3) +
  geom_smooth(method="lm", se=FALSE) +
  theme_minimal() +
  labs(title="MeanSUVR vs Age", y="MeanSUVR")

ggsave("/Users/kayti/Desktop/Projects/IAM/Centiloids/MeanSUVR_vs_Age.pdf", plot=p2, width=6, height=5)

# ---- Plot 3: Combined with dual axis ----
p3 <- ggplot(df, aes(x=Age)) +
  geom_point(aes(y=Centiloid, color="Centiloid"), size=3) +
  geom_point(aes(y=MeanSUVR*50, color="MeanSUVR"), size=3) +  # scale SUVr
  scale_y_continuous(
    name = "Centiloid",
    sec.axis = sec_axis(~./50, name="MeanSUVR")
  ) +
  theme_minimal() +
  labs(title="Centiloid and MeanSUVR vs Age") +
  scale_color_manual(values=c("Centiloid"="blue", "MeanSUVR"="red")) +
  theme(legend.title=element_blank())

ggsave("/Users/kayti/Desktop/Projects/IAM/Centiloids/Centiloid_and_MeanSUVR_vs_Age.pdf", plot=p3, width=7, height=5)
