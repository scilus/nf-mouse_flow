process MOUSE_BETDWI {
    tag "$meta.id"
    label 'process_high'

    container "scilus/mouse-flow:dev"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec)
    output:
        tuple val(meta), path(bval)                  , emit: bval
        tuple val(meta), path(bvec)                  , emit: bvec
        tuple val(meta), path("*__dwi_bet.nii.gz")   , emit: dwi_bet
        tuple val(meta), path("*__b0_bet.nii.gz")    , emit: b0_bet
        tuple val(meta), path("*__mask_bet.nii.gz")      , emit: mask_bet
        path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? task.ext.dwi_shell_tolerance : ""
    def min_fodf_shell_value = task.ext.min_fodf_shell_value ? task.ext.min_fodf_shell_value : ""

    """
    shells=\$(tr ' ' '\n' < $bval  | \
        awk -F' ' '{v=int(\$1)}{if(v>=$min_fodf_shell_value)print v}' | uniq)

    scil_dwi_extract_shell.py $dwi \
        $bval $bvec \$shells ${prefix}__non_zero.nii.gz \
        ${prefix}__non_zero.bval ${prefix}__non_zero.bvec -t $dwi_shell_tolerance -f

    scil_volume_math.py mean ${prefix}__non_zero.nii.gz ${prefix}__mean.nii.gz -f
    maskbackgroundnoise -i ${prefix}__mean.nii.gz -o ${prefix}__mask_bet.nii.gz --level 0.6
    ImageMath 3 ${prefix}__mask_bet.nii.gz GetLargestComponent ${prefix}__mask_bet.nii.gz 200
    ImageMath 3 ${prefix}__mask_bet.nii.gz FillHoles ${prefix}__mask_bet.nii.gz

    fslmaths $dwi -mul ${prefix}__mask_bet.nii.gz ${prefix}__dwi_bet.nii.gz
    scil_dwi_extract_b0.py ${prefix}__dwi_bet.nii.gz $bval $bvec ${prefix}__b0_bet.nii.gz -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
        maskbackgroundnoise: \$(maskbackgroundnoise -h)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    fslmaths -h
    scil_dwi_prepare_eddy_command.py -h
    maskbackgroundnoise -h

    touch ${prefix}__dwi_bet.nii.gz
    touch ${prefix}__b0_bet.nii.gz
    touch ${prefix}__mask_bet.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')

    END_VERSIONS
    """
}