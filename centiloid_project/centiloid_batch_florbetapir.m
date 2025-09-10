function centiloid_batch_florbetapir
    % ---------------------------------------------------------------------
    % Centiloid batch pipeline for florbetapir
    % Uses standard Centiloid VOIs (GAAIN cortex + whole cerebellum)
    %
    % Equation (Navitsky et al. 2018, standard Centiloid VOIs):
    %   Centiloid = 175 * SUVR - 182 (florbetapir)
    %   Centiloid = 153.4 * SUVR - 154.9 (florbetaben)
    % ---------------------------------------------------------------------

spm('defaults','PET');  
spm_jobman('initcfg');  

root_dir = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv';
subj_dirs = dir(fullfile(root_dir, 'IAM_*'));

out_csv = fullfile(root_dir, 'centiloid_results_florbetapir.csv');  
fid = fopen(out_csv,'w');  
if fid == -1
    error('Could not open output CSV file: %s', out_csv);
end
fprintf(fid, 'SubjectID,MeanSUVR,Centiloid\n');

% Standard VOIs (already in MNI space)
voi_cortex = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/Centiloid_Std_VOI/nifti/1mm/voi_ctx_1mm.nii';  
voi_cereb  = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/Centiloid_Std_VOI/nifti/1mm/voi_WhlCblBrnStm_1mm.nii';  

for s = 1:length(subj_dirs)
    subj_id = subj_dirs(s).name;
    subj_dir = fullfile(root_dir, subj_id);
    fprintf('--- Processing %s ---\n', subj_id);

    % Locate T1 and PET
    t1  = spm_select('FPList', subj_dir, '^T1\.nii$');
    suv = spm_select('FPList', subj_dir, '^SUV_REG\.nii$');
    if isempty(t1) || isempty(suv)
        fprintf('  Missing T1 or SUV_REG, skipping...\n'); 
        continue;
    end
    t1  = strtrim(t1(1,:));
    suv = strtrim(suv(1,:));
    fprintf('  Using T1 : %s\n', t1);
    fprintf('  Using SUV_REG: %s\n', suv);

    try
        %% Step 1: Segment T1 to get deformation field
        matlabbatch = {};
        matlabbatch{1}.spm.spatial.preproc.channel.vols = {t1};
        matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
        matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 60;
        matlabbatch{1}.spm.spatial.preproc.channel.write = [0 0]; 

        for t = 1:6
            matlabbatch{1}.spm.spatial.preproc.tissue(t).tpm = {fullfile(spm('Dir'),'tpm',['TPM.nii,' num2str(t)])};
            matlabbatch{1}.spm.spatial.preproc.tissue(t).ngaus = 1;
            matlabbatch{1}.spm.spatial.preproc.tissue(t).native = [0 0];
            matlabbatch{1}.spm.spatial.preproc.tissue(t).warped = [0 0];
        end

        matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
        matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
        matlabbatch{1}.spm.spatial.preproc.warp.reg = [4 4 4 4 4];  % 1x5 vector
        matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
        matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
        matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
        matlabbatch{1}.spm.spatial.preproc.warp.write = [0 1];  % only write deformation field
        spm_jobman('run', matlabbatch);

        def_file = fullfile(subj_dir,'y_T1.nii'); 

        %% Step 2: Apply deformation to PET
        matlabbatch = {};
        matlabbatch{1}.spm.spatial.normalise.write.subj.def = {def_file};
        matlabbatch{1}.spm.spatial.normalise.write.subj.resample = {suv};
        matlabbatch{1}.spm.spatial.normalise.write.woptions.bb = [-78 -112 -70; 78 76 85];
        matlabbatch{1}.spm.spatial.normalise.write.woptions.vox = [1 1 1];
        matlabbatch{1}.spm.spatial.normalise.write.woptions.interp = 4;
        matlabbatch{1}.spm.spatial.normalise.write.woptions.prefix = 'w';
        spm_jobman('run', matlabbatch);

        [suv_path, suv_name, ext] = fileparts(suv);
        norm_suv = fullfile(suv_path, ['w' suv_name ext]);

        %% Step 3: Reslice VOIs to PET space (SPM12 way)
        resliced_cortex = fullfile(subj_dir, ['r' sog_name(voi_cortex)]);
        resliced_cereb  = fullfile(subj_dir, ['r' sog_name(voi_cereb)]);

        matlabbatch = {};
        matlabbatch{1}.spm.spatial.coreg.write.ref = {norm_suv};
        matlabbatch{1}.spm.spatial.coreg.write.source = {voi_cortex};
        matlabbatch{1}.spm.spatial.coreg.write.roptions.interp = 1; % nearest neighbor
        matlabbatch{1}.spm.spatial.coreg.write.roptions.wrap = [0 0 0];
        matlabbatch{1}.spm.spatial.coreg.write.roptions.mask = 0;
        matlabbatch{1}.spm.spatial.coreg.write.roptions.prefix = 'r';
        spm_jobman('run', matlabbatch);

        matlabbatch{1}.spm.spatial.coreg.write.source = {voi_cereb};
        spm_jobman('run', matlabbatch);

        % Read resliced VOIs
        Vctx = spm_vol(fullfile(fileparts(voi_cortex),['r' sog_name(voi_cortex)]));
        Vref = spm_vol(fullfile(fileparts(voi_cereb),['r' sog_name(voi_cereb)]));
        Yctx = spm_read_vols(Vctx);
        Yref = spm_read_vols(Vref);

        %% Step 4: SUVR and Centiloid calculation
        Vpet = spm_vol(norm_suv);
        Ypet = spm_read_vols(Vpet);

        target_vals    = Ypet(Yctx > 0.5);
        reference_vals = Ypet(Yref > 0.5);
        target_vals    = target_vals(target_vals>0 & ~isnan(target_vals));
        reference_vals = reference_vals(reference_vals>0 & ~isnan(reference_vals));

        mean_suvr = mean(target_vals)/mean(reference_vals);
        centiloid = 175 * mean_suvr - 182;

        fprintf(fid, '%s,%.4f,%.4f\n', subj_id, mean_suvr, centiloid);
        fprintf('  Done: SUVR=%.4f, Centiloid=%.2f\n', mean_suvr, centiloid);

    catch ME
        fprintf('  ERROR in subject %s: %s\n', subj_id, ME.message);
        continue;
    end
end

fclose(fid);
fprintf('Done! Results written to %s\n', out_csv);

end

%% Helper function to get file name from path
function fname = sog_name(path)
[~, fname, ext] = fileparts(path);
fname = [fname ext];
end