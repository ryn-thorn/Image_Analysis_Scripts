export base=/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Analysis_reorg/nomis/02_Data
export analysis=/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Analysis_reorg/nomis/03_Analysis
export nomis=/Users/kayti/Repos/NOMIS/NOMIS/NOMIS.py
export csv=/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Analysis_reorg/nomis/01_Protocols/PUMA_norms_last_subj.csv
export output=/Volumes/vdrive/helpern_users/benitez_a/PUMA/PUMA_Analysis_reorg/nomis/04_Summary/last_subjects

for i in M159 ; do 
  recon-all -all -i $base/${i}/${i}_T1.nii -sd $base/${i} -subjid ${i}
done

