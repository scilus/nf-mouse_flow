process MOUSE_REGRIDMASK {
    tag "$meta.id"
    label 'process_high'

    container "mrtrix/mrtrix:3.0.7"

    input:
        tuple val(meta), path(ref), path(mask)
    output:
        tuple val(meta), path("*__mask.nii.gz")   , emit: mask
        path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
	export OMP_NUM_THREADS=$task.cpus
	export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
	export OPENBLAS_NUM_THREADS=1

    ref_extract_res=\$(mrinfo ${ref} -spacing)
    ref_min_res=\$(tr ' ' '\n' <<< "\$extract_res" | awk 'NR==1 || \$1 < min {min=\$1} END {print min}')
    ref_min_res_um=\$(echo \$min_res '*' 1000 | bc)
    
    mask_extract_res=\$(mrinfo ${ref} -spacing)
    mask_min_res=\$(tr ' ' '\n' <<< "\$extract_res" | awk 'NR==1 || \$1 < min {min=\$1} END {print min}')
    mask_min_res_um=\$(echo \$min_res '*' 1000 | bc)

    if (( $(echo "\$mask_min_res_um < \$ref_min_res_um" | bc -l) )); then
        mrgrid -template $ref -interp nearest $mask ${prefix}__mask.nii.gz
    else
        mv 
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrconvert -version 2>&1 | sed -n 's/== mrconvert \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mrgrid -h

    touch ${prefix}__dwi_n4.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
         mrtrix: \$(mrgrid -version | grep mrgrid | cut -d" " -f3)
    END_VERSIONS
    """
}