include { IMAGE_POWDERAVERAGE } from '../../../modules/nf-neuro/image/powderaverage/main.nf'
include { MOUSE_PREPARENNUNET as PREPARE_NNUNET_DWI } from '../../../modules/local/mouse/preparennunet/main.nf'
include { MOUSE_PREPARENNUNET as PREPARE_NNUNET_B0 } from '../../../modules/local/mouse/preparennunet/main.nf'
include { MOUSE_BETNNUNET } from '../../../modules/local/mouse/betnnunet/main.nf'
include { MOUSE_REGRIDMASK } from '../../../modules/local/mouse/regridmask/main.nf'

workflow NNUNET {

    take:
        ch_nnunet           // channel: [ val(meta), dwi, bval, b0, mask]

    main:

        ch_versions = Channel.empty()
        ch_multiqc_files = Channel.empty()

        ch_dwi = ch_nnunet
            .map { meta, dwi, bval, b0, mask ->   
                [meta, dwi, bval, mask ?: [ ]]}
    
        ch_b0 = ch_nnunet
            .map { meta, dwi, bval, b0, mask ->   
                [meta, b0]}
        
        ch_mask = ch_nnunet
            .map { meta, dwi, bval, b0, mask ->   
               [meta, mask ?: [ ]]}


        IMAGE_POWDERAVERAGE(ch_dwi)

        PREPARE_NNUNET_B0(ch_b0)
        PREPARE_NNUNET_DWI(IMAGE_POWDERAVERAGE.out.pwd_avg)

        ch_for_bet = PREPARE_NNUNET_DWI.out.nnunetready
            .join(PREPARE_NNUNET_B0.out.nnunetready, by: 0, remainder: true)
            .join(ch_mask, by: 0, remainder: true)
            .map { meta, dwi, b0, mask ->   
                [meta, dwi, b0, mask ?: [   ]]}  // Use empty list if mask is null

        MOUSE_BETNNUNET(ch_for_bet)

        ch_for_regrid = ch_b0
            .join(MOUSE_BETNNUNET.out.mask)

        MOUSE_REGRIDMASK(ch_for_regrid)

    emit:
        mask = MOUSE_BETNNUNET.out.mask                     // channel: [ val(meta), mask ]
        mqc                 = ch_multiqc_files              // channel: [ val(meta), mqc ]
        versions            = ch_versions                   // channel: [ versions.yml ]
}