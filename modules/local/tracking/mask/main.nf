process TRACKING_MASK {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif":
        "scilus/scilus:2.1.0"}"

    input:
        tuple val(meta), path(mask), path(ano)
    output:
        tuple val(meta), path("*__tracking_mask.nii.gz")   , emit: tracking_mask
        tuple val(meta), path("*__seeding_mask.nii.gz")   , emit: seeding_mask
        path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ventricules_labels_ids = task.ext.ventricules_labels_ids ? task.ext.ventricules_labels_ids : ""
    def seeding_labels_ids = task.ext.seeding_labels_ids ? task.ext.seeding_labels_ids : ""

    """
    scil_volume_math.py convert $ano $ano --data_type int16 -f
    scil_labels_combine.py ${prefix}__ventricles_mask.nii.gz \
        --volume_ids $ano $ventricules_labels_ids \
        --merge_groups -f
    scil_labels_combine.py ${prefix}__seeding_mask.nii.gz \
        --volume_ids $ano $seeding_labels_ids \
        --merge_groups -f

    scil_volume_math.py subtraction $mask ${prefix}__ventricles_mask.nii.gz ${prefix}__tracking_mask.nii.gz --data_type uint8 -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_labels_combine -h

    touch ${prefix}__tracking_mask.nii.gz
    touch ${prefix}__seeding_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)

    END_VERSIONS
    """
}