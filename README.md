These are generic image analysis scripts that I have written, collected, 
and otherwise given cobbled-together life to through much trial and error during my time 
at MUSC in the BRIDGE Lab. Versions of these scripts can be found in various studies' 
"STUDY_code" BIDS folders. These are here as a log/reference do the most basic, generic 
forms of these scripts, not modified for any particular study's analysis pipeline.

www.bridge-lab.org</br>
www.bridgelab.info</br>

<img src="https://www.bridge-lab.org/storage/329/9f17e7e8-434b-4d67-85f7-bc57bcd496cc/bridge-logo.png">

<h1>Script Documentation</h1>

<h2>Preprocessing</h2>

Standard PyDesigner processing: 

<pre><code>/path/to/pyd_preproc.sh --base /path/to/BIDS_folder</code></pre>

<h2>Registration</h2>

Integrated DTI-TK and TBSS with optional ROI Analysis: 

<pre><code>
# 1_DTI-TK.sh
   /path/to/1_DTI-TK.sh \
      --input /path/to/dki_pydesigner \
      --output /path/to/dti-tk \
      --subjects sub-101 sub-104 sub-110 \
      --bet-thr 0.25
</code></pre>
      
<pre><code>
# 2_TBSS.sh
   /path/to//2_TBSS.sh \
      --input /path/to/derivatives/dti-tk \
      --output /path/to/derivatives/tbss \
      --subjects sub-101 sub-104 sub-110 \
      --wmmets    
</code></pre>

<pre><code>
# 3_Stats.sh
   /path/to//3_StatsS.sh \
      coming soon!    
</code></pre>

<h2>Segmentation</h2>

Freesurfer recon-all -all Segmentation: 

<pre><code>
    /path/to/freesurfer-reconall.sh \
       --input /path/to/T1s \
       --output /path/to/freesurfer_output \
       --subjects A001 A002 A003
</code></pre>

NOMIS Normalization: 

<pre><code>
    /path/to/FS_NOMIS.sh \
       --base /base/derivatives/freesurfer \
       --csv /path/to/PUMA_norms.csv \
       --nomis /path/to/NOMIS.py \
       --output /base/derivatives/nomis \
       --env [name of nomis conda env]
</code></pre>

Lesion Segmentation Tool: 

<pre><code>
    /path/to/run_lst.sh /path/to/raw_data_ /path/to/Outputs 
</code></pre>

<h2>Native Space Analysis</h2>

Gross White Matter Estimation: 

<pre><code>
    /path/to/gross_wm_thr.sh /path/to/base_dir /path/to/out_dir /path/to/output.csv 
</code></pre>

<h2>PET and MRS</h2>

Centiloid Processing: 

MRS T1 Mask Conversion:

<pre><code>
    python MRS_T1_Mask.py <mrs_complex_nifti> <t1_nifti> <output_mask> 
</code></pre>

<h2>Miscellaneous</h2>

Converting a complex NiFTi to a FLOAT23 NiFTi: 

<pre><code>
    python convert_complex_to_float.py input.nii output.nii
</code></pre>

