/*
 * Copyright © 2018-2020, VideoLAN and dav1d authors
 * Copyright © 2018, Two Orioles, LLC
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef AV1D_HEADERS_H
#define AV1D_HEADERS_H

#include <stdint.h>
#include <stddef.h>

// Constants from Section 3. "Symbols and abbreviated terms"
#define AV1D_MAX_CDEF_STRENGTHS 8
#define AV1D_MAX_OPERATING_POINTS 32
#define AV1D_MAX_TILE_COLS 64
#define AV1D_MAX_TILE_ROWS 64
#define AV1D_MAX_SEGMENTS 8
#define AV1D_NUM_REF_FRAMES 8
#define AV1D_PRIMARY_REF_NONE 7
#define AV1D_REFS_PER_FRAME 7
#define AV1D_TOTAL_REFS_PER_FRAME (AV1D_REFS_PER_FRAME + 1)

enum Av1dObuType {
    AV1D_OBU_SEQ_HDR   = 1,
    AV1D_OBU_TD        = 2,
    AV1D_OBU_FRAME_HDR = 3,
    AV1D_OBU_TILE_GRP  = 4,
    AV1D_OBU_METADATA  = 5,
    AV1D_OBU_FRAME     = 6,
    AV1D_OBU_REDUNDANT_FRAME_HDR = 7,
    AV1D_OBU_PADDING   = 15,
};

enum Av1dTxfmMode {
    AV1D_TX_4X4_ONLY,
    AV1D_TX_LARGEST,
    AV1D_TX_SWITCHABLE,
    AV1D_N_TX_MODES,
};

enum Av1dFilterMode {
    AV1D_FILTER_8TAP_REGULAR,
    AV1D_FILTER_8TAP_SMOOTH,
    AV1D_FILTER_8TAP_SHARP,
    AV1D_N_SWITCHABLE_FILTERS,
    AV1D_FILTER_BILINEAR = AV1D_N_SWITCHABLE_FILTERS,
    AV1D_N_FILTERS,
    AV1D_FILTER_SWITCHABLE = AV1D_N_FILTERS,
};

enum Av1dAdaptiveBoolean {
    AV1D_OFF = 0,
    AV1D_ON = 1,
    AV1D_ADAPTIVE = 2,
};

enum Av1dRestorationType {
    AV1D_RESTORATION_NONE,
    AV1D_RESTORATION_SWITCHABLE,
    AV1D_RESTORATION_WIENER,
    AV1D_RESTORATION_SGRPROJ,
};

enum Av1dWarpedMotionType {
    AV1D_WM_TYPE_IDENTITY,
    AV1D_WM_TYPE_TRANSLATION,
    AV1D_WM_TYPE_ROT_ZOOM,
    AV1D_WM_TYPE_AFFINE,
};

typedef struct Av1dWarpedMotionParams {
    enum Av1dWarpedMotionType type;
    int32_t matrix[6];
    union {
        struct {
            int16_t alpha, beta, gamma, delta;
        } p;
        int16_t abcd[4];
    } u;
} Av1dWarpedMotionParams;

enum Av1dPixelLayout {
    AV1D_PIXEL_LAYOUT_I400, ///< monochrome
    AV1D_PIXEL_LAYOUT_I420, ///< 4:2:0 planar
    AV1D_PIXEL_LAYOUT_I422, ///< 4:2:2 planar
    AV1D_PIXEL_LAYOUT_I444, ///< 4:4:4 planar
};

enum Av1dFrameType {
    AV1D_FRAME_TYPE_KEY = 0,    ///< Key Intra frame
    AV1D_FRAME_TYPE_INTER = 1,  ///< Inter frame
    AV1D_FRAME_TYPE_INTRA = 2,  ///< Non key Intra frame
    AV1D_FRAME_TYPE_SWITCH = 3, ///< Switch Inter frame
};

enum Av1dColorPrimaries {
    AV1D_COLOR_PRI_BT709 = 1,
    AV1D_COLOR_PRI_UNKNOWN = 2,
    AV1D_COLOR_PRI_BT470M = 4,
    AV1D_COLOR_PRI_BT470BG = 5,
    AV1D_COLOR_PRI_BT601 = 6,
    AV1D_COLOR_PRI_SMPTE240 = 7,
    AV1D_COLOR_PRI_FILM = 8,
    AV1D_COLOR_PRI_BT2020 = 9,
    AV1D_COLOR_PRI_XYZ = 10,
    AV1D_COLOR_PRI_SMPTE431 = 11,
    AV1D_COLOR_PRI_SMPTE432 = 12,
    AV1D_COLOR_PRI_EBU3213 = 22,
    AV1D_COLOR_PRI_RESERVED = 255,
};

enum Av1dTransferCharacteristics {
    AV1D_TRC_BT709 = 1,
    AV1D_TRC_UNKNOWN = 2,
    AV1D_TRC_BT470M = 4,
    AV1D_TRC_BT470BG = 5,
    AV1D_TRC_BT601 = 6,
    AV1D_TRC_SMPTE240 = 7,
    AV1D_TRC_LINEAR = 8,
    AV1D_TRC_LOG100 = 9,         ///< logarithmic (100:1 range)
    AV1D_TRC_LOG100_SQRT10 = 10, ///< lograithmic (100*sqrt(10):1 range)
    AV1D_TRC_IEC61966 = 11,
    AV1D_TRC_BT1361 = 12,
    AV1D_TRC_SRGB = 13,
    AV1D_TRC_BT2020_10BIT = 14,
    AV1D_TRC_BT2020_12BIT = 15,
    AV1D_TRC_SMPTE2084 = 16,     ///< PQ
    AV1D_TRC_SMPTE428 = 17,
    AV1D_TRC_HLG = 18,           ///< hybrid log/gamma (BT.2100 / ARIB STD-B67)
    AV1D_TRC_RESERVED = 255,
};

enum Av1dMatrixCoefficients {
    AV1D_MC_IDENTITY = 0,
    AV1D_MC_BT709 = 1,
    AV1D_MC_UNKNOWN = 2,
    AV1D_MC_FCC = 4,
    AV1D_MC_BT470BG = 5,
    AV1D_MC_BT601 = 6,
    AV1D_MC_SMPTE240 = 7,
    AV1D_MC_SMPTE_YCGCO = 8,
    AV1D_MC_BT2020_NCL = 9,
    AV1D_MC_BT2020_CL = 10,
    AV1D_MC_SMPTE2085 = 11,
    AV1D_MC_CHROMAT_NCL = 12, ///< Chromaticity-derived
    AV1D_MC_CHROMAT_CL = 13,
    AV1D_MC_ICTCP = 14,
    AV1D_MC_RESERVED = 255,
};

enum Av1dChromaSamplePosition {
    AV1D_CHR_UNKNOWN = 0,
    AV1D_CHR_VERTICAL = 1,  ///< Horizontally co-located with luma(0, 0)
                           ///< sample, between two vertical samples
    AV1D_CHR_COLOCATED = 2, ///< Co-located with luma(0, 0) sample
};

typedef struct Av1dContentLightLevel {
    int max_content_light_level;
    int max_frame_average_light_level;
} Av1dContentLightLevel;

typedef struct Av1dMasteringDisplay {
    ///< 0.16 fixed point
    uint16_t primaries[3][2];
    ///< 0.16 fixed point
    uint16_t white_point[2];
    ///< 24.8 fixed point
    uint32_t max_luminance;
    ///< 18.14 fixed point
    uint32_t min_luminance;
} Av1dMasteringDisplay;

typedef struct Av1dITUTT35 {
    uint8_t  country_code;
    uint8_t  country_code_extension_byte;
    size_t   payload_size;
    uint8_t *payload;
} Av1dITUTT35;

typedef struct Av1dSequenceHeader {
    /**
     * Stream profile, 0 for 8-10 bits/component 4:2:0 or monochrome;
     * 1 for 8-10 bits/component 4:4:4; 2 for 4:2:2 at any bits/component,
     * or 12 bits/component at any chroma subsampling.
     */
    int profile;
    /**
     * Maximum dimensions for this stream. In non-scalable streams, these
     * are often the actual dimensions of the stream, although that is not
     * a normative requirement.
     */
    int max_width, max_height;
    enum Av1dPixelLayout layout; ///< format of the picture
    enum Av1dColorPrimaries pri; ///< color primaries (av1)
    enum Av1dTransferCharacteristics trc; ///< transfer characteristics (av1)
    enum Av1dMatrixCoefficients mtrx; ///< matrix coefficients (av1)
    enum Av1dChromaSamplePosition chr; ///< chroma sample position (av1)
    /**
     * 0, 1 and 2 mean 8, 10 or 12 bits/component, respectively. This is not
     * exactly the same as 'hbd' from the spec; the spec's hbd distinguishes
     * between 8 (0) and 10-12 (1) bits/component, and another element
     * (twelve_bit) to distinguish between 10 and 12 bits/component. To get
     * the spec's hbd, use !!our_hbd, and to get twelve_bit, use hbd == 2.
     */
    int hbd;
    /**
     * Pixel data uses JPEG pixel range ([0,255] for 8bits) instead of
     * MPEG pixel range ([16,235] for 8bits luma, [16,240] for 8bits chroma).
     */
    int color_range;

    int num_operating_points;
    struct Av1dSequenceHeaderOperatingPoint {
        int major_level, minor_level;
        int initial_display_delay;
        int idc;
        int tier;
        int decoder_model_param_present;
        int display_model_param_present;
    } operating_points[AV1D_MAX_OPERATING_POINTS];

    int still_picture;
    int reduced_still_picture_header;
    int timing_info_present;
    int num_units_in_tick;
    int time_scale;
    int equal_picture_interval;
    unsigned num_ticks_per_picture;
    int decoder_model_info_present;
    int encoder_decoder_buffer_delay_length;
    int num_units_in_decoding_tick;
    int buffer_removal_delay_length;
    int frame_presentation_delay_length;
    int display_model_info_present;
    int width_n_bits, height_n_bits;
    int frame_id_numbers_present;
    int delta_frame_id_n_bits;
    int frame_id_n_bits;
    int sb128;
    int filter_intra;
    int intra_edge_filter;
    int inter_intra;
    int masked_compound;
    int warped_motion;
    int dual_filter;
    int order_hint;
    int jnt_comp;
    int ref_frame_mvs;
    enum Av1dAdaptiveBoolean screen_content_tools;
    enum Av1dAdaptiveBoolean force_integer_mv;
    int order_hint_n_bits;
    int super_res;
    int cdef;
    int restoration;
    int ss_hor, ss_ver, monochrome;
    int color_description_present;
    int separate_uv_delta_q;
    int film_grain_present;

    // Av1dSequenceHeaders of the same sequence are required to be
    // bit-identical until this offset. See 7.5 "Ordering of OBUs":
    //   Within a particular coded video sequence, the contents of
    //   sequence_header_obu must be bit-identical each time the
    //   sequence header appears except for the contents of
    //   operating_parameters_info.
    struct Av1dSequenceHeaderOperatingParameterInfo {
        int decoder_buffer_delay;
        int encoder_buffer_delay;
        int low_delay_mode;
    } operating_parameter_info[AV1D_MAX_OPERATING_POINTS];
} Av1dSequenceHeader;

typedef struct Av1dSegmentationData {
    int delta_q;
    int delta_lf_y_v, delta_lf_y_h, delta_lf_u, delta_lf_v;
    int ref;
    int skip;
    int globalmv;
} Av1dSegmentationData;

typedef struct Av1dSegmentationDataSet {
    Av1dSegmentationData d[AV1D_MAX_SEGMENTS];
    int preskip;
    int last_active_segid;
} Av1dSegmentationDataSet;

typedef struct Av1dLoopfilterModeRefDeltas {
    int mode_delta[2 /* is_zeromv */];
    int ref_delta[AV1D_TOTAL_REFS_PER_FRAME];
} Av1dLoopfilterModeRefDeltas;

typedef struct Av1dFilmGrainData {
    unsigned seed;
    int num_y_points;
    uint8_t y_points[14][2 /* value, scaling */];
    int chroma_scaling_from_luma;
    int num_uv_points[2];
    uint8_t uv_points[2][10][2 /* value, scaling */];
    int scaling_shift;
    int ar_coeff_lag;
    int8_t ar_coeffs_y[24];
    int8_t ar_coeffs_uv[2][25 + 3 /* padding for alignment purposes */];
    uint64_t ar_coeff_shift;
    int grain_scale_shift;
    int uv_mult[2];
    int uv_luma_mult[2];
    int uv_offset[2];
    int overlap_flag;
    int clip_to_restricted_range;
} Av1dFilmGrainData;

typedef struct Av1dFrameHeader {
    struct {
        Av1dFilmGrainData data;
        int present, update;
    } film_grain; ///< film grain parameters
    enum Av1dFrameType frame_type; ///< type of the picture
    int width[2 /* { coded_width, superresolution_upscaled_width } */], height;
    int frame_offset; ///< frame number
    int temporal_id; ///< temporal id of the frame for SVC
    int spatial_id; ///< spatial id of the frame for SVC

    int show_existing_frame;
    int existing_frame_idx;
    int frame_id;
    int frame_presentation_delay;
    int show_frame;
    int showable_frame;
    int error_resilient_mode;
    int disable_cdf_update;
    int allow_screen_content_tools;
    int force_integer_mv;
    int frame_size_override;
    int primary_ref_frame;
    int buffer_removal_time_present;
    struct Av1dFrameHeaderOperatingPoint {
        int buffer_removal_time;
    } operating_points[AV1D_MAX_OPERATING_POINTS];
    int refresh_frame_flags;
    int render_width, render_height;
    struct {
        int width_scale_denominator;
        int enabled;
    } super_res;
    int have_render_size;
    int allow_intrabc;
    int frame_ref_short_signaling;
    int refidx[AV1D_REFS_PER_FRAME];
    int hp;
    enum Av1dFilterMode subpel_filter_mode;
    int switchable_motion_mode;
    int use_ref_frame_mvs;
    int refresh_context;
    struct {
        int uniform;
        unsigned n_bytes;
        int min_log2_cols, max_log2_cols, log2_cols, cols;
        int min_log2_rows, max_log2_rows, log2_rows, rows;
        uint16_t col_start_sb[AV1D_MAX_TILE_COLS + 1];
        uint16_t row_start_sb[AV1D_MAX_TILE_ROWS + 1];
        int update;
    } tiling;
    struct {
        int yac;
        int ydc_delta;
        int udc_delta, uac_delta, vdc_delta, vac_delta;
        int qm, qm_y, qm_u, qm_v;
    } quant;
    struct {
        int enabled, update_map, temporal, update_data;
        Av1dSegmentationDataSet seg_data;
        int lossless[AV1D_MAX_SEGMENTS], qidx[AV1D_MAX_SEGMENTS];
    } segmentation;
    struct {
        struct {
            int present;
            int res_log2;
        } q;
        struct {
            int present;
            int res_log2;
            int multi;
        } lf;
    } delta;
    int all_lossless;
    struct {
        int level_y[2 /* dir */];
        int level_u, level_v;
        int mode_ref_delta_enabled;
        int mode_ref_delta_update;
        Av1dLoopfilterModeRefDeltas mode_ref_deltas;
        int sharpness;
    } loopfilter;
    struct {
        int damping;
        int n_bits;
        int y_strength[AV1D_MAX_CDEF_STRENGTHS];
        int uv_strength[AV1D_MAX_CDEF_STRENGTHS];
    } cdef;
    struct {
        enum Av1dRestorationType type[3 /* plane */];
        int unit_size[2 /* y, uv */];
    } restoration;
    enum Av1dTxfmMode txfm_mode;
    int switchable_comp_refs;
    int skip_mode_allowed, skip_mode_enabled, skip_mode_refs[2];
    int warp_motion;
    int reduced_txtp_set;
    Av1dWarpedMotionParams gmv[AV1D_REFS_PER_FRAME];
} Av1dFrameHeader;

#endif /* AV1D_HEADERS_H */
