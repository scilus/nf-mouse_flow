
process RECONST_QBALL {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0' }"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask)

    output:
        tuple val(meta), path("*__qball.nii.gz")          , emit: qball
        tuple val(meta), path("*__gfa.nii.gz")            , emit: gfa, optional: true
        tuple val(meta), path("*__apower.nii.gz")         , emit: apower, optional: true
        tuple val(meta), path("*__peaks.nii.gz")          , emit: peaks, optional: true
        tuple val(meta), path("*__peak_indices.nii.gz")   , emit: peak_indices, optional: true
        tuple val(meta), path("*__nufo.nii.gz")           , emit: nufo, optional: true
        path "versions.yml"                               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def run_qball = task.ext.run_qball ? "--use_qball" : ""
    def dwi_shell_tolerance = task.ext.dwi_shell_tolerance ? "--tolerance " + task.ext.dwi_shell_tolerance : ""
    def min_fodf_shell_value = task.ext.min_fodf_shell_value ?: 100     /* Default value for min_fodf_shell_value */
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ?: 10        /* Default value for b0_thr_extract_b0 */
    def fodf_shells = task.ext.fodf_shells ? "0 " + task.ext.fodf_shells : "\$(cut -d ' ' --output-delimiter=\$'\\n' -f 1- $bval | awk -F' ' '{v=int(\$1)}{if(v>=$min_fodf_shell_value|| v<=$b0_thr_extract_b0)print v}' | sort | uniq)"
    def sh_order = task.ext.sh_order ? "--sh_order " + task.ext.sh_order : ""
    def sh_basis = task.ext.sh_basis ? "--sh_basis " + task.ext.sh_basis : ""
    def processes = task.cpus > 1 ? "--processes " + task.cpus : ""
    def set_mask = mask ? "--mask $mask" : ""
    def run_qc = task.ext.run_qc ?: false

    if ( task.ext.peaks ) peaks = "--peaks ${prefix}__peaks.nii.gz" else peaks = ""
    if ( task.ext.peak_indices ) peak_indices = "--peak_indices ${prefix}__peak_indices.nii.gz" else peak_indices = ""
    if ( task.ext.gfa ) gfa = "--gfa ${prefix}__gfa.nii.gz" else gfa = ""
    if ( task.ext.nufo ) nufo = "--nufo ${prefix}__nufo.nii.gz" else nufo = ""
    if ( task.ext.a_power ) a_power = "--a_power ${prefix}__a_power.nii.gz" else a_power = ""


    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_shell.py $dwi $bval $bvec $fodf_shells \
        dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells \
        $dwi_shell_tolerance -f

    scil_qball_metrics.py dwi_fodf_shells.nii.gz bval_fodf_shells bvec_fodf_shells \
        --sh ${prefix}__qball.nii.gz \
        $set_mask $sh_order $sh_basis  $run_qball $processes \
        --not_all $peaks $peak_indices $gfa $nufo $a_power

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_shell.py -h
    scil_qball_metrics.py -h

    touch ${prefix}__qball.nii.gz
    touch ${prefix}__apower.nii.gz
    touch ${prefix}__peaks.nii.gz
    touch ${prefix}__peak_indices.nii.gz
    touch ${prefix}__afd_sum.nii.gz
    touch ${prefix}__nufo.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
