process MOUSE_BETNNUNET {
    tag "$meta.id"
    label 'process_high'

    container "scilus/nnunet_bet_mouse:dev"

    input:
        tuple val(meta), path(dwi), path(b0), path(mask)
    output:
        tuple val(meta), path("*__mask.nii.gz")      , emit: mask
        path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    if [[ -f "$mask" ]]
    then
        mv $mask ${prefix}__mask.nii.gz
    else
        mkdir -p Database/RAW/Dataset012_ExVivoBrainFSboth/imageTs
        ln -s /Database/RAW/Dataset012_ExVivoBrainFSboth/dataset.json Database/RAW/Dataset012_ExVivoBrainFSboth/imageTs/dataset.json
        ln -s /Database/RESULTS Database/RESULTS
        mv $b0 Database/RAW/Dataset012_ExVivoBrainFSboth/imageTs/exvivobrain_000_0000.nii.gz
        mv $dwi Database/RAW/Dataset012_ExVivoBrainFSboth/imageTs/exvivobrain_000_0001.nii.gz
        nnUNetv2_predict -i Database/RAW/Dataset012_ExVivoBrainFSboth/imagesTs -o ./ -d 012 -c 3d_fullres -f all -npp 1 -nps 1 -device 'cpu' -tr nnUNetTrainer -chk checkpoint_best.pth
        mv exvivobrain_000.nii.gz ${prefix}__mask.nii.gz
    fi  

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":

    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}__mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
    END_VERSIONS
    """
}