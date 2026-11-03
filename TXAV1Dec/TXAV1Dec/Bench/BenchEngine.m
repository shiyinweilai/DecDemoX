//
//  BenchEngine.m
//  TXAV1Dec
//

#import "BenchEngine.h"
#import "BenchSystemMetrics.h"
#import "BenchDecoderLoader.h"

#include <math.h>
#include <os/lock.h>

#pragma mark - BenchStream

@implementation BenchStream

+ (instancetype)streamAtPath:(NSString *)path {
    BenchStream *stream = [[BenchStream alloc] init];
    stream.path = path;
    stream.name = path.lastPathComponent;

    NSNumber *size = nil;
    [[NSURL fileURLWithPath:path] getResourceValue:&size
                                            forKey:NSURLFileSizeKey
                                             error:nil];
    stream.sizeBytes = size.unsignedLongLongValue;
    return stream;
}

- (NSString *)sizeDescription {
    const double bytes = (double)self.sizeBytes;
    if (bytes >= 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
    }
    if (bytes >= 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    }
    if (bytes >= 1024.0) {
        return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%llu B", self.sizeBytes];
}

- (NSString *)menuDescription {
    return self.sizeDescription;
}

@end

#pragma mark - BenchRunConfig

@implementation BenchRunConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        // 默认值面向「快速拿到可信数字」：3 轮正式 + 1 轮预热，
        // 200 帧足以摊薄固定开销，又不至于让单次测试等太久。
        _limitFrames = 200;
        _rounds = 3;
        _warmupRounds = 1;
        _skipFrames = 0;
        _threads = 0;
        // 默认不定速：测速的目的是找出解码器的性能上限，
        // 默认就限帧只会让所有版本都收敛到目标帧率、彼此看不出差异。
        _pacingEnabled = NO;
        _pacingUseSourceFPS = YES;
        _pacingFPS = 0;
        // 默认不填 decoderName：早期实现为了给这个字段一个默认值，在 init 里
        // 调 BenchDecoderVersionDescription()，而它会顺着 preferredDecoder
        // 把所有版本的 dylib 全部 dlopen 一遍。构造一个配置对象本该是纯内存操作，
        // 不该有 I/O 和动态库加载副作用。名字由真正开跑时绑定解码器的人填
        // （见 ViewController buildConfigForStream:）。
        _decoderName = nil;
    }
    return self;
}

@end

NSString *BenchDecoderVersionDescription(void) {
    // 注意：本函数会加载动态库，只能在后台队列或确实需要展示版本名时调用，
    // 不能出现在启动路径或配置对象的初始化路径里。
    BenchDecoder *decoder = [BenchDecoderLibrary preferredDecoder];
    if (!decoder) return @"txav1d（无可用版本）";
    return decoder.displayName;
}

#pragma mark - BenchRoundMetrics

@implementation BenchRoundMetrics

- (double)actualFPS {
    // 用端到端总时长做分母，而不是 decodeMs：定速的等待虽然不计入解码耗时，
    // 却实实在在占据墙钟时间，正是它把实际产帧率压到目标值。
    if (self.totalMs <= 0 || self.decodedFrames == 0) return 0;
    return (double)self.decodedFrames * 1000.0 / self.totalMs;
}

- (double)decodeFPS {
    if (self.avgFrameMs <= 0) return 0;
    return 1000.0 / self.avgFrameMs;
}

- (double)sourceFPS {
    if (self.fpsDen == 0) return 0;
    return (double)self.fpsNum / (double)self.fpsDen;
}

- (double)speedRatio {
    const double source = self.sourceFPS;
    if (source <= 0) return 0;
    return self.decodeFPS / source;
}

- (NSString *)resolutionDescription {
    if (self.width <= 0 || self.height <= 0) return @"--";
    return [NSString stringWithFormat:@"%dx%d %dbit", self.width, self.height, self.bpc];
}

#pragma mark CPU 换算

- (double)avgCPUCores {
    return self.avgCPUPercent / 100.0;
}

- (double)peakCPUCores {
    return self.peakCPUPercent / 100.0;
}

- (double)cpuSharePercent {
    const NSInteger cores = [BenchSystemMetrics processorCount];
    if (cores <= 0) return 0;
    return self.avgCPUCores / (double)cores * 100.0;
}

- (double)cpuSecondsPerFrame {
    // 「每帧花掉多少核心·秒」把吞吐与占用合成单一指标：
    // 300 fps 吃 1 核 → 0.0033；150 fps 吃 1 核 → 0.0067。
    // 两组数字谁更高效，只凭 fps 和 CPU 分别看是比不出来的。
    const double fps = self.decodeFPS;
    if (fps <= 0) return 0;
    return self.avgCPUCores / fps;
}

#pragma mark 内存增量

- (double)footprintDeltaMB {
    // 基线可能因采样时机略高于峰值，下限归零，避免出现负的「开销」
    const double delta = self.peakFootprintMB - self.baselineFootprintMB;
    return delta > 0 ? delta : 0;
}

- (double)footprintDeltaKBPerFrame {
    if (self.decodedFrames == 0) return 0;
    return self.footprintDeltaMB * 1024.0 / (double)self.decodedFrames;
}

@end

#pragma mark - BenchSummary

@interface BenchSummary ()
@property (nonatomic, strong) NSArray<BenchRoundMetrics *> *scoredRounds;
@end

@implementation BenchSummary

+ (instancetype)summaryWithRounds:(NSArray<BenchRoundMetrics *> *)rounds {
    BenchSummary *summary = [[BenchSummary alloc] init];
    NSMutableArray *scored = [NSMutableArray array];
    for (BenchRoundMetrics *round in rounds) {
        // 预热轮的冷启动成本会显著拉高均值，绝不能混入统计
        if (!round.isWarmup) [scored addObject:round];
    }
    summary.scoredRounds = scored;
    return summary;
}

- (NSUInteger)scoredCount {
    return self.scoredRounds.count;
}

- (double)avgFrameMs {
    if (self.scoredRounds.count == 0) return 0;
    double sum = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) sum += r.avgFrameMs;
    return sum / (double)self.scoredRounds.count;
}

- (double)minAvgFrameMs {
    double best = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (best <= 0 || r.avgFrameMs < best) best = r.avgFrameMs;
    }
    return best;
}

- (double)maxAvgFrameMs {
    double worst = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.avgFrameMs > worst) worst = r.avgFrameMs;
    }
    return worst;
}

- (double)stddevFrameMs {
    const NSUInteger n = self.scoredRounds.count;
    if (n < 2) return 0;
    const double mean = self.avgFrameMs;
    double acc = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        const double d = r.avgFrameMs - mean;
        acc += d * d;
    }
    // 样本标准差（n-1）：轮次是抽样，用总体标准差会低估波动
    return sqrt(acc / (double)(n - 1));
}

- (double)fluctuationPercent {
    const double mean = self.avgFrameMs;
    if (mean <= 0) return 0;
    return self.stddevFrameMs / mean * 100.0;
}

- (double)avgCPUPercent {
    if (self.scoredRounds.count == 0) return 0;
    double sum = 0;
    NSUInteger used = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        // 只累加真正采到的轮次：把无采样的 0 混进均值会把整体水平拉低，
        // 这正是「多版本连测时 CPU 显示 0.00%」的直接来源。
        if (!r.cpuSampled) continue;
        sum += r.avgCPUPercent;
        used++;
    }
    if (used == 0) return 0;
    return sum / (double)used;
}

- (BOOL)avgCPUSampled {
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.cpuSampled) return YES;
    }
    return NO;
}

- (BOOL)peakCPUSampled {
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.peakCPUSampled) return YES;
    }
    return NO;
}

- (BOOL)memorySampled {
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.memorySampled) return YES;
    }
    return NO;
}

- (double)peakCPUPercent {
    double peak = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.peakCPUPercent > peak) peak = r.peakCPUPercent;
    }
    return peak;
}

- (double)avgCPUCores {
    return self.avgCPUPercent / 100.0;
}

- (double)peakCPUCores {
    return self.peakCPUPercent / 100.0;
}

- (double)cpuSharePercent {
    const NSInteger cores = [BenchSystemMetrics processorCount];
    if (cores <= 0) return 0;
    return self.avgCPUCores / (double)cores * 100.0;
}

- (double)cpuSecondsPerFrame {
    const double fps = self.decodeFPS;
    if (fps <= 0) return 0;
    return self.avgCPUCores / fps;
}

- (double)avgFootprintMB {
    if (self.scoredRounds.count == 0) return 0;
    double sum = 0;
    NSUInteger used = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (!r.memorySampled) continue;
        sum += r.avgFootprintMB;
        used++;
    }
    if (used == 0) return 0;
    return sum / (double)used;
}

- (double)peakFootprintMB {
    double peak = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.peakFootprintMB > peak) peak = r.peakFootprintMB;
    }
    return peak;
}

- (double)avgResidentMB {
    if (self.scoredRounds.count == 0) return 0;
    double sum = 0;
    NSUInteger used = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (!r.memorySampled) continue;
        sum += r.avgResidentMB;
        used++;
    }
    if (used == 0) return 0;
    return sum / (double)used;
}

- (double)peakResidentMB {
    double peak = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.peakResidentMB > peak) peak = r.peakResidentMB;
    }
    return peak;
}

- (double)footprintDeltaMB {
    // 取各轮增量的均值再取峰值没有意义：增量的峰值才是「最坏情况开销」，
    // 这里用所有轮次中出现过的最大增量，反映解码器在压力最大时的净占用。
    double peak = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.footprintDeltaMB > peak) peak = r.footprintDeltaMB;
    }
    return peak;
}

- (double)footprintDeltaKBPerFrame {
    NSUInteger frames = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) frames += r.decodedFrames;
    if (frames == 0) return 0;
    return self.footprintDeltaMB * 1024.0 / (double)frames;
}

- (double)decodeFPS {
    const double avg = self.avgFrameMs;
    if (avg <= 0) return 0;
    return 1000.0 / avg;
}

- (double)actualFPS {
    if (self.scoredRounds.count == 0) return 0;
    double sum = 0;
    NSUInteger used = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.actualFPS <= 0) continue;
        sum += r.actualFPS;
        used++;
    }
    if (used == 0) return 0;
    return sum / (double)used;
}

- (double)pacingDeviationPercent {
    const double target = [self pacingTargetFPS];
    if (target <= 0) return 0;
    const double actual = self.actualFPS;
    if (actual <= 0) return 0;
    // 以目标为基准：观众关心的是「离目标差多少」，而不是离实测差多少
    return (actual - target) / target * 100.0;
}

/**
 * 各计分轮的目标帧率，取第一个真正定速生效的轮次。
 *
 * 同一批次里不同码流按码流帧率定速时目标各不相同，此时该值只能代表
 * 其中一轮；展示层若要逐码流比较，应看轮次级 pacingFPS。
 */
- (double)pacingTargetFPS {
    for (BenchRoundMetrics *r in self.scoredRounds) {
        if (r.pacingApplied && r.pacingFPS > 0) return r.pacingFPS;
    }
    return 0;
}

- (double)peakDecodeFPS {
    // 与 minAvgFrameMs 严格互为倒数：汇总表把这两列并排展示，
    // 若各自取不同的轮次，读者会看到「fps 涨了但 ms 也涨了」这种不可能的组合。
    const double best = self.minAvgFrameMs;
    if (best <= 0) return 0;
    return 1000.0 / best;
}

- (double)speedRatio {
    BenchRoundMetrics *first = self.scoredRounds.firstObject;
    if (!first || first.sourceFPS <= 0) return 0;
    return self.decodeFPS / first.sourceFPS;
}

@end

#pragma mark - BenchEngine

@interface BenchEngine ()

@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) NSUInteger roundsDone;
@property (nonatomic, assign) NSUInteger roundsPlanned;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) dispatch_source_t sampleTimer;
@property (nonatomic, strong) BenchSystemMetrics *metrics;

// 采样累积值。定时器跑在主线程，解码跑在工作队列，两者并发访问这组字段，
// 必须加锁，否则会出现读到半更新的中间值。
@property (nonatomic, assign) os_unfair_lock sampleLock;
@property (nonatomic, assign) BOOL samplingActive;
@property (nonatomic, assign) double currentRoundPeakCPU;
@property (nonatomic, assign) double currentRoundCPUSum;
@property (nonatomic, assign) NSUInteger currentRoundCPUSamples;

@property (nonatomic, assign) double currentRoundPeakFootprint;
@property (nonatomic, assign) double currentRoundFootprintSum;
@property (nonatomic, assign) double currentRoundPeakResident;
@property (nonatomic, assign) double currentRoundResidentSum;
@property (nonatomic, assign) NSUInteger currentRoundMemorySamples;

@property (nonatomic, assign) NSInteger currentRoundPeakThreads;

@end

@implementation BenchEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        // 串行队列：txav1d 内部使用大量全局状态，并发跑会互相破坏；
        // 同时放在非主线程，避免解码期间界面卡死触发系统手势超时。
        _workQueue = dispatch_queue_create("dev.rbyang.txav1d.bench",
                                          DISPATCH_QUEUE_SERIAL);
        _metrics = [[BenchSystemMetrics alloc] init];
        _sampleLock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (BOOL)isRunning { return self.running; }
- (NSUInteger)completedRounds { return self.roundsDone; }
- (NSUInteger)plannedRounds { return self.roundsPlanned; }

- (void)cancel {
    self.cancelled = YES;
}

- (void)startWithConfig:(BenchRunConfig *)config
               onProgress:(void (^)(NSString *, double))onProgress
             onCompletion:(void (^)(NSArray<BenchRoundMetrics *> *, NSString *))onCompletion {
    if (self.running) return;

    self.running = YES;
    self.cancelled = NO;
    self.roundsDone = 0;
    self.roundsPlanned = config.warmupRounds + config.rounds;

    // 配置在进入后台队列前全部固化为值类型：后台线程不能碰 Objective-C 对象
    // 的可变状态，否则会有数据竞争。
    const NSUInteger warmupRounds = config.warmupRounds;
    const BOOL hasWarmup = warmupRounds > 0;
    const NSUInteger totalRounds = self.roundsPlanned;
    const NSUInteger limitFrames = config.limitFrames;
    const NSUInteger skipFrames = config.skipFrames;
    const NSUInteger threads = config.threads;
    const BOOL playerCoreThreading = config.playerCoreThreading;
    const BenchSchedulePolicy schedulePolicy = config.schedulePolicy;
    const BOOL pacingEnabled = config.pacingEnabled;
    const BOOL pacingUseSourceFPS = config.pacingUseSourceFPS;
    const double pacingFPS = config.pacingFPS;
    // 不再在这里兜底调 preferredDecoder：那是主线程上的隐式 dlopen。
    // 解码器必须由调用方从勾选结果里显式传入，缺失即视为配置错误。
    BenchDecoder *decoder = config.decoder;
    NSString *streamPath = [config.streamPath copy];

    if (streamPath.length == 0) {
        self.running = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(@[], @"未选择码流文件");
        });
        return;
    }

    if (!decoder) {
        self.running = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(@[], @"未选择解码器版本");
        });
        return;
    }

    __weak typeof(self) weakSelf = self;

    dispatch_async(self.workQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        // dlopen 放在后台队列：一个版本约几十毫秒，且 RTLD_NOW 会立即绑定
        // 全部符号。放在主线程会让「点开始」到界面响应之间出现可感知的停顿。
        if (![decoder loadIfNeeded]) {
            self.running = NO;
            NSString *reason = decoder.loadError
                ?: [NSString stringWithFormat:@"解码器 %@ 加载失败", decoder.version];
            dispatch_async(dispatch_get_main_queue(), ^{
                onCompletion(@[], reason);
            });
            return;
        }

        // 此刻 dlopen 已完成，displayName 才包含「库自报版本与目录名是否一致」
        // 这项交叉校验。从这里到 onCompletion 之间有 dispatch 到主队列的屏障，
        // 报告在主线程读取 config 时一定看到已写入的值。
        if (config.decoderName.length == 0) {
            config.decoderName = decoder.displayName;
        }

        NSMutableArray<BenchRoundMetrics *> *rounds = [NSMutableArray array];
        NSString *fatalError = nil;

        // 采样器只在正式阶段运行，避免预热阶段把冷启动的 CPU 峰值算进去
        [self startSampling];

        for (NSUInteger i = 0; i < totalRounds; i++) {
            if (self.cancelled) break;

            // 前 warmupRounds 轮是预热
            const BOOL isWarmup = hasWarmup && i < warmupRounds;

            if (onProgress) {
                NSString *stage = [NSString stringWithFormat:@"%@ 第 %lu/%lu 轮",
                                   isWarmup ? @"预热" : @"测量",
                                   (unsigned long)(i + 1), (unsigned long)totalRounds];
                const double fraction = (double)i / (double)totalRounds;
                dispatch_async(dispatch_get_main_queue(), ^{
                    onProgress(stage, fraction);
                });
            }

            BenchRoundMetrics *metrics = [self runSingleRoundWithPath:streamPath
                                                                limit:limitFrames
                                                                 skip:skipFrames
                                                              threads:threads
                                                  playerCoreThreading:playerCoreThreading
                                                       schedulePolicy:schedulePolicy
                                                               pacing:pacingEnabled
                                                    pacingUseSourceFPS:pacingUseSourceFPS
                                                            pacingFPS:pacingFPS
                                                              decoder:decoder];
            if (!metrics) {
                fatalError = @"解码失败，请检查码流是否有效";
                break;
            }
            metrics.index = i + 1;
            metrics.isWarmup = isWarmup;
            [rounds addObject:metrics];

            self.roundsDone = i + 1;

            if (onProgress) {
                const double fraction = (double)(i + 1) / (double)totalRounds;
                dispatch_async(dispatch_get_main_queue(), ^{
                    onProgress(@"完成", fraction);
                });
            }
        }

        [self stopSampling];
        self.running = NO;

        NSArray *resultRounds = [rounds copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(resultRounds, fatalError);
        });
    });
}

/**
 * 跑一轮解码并采集该轮的 CPU/内存曲线。
 *
 * 注意：txav1d_bench 是阻塞调用，整轮跑完才返回，所以这里的采样
 * 是通过外部定时器并行进行的，而不是在解码循环内部埋点。
 */
- (BenchRoundMetrics *)runSingleRoundWithPath:(NSString *)path
                                       config:(BenchRunConfig *)config {
    return [self runSingleRoundWithPath:path
                                  limit:config.limitFrames
                                   skip:config.skipFrames
                                threads:config.threads
                    playerCoreThreading:config.playerCoreThreading
                         schedulePolicy:config.schedulePolicy
                                 pacing:config.pacingEnabled
                      pacingUseSourceFPS:config.pacingUseSourceFPS
                              pacingFPS:config.pacingFPS
                                decoder:config.decoder];
}

/**
 * 真正执行一轮测试。
 *
 * 参数全为值类型，避免在后台队列上读取 BenchRunConfig 对象的可变属性——
 * 该对象在主线程创建，跨线程读取虽对不可变快照安全，但显式传值更清晰。
 */
- (BenchRoundMetrics *)runSingleRoundWithPath:(NSString *)path
                                        limit:(NSUInteger)limitFrames
                                         skip:(NSUInteger)skipFrames
                                      threads:(NSInteger)threads
                          playerCoreThreading:(BOOL)playerCoreThreading
                               schedulePolicy:(BenchSchedulePolicy)schedulePolicy
                                       pacing:(BOOL)pacingEnabled
                            pacingUseSourceFPS:(BOOL)pacingUseSourceFPS
                                    pacingFPS:(double)pacingFPS
                                      decoder:(BenchDecoder *)decoder {
    Txav1dBenchConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.input_file = path.UTF8String;
    cfg.limit = (unsigned)limitFrames;
    cfg.skip = (unsigned)skipFrames;
    cfg.threads = (int)threads;
    cfg.thread_policy = playerCoreThreading ? TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE
                                            : TXAV1D_BENCH_THREAD_POLICY_CAPABILITY;
    cfg.apply_grain = -1;   // 未显式指定时交由库默认
    cfg.wpp = -1;
    // 定速是「解码循环节流」，不是解码器参数，所以它走 bench 配置而不是
    // settings。关闭时填 OFF 而不是依赖 memset 的 0：靠 0 值巧合语义
    // 太脆弱，将来若新增「按帧数」之类模式，0 的含义就会变。
    if (pacingEnabled) {
        cfg.pacing = pacingUseSourceFPS ? TXAV1D_BENCH_PACING_SOURCE
                                        : TXAV1D_BENCH_PACING_CUSTOM;
        cfg.pacing_fps = pacingUseSourceFPS ? 0 : pacingFPS;
    } else {
        cfg.pacing = TXAV1D_BENCH_PACING_OFF;
        cfg.pacing_fps = 0;
    }

    Txav1dBenchResult result;
    memset(&result, 0, sizeof(result));

    // 采样基线与累积值必须在同一把锁内重置：定时器回调在主线程，
    // 这里在工作队列，两者会同时访问 metrics 的内部状态。
    os_unfair_lock_lock(&_sampleLock);
    [self.metrics reset];
    self.currentRoundPeakCPU = 0;
    self.currentRoundCPUSum = 0;
    self.currentRoundCPUSamples = 0;
    self.currentRoundPeakFootprint = 0;
    self.currentRoundFootprintSum = 0;
    self.currentRoundPeakResident = 0;
    self.currentRoundResidentSum = 0;
    self.currentRoundMemorySamples = 0;
    self.currentRoundPeakThreads = 0;
    self.samplingActive = YES;
    os_unfair_lock_unlock(&_sampleLock);

    // 基线必须在解码器初始化之前取：av1d 会在初始化时分配线程池、
    // 帧缓冲等长期驻留结构，若放在之后取，这部分开销会被算进增量里。
    BenchMemorySnapshot *baseline = [BenchSystemMetrics currentMemorySnapshot];

    // 但「本轮开始前」的内存从第二轮起已包含上一轮的解码占用（帧池不归还），
    // 用它算增量会得到恒为 0 的假结果。所以净内存统一减去全局空载基线，
    // 该基线在进程首次解码前就已固化。
    [BenchSystemMetrics captureIdleBaselineIfNeeded];

    // 调度偏好必须在真正执行解码的线程上设置：txav1d 内部用 pthread_create
    // 派生工作线程，子线程继承创建时刻的 QoS，所以在这里设置能影响它们。
    [BenchSystemMetrics applySchedulePolicyToCurrentThread:schedulePolicy];

    // 解码器缺失说明构建产物里没有任何可用版本；直接失败并给出原因，
    // 比拿一个空指针继续跑更容易定位问题。这里再调一次 loadIfNeeded 是幂等的，
    // 正常情况下在批次开始前已经加载过，只是让本函数单独被调用时也能自洽。
    if (![decoder loadIfNeeded]) {
        os_unfair_lock_lock(&_sampleLock);
        self.samplingActive = NO;
        os_unfair_lock_unlock(&_sampleLock);
        return nil;
    }

    // 区间起点紧贴解码调用：只要中间夹了别的准备工作，CPU 平均值就会被稀释。
    [self.metrics beginCPUInterval];
    const int status = [decoder runBenchWithConfig:&cfg result:&result];

    // 区间 CPU 必须在解码返回后立刻取：区间越贴近真实解码段，
    // 混入的收尾开销越少。这里取到的是「整轮平均占用」，与轮次长短无关。
    const double intervalCPU = [self.metrics cpuPercentSinceIntervalBegin];

    // 定时器可能一次都没触发（单轮短于采样间隔），此时峰值与内存样本均为空。
    // 解码器返回后会保留帧池、线程栈等结构，轮末快照仍是这些开销的有效下界，
    // 因此用它兜底；否则会退化成「内存 0 MB」，比不显示更误导。
    BenchMemorySnapshot *endSnapshot = [BenchSystemMetrics currentMemorySnapshot];

    os_unfair_lock_lock(&_sampleLock);
    self.samplingActive = NO;
    const double peakCPU = self.currentRoundPeakCPU;
    const double cpuSum = self.currentRoundCPUSum;
    const NSUInteger cpuSamples = self.currentRoundCPUSamples;
    const double peakFootprint = self.currentRoundPeakFootprint;
    const double footprintSum = self.currentRoundFootprintSum;
    const double peakResident = self.currentRoundPeakResident;
    const double residentSum = self.currentRoundResidentSum;
    const NSUInteger memorySamples = self.currentRoundMemorySamples;
    const NSInteger peakThreads = self.currentRoundPeakThreads;
    os_unfair_lock_unlock(&_sampleLock);

    // 内存：定时器采到就用它的峰值与均值（能看到解码中段的高点）；
    // 没采到就退回轮末快照，并显式标记为「下界」而非「平均值」。
    BOOL memorySampled = (memorySamples > 0);
    double roundPeakFootprint = peakFootprint;
    double roundPeakResident = peakResident;
    double roundAvgFootprint = 0;
    double roundAvgResident = 0;
    if (memorySampled) {
        roundAvgFootprint = footprintSum / (double)memorySamples;
        roundAvgResident = residentSum / (double)memorySamples;
    } else if (endSnapshot.valid) {
        // 单一样本：峰值即该样本，均值也取它，避免出现 0 值参与后续均值。
        roundPeakFootprint = endSnapshot.footprintMB;
        roundPeakResident = endSnapshot.residentMB;
        roundAvgFootprint = endSnapshot.footprintMB;
        roundAvgResident = endSnapshot.residentMB;
        memorySampled = YES;
    }

    BenchRoundMetrics *metrics = [[BenchRoundMetrics alloc] init];
    metrics.decodedFrames = result.decoded_frames;
    metrics.totalFrames = result.total_frames;
    metrics.width = result.width;
    metrics.height = result.height;
    metrics.bpc = result.bpc;
    metrics.fpsNum = result.fps_num;
    metrics.fpsDen = result.fps_den;
    metrics.totalMs = result.total_ms;
    metrics.demuxMs = result.demux_ms;
    metrics.decodeMs = result.decode_ms;
    metrics.firstFrameMs = result.first_frame_ms;
    metrics.avgFrameMs = result.avg_frame_ms;
    metrics.minFrameMs = result.min_frame_ms;
    metrics.maxFrameMs = result.max_frame_ms;
    metrics.p50FrameMs = result.p50_frame_ms;
    metrics.p95FrameMs = result.p95_frame_ms;
    // 定速状态取库回填值：配置说「按码流帧率」但码流头缺帧率时库会退回
    // 不定速，此时若照抄配置，下游会误以为这组数据是在定速下跑的。
    metrics.pacingApplied = (result.pacing != TXAV1D_BENCH_PACING_OFF)
        && (result.pacing_fps > 0);
    metrics.pacingFPS = result.pacing_fps;
    metrics.pacingWaitMs = result.pacing_wait_ms;
    metrics.bufferCapacity = result.buffer_capacity;
    metrics.bufferFullEvents = result.buffer_full_events;
    metrics.bufferStarveEvents = result.buffer_starve_events;
    metrics.appliedPlayerCoreThreading =
        (result.applied_thread_policy == TXAV1D_BENCH_THREAD_POLICY_PLAYERCORE);
    metrics.appliedNThreads = result.applied_n_threads;
    metrics.appliedThreadOverride = result.applied_thread_override;
    metrics.appliedFrameDelay = result.applied_frame_delay;

    // 平均值改用整轮同步差分：它覆盖解码全程、与轮次长短无关。
    // 区间无效（时钟跳变等）时退回定时器均值；两者都没有就标记为「无采样」。
    metrics.cpuSampled = (intervalCPU >= 0) || (cpuSamples > 0);
    metrics.cpuIntervalWallMs = [self.metrics lastIntervalWallMilliseconds];
    metrics.cpuIntervalCPUMs = [self.metrics lastIntervalCPUMilliseconds];
    if (intervalCPU >= 0) {
        metrics.avgCPUPercent = intervalCPU;
    } else if (cpuSamples > 0) {
        metrics.avgCPUPercent = cpuSum / (double)cpuSamples;
    } else {
        metrics.avgCPUPercent = 0;
    }

    // 峰值只来自定时器：区间差分只能得到平均值，看不到区间内部的起伏。
    // 定时器一次都没触发时峰值未知，用平均值兜底并标记来源，
    // 避免把它当成「真实峰值」参与跨版本比较。
    if (cpuSamples > 0) {
        metrics.peakCPUPercent = peakCPU;
        metrics.peakCPUSampled = YES;
    } else {
        metrics.peakCPUPercent = metrics.avgCPUPercent;
        metrics.peakCPUSampled = NO;
    }
    metrics.peakThreadCount = peakThreads;

    metrics.memorySampled = memorySampled;
    metrics.peakFootprintMB = roundPeakFootprint;
    metrics.peakResidentMB = roundPeakResident;
    // 记录空载基线（而非本轮基线），这样 footprintDeltaMB 在任何轮次都等于
    // 「相对 App 空载时的净增量」，跨轮、跨码流可直接比较。
    metrics.baselineFootprintMB = [BenchSystemMetrics idleBaselineFootprintMB];
    metrics.baselineResidentMB = baseline.residentMB;
    metrics.avgFootprintMB = roundAvgFootprint;
    metrics.avgResidentMB = roundAvgResident;

    // 逐帧数组由 dylib 内部 malloc 分配，必须由同一个库释放：
    // 换 App 侧释放或跨版本释放会破坏堆。
    [decoder freeBenchResult:&result];

    if (status != 0) return nil;
    return metrics;
}

#pragma mark - 采样

- (void)startSampling {
    if (self.sampleTimer) return;

    // 采样间隔要明显小于最短单轮时长，否则一整轮可能一次都不触发，
    // 峰值与内存曲线直接丢失（实测 30 帧单轮约 33ms，100ms 间隔命中率几乎为 0）。
    // 25ms 在 iPhone 上开销可忽略（每次采样仅两次 task_info 系统调用），
    // 又能保证 30ms 的短轮至少命中一次。
    const uint64_t intervalNanos = 25ULL * NSEC_PER_MSEC;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     dispatch_get_main_queue());
    // leeway 给到间隔的一半：系统可以合并唤醒省电，又不会因此错过整轮。
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, intervalNanos),
                              intervalNanos,
                              12ULL * NSEC_PER_MSEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        os_unfair_lock_lock(&self->_sampleLock);
        const BOOL active = self.samplingActive;
        os_unfair_lock_unlock(&self->_sampleLock);
        if (!active) return;

        const double cpu = [self.metrics sampleCPUPercentOfCore];
        BenchMemorySnapshot *memory = [BenchSystemMetrics currentMemorySnapshot];
        const NSInteger threads = [BenchSystemMetrics currentThreadCount];

        os_unfair_lock_lock(&self->_sampleLock);
        // 负值代表本次采样无效（超出物理上限或计数器倒退），
        // 直接跳过：0 会被当成「几乎不占 CPU」拉低均值。
        if (cpu >= 0) {
            self.currentRoundCPUSum += cpu;
            self.currentRoundCPUSamples += 1;
            if (cpu > self.currentRoundPeakCPU) self.currentRoundPeakCPU = cpu;
        }

        // task_info 偶发失败时各字段为 0，若照常累加会把均值严重拉低，
        // 因此只在读取成功时计入本次内存采样。
        if (memory.valid) {
            self.currentRoundFootprintSum += memory.footprintMB;
            self.currentRoundResidentSum += memory.residentMB;
            self.currentRoundMemorySamples += 1;
            if (memory.footprintMB > self.currentRoundPeakFootprint) {
                self.currentRoundPeakFootprint = memory.footprintMB;
            }
            if (memory.residentMB > self.currentRoundPeakResident) {
                self.currentRoundPeakResident = memory.residentMB;
            }
        }
        if (threads > self.currentRoundPeakThreads) self.currentRoundPeakThreads = threads;
        os_unfair_lock_unlock(&self->_sampleLock);
    });

    self.sampleTimer = timer;
    dispatch_resume(timer);
}

- (void)stopSampling {
    if (!self.sampleTimer) return;
    dispatch_source_cancel(self.sampleTimer);
    self.sampleTimer = nil;
}

@end

#pragma mark - BenchStreamLibrary

@implementation BenchStreamLibrary

/// 视为码流的扩展名集合
+ (NSSet<NSString *> *)streamExtensions {
    static NSSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithObjects:@"stream", @"ivf", @"obu", @"av1", @"av1b", nil];
    });
    return set;
}

+ (NSString *)streamsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *docs = paths.firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"Streams"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
    }
    return dir;
}

+ (NSArray<BenchStream *> *)availableStreams {
    NSString *dir = [self streamsDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:nil];
    NSSet *exts = [self streamExtensions];

    NSMutableArray *streams = [NSMutableArray array];
    for (NSString *name in names) {
        // .DS_Store 之类的隐藏文件直接跳过
        if ([name hasPrefix:@"."]) continue;
        NSString *ext = name.pathExtension.lowercaseString;
        if (ext.length > 0 && ![exts containsObject:ext]) continue;

        NSString *full = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;

        [streams addObject:[BenchStream streamAtPath:full]];
    }

    [streams sortUsingComparator:^NSComparisonResult(BenchStream *a, BenchStream *b) {
        return [a.name caseInsensitiveCompare:b.name];
    }];
    return streams;
}

+ (NSUInteger)syncBundledStreams {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *targetDir = [self streamsDirectory];
    NSSet *exts = [self streamExtensions];
    NSUInteger copied = 0;

    NSMutableArray<NSString *> *sources = [NSMutableArray array];

    // 优先按「文件夹引用」方式查找内置目录，这样能完整保留 streams 目录结构
    NSString *bundledDir = [bundle.resourcePath stringByAppendingPathComponent:@"streams"];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:bundledDir isDirectory:&isDir] && isDir) {
        NSArray *children = [fm contentsOfDirectoryAtPath:bundledDir error:nil];
        for (NSString *child in children) {
            if ([child hasPrefix:@"."]) continue;
            [sources addObject:[bundledDir stringByAppendingPathComponent:child]];
        }
    }

    // 兜底：资源被扁平化打包时，直接按扩展名从包根目录扫一遍
    if (sources.count == 0) {
        NSArray *rootChildren = [fm contentsOfDirectoryAtPath:bundle.resourcePath error:nil];
        for (NSString *child in rootChildren) {
            NSString *ext = child.pathExtension.lowercaseString;
            if (ext.length > 0 && [exts containsObject:ext]) {
                [sources addObject:[bundle.resourcePath stringByAppendingPathComponent:child]];
            }
        }
    }

    for (NSString *src in sources) {
        NSString *name = src.lastPathComponent;
        NSString *dst = [targetDir stringByAppendingPathComponent:name];

        NSDictionary *srcAttr = [fm attributesOfItemAtPath:src error:nil];
        NSDictionary *dstAttr = [fm attributesOfItemAtPath:dst error:nil];

        const unsigned long long srcSize = [srcAttr[NSFileSize] unsignedLongLongValue];
        const unsigned long long dstSize = [dstAttr[NSFileSize] unsignedLongLongValue];

        // 大小一致就认为已同步。完整校验需读全文件，20MB 的码流每次启动都算一遍不划算。
        if (dstAttr && srcSize == dstSize) continue;

        [fm removeItemAtPath:dst error:nil];
        NSError *copyError = nil;
        if ([fm copyItemAtPath:src toPath:dst error:&copyError]) {
            copied++;
        } else {
            NSLog(@"[Bench] 同步内置码流失败 %@: %@", name, copyError.localizedDescription);
        }
    }

    return copied;
}

+ (BOOL)removeStream:(BenchStream *)stream error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:stream.path error:error];
}

@end
