process TRACKING_MASK {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_latest.sif':
        'scilus/scilus:latest' }"

    input:
        tuple val(meta), path(mask), path(ano)
    output:
        tuple val(meta), path("*__tracking_mask.nii.gz")   , emit: tracking_mask
        tuple val(meta), path("*__seeding_mask.nii.gz")   , emit: seeding_mask
        tuple val(meta), path("*__mask_tracking_mqc.png"), emit: mqc
        path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ventricules_labels_ids = task.ext.ventricules_labels_ids ? task.ext.ventricules_labels_ids : ""
    def seeding_labels_ids = task.ext.seeding_labels_ids ? task.ext.seeding_labels_ids : ""
    def run_qc = task.ext.run_qc ? task.ext.run_qc : false

    """
    scil_volume_math.py convert $ano $ano --data_type int16 -f
    scil_labels_combine.py ${prefix}__ventricles_mask.nii.gz \
        --volume_ids $ano $ventricules_labels_ids \
        --merge_groups -f
    scil_labels_combine.py ${prefix}__seeding_mask.nii.gz \
        --volume_ids $ano $seeding_labels_ids \
        --merge_groups -f
    scil_volume_math.py convert ${prefix}__ventricles_mask.nii.gz  ${prefix}__ventricles_mask.nii.gz --data_type uint8 -f

    scil_volume_math.py difference $mask ${prefix}__ventricles_mask.nii.gz ${prefix}__tracking_mask.nii.gz --data_type uint8 -f

    if $run_qc;
    then
        nii_files=\$(ls ${prefix}__tracking_mask.nii.gz ${prefix}__seeding_mask.nii.gz)

        for image in \${nii_files};
        do
            extract_dim=\$(mrinfo \${image} -size)
            read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"

            # Get the middle slice
            coronal_dim=\$((\$coronal_dim / 2))
            axial_dim=\$((\$axial_dim / 2))
            sagittal_dim=\$((\$sagittal_dim / 2))

            image=\${image/${prefix}__/}
            image=\${image/.nii.gz/}
            viz_params="--display_slice_number --display_lr --size 256 256"
            scil_viz_volume_screenshot.py ${prefix}__\${image}.nii.gz ${prefix}__\${image}_coronal.png \${viz_params} --slices \${coronal_dim} --axis coronal
            scil_viz_volume_screenshot.py ${prefix}__\${image}.nii.gz ${prefix}__\${image}_axial.png \${viz_params} --slices \${axial_dim} --axis axial
            scil_viz_volume_screenshot.py ${prefix}__\${image}.nii.gz ${prefix}__\${image}_sagittal.png \${viz_params} --slices \${sagittal_dim} --axis sagittal

            convert +append ${prefix}__\${image}_coronal_slice_\${coronal_dim}.png \
                    ${prefix}__\${image}_axial_slice_\${axial_dim}.png  \
                    ${prefix}__\${image}_sagittal_slice_\${sagittal_dim}.png \
                    ${prefix}__\${image}.png

            convert -annotate +20+230 "\${image}" -fill white -pointsize 30 ${prefix}__\${image}.png ${prefix}__\${image}.png
        done

        rm -rf *slice*
        convert -append *png ${prefix}__mask_tracking_mqc.png
    fi

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