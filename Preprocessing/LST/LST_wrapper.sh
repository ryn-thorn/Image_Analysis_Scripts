#!/bin/bash
###############################
#
# usage: ./run_lst.sh /Volumes/Analysis/Imaging_Analysis/lst/02_Data /Volumes/Analysis/Outputs
#
###############################

#!/bin/bash
BASE=$1     # e.g. /Volumes/Analysis/Imaging_Analysis/lst/02_Data
OUT=$2      # output path

matlab -nodisplay -nosplash -r "run_lga('$BASE', '$OUT'); exit"

