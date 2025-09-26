process MOUSE_PREPARENNUNET {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilus:2.2.0"

    input:
        tuple val(meta), path(image)
    output:
        tuple val(meta), path("*_nnunetReady.nii.gz"), emit: nnunetready
        path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? "__" + task.ext.suffix : ""
    """
    OUTPUT_N4_FIRST=${prefix}_first_N4.nii.gz
    CONVERGENCE_1=20x20x20x20
    CONVERGENCE_2=10x10x10x10
    PARAMETERA=4

    MASK_OTSU_RESAMPLED_FIRST=./mask_otsu_first.nii.gz
    MASK_OTSU_RESAMPLED_SECOND=./mask_otsu_second.nii.gz

    ThresholdImage 3 ${image} \${MASK_OTSU_RESAMPLED_FIRST}  Otsu \${PARAMETERA}
    ThresholdImage 3 \${MASK_OTSU_RESAMPLED_FIRST} \${MASK_OTSU_RESAMPLED_FIRST} 1 Inf 1 0
    ImageMath 3 \${MASK_OTSU_RESAMPLED_FIRST} GetLargestComponent \${MASK_OTSU_RESAMPLED_FIRST}
    N4BiasFieldCorrection  -d 3  -i ${image}  -o \${OUTPUT_N4_FIRST}  -s 4 -b [80,3] -c [\${CONVERGENCE_1},1e-6] -x \${MASK_OTSU_RESAMPLED_FIRST}  -v

    ThresholdImage 3 \${OUTPUT_N4_FIRST} \${MASK_OTSU_RESAMPLED_SECOND}  Otsu \${PARAMETERA}
    ThresholdImage 3 \${MASK_OTSU_RESAMPLED_SECOND} \${MASK_OTSU_RESAMPLED_SECOND} 1 Inf 1 0
    ImageMath 3 \${MASK_OTSU_RESAMPLED_SECOND} GetLargestComponent \${MASK_OTSU_RESAMPLED_SECOND}
    N4BiasFieldCorrection  -d 3  -i \${OUTPUT_N4_FIRST}  -o ${prefix}${suffix}_nnunetready.nii.gz  -s 2 -b [80,3] -c [\${CONVERGENCE_2},1e-6] -x \${MASK_OTSU_RESAMPLED_SECOND} -v

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? "__" + task.ext.suffix : ""
    """
    touch ${prefix}${suffix}_nnunetReady.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
    END_VERSIONS
    """
}
