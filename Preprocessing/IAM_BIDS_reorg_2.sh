#!/usr/bin/env bash
set -euo pipefail

# ============================================
# IAM BIDS Copy & Reorganize (Fixed)
# Version: 2.0
# ============================================

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <SRC_BIDS_WRONG> <DEST_BIDS>"
    exit 1
fi

SRC_BASE="$1"
DEST_BASE="$2"

echo "=== IAM BIDS Copy & Reorganize (Fixed) ==="
echo "Started: $(date)"
echo "Source: $SRC_BASE"
echo "Destination: $DEST_BASE"
echo ""

# ============================================
# 🧩 Sequence rename mapping (quoted for safety)
# ============================================
declare -A rename_map=(
  ["01_AAHead_Scout_32ch-head-coil"]="01_AAHead_Scout_32ch-head-coil"
  ["02_AAHead_Scout_32ch-head-coil_MPR_sag_i00001"]="02_AAHead_Scout_32ch-head-coil_MPR_sag_i00001"
  ["02_AAHead_Scout_32ch-head-coil_MPR_sag_i00002"]="02_AAHead_Scout_32ch-head-coil_MPR_sag_i00002"
  ["02_AAHead_Scout_32ch-head-coil_MPR_sag_i00003"]="02_AAHead_Scout_32ch-head-coil_MPR_sag_i00003"
  ["02_AAHead_Scout_32ch-head-coil_MPR_sag_i00004"]="02_AAHead_Scout_32ch-head-coil_MPR_sag_i00004"
  ["03_AAHead_Scout_32ch-head-coil_MPR_cor_i00001"]="03_AAHead_Scout_32ch-head-coil_MPR_cor_i00001"
  ["03_AAHead_Scout_32ch-head-coil_MPR_cor_i00002"]="03_AAHead_Scout_32ch-head-coil_MPR_cor_i00002"
  ["03_AAHead_Scout_32ch-head-coil_MPR_cor_i00003"]="03_AAHead_Scout_32ch-head-coil_MPR_cor_i00003"
  ["04_AAHead_Scout_32ch-head-coil_MPR_tra_i00001"]="04_AAHead_Scout_32ch-head-coil_MPR_tra_i00001"
  ["04_AAHead_Scout_32ch-head-coil_MPR_tra_i00002"]="04_AAHead_Scout_32ch-head-coil_MPR_tra_i00002"
  ["04_AAHead_Scout_32ch-head-coil_MPR_tra_i00003"]="04_AAHead_Scout_32ch-head-coil_MPR_tra_i00003"
  ["05_t1_mprage_sag_p2_iso"]="T1w"
  ["08_sms3_3_0iso_Task"]="Task"
  ["09_sms3_3_0iso_Resting_State_1"]="Resting_State_1"
  ["10_sms3_3_0iso_Resting_State_2"]="Resting_State_2"
  ["11_gre_field_mapping_e1"]="field_map_e1"
  ["11_gre_field_mapping_e2"]="field_map_e2"
  ["12_gre_field_mapping_e2_ph"]="field_map_e2_ph"
  ["13_DKI_BIPOLAR_2_5mm_64dir_50slices"]="DKI_64dir"
  ["14_DKI_BIPOLAR_2_5mm_64dir_50slices_TOP_UP_PA"]="DKI_64dir_TOPUP"
  ["15_t2_tse_dark-fluid_tra"]="T2w"
  ["16_FBI_b6000_128"]="FBI"
  ["17_DKI_30_Dir"]="DKI_30dir"
  ["18_DKI_30_Dir_TOP_UP_PA"]="DKI_30dir_TOPUP"
  ["ViSTa_2"]="ViSTa"
  ["ViSTa_REF_2"]="ViSTa_REF"
)

# ============================================
# 🧠 Function to get modality folder
# ============================================
get_modality_folder() {
  local seq="$1"
  case "$seq" in
    *T1w*|*T2w*) echo "anat" ;;
    *DKI*|*FBI*) echo "dwi" ;;
    *Resting*|*Task*) echo "func" ;;
    *field_map*) echo "fmap" ;;
    *ViSTa*) echo "vista" ;;
    *) echo "other" ;;
  esac
}

# ============================================
# 🧩 Copy and rename logic
# ============================================
for subj_dir in "$SRC_BASE"/sub-*; do
  subj=$(basename "$subj_dir")
  echo "🔄 Processing $subj ..."
  
  for ses_dir in "$subj_dir"/ses-*; do
    ses=$(basename "$ses_dir")
    echo "   → $ses"

    # ensure dest session path
    dest_ses="$DEST_BASE/$subj/$ses"
    mkdir -p "$dest_ses"

    # iterate through each sequence folder
    for seq_dir in "$ses_dir"/*; do
      [[ -d "$seq_dir" ]] || continue
      seq_name=$(basename "$seq_dir")
      new_name="${rename_map[$seq_name]:-$seq_name}"
      modality=$(get_modality_folder "$new_name")

      dest_mod="$dest_ses/$modality"
      mkdir -p "$dest_mod"

      echo "      • Copying $seq_name → $modality/$new_name"
      cp -R "$seq_dir" "$dest_mod/$new_name"
    done
  done
done

echo ""
echo "✅ Reorganization complete!"
echo "Finished: $(date)"
