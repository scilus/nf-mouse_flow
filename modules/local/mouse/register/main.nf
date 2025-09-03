process MOUSE_REGISTRATION {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0' }"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask), path(atlas_directory)


    output:
        tuple val(meta), path("*__0GenericAffine.mat")    , emit: GenericAffine
        tuple val(meta), path("*__1InverseWarp.nii.gz")   , emit: InverseWarp
        tuple val(meta), path("*__1Warp.nii.gz")          , emit: Warp
        tuple val(meta), path("*__ANO_LR.nii.gz")           , emit: ANO_LR
        tuple val(meta), path("*__ANO.nii.gz")              , emit: ANO
        tuple val(meta), path("*__ToM.nii.gz")              , emit: TOM
        tuple val(meta), path("*__moving_check.nii.gz")     , emit: moving_check
        tuple val(meta), path("*_registration_ants_mqc.gif"), emit: mqc
        path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def laplacian_value = task.ext.laplacian_value ? task.ext.laplacian_value : ""
    def atlas_resolution = task.ext.atlas_resolution ? task.ext.atlas_resolution : ""
    def atlas_50_resolution = task.ext.atlas_50_resolution
    def atlas_100_resolution = task.ext.atlas_100_resolution
    def run_qc = task.ext.run_qc ?: false

    """
    export OMP_NUM_THREADS=$task.cpus
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OPENBLAS_NUM_THREADS=1

	scil_dti_metrics.py $dwi $bval $bvec --mask $mask --not_all --fa ${prefix}__fa.nii.gz -f
	scil_dwi_extract_b0.py $dwi $bval $bvec ${prefix}__b0.nii.gz -f

    # Apply mask to b0
    fslmaths ${prefix}__b0.nii.gz -mul $mask ${prefix}__b0_masked.nii.gz

    # Get values to extract iterations
    extract_dim=\$(mrinfo ${prefix}__b0.nii.gz -size) 
    extract_res=\$(mrinfo ${prefix}__b0.nii.gz -spacing)

    max_dim=\$(tr ' ' '\n' <<< "\$extract_dim" | awk 'NR==1 || \$1 > max {max=\$1} END {print max}')
    min_res=\$(tr ' ' '\n' <<< "\$extract_res" | awk 'NR==1 || \$1 < min {min=\$1} END {print min}')

    max_param=\$(echo \$min_res '*' \$max_dim | bc)
    step_param=\$(echo \$min_res '/' 2 | bc -l | awk '{printf "%f", \$0}')

    echo "Max param: \$max_param"
    echo "Min res: \$min_res"
    echo "Step_param res: \$step_param"

    params_iterations=\$(ants_generate_iterations.py --min \$min_res --max \$max_param --step \$step_param | tr -d '\\')
    echo "Params iteration: \n \$params_iterations \n\n"

    # Which atlas resolution is closest to the input resolution
    if [[ -z "$atlas_resolution" ]]; then
        min_res_mm=\$(echo \$min_res '*' 1000 | bc)
        
        diff1=\$(echo "scale=6; \$min_res_mm - $atlas_50_resolution" | bc | awk '{print (\$1<0)?-\$1:\$1}')
        diff2=\$(echo "scale=6; \$min_res_mm - $atlas_100_resolution" | bc | awk '{print (\$1<0)?-\$1:\$1}')

        echo \$min_res_mm  $atlas_50_resolution  $atlas_100_resolution \$diff1 \$diff2

        if (( \$(echo "\$diff1 < \$diff2" | bc -l) )); then
            atlas_resolution=50
        else
            atlas_resolution=100
        fi
    else
        atlas_resolution=$atlas_resolution
    fi

    echo "Atlas resolution: \$atlas_resolution"

    AMBA_ref=$atlas_directory/\${atlas_resolution}_AMBA_ref.nii.gz
    AMBA_inv=$atlas_directory/\${atlas_resolution}_AMBA_inv_novent.nii.gz
    AMBA_ANO=$atlas_directory/\${atlas_resolution}_AMBA_ANO.nii.gz
    AMBA_LR=$atlas_directory/\${atlas_resolution}_AMBA_LR.nii.gz
    AMBA_ToM=$atlas_directory/\${atlas_resolution}_AMBA_ToM.nii.gz

	ImageMath  3 ${prefix}__b0_lp.nii.gz  Laplacian ${prefix}__b0_masked.nii.gz $laplacian_value
	ImageMath  3 ${prefix}__fa_lp.nii.gz  Laplacian ${prefix}__fa.nii.gz $laplacian_value
	ImageMath  3 AMBA_ref_lp.nii.gz  Laplacian \$AMBA_ref $laplacian_value
	ImageMath  3 AMBA_inv_lp.nii.gz  Laplacian \$AMBA_inv $laplacian_value

    # Get Affine convergence
    echo "Running SyN"
    antsRegistrationSyN.sh -d 3 -f ${prefix}__b0_masked.nii.gz -m \$AMBA_ref \
        -f ${prefix}__fa.nii.gz -m \$AMBA_inv \
        -f ${prefix}__b0_lp.nii.gz -m AMBA_ref_lp.nii.gz \
        -f ${prefix}__fa_lp.nii.gz -m AMBA_inv_lp.nii.gz -i  [${prefix}__b0_masked.nii.gz,\$AMBA_ref,0] -o test_ > log_synQuick.txt
    log=\$(cat log_synQuick.txt | grep "convergence" | tail -n 1)
    params_iterations_SyN=\$(echo "\$log" | grep -oP '(--convergence \\[ [^\\]]+\\] --shrink-factors [^ ]+ --smoothing-sigmas [^ ]+)(?=(?!.*--convergence))' | tail -1)
    echo "Params iteration SyN: \n \$params_iterations_SyN \n\n"

    antsRegistration --verbose 1 --dimensionality 3 --float 0 \
        --collapse-output-transforms 1  \
        --output [ ${prefix}__,${prefix}__Warped.nii.gz,${prefix}__InverseWarped.nii.gz ]  \
      	--interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [ 0.005,0.995 ] \
        --initial-moving-transform [${prefix}__b0_masked.nii.gz,\$AMBA_ref,0] \
       	--transform Rigid[ 0.1 ] --metric MI[ ${prefix}__b0_masked.nii.gz,\$AMBA_ref,1,32,Regular,0.25 ] \
        \${params_iterations} \
        --transform Affine[ 0.1 ] --metric MI[ ${prefix}__b0_masked.nii.gz,\$AMBA_ref,1,32,Regular,0.25 ] \
        \${params_iterations} \
        --transform SyN[ 0.1,3,0 ] \
        --metric CC[ ${prefix}__b0_masked.nii.gz,\$AMBA_ref,1,4 ] --metric CC[ ${prefix}__fa.nii.gz,\$AMBA_inv,1,4 ] --metric CC[ ${prefix}__b0_lp.nii.gz,AMBA_ref_lp.nii.gz,1,4 ] \
        --metric CC[ ${prefix}__fa_lp.nii.gz,AMBA_inv_lp.nii.gz,1,4 ] \
        \${params_iterations_SyN}

	antsApplyTransforms -d 3 -r ${prefix}__b0_masked.nii.gz -i \$AMBA_ref -t ${prefix}__1Warp.nii.gz -t ${prefix}__0GenericAffine.mat -v -o ${prefix}__moving_check.nii.gz
	antsApplyTransforms -d 3 -r ${prefix}__b0_masked.nii.gz -i \$AMBA_LR -t ${prefix}__1Warp.nii.gz -t ${prefix}__0GenericAffine.mat -n NearestNeighbor -v -o ${prefix}__ANO_LR.nii.gz -u short
	antsApplyTransforms -d 3 -r ${prefix}__b0_masked.nii.gz -i \$AMBA_ANO -t ${prefix}__1Warp.nii.gz -t ${prefix}__0GenericAffine.mat -n NearestNeighbor -v -o ${prefix}__ANO.nii.gz -u short
	antsApplyTransforms -d 3 -r ${prefix}__b0_masked.nii.gz -i \$AMBA_ToM -t ${prefix}__1Warp.nii.gz -t ${prefix}__0GenericAffine.mat -n NearestNeighbor -v -o ${prefix}__ToM.nii.gz -u short

    antsApplyTransforms -d 3 -r \$AMBA_ref -i ${prefix}__b0_masked.nii.gz -t [${prefix}__0GenericAffine.mat, 1] -t ${prefix}__1InverseWarp.nii.gz -v -o ${prefix}__fixed_check.nii.gz

    ### ** QC ** ###
    if $run_qc;
    then
        extract_dim=\$(mrinfo ${prefix}__b0.nii.gz -size)
        read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"

        # Get the middle slice
        coronal_dim=\$((\$coronal_dim / 2))
        axial_dim=\$((\$axial_dim / 2))
        sagittal_dim=\$((\$sagittal_dim / 2))

        # Set viz params.
        viz_params="--display_slice_number --display_lr --size 256 256"
        # Iterate over images.
        for image in b0 ANO_LR ANO ToM;
        do
            scil_viz_volume_screenshot.py ${prefix}__\${image}.nii.gz \${image}_coronal.png \
                --slices \$coronal_dim --axis coronal \$viz_params
            scil_viz_volume_screenshot.py ${prefix}__\${image}.nii.gz \${image}_sagittal.png \
                --slices \$sagittal_dim --axis sagittal \$viz_params
            scil_viz_volume_screenshot.py ${prefix}__\${image}.nii.gz \${image}_axial.png \
                --slices \$axial_dim --axis axial \$viz_params
            if [ \$image != b0 ];
            then
                title="\${image} Warped"
            else
                title="Reference b0"
            fi
            convert +append \${image}_coronal*.png \${image}_axial*.png \
                \${image}_sagittal*.png \${image}_mosaic.png
            convert -annotate +20+230 "\${title}" -fill white -pointsize 30 \
                \${image}_mosaic.png \${image}_mosaic.png
            # Clean up.
            rm \${image}_coronal*.png \${image}_sagittal*.png \${image}_axial*.png
        done
        # Create GIF.
        for image in ANO_LR ANO ToM;
        do
            convert -delay 10 -loop 0 -morph 10 \
                \${image}_mosaic.png b0_mosaic.png \${image}_mosaic.png \
                ${prefix}_\${image}_registration_ants_mqc.gif
        done
        # Clean up.
        rm *_mosaic.png
    fi


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    fslmaths -h
    antsApplyTransforms -h
    N4BiasFieldCorrection -h

    touch ${prefix}__0GenericAffine.mat
    touch ${prefix}__1InverseWarp.nii.gz
    touch ${prefix}__1Warp.nii.gz
    touch ${prefix}__ANO_LR.nii.gz
    touch ${prefix}__ANO.nii.gz
    touch ${prefix}__moving_check.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """
}