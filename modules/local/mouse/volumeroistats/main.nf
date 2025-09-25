process MOUSE_VOLUMEROISTATS {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilpy:2.2.0_cpu"

    input:
        tuple val(meta), path(metrics_list), path(mask_directory)
    output:
        tuple val(meta), path("*__stats.json")   , emit: stats
        path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    shopt -s extglob
    mkdir metrics
    mkdir masks
    
    for metric in $metrics_list;
    do
        pos=\$((\$(echo \$metric | grep -b -o __ | cut -d: -f1)+2))
        bname=\${metric:\$pos}
        bname=\$(basename \$bname .nii.gz)
        mv \$metric metrics/\${bname}.nii.gz
    done

    for mask in $mask_directory/*nii.gz;
    do
        bmask=\$(basename \$mask)
        pos=\$((\$(echo \$bmask | grep -b -o __ | cut -d: -f1)+2))
        bname=\${bmask:\$pos}
        bname=\$(basename \$bname .nii.gz)
        cp \$mask masks/\${bname}.nii.gz
    done

    scil_volume_stats_in_ROI masks/*gz --metrics_dir metrics -f > ${prefix}__stats.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_volume_stats_in_ROI -h

    touch ${prefix}__stats.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}