//
//  txav1d/txav1d.h —— dav1d 兼容层
//
//  为什么需要这一层：
//  工程里 DecoderTools/ 下的 bench、demux、mux 源码各版本共用一份，它们全部
//  按 txav1d 的名字书写（txav1d_open、Txav1dPicture 等）。上游 dav1d 的 API 与
//  txav1d 几乎一一对应，但名字前缀是 dav1d_ / Dav1d。若为了接 dav1d 而复制一份
//  tools 源码改名，就会变成两份要同步维护的文件，新增一个解码器族就要再复制一次，
//  迟早出现「改了一份漏了另一份」的静默错配。
//
//  所以这里用头文件做名字映射：共用源码原样编译，只是把 txav1d_* 解析到 dav1d_*。
//  代价是需要仔细核对两者的差异，收益是共用代码路径始终只有一份。
//
//  已核对的差异（v1.5.1）：
//  1. 前缀不同：txav1d_ / Txav1d → dav1d_ / Dav1d。
//  2. Dav1dSettings 没有 use_wpp 字段。use_wpp 是 txav1d 的私有扩展，
//     上游没有对应开关，因此本层自己定义一个含 use_wpp 的 Txav1dSettings，
//     在 open 时逐字段搬进真正的 Dav1dSettings，use_wpp 不生效。
//  3. 其余结构体（Data / Picture / PictureParameters / SequenceHeader /
//     FrameHeader）字段与顺序完全一致，直接做类型别名即可，无需转换。
//

#ifndef TXAV1D_SHIM_DAV1D_TXAV1D_H
#define TXAV1D_SHIM_DAV1D_TXAV1D_H

#include <string.h>

#include "dav1d/dav1d.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 类型别名

// 布局与字段完全一致，别名即可。这里不另建包装结构体：
// 包装会引入一次拷贝，且 Picture 内部指针的归属规则（由哪个库释放）
// 会在包装层变得模糊，容易演变成跨库 free。
#define Txav1dContext Dav1dContext
#define Txav1dData Dav1dData
#define Txav1dDataProps Dav1dDataProps
#define Txav1dPicture Dav1dPicture
#define Txav1dPictureParameters Dav1dPictureParameters
#define Txav1dSequenceHeader Dav1dSequenceHeader
#define Txav1dFrameHeader Dav1dFrameHeader
#define Txav1dRef Dav1dRef
#define Txav1dPicAllocator Dav1dPicAllocator
#define Txav1dLogger Dav1dLogger
#define Txav1dInloopFilterType Dav1dInloopFilterType
#define Txav1dDecodeFrameType Dav1dDecodeFrameType
#define Txav1dObuType Dav1dObuType
#define Txav1dChromaSamplePosition Dav1dChromaSamplePosition

#pragma mark - 枚举别名

#define TXAV1D_PIXEL_LAYOUT_I400 DAV1D_PIXEL_LAYOUT_I400
#define TXAV1D_PIXEL_LAYOUT_I420 DAV1D_PIXEL_LAYOUT_I420
#define TXAV1D_PIXEL_LAYOUT_I422 DAV1D_PIXEL_LAYOUT_I422
#define TXAV1D_PIXEL_LAYOUT_I444 DAV1D_PIXEL_LAYOUT_I444

#define TXAV1D_CHR_UNKNOWN DAV1D_CHR_UNKNOWN
#define TXAV1D_CHR_VERTICAL DAV1D_CHR_VERTICAL
#define TXAV1D_CHR_COLOCATED DAV1D_CHR_COLOCATED

#define TXAV1D_OBU_SEQ_HDR DAV1D_OBU_SEQ_HDR
#define TXAV1D_OBU_TD DAV1D_OBU_TD
#define TXAV1D_OBU_FRAME_HDR DAV1D_OBU_FRAME_HDR
#define TXAV1D_OBU_TILE_GRP DAV1D_OBU_TILE_GRP
#define TXAV1D_OBU_FRAME DAV1D_OBU_FRAME

#define TXAV1D_INLOOPFILTER_NONE DAV1D_INLOOPFILTER_NONE
#define TXAV1D_INLOOPFILTER_DEBLOCK DAV1D_INLOOPFILTER_DEBLOCK
#define TXAV1D_INLOOPFILTER_CDEF DAV1D_INLOOPFILTER_CDEF
#define TXAV1D_INLOOPFILTER_RESTORATION DAV1D_INLOOPFILTER_RESTORATION
#define TXAV1D_INLOOPFILTER_ALL DAV1D_INLOOPFILTER_ALL

#define TXAV1D_DECODEFRAMETYPE_ALL DAV1D_DECODEFRAMETYPE_ALL
#define TXAV1D_DECODEFRAMETYPE_REFERENCE DAV1D_DECODEFRAMETYPE_REFERENCE
#define TXAV1D_DECODEFRAMETYPE_INTRA DAV1D_DECODEFRAMETYPE_INTRA
#define TXAV1D_DECODEFRAMETYPE_KEY DAV1D_DECODEFRAMETYPE_KEY

#define TXAV1D_PICTURE_ALIGNMENT DAV1D_PICTURE_ALIGNMENT

#define TXAV1D_ERR(e) DAV1D_ERR(e)

#pragma mark - 设置结构体

/**
 * 含 use_wpp 的设置结构。
 *
 * 字段顺序与 Dav1dSettings 保持一致（use_wpp 插在 reserved 之前），
 * 但 open 时不依赖这个顺序做 memcpy——而是逐字段搬运。原因是上游以后
 * 往 reserved 之前插字段时，memcpy 会把错位的数据悄悄带进去，症状是
 * 「某些参数莫名不生效」，很难查。逐字段搬运在那种情况下会编译失败，
 * 是更好的失败方式。
 */
typedef struct Txav1dSettings {
    int n_threads;
    int max_frame_delay;
    int apply_grain;
    int operating_point;                 ///< 0 - 31
    int all_layers;
    unsigned frame_size_limit;           ///< 像素数上限，0 表示不限
    Dav1dPicAllocator allocator;
    Dav1dLogger logger;
    int strict_std_compliance;
    int output_invisible_frames;
    enum Dav1dInloopFilterType inloop_filters;
    enum Dav1dDecodeFrameType decode_frame_type;
    /**
     * txav1d 私有扩展，dav1d 无对应项。
     * 保留字段是为了让共用源码无需条件编译；置 -1 表示「按默认」，
     * 任何非 -1 取值在本层都会被忽略。
     */
    int use_wpp;
    uint8_t reserved[16];
} Txav1dSettings;

#pragma mark - 需要真实包装的函数

// 这两个不能做宏映射：设置结构体类型不同，必须转换。
DAV1D_API void txav1d_default_settings(Txav1dSettings *settings);
DAV1D_API int txav1d_open(Txav1dContext **c_out, const Txav1dSettings *settings);

/** 与 txav1d_version() 同义，返回本库自称的版本串（此处为上游 dav1d 版本） */
DAV1D_API const char *txav1d_version(void);

#pragma mark - 纯名字映射

// 签名与语义完全一致，直接改名字即可，不引入包装函数开销。
#define txav1d_close dav1d_close
#define txav1d_flush dav1d_flush
#define txav1d_send_data dav1d_send_data
#define txav1d_get_picture dav1d_get_picture
#define txav1d_data_create dav1d_data_create
#define txav1d_data_unref dav1d_data_unref
#define txav1d_picture_unref dav1d_picture_unref
#define txav1d_parse_sequence_header dav1d_parse_sequence_header
#define txav1d_get_event_flags dav1d_get_event_flags

#ifdef __cplusplus
}
#endif

#endif /* TXAV1D_SHIM_DAV1D_TXAV1D_H */
