process MOUSE_EXTRACTMASKS {
    tag "$meta.id"
    label 'process_high'

    container "scilus/mouse-flow:dev"

    input:
        tuple val(meta), path(atlas)

    output:
        tuple val(meta), path("*masks")  , emit: masks_dir
        tuple val(meta), path("*__masks/*_MO_L.nii.gz"), path("*__masks/*_MO_R.nii.gz") , emit: masks_MO, optional: true
        tuple val(meta), path("*__masks/*_SS_L.nii.gz"), path("*__masks/*_SS_R.nii.gz") , emit: masks_SS, optional: true
        path("*__masks/*.txt")
        path "versions.yml"                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def labels = task.ext.labels
    """
    mouse_extract_masks.py $atlas $labels ${prefix}__masks -f

    for curr_label in $labels; do
        for side in L R; do
            ids=\$(cat ${prefix}__masks/\${curr_label}_\$side.txt)
            if [[ \$ids ]]; then
                scil_labels_combine.py ${prefix}__masks/${prefix}__\${curr_label}_\$side.nii.gz \
                    --volume_ids $atlas \${ids} \
                    --merge_groups -f
            fi
        done
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mouse_extract_masks.py -h

    touch ${prefix}__masks

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}