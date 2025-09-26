#!/usr/bin/env nextflow
include { DENOISING_MPPCA } from './modules/nf-neuro/denoising/mppca/main.nf'
include { PREPROC_SINGLEEDDY } from './modules/local/preproc/singleeddy/main.nf'
include { UTILS_EXTRACTB0 } from './modules/nf-neuro/utils/extractb0/main.nf'
include { MOUSE_BETNNUNET } from './modules/local/mouse/betnnunet/main.nf'
include { MOUSE_N4 } from './modules/local/mouse/n4/main.nf'
include { IMAGE_RESAMPLE as RESAMPLE_DWI} from './modules/nf-neuro/image/resample/main.nf'
include { IMAGE_RESAMPLE as RESAMPLE_MASK} from './modules/nf-neuro/image/resample/main.nf'
include { IMAGE_CONVERT } from './modules/nf-neuro/image/convert/main.nf'
include { MOUSE_REGISTRATION } from './modules/local/mouse/register/main.nf'
include { RECONST_DTIMETRICS } from './modules/nf-neuro/reconst/dtimetrics/main.nf'
include { RECONST_FRF } from './modules/nf-neuro/reconst/frf/main.nf'
include { RECONST_FODF } from './modules/nf-neuro/reconst/fodf/main.nf'
include { RECONST_QBALL } from './modules/nf-neuro/reconst/qball/main.nf'
include { TRACKING_MASK } from './modules/local/tracking/mask/main.nf'
include { TRACKING_LOCALTRACKING } from './modules/nf-neuro/tracking/localtracking/main.nf'
include { MOUSE_EXTRACTMASKS } from './modules/local/mouse/extractmasks/main.nf'
include { MOUSE_VOLUMEROISTATS } from './modules/local/mouse/volumeroistats/main.nf'
include { MOUSE_COMBINESTATS } from './modules/local/mouse/combinestats/main.nf'
include { MULTIQC } from "./modules/nf-core/multiqc/main"

workflow get_data {
    main:
        if ( !params.input && !params.atlas ) {
            log.info "You must provide an input directory containing all images using:"
            log.info ""
            log.info "        --input=/path/to/[input]             Input directory containing your subjects"
            log.info ""
            log.info "                         [input]"
            log.info "                           ├-- S1"
            log.info "                           |   ├-- *dwi.nii.gz"
            log.info "                           |   ├-- *dwi.bval"
            log.info "                           |   └-- *dwi.bvec"
            log.info "                           └-- S2"
            log.info "                                ├-- *dwi.nii.gz"
            log.info "                                ├-- *dwi.bval"
            log.info "                                └-- *dwi.bvec"
            log.info ""
            log.info "        --atlas=/path/to/[atlas]             Input Atlas directory"
            log.info ""
            error "Please resubmit your command with the previous file structure."
        }
        input = file(params.input)
        atlas = file(params.atlas)
        // ** Loading all files. ** //
        atlas_channel = Channel.fromPath("$atlas", type: 'dir')
        dwi_channel = Channel.fromFilePairs("$input/**/*dwi.{nii.gz,bval,bvec}", size: 3, flat: true)
            { it.parent.name }
            .map{ sid, bvals, bvecs, dwi -> [ [id: sid], dwi, bvals, bvecs ] } // Reordering the inputs.
        
        mask_channel = Channel.fromPath("$input/**/*mask.nii.gz")
                        .map { mask_file -> def sid = mask_file.parent.name
                        [[id: sid], mask_file] }

    emit:
        dwi   = dwi_channel
        atlas = atlas_channel
        mask  = mask_channel
}

workflow {

    log.info("Uses GPU: $params.use_gpu")
    // Define channel for multiqc files
    ch_multiqc_files = Channel.empty()
    ch_multiqc_config = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)

    // ** Now call your input workflow to fetch your files ** //
    data = get_data()

   ch_dwi_bvalbvec = data.dwi
        .multiMap { meta, dwi, bval, bvec ->
            dwi:    [ meta, dwi ]
            bvs_files: [ meta, bval, bvec ]
            bval:   [meta, bval]
            bvec:   [meta, bvec]
        }

    if (params.run_denoising){
        ch_mppca = ch_dwi_bvalbvec.dwi
            .map{ it + [[]] } // This add one empty list to the channel, since we do not have a mask.
        DENOISING_MPPCA( ch_mppca )
        ch_after_denoising = DENOISING_MPPCA.out.image
    }
    else {
        ch_after_denoising = ch_dwi_bvalbvec.dwi
    }

    ch_eddy = ch_after_denoising.join(ch_dwi_bvalbvec.bvs_files)
    if (params.run_eddy){
        PREPROC_SINGLEEDDY(ch_eddy)
        ch_after_eddy = PREPROC_SINGLEEDDY.out.dwi_corrected.join(
            PREPROC_SINGLEEDDY.out.bval_corrected).join(
            PREPROC_SINGLEEDDY.out.bvec_corrected)
    }
    else {
        ch_after_eddy = ch_eddy
    }
    
    UTILS_EXTRACTB0(ch_after_eddy)

    ch_for_bet = ch_after_eddy.map{[ it[0], it[1] ]}
        .join(UTILS_EXTRACTB0.out.b0, by: 0, remainder: true)
        .join(data.mask, by: 0, remainder: true)
        .map { meta, dwi, b0, mask ->
            [meta, dwi, b0, mask ?: []]}  // Use empty list if mask is null

    MOUSE_BETNNUNET(ch_for_bet)

    if (params.run_n4) {
        ch_N4 = ch_after_eddy
            .map{ meta, dwi, _bval, _bvec ->
                    tuple(meta, dwi)}
            .join(UTILS_EXTRACTB0.out.b0)
            .join(MOUSE_BETNNUNET.out.mask)
        MOUSE_N4(ch_N4)
        ch_after_n4 = MOUSE_N4.out.dwi_n4
    }
    else {
        ch_after_n4 = ch_after_eddy
            .map{ meta, dwi, _bval, _bvec -> tuple(meta, dwi)}
    }
    RESAMPLE_DWI(ch_after_n4.map{ meta, dwi -> [meta, dwi, []] }) // Add an empty list for the optional reference image
    RESAMPLE_MASK(MOUSE_BETNNUNET.out.mask.map{ meta, mask -> [meta, mask, []] })

    IMAGE_CONVERT(RESAMPLE_MASK.out.image)
    
    ch_for_mouse_registration = RESAMPLE_DWI.out.image
                                    .join(ch_after_eddy.map{ [it[0], it[2], it[3]] })
                                    .join(IMAGE_CONVERT.out.image)
                                    .combine(data.atlas)
    MOUSE_REGISTRATION(ch_for_mouse_registration)
    ch_multiqc_files = ch_multiqc_files.mix(MOUSE_REGISTRATION.out.mqc)

    ch_for_reconst = RESAMPLE_DWI.out.image
                                    .join(ch_after_eddy.map{ [it[0], it[2], it[3]] })
                                    .join(IMAGE_CONVERT.out.image)



    RECONST_DTIMETRICS(ch_for_reconst)
    ch_multiqc_files = ch_multiqc_files.mix(RECONST_DTIMETRICS.out.mqc)


    if (params.use_fodf)
    {
        RECONST_FRF(ch_for_reconst
                        .map{ it + [[], [], []]})

        ch_for_reconst_fodf = ch_for_reconst
                                .join(RECONST_DTIMETRICS.out.fa)
                                .join(RECONST_DTIMETRICS.out.md)
                                .join(RECONST_FRF.out.frf)
                                .map{ it + [[], []]}
        RECONST_FODF(ch_for_reconst_fodf)
        reconst_sh = RECONST_FODF.out.fodf
    }
    else
    {
        RECONST_QBALL(ch_for_reconst)
        reconst_sh = RECONST_QBALL.out.qball
    }

    TRACKING_MASK(IMAGE_CONVERT.out.image
                    .join(MOUSE_REGISTRATION.out.ANO))

    TRACKING_LOCALTRACKING(TRACKING_MASK.out.tracking_mask
                .join(reconst_sh)
                .join(TRACKING_MASK.out.seeding_mask))
    ch_multiqc_files = ch_multiqc_files.mix(TRACKING_LOCALTRACKING.out.mqc)


    MOUSE_EXTRACTMASKS(MOUSE_REGISTRATION.out.ANO_LR)

    ch_metrics = RECONST_DTIMETRICS.out.md
                    .join(RECONST_DTIMETRICS.out.fa)
                    .join(RECONST_DTIMETRICS.out.rd)
                    .join(RECONST_DTIMETRICS.out.ad)
                    .map{ meta, fa, md, ad, rd ->
                    tuple(meta, [ fa, md, ad, rd ])}

    ch_for_stats = ch_metrics
                    .combine(MOUSE_EXTRACTMASKS.out.masks_dir, by: 0)
    MOUSE_VOLUMEROISTATS(ch_for_stats)

    all_stats = MOUSE_VOLUMEROISTATS.out.stats
                .map{ _meta, json -> json}
                .collect()
    MOUSE_COMBINESTATS(all_stats)

    ch_multiqc_files = ch_multiqc_files
    .groupTuple()
    .map { meta, files_list ->
        def files = files_list.flatten().findAll { it != null }
        return tuple(meta, files)
    }

    MULTIQC(ch_multiqc_files, [], ch_multiqc_config.toList(), [], [], [])
}
