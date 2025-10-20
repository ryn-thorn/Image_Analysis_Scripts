function centiloid_batch_florbetaben
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

    root_dir = '/Volumes/vdrive/helpern_users/helpern_j/IAM/IAM_Analysis/IAM_BIDS/derivatives/pet/pet_suv/florbetaben';
    subj_dirs = dir(fullfile(root_dir, 'IAM_*'));

    out_csv = fullfile(root_dir, 'centiloid_results_florbetaben.csv');  
    fid = fopen(out_csv,'w');  
    if fid == -1
        error('Could not open output CSV file: %s', out_csv);
    end
    fprintf(fid, 'SubjectID,MeanSUVR,Centiloid\n');

    % Standard VOIs (MNI space)
    voi_cortex = fullfile(root_dir, 'Centiloid_Std_VOI/nifti/1mm/voi_ctx_1mm.nii');  
    voi_cereb  = fullfile(root_dir, 'Centiloid_Std_VOI/nifti/1mm/voi_WhlCblBrnStm_1mm.nii');  

    for s = 1:length(subj_dirs)
        subj_id = subj_dirs(s).name;
        subj_dir = fullfile(root_dir, subj_id);
        fprintf('--- Processing %s ---\n', subj_id);

        % Locate T1 and SUV_REG (already in T1 space)
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
            matlabbatch{1}.spm.spatial.preproc.warp.reg = [4 4 4 4 4];  
            matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
            matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
            matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
            matlabbatch{1}.spm.spatial.preproc.warp.write = [0 1];  % deformation field only
            spm_jobman('run', matlabbatch);

            def_file = fullfile(subj_dir,'y_T1.nii'); 

            %% Step 2: Invert deformation to warp VOIs into native space
            matlabbatch = {};
            matlabbatch{1}.spm.util.defs.comp{1}.def = {def_file};
            matlabbatch{1}.spm.util.defs.comp{2}.inv.comp{1}.def = {def_file};
            matlabbatch{1}.spm.util.defs.comp{2}.inv.space = {t1};
            matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = {voi_cortex};
            matlabbatch{1}.spm.util.defs.out{1}.pull.savedir.saveusr = {subj_dir};
            matlabbatch{1}.spm.util.defs.out{1}.pull.interp = 0; % nearest neighbour
            matlabbatch{1}.spm.util.defs.out{1}.pull.mask = 1;
            matlabbatch{1}.spm.util.defs.out{1}.pull.fwhm = [0 0 0];
            matlabbatch{1}.spm.util.defs.out{1}.pull.prefix = 'i';
            spm_jobman('run', matlabbatch);

            matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = {voi_cereb};
            spm_jobman('run', matlabbatch);

            resliced_cortex = fullfile(subj_dir, ['i' sog_name(voi_cortex)]);
            resliced_cereb  = fullfile(subj_dir, ['i' sog_name(voi_cereb)]);

            %% Step 3: Extract SUVR
            Vctx = spm_vol(resliced_cortex);
            Vref = spm_vol(resliced_cereb);
            Yctx = spm_read_vols(Vctx);
            Yref = spm_read_vols(Vref);

            Vpet = spm_vol(suv);
            Ypet = spm_read_vols(Vpet);

            target_vals    = Ypet(Yctx > 0);
            reference_vals = Ypet(Yref > 0);
            target_vals    = target_vals(target_vals>0 & ~isnan(target_vals));
            reference_vals = reference_vals(reference_vals>0 & ~isnan(reference_vals));

            mean_suvr = mean(target_vals)/mean(reference_vals);
            centiloid = 153.4 * mean_suvr - 154.9;  

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