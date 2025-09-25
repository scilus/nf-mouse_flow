process MOUSE_IMAGECOMBINE {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilpy:2.2.0_cpu"

    input:
        tuple val(meta), path(l_side), path(r_side)

    output:
        tuple val(meta), path("*mask.nii.gz")  , emit: mask_combined
        path "versions.yml"               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_mask" : "mask"
    """
    scil_volume_math addition $l_side $r_side ${prefix}__${suffix}.nii.gz --data_type uint8 -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_volume_math -h

    touch ${prefix}__masks

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}