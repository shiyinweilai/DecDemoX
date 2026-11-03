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

static void set_error(Txav1dBenchResult *const r, const char *const msg) {
    if (!r) return;
    r->status = TXAV1D_BENCH_ERROR;
    snprintf(r->error, sizeof(r->error), "%s", msg ? msg : "unknown error");
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
    // 「自动」必须显式填满核数，不能只靠库默认值：
    // txav1d_default_settings 里 s->n_threads = 1，而 dav1d 是 0（按逻辑核自动取满）。
    // 两边都留 0 让库自己决定时，同一个「自动」档在 txav1d 上实际是纯单线程，
    // 会得出「txav1d 比 dav1d 慢 2.4 倍」这种线程数不对齐的结论。
    // 这里统一在自动档按本机逻辑核数填写，并同样走 reserved[0] 绕过 2 线程上限。
    if (cfg->threads > 0) {
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
    }
#else
    if (cfg->threads > 0) settings.n_threads = cfg->threads;
#endif
    if (cfg->frame_delay > 0) settings.max_frame_delay = cfg->frame_delay;
    if (cfg->apply_grain >= 0) settings.apply_grain = cfg->apply_grain;
    if (cfg->wpp >= 0) settings.use_wpp = cfg->wpp;

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

    // 单帧耗时按「相邻两次产出帧之间的时间间隔」统计。
    // 原因：av1d 的实际解码工作几乎都发生在 txav1d_send_data 内部，
    // txav1d_get_picture 多数时候只是从输出队列取走一帧，耗时接近 0。
    // 如果只测 get_picture，得到的会是 0.0000 ms/f 这种无效数字。
    uint64_t lastFrameNanos = tStart;
    uint64_t demuxSinceLastFrame = 0;
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
            // 首帧包含解码器内部初始化的成本，单独用 first_frame_ms 记录。
            uint64_t frameNanos = nowNanos - lastFrameNanos;
            if (demuxSinceLastFrame < frameNanos) {
                frameNanos -= demuxSinceLastFrame;
            }
            lastFrameNanos = nowNanos;
            demuxSinceLastFrame = 0;
            if (!haveFirstFrame) {
                haveFirstFrame = 1;
                result->first_frame_ms = nanos_to_ms(frameNanos);
            }
            if (!openedOutput) {
                // 直到第一帧解出来才知道真实分辨率，输出模块必须在此刻初始化
                if (output_open(&out, "null", "/dev/null", &pic.p, fps) < 0) {
                    txav1d_picture_unref(&pic);
                    snprintf(failMsg, sizeof(failMsg), "初始化输出模块失败");
                    failed = 1;
                    break;
                }
                openedOutput = 1;
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

            // null muxer 的 write_picture 内部会调用 picture_unref，
            // 这里不能再 unref，否则是 double free。
            if (output_write(out, &pic) < 0) {
                snprintf(failMsg, sizeof(failMsg), "输出帧失败");
                failed = 1;
                break;
            }

            // ---- 定速节流 ----
            // 以「第 n 帧的绝对应产出时刻」为基准等待，而不是每帧固定 sleep
            // 一帧时长：解码本身有快有慢，逐帧固定等待会把偏差累加成漂移，
            // 跑几千帧后实际帧率会明显偏离目标。
            if (pacingNspf != 0) {
                const uint64_t deadline = pacingNspf * (uint64_t)decoded;
                const uint64_t elapsedAfter = bench_now_nanos() - tStart;
                if (elapsedAfter < deadline) {
                    const uint64_t waitStart = bench_now_nanos();
                    bench_sleep_nanos(deadline - elapsedAfter);
                    pacingWaitNanos += bench_now_nanos() - waitStart;
                }
                // 把节流等待排除出单帧耗时：lastFrameNanos 推到等待结束之后，
                // 下一帧的间隔里就不含这段空转。否则定速下的 ms/f 会恰好等于
                // 目标帧间隔，得到「解码速度和目标帧率完全一致」的假象。
                lastFrameNanos = bench_now_nanos();
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
            lastFrameNanos = nowNanos;
            demuxSinceLastFrame = 0;
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

            if (output_write(out, &pic) < 0) break;

            // 冲刷阶段的帧同样受定速约束：这些帧在 CLI 里也走同一个
            // synchronize()，若这里跳过，长尾帧会在最后瞬间倾泻出来，
            // 实际平均帧率高于目标值。
            if (pacingNspf != 0) {
                const uint64_t deadline = pacingNspf * (uint64_t)decoded;
                const uint64_t elapsedAfter = bench_now_nanos() - tStart;
                if (elapsedAfter < deadline) {
                    const uint64_t waitStart = bench_now_nanos();
                    bench_sleep_nanos(deadline - elapsedAfter);
                    pacingWaitNanos += bench_now_nanos() - waitStart;
                }
                lastFrameNanos = bench_now_nanos();
            }

            if (cfg->limit > 0 && decoded >= cfg->limit) break;
        }
    }

    const uint64_t totalNanos = bench_now_nanos() - tStart;

    if (data.sz > 0) txav1d_data_unref(&data);
    if (out) output_close(out);
    txav1d_close(&c);
    input_close(in);

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
