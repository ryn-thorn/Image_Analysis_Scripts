function run_lst(base_dir, outdir)
    % Usage: run_lst('/path/to/base', '/path/to/output')

    if nargin < 2
        error('Usage: run_lga(base_dir, outdir)');
    end

    spm('defaults','PET');  % or 'FMRI' depending on your setup
    spm_jobman('initcfg');

    % List all folders in base_dir
    d = dir(base_dir);
    isub = [d(:).isdir];
    subj_dirs = {d(isub).name};
    subj_dirs = subj_dirs(~ismember(subj_dirs,{'.','..'}));

    % Loop through subjects
    for i = 1:length(subj_dirs)
        subj = subj_dirs{i};
        T1path = fullfile(base_dir, subj, 'T1.nii');
        T2path = fullfile(base_dir, subj, 'T2.nii');

        if ~isfile(T1path) || ~isfile(T2path)
            fprintf('Skipping %s: missing T1/T2\n', subj);
            continue
        end

        fprintf('>>> Processing subject %s\n', subj);

        clear matlabbatch
        matlabbatch{1}.spm.tools.LST.lga.data_T1 = {[T1path ',1']};
        matlabbatch{1}.spm.tools.LST.lga.data_F2 = {[T2path ',1']};
        matlabbatch{1}.spm.tools.LST.lga.opts_lga.initial = 0.25;
        matlabbatch{1}.spm.tools.LST.lga.opts_lga.mrf = 1;
        matlabbatch{1}.spm.tools.LST.lga.opts_lga.maxiter = 50;
        matlabbatch{1}.spm.tools.LST.lga.html_report = 1;

        subj_outdir = fullfile(outdir, subj);
        if ~exist(subj_outdir, 'dir')
            mkdir(subj_outdir);
        end
        matlabbatch{1}.spm.tools.LST.lga.output_directory = {subj_outdir};

        spm_jobman('run', matlabbatch);
    end
end
