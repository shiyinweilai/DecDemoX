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

/**
 * 定速（pacing）模式。
 *
 * 模拟真实播放器的实时节拍：解码线程全速解帧入缓冲，一条独立的出帧线程
 * 按目标帧率的绝对时刻取帧，缓冲满则解码线程阻塞等待（背压）。这与真实
 * 播放器「解码全速 + 渲染侧按帧率出帧 + 缓冲满回压」的架构一致，而不是
 * 在解码循环里逐帧 sleep——后者会打断解码器的跨帧流水，测出的 CPU 与
 * 单帧耗时都不反映真实播放形态。
 *
 * 它不改变解码器任何内部配置，只控制出帧节奏。
 */
#define TXAV1D_BENCH_PACING_OFF    0  ///< 不定速，全速解码（默认）
#define TXAV1D_BENCH_PACING_SOURCE 1  ///< 按码流标称帧率对齐
#define TXAV1D_BENCH_PACING_CUSTOM 2  ///< 按 pacing_fps 指定的帧率对齐

/**
 * 线程口径：决定 threads 配置如何下发给解码器。
 *
 * CAPABILITY（默认）：解码器能力口径。txav1d 额外写 reserved[0] 绕过库内部
 *   的 2 线程上限，填几个线程就真跑几个，用于线程扩展性横向对比。
 * PLAYERCORE：对齐线上 PlayerCore（FFmpeg libtxav1d 封装 libtxav1d_init）：
 *   thread_count = threads > 0 ? threads : 逻辑核数；
 *   n_threads = min(thread_count, TXAV1D_MAX_THREADS)；
 *   max_frame_delay 按 thread_count*3/2 推导。
 *   自动档（threads <= 0）不写 reserved[0]，库内部 2 线程截断照常生效，
 *   与线上一致；手动档写 reserved[0]，txav1d 与 dav1d 线程边界一致。
 */
#define TXAV1D_BENCH_THREAD_POLICY_CAPABILITY 0
#define TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE 1

/** 测试配置 */
typedef struct Txav1dBenchConfig {
    const char *input_file;   ///< 码流路径，必填
    unsigned limit;           ///< 最多解多少帧，0 表示全部
    unsigned skip;            ///< 跳过多少个包（用于 seek 到关键帧附近）
    int threads;              ///< 解码线程数，0 表示使用库默认（自动）
    int frame_delay;          ///< 帧延迟，0 表示使用库默认
    int apply_grain;          ///< 是否应用 film grain：-1 默认，0 关闭，1 开启
    int wpp;                  ///< 是否启用 WPP：-1 默认，0 关闭，1 开启
    int pacing;               ///< 定速模式，取 TXAV1D_BENCH_PACING_*
    double pacing_fps;        ///< 自定义目标帧率，pacing 为 CUSTOM 时有效
    int pacing_buffer;        ///< 定速时解码可提前出帧线程的帧数（run-ahead 缓冲深度），
                              ///< 0 表示用内部默认值。仅 pacing 生效时有意义。
    int thread_policy;        ///< 线程口径，取 TXAV1D_BENCH_THREAD_POLICY_*，默认 0
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

    double total_ms;          ///< 端到端总耗时。定速时 = 出帧线程走完全部帧的墙钟
                              ///< （含按帧率对齐的等待），据此算实际产帧率。
    double demux_ms;          ///< 其中读包耗时
    double decode_ms;         ///< 纯解码耗时（解码线程累计，不含出帧等待）。
                              ///< 定速与否都只反映解码器本身的处理速度。

    double first_frame_ms;    ///< 首帧耗时，反映解码器冷启动成本
    double avg_frame_ms;      ///< 平均单帧耗时（decode_ms / decoded_frames）
    double min_frame_ms;      ///< 最快单帧
    double max_frame_ms;      ///< 最慢单帧
    double p50_frame_ms;      ///< 单帧耗时中位数
    double p95_frame_ms;      ///< 单帧耗时 P95

    /**
     * 实际生效的定速模式与目标帧率。
     *
     * 与配置分开返回，是因为「选了按码流帧率」但码流头里没有帧率信息时
     * 会退回不定速。只看配置会让下游以为这组数据是定速跑的。
     * pacing 非 OFF 且 pacing_fps > 0 才代表真的定速生效。
     */
    int pacing;
    double pacing_fps;

    /**
     * 累计节流等待时长（毫秒）。
     *
     * 定速时为出帧线程按帧率对齐而阻塞等待的累计时长。它不并入 decode_ms：
     * 等待是出帧线程「故意不做事的空转」，与解码线程的计算无关。
     * 用途是核对 total_ms 构成：out 线程 total ≈ 实际取帧耗时 + wait。
     */
    double pacing_wait_ms;

    /**
     * 定速缓冲观测。反映「解码跟不跟得上目标帧率」。
     *
     * buffer_capacity：实际使用的缓冲深度（run-ahead 帧数）。
     * buffer_full_events：解码线程因缓冲满而阻塞的次数；越大说明解码越轻松，
     *     解码产能远超目标帧率。
     * buffer_starve_events：出帧线程到点却取不到帧（缓冲空）的次数；大于 0
     *     说明解码跟不上目标帧率，实时性不达标，是定速测试最关键的信号。
     * 非定速时三者均为 0。
     */
    int buffer_capacity;
    unsigned buffer_full_events;
    unsigned buffer_starve_events;

    /// 逐帧解码耗时（毫秒），反映解码能力。定速下仍是解码线程的纯解码耗时，
    /// 不含出帧等待。由本函数 malloc，调用方用 txav1d_bench_free_result() 释放。
    double *frame_ms;
    size_t frame_ms_count;

    /**
     * 实际下发给解码器 settings 的线程参数（打开解码器前的最终值）。
     * applied_thread_policy：实际采用的线程口径。
     * applied_n_threads：settings.n_threads；0 表示交给库自动。
     * applied_thread_override：txav1d 的 reserved[0]，0 表示未写（库内部
     *     可能截断 n_threads）；dav1d 恒为 0。
     * applied_frame_delay：settings.max_frame_delay；0 表示库默认。
     * 放在结构体末尾，避免影响既有字段偏移。
     */
    int applied_thread_policy;
    int applied_n_threads;
    int applied_thread_override;
    int applied_frame_delay;
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
