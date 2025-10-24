import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# =========================
# Input
# =========================
input_file = "/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_Summary_Files/pet/centiloid_project/MiM_Centiloids.csv"
output_folder = os.path.dirname(input_file)

data = pd.read_csv(input_file)

# Ensure numeric columns
num_cols = ["Calibrated Centiloid", "MiM Centiloid", "MeanSUVR", "MiM_SUVr"]
for col in num_cols:
    data[col] = pd.to_numeric(data[col], errors='coerce')

data = data.dropna(subset=num_cols)

# =========================
# Prepare long-form data for violins
# =========================
centiloid_long = data.melt(id_vars=["Tracer"], 
                           value_vars=["Calibrated Centiloid","MiM Centiloid"],
                           var_name="Type", value_name="Centiloid")
suvr_long = data.melt(id_vars=["Tracer"], 
                      value_vars=["MeanSUVR","MiM_SUVr"],
                      var_name="Type", value_name="SUVR")

# =========================
# 1. Plots BY TRACER
# =========================
palette_tracer = {"Florbetapir": "#E88BD4", "Florbetaben": "#8BE8CF"}

fig, axes = plt.subplots(2,2, figsize=(14,12))

# Scatter: Centiloid
sns.scatterplot(ax=axes[0,0], data=data, x="Calibrated Centiloid", y="MiM Centiloid",
                hue="Tracer", style="Tracer", s=70, palette=palette_tracer)
axes[0,0].plot([-35,150], [-35,150], 'k--')
axes[0,0].set_xlim(-35,150)
axes[0,0].set_ylim(-35,150)
axes[0,0].set_title("MiM Centiloid vs Calibrated Centiloid")
axes[0,0].set_xlabel("Calibrated Centiloid")
axes[0,0].set_ylabel("MiM Centiloid")

# Scatter: SUVR
sns.scatterplot(ax=axes[0,1], data=data, x="MeanSUVR", y="MiM_SUVr",
                hue="Tracer", style="Tracer", s=70, palette=palette_tracer)
axes[0,1].plot([0.8,2],[0.8,2],'k--')
axes[0,1].set_xlim(0.8,2)
axes[0,1].set_ylim(0.8,2)
axes[0,1].set_title("MiM SUVR vs Mean SUVR")
axes[0,1].set_xlabel("Mean SUVR")
axes[0,1].set_ylabel("MiM SUVR")

# Violin: Centiloid
sns.violinplot(ax=axes[1,0], data=centiloid_long, x="Type", y="Centiloid", hue="Tracer",
               split=False, inner="box", palette=palette_tracer)
sns.stripplot(ax=axes[1,0], data=centiloid_long, x="Type", y="Centiloid", hue="Tracer",
              dodge=True, color='black', size=4, alpha=0.7)
axes[1,0].set_ylim(-35,150)
axes[1,0].set_title("Distribution: MiM vs Calibrated Centiloids")
axes[1,0].set_ylabel("Centiloid Value")
axes[1,0].set_xlabel("")
axes[1,0].legend_.remove()

# Violin: SUVR
sns.violinplot(ax=axes[1,1], data=suvr_long, x="Type", y="SUVR", hue="Tracer",
               split=False, inner="box", palette=palette_tracer)
sns.stripplot(ax=axes[1,1], data=suvr_long, x="Type", y="SUVR", hue="Tracer",
              dodge=True, color='black', size=4, alpha=0.7)
axes[1,1].set_ylim(0.8,2)
axes[1,1].set_title("Distribution: MiM SUVR vs Mean SUVR")
axes[1,1].set_ylabel("SUVR")
axes[1,1].set_xlabel("")
axes[1,1].legend_.remove()

# Shared legend
handles, labels = axes[0,0].get_legend_handles_labels()
fig.legend(handles, labels, loc="upper center", ncol=2, title="Tracer")

plt.tight_layout(rect=[0,0,1,0.95])
plt.savefig(os.path.join(output_folder, "MiM_All_Plots_Combined_byTracer.png"), dpi=300)
plt.close()

# =========================
# 2. Plots WITHOUT TRACER
# =========================
fig, axes = plt.subplots(2,2, figsize=(14,12))

# Scatter: Centiloid
sns.scatterplot(ax=axes[0,0], data=data, x="Calibrated Centiloid", y="MiM Centiloid",
                color='steelblue', s=70)
axes[0,0].plot([-35,150], [-35,150], 'k--')
axes[0,0].set_xlim(-35,150)
axes[0,0].set_ylim(-35,150)
axes[0,0].set_title("MiM Centiloid vs Calibrated Centiloid")
axes[0,0].set_xlabel("Calibrated Centiloid")
axes[0,0].set_ylabel("MiM Centiloid")

# Scatter: SUVR
sns.scatterplot(ax=axes[0,1], data=data, x="MeanSUVR", y="MiM_SUVr",
                color='steelblue', s=70)
axes[0,1].plot([0.8,2],[0.8,2],'k--')
axes[0,1].set_xlim(0.8,2)
axes[0,1].set_ylim(0.8,2)
axes[0,1].set_title("MiM SUVR vs Mean SUVR")
axes[0,1].set_xlabel("Mean SUVR")
axes[0,1].set_ylabel("MiM SUVR")

# Violin: Centiloid
sns.violinplot(ax=axes[1,0], data=centiloid_long, x="Type", y="Centiloid", color='steelblue', inner="box")
sns.stripplot(ax=axes[1,0], data=centiloid_long, x="Type", y="Centiloid", color='black', size=4, alpha=0.7)
axes[1,0].set_ylim(-35,150)
axes[1,0].set_title("Distribution: MiM vs Calibrated Centiloids")
axes[1,0].set_ylabel("Centiloid Value")
axes[1,0].set_xlabel("")

# Violin: SUVR
sns.violinplot(ax=axes[1,1], data=suvr_long, x="Type", y="SUVR", color='steelblue', inner="box")
sns.stripplot(ax=axes[1,1], data=suvr_long, x="Type", y="SUVR", color='black', size=4, alpha=0.7)
axes[1,1].set_ylim(0.8,2)
axes[1,1].set_title("Distribution: MiM SUVR vs Mean SUVR")
axes[1,1].set_ylabel("SUVR")
axes[1,1].set_xlabel("")

plt.tight_layout()
plt.savefig(os.path.join(output_folder, "MiM_All_Plots_Combined_noTracer.png"), dpi=300)
plt.show()
