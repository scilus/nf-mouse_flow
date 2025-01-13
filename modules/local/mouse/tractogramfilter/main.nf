process MOUSE_TRACTOGRAMFILTER {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.0.2.sif':
        'scilus/scilus:2.0.2' }"

    input:
        tuple val(meta), path(trk), path(mask1), path(mask2)

    output:
        tuple val(meta), path("*_filtered.trk"), emit: trk_filtered
        path "versions.yml"                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_filtered" : "filtered"
    def mode_mask1 = task.ext.mode_mask1 ?: "any"
    def mode_mask2 = task.ext.mode_mask2 ?: "any"
    def criteria_mask1 = task.ext.criteria_mask1 ?: "include"
    def criteria_mask2 = task.ext.criteria_mask2 ?: "include"
    def alpha = task.ext.alpha ?: "0.6"

    """
    scil_tractogram_filter_by_roi.py ${trk} ${prefix}__tmp.trk \
        --drawn_roi ${mask1} ${mode_mask1} ${criteria_mask1} \
        --drawn_roi ${mask2} ${mode_mask2} ${criteria_mask2}
    
    scil_bundle_reject_outliers.py ${prefix}__tmp.trk ${prefix}__${suffix}.trk --alpha ${alpha}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_filtered" : "filtered"
    """
    scil_tractogram_filter_by_roi.py -h

    touch ${prefix}__${suffix}.trk

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}