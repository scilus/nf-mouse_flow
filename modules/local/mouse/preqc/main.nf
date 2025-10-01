process PRE_QC {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilus:2.2.0"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*__stride_dwi.nii.gz")                                       , emit: dwi
    tuple val(meta), path("*__stride_dwi.bval"), path("*__stride_corrected_dwi.bvec")   , emit: bvs
    tuple val(meta), path("*__rgb_mqc.png")                                             , emit: rgb_mqc
    tuple val(meta), path("*__sampling_mqc.png")                                        , emit: sampling_mqc
    path "versions.yml"                                                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    echo "This module is highly experimental"
    echo "Be careful with the output."
    echo ""

    # Fetch strides.
    strides=\$(mrinfo $dwi -strides)
    # Compare strides
    if [ "\$strides" != "1 2 3 4" ]; then
        echo "Strides are not (1,2,3,4), converting to 1,2,3,4."
        echo "Strides were: \$strides"
        echo "Strides are: \$strides"
        mrconvert $dwi -strides 1,2,3,4 \
            -fslgrad $bvec $bval \
            -export_grad_fsl ${prefix}__stride_dwi.bvec ${prefix}__stride_dwi.bval \
            ${prefix}__stride_dwi.nii.gz -force
    else
        echo "Strides are already 1,2,3,4"
        cp $dwi ${prefix}__stride_dwi.nii.gz
        cp $bval ${prefix}__stride_dwi.bval
        cp $bvec ${prefix}__stride_dwi.bvec
    fi

    echo ""

    # Compute DTI BEFORE
    scil_dti_metrics ${prefix}__stride_dwi.nii.gz ${prefix}__stride_dwi.bval ${prefix}__stride_dwi.bvec \
        --not_all \
        --rgb ${prefix}_rgb_pre.nii.gz \
        --fa ${prefix}_fa_pre.nii.gz \
        --evecs ${prefix}_peaks_pre.nii.gz -f

    # Check gradient directions
    scil_gradients_validate_correct ${prefix}__stride_dwi.bvec \
                                    ${prefix}_peaks_pre_v1.nii.gz \
                                    ${prefix}_fa_pre.nii.gz \
                                    ${prefix}__stride_corrected_dwi.bvec -f

    # Compute DTI AFTER
    scil_dti_metrics ${prefix}__stride_dwi.nii.gz ${prefix}__stride_dwi.bval ${prefix}__stride_corrected_dwi.bvec \
        --not_all \
        --rgb ${prefix}_rgb_post.nii.gz \

    # Check gradient sampling scheme
    scil_gradients_validate_sampling ${prefix}__stride_dwi.bval ${prefix}__stride_dwi.bvec --save_viz ./ -f > log_sampling.txt
    echo \$(cat log_sampling.txt)
    convert -append inputed_gradient_scheme.png optimized_gradient_scheme.png ${prefix}__sampling_mqc.png

    # Check vox isotropic
    iso=\$(mrinfo ${prefix}_rgb_pre.nii.gz -spacing)
    valid=\$(awk '{ref=\$1; for(i=1;i<NF;i++) if(\$i!=ref){print "NOT equal"; exit} print "Equal"}' <<< "\$iso")
    echo "Voxels are \$valid"

    # QC - Screenshots - Fetch middle slices and screenshots RGB
    for p in pre post
    do
        size=\$(mrinfo ${prefix}_rgb_\${p}.nii.gz -size)
        mid_slice_axial=\$(echo \$size | awk '{print int((\$3 + 1) / 2)}')
        mid_slice_coronal=\$(echo \$size | awk '{print int((\$2 + 1) / 2)}')
        mid_slice_sagittal=\$(echo \$size | awk '{print int((\$1 + 1) / 2)}')

        # Axial
        scil_viz_volume_screenshot ${prefix}_rgb_\${p}.nii.gz ${prefix}__ax.png \
        --slices \$mid_slice_axial --axis axial \
        # Coronal
        scil_viz_volume_screenshot ${prefix}_rgb_\${p}.nii.gz ${prefix}__cor.png \
        --slices \$mid_slice_coronal --axis coronal \
        # Sagittal
        scil_viz_volume_screenshot ${prefix}_rgb_\${p}.nii.gz ${prefix}__sag.png \
            --slices \$mid_slice_sagittal --axis sagittal \

        convert +append ${prefix}__cor_slice_\${mid_slice_coronal}.png \
            ${prefix}__ax_slice_\${mid_slice_axial}.png  \
            ${prefix}__sag_slice_\${mid_slice_sagittal}.png \
            ${prefix}_rgb_\${p}_mqc.png

        convert -annotate +20+230 "RGB \${p}" -fill white -pointsize 30 ${prefix}_rgb_\${p}_mqc.png ${prefix}_rgb_\${p}_mqc.png

        rm -rf *_slice_*png
    done
    convert -append ${prefix}_rgb_pre_mqc.png ${prefix}_rgb_post_mqc.png ${prefix}__rgb_mqc.png

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
