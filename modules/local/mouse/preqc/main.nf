process PRE_QC {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilus:2.2.0'}"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*_qc_dwi.nii.gz")           , emit: dwi
    tuple val(meta), path("*_rgb_mqc.png")             , emit: rgb_mqc
    tuple val(meta), path("*_shells_mqc.png")          , emit: shells_mqc
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    # Fetch strides.
    strides=\$(mrinfo $dwi -strides)
    # Compare strides
    if [ "\$strides" != "1,2,3,4" ]; then
        echo "Strides are not (1,2,3,4), converting to 1,2,3,4."
        echo "Strides were: \$strides"
        echo "Strides are: \$strides"
        mrconvert $dwi -strides 1,2,3,4 ${prefix}_qc_dwi.nii.gz -force
    else
        echo "Strides are already 1,2,3,4"
        cp $dwi ${prefix}_qc_dwi.nii.gz
    fi

    # Voir si la carte `RGB est correcte, j'ai repris comme tu avais fait, il faudrait mettre à quoi elle ressemble et à quoi elle devrait ressembler. Si ce n'est pas \
    # le cas, il faut utiliser la ligne scil_gradients_validate_correct pour corriger la carte RGB, peut-être ajouter la création de la FA et des evecs pour faciliter si besoin. 

    scil_dti_metrics ${prefix}_qc_dwi.nii.gz $bval $bvec --not_all --rgb ${prefix}_rgb.nii.gz

    # Fetch middle slices and screenshots RGB
    size=\$(mrinfo ${prefix}_rgb.nii.gz -size)
    mid_slice_axial=\$(echo \$size | awk '{print int((\$3 + 1) / 2)}')
    mid_slice_coronal=\$(echo \$size | awk '{print int((\$2 + 1) / 2)}')
    mid_slice_sagittal=\$(echo \$size | awk '{print int((\$1 + 1) / 2)}')

    # Axial
    scil_viz_volume_screenshot ${prefix}_rgb.nii.gz ${prefix}__ax.png \
    --slices \$mid_slice_axial --axis axial \
    # Coronal
    scil_viz_volume_screenshot ${prefix}_rgb.nii.gz ${prefix}__cor.png \
    --slices \$mid_slice_coronal --axis coronal \
    # Sagittal
    scil_viz_volume_screenshot ${prefix}_rgb.nii.gz ${prefix}__sag.png \
    --slices \$mid_slice_sagittal --axis sagittal \

    convert +append ${prefix}__cor_slice_\${mid_slice_coronal}.png \
        ${prefix}__ax_slice_\${mid_slice_axial}.png  \
        ${prefix}__sag_slice_\${mid_slice_sagittal}.png \
        ${prefix}_rgb_mqc.png

    convert -annotate +20+230 "RGB" -fill white -pointsize 30 ${prefix}_rgb_mqc.png ${prefix}_rgb_mqc.png

    rm -rf *_slice_*png

    # Check vox isotropic
    iso=\$(mrinfo ${prefix}_rgb.nii.gz -spacing)

    # Gradient validation energy
    scil_gradients_validate_sampling $bval $bvec --viz_and_save ./ -f

    # Save Gradient scheme
    scil_viz_gradients_screenshot --in_gradient_scheme $bval $bvec \
        --out_basename ${prefix}__shells_mqc.png --res 600

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv -q -n pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mrconvert -h
    scil_dti_metrics -h
    scil_viz_volume_screenshot -h
    
    touch ${prefix}_dwi.nii.gz
    touch ${prefix}_shells_mqc.png
    touch ${prefix}_rgb_mqc.png

    scil_viz_gradients_screenshot -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv -q -n pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}