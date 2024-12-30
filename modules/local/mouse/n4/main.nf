process MOUSE_N4 {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "https://scil.usherbrooke.ca/containers/scilus_2.0.2.sif":
        "scilus/scilus:2.0.2"}"

    input:
        tuple val(meta), path(dwi), path(b0), path(mask)
    output:
        tuple val(meta), path("*__dwi_n4.nii.gz")       , emit: dwi_n4
        tuple val(meta), path("*__b0_n4.nii.gz")        , emit: b0_n4
        tuple val(meta), path("*__bias_field_b0.nii.gz"), emit: bias_field
        path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def threshold = task.ext.threshold ? task.ext.threshold : ""
    def convergence = task.ext.convergence ? task.ext.convergence : ""

    """
	export OMP_NUM_THREADS=$task.cpus
	export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
	export OPENBLAS_NUM_THREADS=1

	N4BiasFieldCorrection -i $b0 -x $mask -o [${prefix}__b0_n4.nii.gz, ${prefix}__bias_field_b0.nii.gz] -c [$convergence, $threshold]
	scil_dwi_apply_bias_field.py $dwi ${prefix}__bias_field_b0.nii.gz ${prefix}__dwi_n4.nii.gz -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
        N4BiasFieldCorrection: \$(maskbackgroundnoise -h)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_apply_bias_field.py -h
    N4BiasFieldCorrection -h

    touch ${prefix}__dwi_n4.nii.gz
    touch ${prefix}__b0_n4.nii.gz
    touch ${prefix}__bias_field_b0.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')

    END_VERSIONS
    """
}