process ROI_GETMIDSAGITTAL {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_latest.sif':
        'scilus/scilus:latest' }"

    input:
        tuple val(meta), path(volume)
    output:
        tuple val(meta), path("*_mask.nii.gz")      , emit: roi
        tuple val(meta), path("*_mask_mqc.png")     , emit: mqc
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? task.ext.suffix : "bundle"
    def roi_width = task.ext.roi_width ? task.ext.roi_width : 5

    def run_qc = task.ext.run_qc ? task.ext.run_qc : false

    """
    #Extract a mid-saggital CC ROI from the full CC, i.e. from tmp_in.nii.gz
    
    # Retrieve X/Y/Z dimensions
    dimX=\$(fslval ${volume} dim1)
    
    # Calculate startX to center the ROI window
    startX=\$(( (\$dimX - $roi_width) / 2 ))
    
    # Extract the block of ROI_WIDTH sagittal slices
    tmp_roi=\$(mktemp -u)
    fslroi $volume \$tmp_roi \${startX} $roi_width 0 -1 0 -1

    # Create an empty volume of the same size as the input
    tmp_zeros=\$(mktemp -u)
    fslmaths $volume -mul 0 \$tmp_zeros

    # Crop the volume before the ROI block
    tmp_before=\$(mktemp -u)
    fslroi \${tmp_zeros} \${tmp_before} 0 \${startX} 0 -1 0 -1
    
    # Crop the volume after the ROI block
    after_count=\$(( \$dimX - \$startX - $roi_width ))
    tmp_after=\$(mktemp -u)
    fslroi \${tmp_zeros} \${tmp_after} \$((\$startX + $roi_width)) \${after_count} 0 -1 0 -1

    # Reconstruct the full volume by concatenating along the X axis
    tmp_merge=\$(mktemp -u)
    fslmerge -x \${tmp_merge} \${tmp_before} \${tmp_roi} \${tmp_after}

    # Copy the geometry (qform/sform) from the original input
    fslcpgeom $volume \${tmp_merge}

    # Binarize the result to be sure to get a mask of 0s and 1s
    fslmaths \${tmp_merge} -bin ${prefix}__${suffix}_mask.nii.gz -odt int

    # Clean up temporary files
    rm -f \${tmp_roi} \${tmp_zeros} \${tmp_before} \${tmp_after} \${tmp_merge}

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
        scil_viz_volume_screenshot.py ${prefix}__\${image}_mask.nii.gz ${prefix}__\${image}_coronal.png \${viz_params} --slices \${coronal_dim} --axis coronal
        scil_viz_volume_screenshot.py ${prefix}__\${image}_mask.nii.gz ${prefix}__\${image}_axial.png \${viz_params} --slices \${axial_dim} --axis axial
        scil_viz_volume_screenshot.py ${prefix}__\${image}_mask.nii.gz ${prefix}__\${image}_sagittal.png \${viz_params} --slices \${sagittal_dim} --axis sagittal
        convert +append ${prefix}__\${image}_coronal_slice_\${coronal_dim}.png \
                ${prefix}__\${image}_axial_slice_\${axial_dim}.png  \
                ${prefix}__\${image}_sagittal_slice_\${sagittal_dim}.png \
                ${prefix}__\${image}.png
        convert -annotate +20+230 "\${image}" -fill white -pointsize 30 ${prefix}__\${image}.png ${prefix}__\${image}.png

        rm -rf *slice*
        convert -append *png ${prefix}__${suffix}_mask_mqc.png
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