process PRE_QC {
    tag "$meta.id"
    label 'process_high'

    container "scilus/mouse-flow:dev"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*_qc_dwi.nii.gz")           , emit: dwi
    tuple val(meta), path("*_mqc.png")                 , emit: mqcshell
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    # Fetch strides.
    strides=\$(mrinfo $dwi -strides)
    mrconvert $dwi -strides 1,2,3,4 ${prefix}_qc_dwi.nii.gz -force

    scil_dti_metrics.py ${prefix}_qc_dwi.nii.gz $bval $bvec --not_all --rgb ${prefix}_rgb.nii.gz

    # Fetch middle axial slice.
    size=\$(mrinfo ${prefix}_rgb.nii.gz -size)
    mid_slice_axial=\$(echo \$size | awk '{print int((\$3 + 1) / 2)}')

    scil_viz_volume_screenshot.py ${prefix}_rgb.nii.gz ${prefix}__ax_mqc.png \
    --slices \$mid_slice_axial --axis axial \
    
    # Fetch middle coronal slice.
    size=\$(mrinfo ${prefix}_rgb.nii.gz -size)
    mid_slice_coronal=\$(echo \$size | awk '{print int((\$2 + 1) / 2)}')

    scil_viz_volume_screenshot.py ${prefix}_rgb.nii.gz ${prefix}__cor_mqc.png \
    --slices \$mid_slice_coronal --axis coronal \

    # Fetch middle sagittal slice.
    size=\$(mrinfo ${prefix}_rgb.nii.gz -size)
    mid_slice_sagittal=\$(echo \$size | awk '{print int((\$1 + 1) / 2)}')

    scil_viz_volume_screenshot.py ${prefix}_rgb.nii.gz ${prefix}__sag_mqc.png \
    --slices \$mid_slice_sagittal --axis sagittal \

    scil_viz_gradients_screenshot.py --in_gradient_scheme $bval $bvec \
        --out_basename ${prefix}_shell_mqc.png --res 600

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mrconvert -h
    scil_dti_metrics.py -h
    scil_viz_volume_screenshot.py -h
    
    touch ${prefix}_dwi.nii.gz
    touch ${prefix}_shell_mqc.png
    touch ${prefix}__ax.png
    touch ${prefix}__cor.png
    touch ${prefix}__sag.png

    scil_viz_gradients_screenshot.py -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}