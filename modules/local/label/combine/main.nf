process LABEL_COMBINE {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilus:2.2.0_cpu"

    input:
        tuple val(meta), path(labels)
    output:
        tuple val(meta), path("*_mask.nii.gz")   , emit: labels_combined
        tuple val(meta), path("*__*_mqc.png")    , emit: mqc
        path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? task.ext.suffix : "ids_combined"
    def labels_ids = task.ext.labels_ids ? task.ext.labels_ids : ""
    def run_qc = task.ext.run_qc ? task.ext.run_qc : false

    """
    scil_labels_combine ${prefix}__${suffix}_mask.nii.gz \
        --volume_ids ${labels} $labels_ids \
        --merge_groups -f

    if $run_qc;
    then
        image="${prefix}__${suffix}_mask.nii.gz"
        extract_dim=\$(mrinfo \${image} -size)
        read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"
        # Get the middle slice
        coronal_dim=\$((\$coronal_dim / 2))
        axial_dim=\$((\$axial_dim / 2))
        sagittal_dim=\$((\$sagittal_dim / 2))

        image=\${image/${prefix}__/}
        image=\${image/_mask.nii.gz/}
        viz_params="--display_slice_number --display_lr --size 256 256"
        scil_viz_volume_screenshot ${prefix}__\${image}_mask.nii.gz ${prefix}__\${image}_coronal.png \${viz_params} --slices \${coronal_dim} --axis coronal
        scil_viz_volume_screenshot ${prefix}__\${image}_mask.nii.gz ${prefix}__\${image}_axial.png \${viz_params} --slices \${axial_dim} --axis axial
        scil_viz_volume_screenshot ${prefix}__\${image}_mask.nii.gz ${prefix}__\${image}_sagittal.png \${viz_params} --slices \${sagittal_dim} --axis sagittal
        convert +append ${prefix}__\${image}_coronal_slice_\${coronal_dim}.png \
                ${prefix}__\${image}_axial_slice_\${axial_dim}.png  \
                ${prefix}__\${image}_sagittal_slice_\${sagittal_dim}.png \
                ${prefix}__\${image}.png
        convert -annotate +20+230 "\${image}" -fill white -pointsize 30 ${prefix}__\${image}.png ${prefix}__\${image}.png

        rm -rf *slice*
        convert -append *png ${prefix}__mask_tracking_mqc.png
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv -q -n pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
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
        scilpy: \$(uv -q -n pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}