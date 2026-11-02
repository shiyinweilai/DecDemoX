//
//  txav1d_bench.h
//  TXAV1Dec
//
//  App 侧性能测试专用入口。
//
//  与 txav1d_lanuch() 的区别：
//  - 不经过 getopt 参数解析，避免全局状态（optind/optreset）在多次调用间互相影响；
//  - 分离 demux 与解码耗时，便于定位瓶颈在 IO 还是计算；
//  - 返回逐帧耗时数组，可计算 P50/P95 等分位数，而不只是一个平均值。
//

#ifndef TXAV1D_BENCH_H
#define TXAV1D_BENCH_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** txav1d_bench() 的失败返回码 */
#define TXAV1D_BENCH_ERROR (-1)

/** 测试配置 */
typedef struct Txav1dBenchConfig {
    const char *input_file;   ///< 码流路径，必填
    unsigned limit;           ///< 最多解多少帧，0 表示全部
    unsigned skip;            ///< 跳过多少个包（用于 seek 到关键帧附近）
    int threads;              ///< 解码线程数，0 表示使用库默认（自动）
    int frame_delay;          ///< 帧延迟，0 表示使用库默认
    int apply_grain;          ///< 是否应用 film grain：-1 默认，0 关闭，1 开启
    int wpp;                  ///< 是否启用 WPP：-1 默认，0 关闭，1 开启
} Txav1dBenchConfig;

/** 测试结果，所有时间单位均为毫秒 */
typedef struct Txav1dBenchResult {
    int status;               ///< 0 成功，TXAV1D_BENCH_ERROR 失败
    char error[192];          ///< 失败原因，status 非 0 时有效

    unsigned total_frames;    ///< 码流头中报告的总帧数
    unsigned decoded_frames;  ///< 实际解码输出的帧数

    int width;                ///< 若解码成功，第一帧的宽
    int height;               ///< 若解码成功，第一帧的高
    int bpc;                  ///< 位深（8/10）

    unsigned fps_num;         ///< 码流帧率分子
    unsigned fps_den;         ///< 码流帧率分母

    double total_ms;          ///< 端到端总耗时
    double demux_ms;          ///< 其中读包耗时
    double decode_ms;         ///< 其中解码耗时（total - demux）

    double first_frame_ms;    ///< 首帧耗时，反映解码器冷启动成本
    double avg_frame_ms;      ///< 平均单帧耗时（decode_ms / decoded_frames）
    double min_frame_ms;      ///< 最快单帧
    double max_frame_ms;      ///< 最慢单帧
    double p50_frame_ms;      ///< 单帧耗时中位数
    double p95_frame_ms;      ///< 单帧耗时 P95

    /// 逐帧解码耗时（毫秒）。由本函数 malloc，调用方用 txav1d_bench_free_result() 释放。
    double *frame_ms;
    size_t frame_ms_count;
} Txav1dBenchResult;

/**
 * 执行一次完整的解码测速。
 *
 * 每次调用都会重新打开 demuxer 与解码器，因此多次调用之间的开销互相独立，
 * 适合作为「一轮」测试反复执行。
 *
 * @return 0 表示测试完成（即使解码中途出错也会填充 error 字段），
 *         TXAV1D_BENCH_ERROR 表示参数非法或无法打开输入。
 */
int txav1d_bench(const Txav1dBenchConfig *cfg, Txav1dBenchResult *result);

/** 释放 result 内部由本模块分配的内存，可安全传入 NULL。 */
void txav1d_bench_free_result(Txav1dBenchResult *result);

#ifdef __cplusplus
}
#endif

#endif /* TXAV1D_BENCH_H */
