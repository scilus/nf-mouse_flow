process IMAGE_EXTRACTSHELLS {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.0_cpu"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*__shells.nii.gz")   , emit: shells
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? "--tolerance " + task.ext.dwi_shell_tolerance : ""
    def min_shell_value = task.ext.min_shell_value ?: 0     /* Default value for min_fodf_shell_value */
    def max_shell_value = task.ext.max_shell_value ?: 10000000     /* Default value for min_fodf_shell_value */
    def shells = task.ext.shells ?: "\$(tr ' ' '\n' < b136_dwi.bval | awk -v min=${min_shell_value} -v max=${max_shell_value} '{v=int(\$1)} v>=min && v<=max {print v}' | sort -nu | xargs)"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_shell $dwi $bval $bvec $shells \
                ${prefix}__shells.nii.gz ${prefix}__shells.bval ${prefix}__shells.bvec \
                $dwi_shell_tolerance -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell -h

    touch ${prefix}_b0.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
