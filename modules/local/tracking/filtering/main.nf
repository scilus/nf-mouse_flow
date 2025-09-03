process TRACKING_FILTERING {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0'}"

    input:
        tuple val(meta), path(tractogram), path(mask_include), path(mask_exclude)
    output:
        tuple val(meta), path("*_tracking.trk")   , emit: trk
        tuple val(meta), path("*_tracking_mqc.png"), emit: mqc
        tuple val(meta), path("*_tracking_stats_mqc.json") , emit: mqc_json
        path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? task.ext.suffix : "bundle"

    def run_qc = task.ext.run_qc ? task.ext.run_qc : false

    """
    scil_tractogram_filter_by_roi.py ${tractogram} ${prefix}__${suffix}_tracking.trk \
        --drawn_roi $mask_include any include \
        --drawn_roi $mask_exclude any exclude -f

    if $run_qc;
    then

        # Create dummy image for visualization
        scil_tractogram_compute_density_map.py ${prefix}__${suffix}_tracking.trk \
            tmp_anat_qc.nii.gz -f

        scil_viz_bundle_screenshot_mosaic.py tmp_anat_qc.nii.gz ${prefix}__${suffix}_tracking.trk\
            ${prefix}__${suffix}_tracking_mqc.png --opacity_background 1 --light_screenshot
        scil_tractogram_print_info.py ${prefix}__${suffix}_tracking.trk >> ${prefix}__${suffix}_tracking_stats_mqc.json
    fi
    rm -f tmp_anat_qc.nii.gz

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