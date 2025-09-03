
base = '/Volumes/Analysis/Imaging_Analysis/lst/02_Data' %path to raw struc data
subj = {'M142'} %subject IDs

for i=1:length(subj)
    clear matlabbatch
    matlabbatch{1}.spm.tools.LST.lga.data_T1 = {[base '/' subj{i} '/T1.nii,1']};
    matlabbatch{1}.spm.tools.LST.lga.data_F2 = {[base '/' subj{i} '/T2.nii,1']};
    matlabbatch{1}.spm.tools.LST.lga.opts_lga.initial = 0.25;
    matlabbatch{1}.spm.tools.LST.lga.opts_lga.mrf = 1;
    matlabbatch{1}.spm.tools.LST.lga.opts_lga.maxiter = 50;
    matlabbatch{1}.spm.tools.LST.lga.html_report = 1;
    spm_jobman('run',matlabbatch);
end
