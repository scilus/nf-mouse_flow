process PREPROC_SINGLEEDDY {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilus:2.2.0"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec)
    output:
        tuple val(meta), path("*__dwi_eddy_corrected.nii.gz")   , emit: dwi_corrected
        tuple val(meta), path("*__dwi_eddy_corrected.bval")     , emit: bval_corrected
        tuple val(meta), path("*__dwi_eddy_corrected.bvec")     , emit: bvec_corrected
        path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def readout = task.ext.readout ? task.ext.readout : ""
    def encoding = task.ext.encoding ? task.ext.encoding : ""
    def eddy_cmd = task.ext.eddy_cmd
    def extra_args = task.ext.extra_args ?: ""
    def extra_ite = task.ext.extra_ite ?: ""
    def extra_thr = task.ext.extra_thr ?: ""

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OMP_NUM_THREADS=$task.cpus
    export OPENBLAS_NUM_THREADS=1
    export ANTS_RANDOM_SEED=7468

    fslmaths $dwi -Tmean -bin ${prefix}__mask_mec.nii.gz -odt short 
	scil_dwi_prepare_eddy_command $dwi $bval $bvec \
        ${prefix}__mask_mec.nii.gz \
        --encoding_direction $encoding\
        --readout $readout \
        --eddy_cmd $eddy_cmd \
        --out_prefix ${prefix}__ \
        --slice_drop_correction \
        --out_script -f

    echo "--nthr=$extra_thr --very_verbose $extra_args --niter=$extra_ite" >> eddy.sh
	sh eddy.sh
	mv ${prefix}__.nii.gz ${prefix}__dwi_eddy_corrected.nii.gz
	mv ${prefix}__.eddy_rotated_bvecs ${prefix}__dwi_eddy_corrected.bvec
    mv ${bval} ${prefix}__dwi_eddy_corrected.bval

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    fslmaths -h
    scil_dwi_prepare_eddy_command -h

    touch ${prefix}__dwi_eddy_corrected.nii.gz
    touch ${prefix}__dwi_eddy_corrected.bval
    touch ${prefix}__dwi_eddy_corrected.bvec

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """
}
