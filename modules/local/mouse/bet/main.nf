process MOUSE_BET {
    tag "$meta.id"
    label 'process_high'

    container "scilus/mouse-flow:dev"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask)
    output:
        tuple val(meta), path(bval)                  , emit: bval
        tuple val(meta), path(bvec)                  , emit: bvec
        tuple val(meta), path("*__b0.nii.gz")        , emit: b0
        tuple val(meta), path("*__bet_mask.nii.gz")      , emit: mask
        path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? task.ext.dwi_shell_tolerance : ""
    def min_fodf_shell_value = task.ext.min_fodf_shell_value ? task.ext.min_fodf_shell_value : ""

    """
    if [[ -f "$mask" ]]
    then
        mv $mask ${prefix}__bet_mask.nii.gz
    else
        shells=\$(tr ' ' '\n' < $bval  | \
            awk -F' ' '{v=int(\$1)}{if(v>=$min_fodf_shell_value)print v}' | uniq)

        scil_dwi_extract_shell.py $dwi \
            $bval $bvec \$shells ${prefix}__non_zero.nii.gz \
            ${prefix}__non_zero.bval ${prefix}__non_zero.bvec -t $dwi_shell_tolerance -f

        scil_volume_math.py mean ${prefix}__non_zero.nii.gz ${prefix}__mean.nii.gz -f
        maskbackgroundnoise -i ${prefix}__mean.nii.gz -o ${prefix}__mask.nii.gz --level 0.6
        ImageMath 3 ${prefix}__mask.nii.gz GetLargestComponent ${prefix}__mask.nii.gz 200
        ImageMath 3 ${prefix}__mask.nii.gz FillHoles ${prefix}__bet_mask.nii.gz
    fi

    scil_dwi_extract_b0.py $dwi $bval $bvec ${prefix}__b0.nii.gz -f
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_prepare_eddy_command.py -h

    touch ${prefix}__dwi_bet.nii.gz
    touch ${prefix}__b0_bet.nii.gz
    touch ${prefix}__bet_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')

    END_VERSIONS
    """
}