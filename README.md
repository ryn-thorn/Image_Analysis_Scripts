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

Standard PyDesigner processing: 

<pre><code>/path/to/pyd_preproc.sh --base /path/to/BIDS_folder</code></pre>

<h2>Native Space Analysis</h2>

Standard PyDesigner processing: 

<pre><code>/path/to/pyd_preproc.sh --base /path/to/BIDS_folder</code></pre>

<h2>PET and MRS</h2>

Standard PyDesigner processing: 

<pre><code>/path/to/pyd_preproc.sh --base /path/to/BIDS_folder</code></pre>

<h2>Miscellaneous</h2>

Standard PyDesigner processing: 

<pre><code>/path/to/pyd_preproc.sh --base /path/to/BIDS_folder</code></pre>