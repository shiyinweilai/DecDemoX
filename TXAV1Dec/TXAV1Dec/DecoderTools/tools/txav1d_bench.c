//
//  txav1d_bench.c
//  TXAV1Dec
//
//  性能测试入口实现。
//
//  设计要点：
//  1. 不走 getopt 参数解析。之前崩溃的根因是 optind/optreset 属于进程级全局状态，
//     多次调用会互相干扰。测速场景天然要反复跑，所以这里直接填配置结构体，
//     彻底绕开全局状态。
//  2. 分离 demux 与 decode 耗时。测速要能回答「慢在 IO 还是慢在计算」，
//     一个总耗时数字回答不了这个问题。
//  3. 保留逐帧耗时。平均值会被冷启动和个别长帧拉偏，只有分位数才能反映
//     真实体验，所以逐帧数据要留下来自己算统计。
//

#include "config.h"
#include "vcs_version.h"
#include "cli_config.h"

#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#else
#include <unistd.h>
#endif

#include "txav1d/txav1d.h"

#include "input/input.h"
#include "output/output.h"

#include "txav1d_bench.h"

/** 单调时钟，纳秒。mach_absolute_time 的时基在部分设备上不是 1，必须换算。 */
static uint64_t bench_now_nanos(void) {
#ifdef __APPLE__
    static mach_timebase_info_data_t timebase = {0, 0};
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }
    return mach_absolute_time() * timebase.numer / timebase.denom;
#elif defined(CLOCK_MONOTONIC)
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return 1000000000ULL * ts.tv_sec + ts.tv_nsec;
#else
    return 0;
#endif
}

static double nanos_to_ms(const uint64_t nanos) {
    return (double)nanos / 1000000.0;
}

/**
 * 阻塞指定纳秒，专用于定速节流。
 *
 * 被打断时不重试剩余时间：节流的基准是「第 n 帧的绝对应产出时刻」，
 * 少睡的那点时间会在下一次计算 deadline 时自动补回来，
 * 局部重试反而会让累计误差越滚越大。
 */
static void bench_sleep_nanos(const uint64_t nanos) {
    if (nanos == 0) return;
    struct timespec ts = {
        .tv_sec = (time_t)(nanos / 1000000000ULL),
        .tv_nsec = (long)(nanos % 1000000000ULL),
    };
    nanosleep(&ts, NULL);
}

/**
 * 本机逻辑核数。与两个解码库内部 num_logical_processors() 在 Apple 平台
 * 的实现保持同一口径（hw.logicalcpu），保证「自动」档两边拿到相同的数。
 * 取不到时返回 0，由调用方退化为单线程。
 */
static int bench_logical_cpu_count(void) {
#if defined(__APPLE__)
    int count = 0;
    size_t len = sizeof(count);
    if (sysctlbyname("hw.logicalcpu", &count, &len, NULL, 0) == 0) {
        return count;
    }
    return 0;
#elif defined(_SC_NPROCESSORS_ONLN)
    const long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 0;
#else
    return 0;
#endif
}

/**
 * 复刻 FFmpeg libtxav1d 封装（libtxav1d_init）的 max_frame_delay 推导：
 *     threads_scaled = thread_count * 3 / 2
 *     tile_threads   = floor(sqrt(threads_scaled))
 *     frame_delay    = ceil(threads_scaled / tile_threads)
 * 用整数运算实现 floor(sqrt) 与 ceil(div)，对正整数精确且无需 math.h。
 */
static int __attribute__((unused)) bench_playercore_frame_delay(int thread_count) {
    int threads_scaled = thread_count * 3 / 2;
    if (threads_scaled < 1) threads_scaled = 1;
    int tile_threads = 1;
    while ((tile_threads + 1) * (tile_threads + 1) <= threads_scaled) {
        tile_threads++;
    }
    int frame_delay = (threads_scaled + tile_threads - 1) / tile_threads;
    if (frame_delay < 1) frame_delay = 1;
#ifdef TXAV1D_MAX_FRAME_DELAY
    if (frame_delay > TXAV1D_MAX_FRAME_DELAY) frame_delay = TXAV1D_MAX_FRAME_DELAY;
#endif
    return frame_delay;
}

static void set_error(Txav1dBenchResult *const r, const char *const msg) {
    if (!r) return;
    r->status = TXAV1D_BENCH_ERROR;
    snprintf(r->error, sizeof(r->error), "%s", msg ? msg : "unknown error");
}

/* ============================================================
 * 定速（真实播放模型）：解码线程 + 出帧线程 + 环形缓冲
 *
 * 解码线程全速把帧推入缓冲（满则阻塞 = 背压），出帧线程按目标帧率
 * 的绝对时刻取帧（空则等待）。这与真实播放器的解码/渲染分离一致，
 * 不在解码路径上插入任何 sleep，因此解码能力指标（decode_ms、
 * frame_ms）不受定速影响；实时节拍由出帧线程独立承担。
 * ============================================================ */

/** 环形缓冲中的一帧。pic 的所有权随之转移给出帧线程负责 unref/write。 */
typedef struct PacedSlot {
    Txav1dPicture pic;
} PacedSlot;

typedef struct PacedRing {
    PacedSlot *slots;
    int capacity;             ///< 槽位数（run-ahead 深度 + 1，留一空位区分满/空）
    int head;                 ///< 出帧线程下一个读取位
    int tail;                 ///< 解码线程下一个写入位
    int count;                ///< 当前缓冲中的帧数

    int producer_done;        ///< 解码线程已结束（正常或出错）
    int producer_abort;       ///< 解码失败，出帧线程应立即丢弃剩余帧并退出
    int consumer_error;       ///< 出帧线程写出失败，通知解码线程尽快停止

    pthread_mutex_t lock;
    pthread_cond_t not_full;  ///< 缓冲从满变为不满
    pthread_cond_t not_empty; ///< 缓冲从空变为非空

    /* 以下由出帧线程维护并最终回填到 result */
    MuxerContext *out;        ///< 输出模块（首帧在出帧线程内初始化）
    const unsigned *fps;      ///< 传给 output_open 的码流帧率
    uint64_t nspf;            ///< 目标帧间隔（纳秒）
    uint64_t t_start;         ///< 出帧计时起点（第一帧取出时刻）
    int started;              ///< 是否已取出第一帧并设定 t_start

    unsigned written;         ///< 已写出帧数
    uint64_t wait_nanos;      ///< 累计按帧率对齐的等待时长
    unsigned starve_events;   ///< 到点却取不到帧（解码跟不上）的次数
    char err_msg[160];        ///< 出帧线程的错误信息
} PacedRing;

/**
 * 出帧线程：按目标帧率的绝对时刻从缓冲取帧并写出。
 *
 * 节拍基准是「第 n 帧的绝对应产出时刻」= t_start + nspf * n，而非逐帧
 * 固定 sleep，避免偏差累加成漂移。取不到帧时：若解码已结束则退出，
 * 否则记一次 starve（解码跟不上），阻塞等待新帧。
 */
static void *paced_consumer(void *arg) {
    PacedRing *ring = (PacedRing *)arg;

    for (;;) {
        pthread_mutex_lock(&ring->lock);
        if (ring->count == 0 && !ring->producer_done) {
            // 到这里要取下一帧却没有帧可取，且解码还没结束——这正是
            // 「解码跟不上目标帧率」的饥饿信号。只在首帧之后计数：首帧前的
            // 等待属于解码器冷启动，不算实时性不达标。
            if (ring->started) ring->starve_events++;
            while (ring->count == 0 && !ring->producer_done) {
                pthread_cond_wait(&ring->not_empty, &ring->lock);
            }
        }
        if (ring->count == 0 && ring->producer_done) {
            pthread_mutex_unlock(&ring->lock);
            break;   // 缓冲排空且解码结束，正常收尾
        }
        if (ring->producer_abort) {
            // 解码失败：丢弃缓冲里所有剩余帧，立即退出，不再按帧率等待
            while (ring->count > 0) {
                Txav1dPicture drop = ring->slots[ring->head].pic;
                ring->head = (ring->head + 1) % ring->capacity;
                ring->count--;
                pthread_mutex_unlock(&ring->lock);
                txav1d_picture_unref(&drop);
                pthread_mutex_lock(&ring->lock);
            }
            pthread_mutex_unlock(&ring->lock);
            break;
        }
        // 取出一帧（所有权转移到本线程）
        Txav1dPicture pic = ring->slots[ring->head].pic;
        ring->head = (ring->head + 1) % ring->capacity;
        ring->count--;
        pthread_cond_signal(&ring->not_full);
        pthread_mutex_unlock(&ring->lock);

        // 首帧：此刻才知道分辨率，初始化输出模块并设定节拍起点
        if (!ring->started) {
            if (output_open(&ring->out, "null", "/dev/null", &pic.p, ring->fps) < 0) {
                txav1d_picture_unref(&pic);
                pthread_mutex_lock(&ring->lock);
                ring->consumer_error = 1;
                snprintf(ring->err_msg, sizeof(ring->err_msg), "初始化输出模块失败");
                pthread_cond_signal(&ring->not_full);
                pthread_mutex_unlock(&ring->lock);
                return NULL;
            }
            ring->started = 1;
            ring->t_start = bench_now_nanos();
        } else {
            // 等到「第 written 帧的绝对应产出时刻」。第 0 帧立即出（定义 t_start）。
            const uint64_t deadline = ring->nspf * (uint64_t)ring->written;
            const uint64_t elapsed = bench_now_nanos() - ring->t_start;
            if (elapsed < deadline) {
                const uint64_t waitStart = bench_now_nanos();
                bench_sleep_nanos(deadline - elapsed);
                ring->wait_nanos += bench_now_nanos() - waitStart;
            }
        }

        // null muxer 的 write_picture 内部会 unref，这里不能再 unref
        if (output_write(ring->out, &pic) < 0) {
            pthread_mutex_lock(&ring->lock);
            ring->consumer_error = 1;
            snprintf(ring->err_msg, sizeof(ring->err_msg), "输出帧失败");
            pthread_cond_signal(&ring->not_full);
            pthread_mutex_unlock(&ring->lock);
            return NULL;
        }
        ring->written++;
    }
    return NULL;
}

/** 解码线程把一帧交给缓冲；满则阻塞等待。返回 0 成功，-1 表示出帧线程已出错。
 *  out_block_nanos 回填本次因缓冲满而阻塞的时长，供调用方从单帧间隔中扣除。 */
static int paced_push(PacedRing *ring, const Txav1dPicture *pic,
                      unsigned *out_full_events, uint64_t *out_block_nanos) {
    *out_block_nanos = 0;
    pthread_mutex_lock(&ring->lock);
    if (ring->count == ring->capacity - 1 && !ring->consumer_error) {
        (*out_full_events)++;
        const uint64_t blockStart = bench_now_nanos();
        while (ring->count == ring->capacity - 1 && !ring->consumer_error) {
            pthread_cond_wait(&ring->not_full, &ring->lock);
        }
        *out_block_nanos = bench_now_nanos() - blockStart;
    }
    if (ring->consumer_error) {
        pthread_mutex_unlock(&ring->lock);
        return -1;
    }
    ring->slots[ring->tail].pic = *pic;
    ring->tail = (ring->tail + 1) % ring->capacity;
    ring->count++;
    pthread_cond_signal(&ring->not_empty);
    pthread_mutex_unlock(&ring->lock);
    return 0;
}

/** 升序比较，供 qsort 计算分位数 */
static int cmp_double(const void *a, const void *b) {
    const double da = *(const double *)a;
    const double db = *(const double *)b;
    return (da > db) - (da < db);
}

/**
 * 计算分位数，输入必须已升序排列。
 *
 * 采用线性插值：n=100、p=0.5 时落在第 49.5 个元素上，
 * 直接取整会引入半个位置的偏差，样本少时误差明显。
 */
static double percentile_sorted(const double *const sorted, const size_t n,
                                const double p)
{
    if (n == 0) return 0.0;
    if (n == 1) return sorted[0];
    const double pos = p * (double)(n - 1);
    const size_t lo = (size_t)pos;
    if (lo >= n - 1) return sorted[n - 1];
    const double frac = pos - (double)lo;
    return sorted[lo] + (sorted[lo + 1] - sorted[lo]) * frac;
}

void txav1d_bench_free_result(Txav1dBenchResult *const result) {
    if (!result) return;
    free(result->frame_ms);
    result->frame_ms = NULL;
    result->frame_ms_count = 0;
}

int txav1d_bench(const Txav1dBenchConfig *const cfg,
                 Txav1dBenchResult *const result)
{
    if (!cfg || !result) return TXAV1D_BENCH_ERROR;
    if (!cfg->input_file || cfg->input_file[0] == '\0') {
        return TXAV1D_BENCH_ERROR;
    }

    memset(result, 0, sizeof(*result));

    unsigned fps[2] = {0, 0};
    unsigned timebase[2] = {0, 0};
    unsigned total = 0;
    DemuxerContext *in = NULL;
    Txav1dContext *c = NULL;
    MuxerContext *out = NULL;
    Txav1dData data;
    Txav1dPicture pic;
    memset(&data, 0, sizeof(data));
    memset(&pic, 0, sizeof(pic));

    if (input_open(&in, NULL, cfg->input_file, fps, &total, timebase) < 0) {
        set_error(result, "无法打开输入文件，请检查路径与格式");
        return TXAV1D_BENCH_ERROR;
    }

    result->total_frames = total;
    result->fps_num = fps[0];
    result->fps_den = fps[1];

    // ---- 定速（pacing）参数 ----
    // 语义对齐命令行 txav1d 的 `--realtime`：按目标帧率对齐每帧的产出时刻。
    // 它是「节流」而非解码器配置，不改变任何内部设置，只在我们自己的解码
    // 循环里插入等待，因此可以安全地在同一个 dylib 上反复开关做对照。
    int pacing = TXAV1D_BENCH_PACING_OFF;
    double pacingFps = 0;
    if (cfg->pacing == TXAV1D_BENCH_PACING_CUSTOM && cfg->pacing_fps > 0) {
        pacing = TXAV1D_BENCH_PACING_CUSTOM;
        pacingFps = cfg->pacing_fps;
    } else if (cfg->pacing == TXAV1D_BENCH_PACING_SOURCE &&
               fps[0] != 0 && fps[1] != 0) {
        pacing = TXAV1D_BENCH_PACING_SOURCE;
        pacingFps = (double)fps[0] / (double)fps[1];
    }
    // 码流头缺帧率时（fps[1]==0）「按码流帧率」无法成立，退回不定速。
    // 这个决定必须回填到 result：只看传入的配置，下游会以为这组数据是定速跑的。
    uint64_t pacingNspf = 0;
    if (pacing != TXAV1D_BENCH_PACING_OFF) {
        pacingNspf = (uint64_t)(1000000000.0 / pacingFps);
        if (pacingNspf == 0) {
            // 目标帧率高到不足 1 纳秒一帧，节流没有意义，按不定速处理
            pacing = TXAV1D_BENCH_PACING_OFF;
            pacingFps = 0;
        }
    }
    result->pacing = pacing;
    result->pacing_fps = pacingFps;

    Txav1dSettings settings;
    txav1d_default_settings(&settings);
    settings.strict_std_compliance = 1;
#ifndef TXAV1D_SHIM_DAV1D
    if (cfg->thread_policy == TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE) {
        // 对齐 PlayerCore：逐行复刻 FFmpeg libtxav1d 封装的 libtxav1d_init。
        //   thread_count：PlayerCore 的 GetDecodeThreadCount()，配置了
        //       decode_thread_count 就用它，否则取 CPU 核数。
        //   n_threads = FFMIN(thread_count, TXAV1D_MAX_THREADS)
        //   max_frame_delay = ceil(threads_scaled / floor(sqrt(threads_scaled)))
        // 自动档：与线上封装完全一致，不写 reserved[0]，库内部对 n_threads
        // 的 2 线程截断照常生效——这是线上 PlayerCore 的真实行为，用于测
        // 「定速下谁更省」。
        // 手动档：用户明确指定线程数，要求 txav1d 与 dav1d 边界一致，
        // 所以额外写 reserved[0]，让 txav1d 填几个就真跑几个（dav1d 本来
        // 就不截断）。frame_delay 仍走封装公式，其余与线上一致。
        int threadCount = cfg->threads > 0 ? cfg->threads : bench_logical_cpu_count();
        if (threadCount < 1) threadCount = 1;
        settings.n_threads = threadCount > TXAV1D_MAX_THREADS ? TXAV1D_MAX_THREADS : threadCount;
        if (cfg->threads > 0) {
            settings.reserved[0] = (uint8_t)(settings.n_threads > 255 ? 255 : settings.n_threads);
        }
        if (cfg->frame_delay <= 0) {
            settings.max_frame_delay = bench_playercore_frame_delay(threadCount);
        }
    } else if (cfg->threads > 0) {
        // 解码器能力口径：「自动」必须显式填满核数，不能只靠库默认值：
        // txav1d_default_settings 里 s->n_threads = 1，而 dav1d 是 0（按逻辑核自动取满）。
        // 两边都留 0 让库自己决定时，同一个「自动」档在 txav1d 上实际是纯单线程，
        // 会得出「txav1d 比 dav1d 慢 2.4 倍」这种线程数不对齐的结论。
        // 这里统一在自动档按本机逻辑核数填写，并同样走 reserved[0] 绕过 2 线程上限。
        settings.n_threads = cfg->threads;
        // txav1d 的 get_num_threads() 对 n_threads 设了硬上限：
        //     threads = imin(s->n_threads, max_threads_used /* = 2 */)
        // 所以只写 n_threads 时，超过 2 的线程数会被静默截掉，
        // 命令行调 8 实际仍只跑 2 个 tile 线程，从数据上几乎看不出来。
        // 同一函数里另有一条私有通道：
        //     if (s->reserved[0]) threads = s->reserved[0];
        // 它的判断在上限之前，能绕过上面的截断。官方 CLI 的 --threads
        // 正是写这个字段（见 txav1d_cli_parse.c 的 ARG_THREADS 分支），
        // 所以这就是官方指定的线程数入口，不是私搭的旁路。
        //
        // 两处都写：n_threads 保持对外语义正确（get_frame_delay 等接口读它），
        // reserved[0] 负责真正突破限制。reserved[0] 是 uint8_t，
        // 超过 255 会被截断，先夹紧再写。
        settings.reserved[0] = (uint8_t)(cfg->threads > 255 ? 255 : cfg->threads);
        // frame delay 按 libtxav1d 封装公式推导，与线上帧级并行深度一致。
        if (cfg->frame_delay <= 0) {
            settings.max_frame_delay = bench_playercore_frame_delay(cfg->threads);
        }
    } else {
        // 自动档：取逻辑核数上限，与 dav1d 的 n_threads=0 语义对齐。
        // 这里不调用 txav1d_num_logical_processors()：它在静态库里存在，
        // 但两个版本的头文件都没声明，属于内部符号。用它会让 dylib 依赖
        // 一个非公开 API，换库版本时可能直接链接失败。库内部在 Apple 平台
        // 读的也是 hw.logicalcpu，这里用同一个系统调用，口径一致。
        int autoThreads = bench_logical_cpu_count();
        if (autoThreads < 1) autoThreads = 1;
        if (autoThreads > 255) autoThreads = 255;
        settings.n_threads = autoThreads;
        settings.reserved[0] = (uint8_t)autoThreads;
        if (cfg->frame_delay <= 0) {
            settings.max_frame_delay = bench_playercore_frame_delay(autoThreads);
        }
    }
    result->applied_thread_override = settings.reserved[0];
#else
    if (cfg->thread_policy == TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE) {
        // 对齐 PlayerCore 的 FFmpeg libdav1d 封装：thread_count 同样取
        // 配置值或 CPU 核数，n_threads = thread_count，max_frame_delay 不设
        // （交给库按 n_threads 自动推导）。
        int threadCount = cfg->threads > 0 ? cfg->threads : bench_logical_cpu_count();
        if (threadCount < 1) threadCount = 1;
        settings.n_threads = threadCount;
    } else if (cfg->threads > 0) {
        settings.n_threads = cfg->threads;
    }
    result->applied_thread_override = 0;
#endif
    if (cfg->frame_delay > 0) settings.max_frame_delay = cfg->frame_delay;
    if (cfg->apply_grain >= 0) settings.apply_grain = cfg->apply_grain;
    if (cfg->wpp >= 0) settings.use_wpp = cfg->wpp;
    result->applied_thread_policy = cfg->thread_policy == TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE
        ? TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE
        : TXAV1D_BENCH_THREAD_POLICY_CAPABILITY;
    result->applied_n_threads = settings.n_threads;
    result->applied_frame_delay = settings.max_frame_delay;

    if (txav1d_open(&c, &settings) < 0) {
        input_close(in);
        set_error(result, "解码器初始化失败");
        return TXAV1D_BENCH_ERROR;
    }

    // 逐帧数组容量预估：优先用 limit，其次用码流声明的总帧数。
    // total 为 0 或 0xFFFFFFFF 表示未知，给一个保底容量，后续按需扩容。
    size_t capacity = 0;
    if (cfg->limit > 0) {
        capacity = cfg->limit;
    } else if (total != 0 && total != 0xFFFFFFFF) {
        capacity = total;
    } else {
        capacity = 1024;
    }
    if (capacity == 0) capacity = 1;

    double *frameMs = (double *)calloc(capacity, sizeof(double));
    if (!frameMs) {
        txav1d_close(&c);
        input_close(in);
        set_error(result, "内存不足，无法分配逐帧耗时数组");
        return TXAV1D_BENCH_ERROR;
    }

    // 首包：skip 为 0 时读第 1 个包；skip>0 时在跳过循环里已读到目标包
    int failed = 0;
    char failMsg[160] = {0};
    int hasPacket = 0;
    uint64_t demuxNanos = 0;

    if (cfg->skip > 0) {
        for (unsigned i = 0; i <= cfg->skip; i++) {
            const uint64_t t0 = bench_now_nanos();
            const int readRes = input_read(in, &data);
            demuxNanos += bench_now_nanos() - t0;
            if (readRes < 0) {
                free(frameMs);
                txav1d_close(&c);
                input_close(in);
                set_error(result, "跳过帧数超过码流长度，无法继续");
                return TXAV1D_BENCH_ERROR;
            }
            if (i < cfg->skip) txav1d_data_unref(&data);
        }
        hasPacket = 1;
    }

    uint64_t decodeNanos = 0;
    uint64_t pacingWaitNanos = 0;
    unsigned decoded = 0;
    int openedOutput = 0;
    const uint64_t tStart = bench_now_nanos();

    // ---- 定速：建立环形缓冲并启动出帧线程 ----
    // 定速时解码线程只负责全速解帧并推入缓冲，由出帧线程按帧率写出。
    // run-ahead 深度默认取 16（经验值：足够铺开 av1d 的帧级并行，又不至于
    // 让缓冲把「解码跟不上」的信号吸收掉）；调用方可通过 pacing_buffer 覆盖。
    PacedRing ring;
    pthread_t consumerThread;
    int consumerStarted = 0;
    unsigned bufferFullEvents = 0;
    int ringCapacity = 0;
    if (pacingNspf != 0) {
        int runAhead = cfg->pacing_buffer > 0 ? cfg->pacing_buffer : 16;
        if (runAhead < 1) runAhead = 1;
        ringCapacity = runAhead + 1;   // 多一个空位以区分满/空
        memset(&ring, 0, sizeof(ring));
        ring.slots = (PacedSlot *)calloc((size_t)ringCapacity, sizeof(PacedSlot));
        if (!ring.slots) {
            free(frameMs);
            txav1d_close(&c);
            input_close(in);
            set_error(result, "内存不足，无法分配定速缓冲");
            return TXAV1D_BENCH_ERROR;
        }
        ring.capacity = ringCapacity;
        ring.fps = fps;
        ring.nspf = pacingNspf;
        pthread_mutex_init(&ring.lock, NULL);
        pthread_cond_init(&ring.not_full, NULL);
        pthread_cond_init(&ring.not_empty, NULL);
        if (pthread_create(&consumerThread, NULL, paced_consumer, &ring) != 0) {
            free(ring.slots);
            pthread_mutex_destroy(&ring.lock);
            pthread_cond_destroy(&ring.not_full);
            pthread_cond_destroy(&ring.not_empty);
            free(frameMs);
            txav1d_close(&c);
            input_close(in);
            set_error(result, "无法创建出帧线程");
            return TXAV1D_BENCH_ERROR;
        }
        consumerStarted = 1;
    }

    // 单帧耗时按「相邻两次产出帧之间的时间间隔」统计。
    // 原因：av1d 的实际解码工作几乎都发生在 txav1d_send_data 内部，
    // txav1d_get_picture 多数时候只是从输出队列取走一帧，耗时接近 0。
    // 如果只测 get_picture，得到的会是 0.0000 ms/f 这种无效数字。
    uint64_t lastFrameNanos = tStart;
    uint64_t demuxSinceLastFrame = 0;
    uint64_t pacingBlockSinceLastFrame = 0;   // 定速下累计缓冲满阻塞时长，供下一帧扣除
    int haveFirstFrame = 0;
    // 连续多次既没读出新包、也没产出帧时，说明解码器已无法推进，
    // 必须主动退出，否则会退化成死循环把 App 拖死。
    unsigned idleIterations = 0;

    while (!failed) {
        // 没有待处理的包就先读一个
        if (!hasPacket) {
            const uint64_t t0 = bench_now_nanos();
            const int readRes = input_read(in, &data);
            const uint64_t readNanos = bench_now_nanos() - t0;
            demuxNanos += readNanos;
            demuxSinceLastFrame += readNanos;
            if (readRes < 0) break;   // EOF 属正常结束
            hasPacket = 1;
        }

        // ---- 送包 ----
        const uint64_t tSend0 = bench_now_nanos();
        const int sendRes = txav1d_send_data(c, &data);
        decodeNanos += bench_now_nanos() - tSend0;
        if (sendRes < 0 && sendRes != TXAV1D_ERR(EAGAIN)) {
            txav1d_data_unref(&data);
            snprintf(failMsg, sizeof(failMsg), "送包失败：%s",
                     strerror(TXAV1D_ERR(sendRes)));
            failed = 1;
            break;
        }
        // send_data 成功时会把 data 消耗掉（sz 归零）；EAGAIN 时 data 仍需保留
        if (data.sz == 0) hasPacket = 0;

        // ---- 取帧 ----
        memset(&pic, 0, sizeof(pic));
        const uint64_t tGet0 = bench_now_nanos();
        const int picRes = txav1d_get_picture(c, &pic);
        const uint64_t nowNanos = bench_now_nanos();
        decodeNanos += nowNanos - tGet0;

        if (picRes < 0) {
            if (picRes != TXAV1D_ERR(EAGAIN)) {
                snprintf(failMsg, sizeof(failMsg), "解码失败：%s",
                         strerror(TXAV1D_ERR(picRes)));
                failed = 1;
                break;
            }
            // EAGAIN：帧数不够，继续喂包。
            // 但如果本轮既没读出包、也没解出帧，说明状态无法推进。
            if (!hasPacket && ++idleIterations > 64) {
                snprintf(failMsg, sizeof(failMsg), "解码器长时间无进展，已中止");
                failed = 1;
                break;
            }
        } else {
            idleIterations = 0;
            // 这一帧的耗时 = 距上一帧产出（或测试开始）的墙钟间隔 - 其中读包的耗时。
            // 定速下还要扣除上一帧因缓冲满而阻塞（背压）的时长：那是等出帧线程
            // 腾位置的空转，属于节拍开销，不是解码耗时，混进去会让 frame_ms 虚高。
            // 首帧包含解码器内部初始化的成本，单独用 first_frame_ms 记录。
            uint64_t frameNanos = nowNanos - lastFrameNanos;
            uint64_t overhead = demuxSinceLastFrame + pacingBlockSinceLastFrame;
            if (overhead < frameNanos) {
                frameNanos -= overhead;
            }
            lastFrameNanos = nowNanos;
            demuxSinceLastFrame = 0;
            pacingBlockSinceLastFrame = 0;
            if (!haveFirstFrame) {
                haveFirstFrame = 1;
                result->first_frame_ms = nanos_to_ms(frameNanos);
            }
            if (!openedOutput && pacingNspf == 0) {
                // 非定速：直到第一帧解出来才知道真实分辨率，在本线程初始化输出。
                // 定速时输出模块改由出帧线程初始化，这里只负责回填分辨率。
                if (output_open(&out, "null", "/dev/null", &pic.p, fps) < 0) {
                    txav1d_picture_unref(&pic);
                    snprintf(failMsg, sizeof(failMsg), "初始化输出模块失败");
                    failed = 1;
                    break;
                }
                openedOutput = 1;
            }
            if (result->width == 0) {
                result->width = pic.p.w;
                result->height = pic.p.h;
                result->bpc = pic.p.bpc;
            }

            if (decoded >= capacity) {
                // 实际帧数超过头部声明时扩容，避免越界写
                const size_t newCap = capacity * 2;
                double *grown = (double *)realloc(frameMs, newCap * sizeof(double));
                if (!grown) {
                    txav1d_picture_unref(&pic);
                    snprintf(failMsg, sizeof(failMsg), "内存不足，逐帧数组扩容失败");
                    failed = 1;
                    break;
                }
                frameMs = grown;
                capacity = newCap;
            }

            frameMs[decoded] = nanos_to_ms(frameNanos);
            decoded++;

            if (pacingNspf != 0) {
                // 定速：把帧交给出帧线程（满则阻塞 = 背压），pic 所有权随之转移，
                // 本线程不再 unref/write。解码路径上没有任何 sleep，所以
                // decode_ms / frame_ms 保持纯解码能力，节拍完全由出帧线程承担。
                uint64_t blockNanos = 0;
                if (paced_push(&ring, &pic, &bufferFullEvents, &blockNanos) < 0) {
                    snprintf(failMsg, sizeof(failMsg), "%s",
                             ring.err_msg[0] ? ring.err_msg : "出帧线程异常");
                    failed = 1;
                    break;
                }
                pacingBlockSinceLastFrame += blockNanos;
            } else {
                // 非定速：null muxer 的 write_picture 内部会 unref，
                // 这里不能再 unref，否则是 double free。
                if (output_write(out, &pic) < 0) {
                    snprintf(failMsg, sizeof(failMsg), "输出帧失败");
                    failed = 1;
                    break;
                }
            }

            if (cfg->limit > 0 && decoded >= cfg->limit) break;
        }
    }

    // ---- 冲刷解码器内部缓冲的帧 ----
    // 有帧延迟时尾部若干帧要等 flush 才输出，不 flush 会少算帧数。
    if (!failed && (cfg->limit == 0 || decoded < cfg->limit)) {
        while (1) {
            memset(&pic, 0, sizeof(pic));
            const uint64_t t0 = bench_now_nanos();
            const int picRes = txav1d_get_picture(c, &pic);
            const uint64_t nowNanos = bench_now_nanos();
            if (picRes < 0) break;   // EAGAIN/EOF 都表示没有更多帧

            decodeNanos += nowNanos - t0;

            uint64_t frameNanos = nowNanos - lastFrameNanos;
            if (pacingBlockSinceLastFrame < frameNanos) {
                frameNanos -= pacingBlockSinceLastFrame;
            }
            lastFrameNanos = nowNanos;
            demuxSinceLastFrame = 0;
            pacingBlockSinceLastFrame = 0;
            if (!haveFirstFrame) {
                haveFirstFrame = 1;
                result->first_frame_ms = nanos_to_ms(frameNanos);
            }

            if (decoded >= capacity) {
                const size_t newCap = capacity * 2;
                double *grown = (double *)realloc(frameMs, newCap * sizeof(double));
                if (!grown) break;
                frameMs = grown;
                capacity = newCap;
            }
            frameMs[decoded] = nanos_to_ms(frameNanos);
            decoded++;

            if (pacingNspf != 0) {
                // 冲刷阶段的帧同样交给出帧线程，长尾帧也会按目标帧率被节拍，
                // 不会在最后瞬间倾泻出来。
                uint64_t blockNanos = 0;
                if (paced_push(&ring, &pic, &bufferFullEvents, &blockNanos) < 0) break;
                pacingBlockSinceLastFrame += blockNanos;
            } else {
                if (output_write(out, &pic) < 0) break;
            }

            if (cfg->limit > 0 && decoded >= cfg->limit) break;
        }
    }

    // ---- 定速：通知出帧线程解码已结束，等它排空缓冲并收尾 ----
    // total_ms 必须等出帧线程把最后一帧按帧率写完才算数，所以 totalNanos
    // 在 join 之后再取。解码线程到这里已不再占用解码器，CPU 统计也到此为止。
    if (consumerStarted) {
        pthread_mutex_lock(&ring.lock);
        ring.producer_done = 1;
        if (failed) ring.producer_abort = 1;   // 失败则让出帧线程立即丢帧退出
        pthread_cond_signal(&ring.not_empty);
        pthread_cond_signal(&ring.not_full);
        pthread_mutex_unlock(&ring.lock);
        pthread_join(consumerThread, NULL);

        pacingWaitNanos = ring.wait_nanos;
        if (ring.consumer_error && !failed) {
            snprintf(failMsg, sizeof(failMsg), "%s",
                     ring.err_msg[0] ? ring.err_msg : "出帧线程异常");
            failed = 1;
        }
        // 出帧线程初始化的输出模块由它持有，统一在这里关闭
        out = ring.out;
        // 出帧线程到点取不到帧的次数 = 缓冲空饥饿次数。它在取帧处无法直接
        // 计数（取帧与节拍解耦），这里用「写出帧数 < 解码帧数且缓冲曾为空」
        // 近似并不可靠，改为在出帧线程内按实际饥饿累计（见 starve_events）。
    }

    const uint64_t totalNanos = bench_now_nanos() - tStart;

    if (data.sz > 0) txav1d_data_unref(&data);
    if (out) output_close(out);
    txav1d_close(&c);
    input_close(in);

    if (consumerStarted) {
        result->buffer_capacity = ringCapacity > 0 ? ringCapacity - 1 : 0;
        result->buffer_full_events = bufferFullEvents;
        result->buffer_starve_events = ring.starve_events;
        free(ring.slots);
        pthread_mutex_destroy(&ring.lock);
        pthread_cond_destroy(&ring.not_full);
        pthread_cond_destroy(&ring.not_empty);
    }

    // ---- 汇总统计 ----
    result->decoded_frames = decoded;
    result->demux_ms = nanos_to_ms(demuxNanos);
    result->decode_ms = nanos_to_ms(decodeNanos);
    result->total_ms = nanos_to_ms(totalNanos);
    result->pacing_wait_ms = nanos_to_ms(pacingWaitNanos);
    if (decoded > 0) result->first_frame_ms = frameMs[0];

    if (decoded > 0) {
        double sum = 0;
        for (unsigned i = 0; i < decoded; i++) sum += frameMs[i];
        result->avg_frame_ms = sum / (double)decoded;

        // 分位数要求有序，但 frame_ms 对外要保留解码顺序，所以用副本排序
        double *sorted = (double *)malloc(decoded * sizeof(double));
        if (sorted) {
            memcpy(sorted, frameMs, decoded * sizeof(double));
            qsort(sorted, decoded, sizeof(double), cmp_double);
            result->min_frame_ms = sorted[0];
            result->max_frame_ms = sorted[decoded - 1];
            result->p50_frame_ms = percentile_sorted(sorted, decoded, 0.50);
            result->p95_frame_ms = percentile_sorted(sorted, decoded, 0.95);
            free(sorted);
        }
    }

    result->frame_ms = frameMs;
    result->frame_ms_count = decoded;

    if (failed) {
        result->status = TXAV1D_BENCH_ERROR;
        snprintf(result->error, sizeof(result->error), "%s", failMsg);
        return TXAV1D_BENCH_ERROR;
    }
    if (decoded == 0) {
        set_error(result, "未解出任何帧，请确认码流有效");
        return TXAV1D_BENCH_ERROR;
    }

    result->status = 0;
    return 0;
}
