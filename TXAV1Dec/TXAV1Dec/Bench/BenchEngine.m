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
        // 版本号取自实际要跑的那个 dylib，不用手填：多版本轮测时若靠人工标注，
        // 极易出现「跑的是 1.4.3、标的是 1.4.2」，而这种错配从数据上看不出来。
        _decoderName = BenchDecoderVersionDescription();
    }
    return self;
}

@end

NSString *BenchDecoderVersionDescription(void) {
    BenchDecoder *decoder = [BenchDecoderLibrary preferredDecoder];
    if (!decoder) return @"txav1d（无可用版本）";
    return decoder.displayName;
}

#pragma mark - BenchRoundMetrics

@implementation BenchRoundMetrics

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
    for (BenchRoundMetrics *r in self.scoredRounds) sum += r.avgCPUPercent;
    return sum / (double)self.scoredRounds.count;
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

- (double)relativeSpeedupAgainstFPS:(double)baselineFPS {
    if (baselineFPS <= 0) return 0;
    return self.decodeFPS / baselineFPS;
}

- (double)avgFootprintMB {
    if (self.scoredRounds.count == 0) return 0;
    double sum = 0;
    for (BenchRoundMetrics *r in self.scoredRounds) sum += r.avgFootprintMB;
    return sum / (double)self.scoredRounds.count;
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
    for (BenchRoundMetrics *r in self.scoredRounds) sum += r.avgResidentMB;
    return sum / (double)self.scoredRounds.count;
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

- (double)speedRatio {
    BenchRoundMetrics *first = self.scoredRounds.firstObject;
    if (!first || first.sourceFPS <= 0) return 0;
    return self.decodeFPS / first.sourceFPS;
}

- (NSString *)textReportWithConfig:(BenchRunConfig *)config {
    BenchRoundMetrics *sample = self.scoredRounds.firstObject;
    NSMutableString *text = [NSMutableString string];

    [text appendString:@"===== txav1d 解码性能测试报告 =====\n"];
    [text appendFormat:@"设备      : %@ (%@)\n",
        [BenchSystemMetrics deviceName], [BenchSystemMetrics machineIdentifier]];
    [text appendFormat:@"CPU       : %@\n", [BenchSystemMetrics coreTopologyDescription]];
    [text appendFormat:@"热状态    : %@\n", [BenchSystemMetrics thermalStateDescription]];
    [text appendFormat:@"时间      : %@\n",
        [NSDateFormatter localizedStringFromDate:[NSDate date]
                                       dateStyle:NSDateFormatterMediumStyle
                                       timeStyle:NSDateFormatterMediumStyle]];

    if (sample) {
        [text appendFormat:@"码流      : %@\n", config.streamName ?: sample.resolutionDescription];
        [text appendFormat:@"分辨率    : %@\n", sample.resolutionDescription];
        [text appendFormat:@"源帧率    : %.3f fps\n", sample.sourceFPS];
        [text appendFormat:@"码流总帧  : %lu\n", (unsigned long)sample.totalFrames];
    }
    if (config) {
        [text appendFormat:@"解码器    : %@\n", config.decoderName.length > 0
            ? config.decoderName : @"（未标注）"];
        [text appendFormat:@"每轮帧数  : %@\n",
            config.limitFrames > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)config.limitFrames] : @"全部"];
        [text appendFormat:@"轮次      : %lu 正式 + %lu 预热\n",
            (unsigned long)config.rounds, (unsigned long)config.warmupRounds];
        [text appendFormat:@"线程数    : %@\n",
            config.threads > 0 ? [NSString stringWithFormat:@"%ld", (long)config.threads] : @"自动"];
        [text appendFormat:@"调度偏好  : %@ —— %@\n",
            [BenchSystemMetrics schedulePolicyName:config.schedulePolicy],
            [BenchSystemMetrics schedulePolicyNote:config.schedulePolicy]];
    }

    [text appendString:@"\n---------- 汇总（不含预热）----------\n"];
    [text appendFormat:@"解码帧率      : %.2f fps\n", self.decodeFPS];
    if (self.speedRatio > 0) {
        [text appendFormat:@"相对源帧率    : %.2fx\n", self.speedRatio];
    }
    [text appendFormat:@"平均单帧耗时  : %.4f ms/f\n", self.avgFrameMs];
    [text appendFormat:@"最快/最慢轮次 : %.4f / %.4f ms/f\n", self.minAvgFrameMs, self.maxAvgFrameMs];
    [text appendFormat:@"波动          : %.2f%%（轮间标准差 %.4f ms/f）← 越低越稳定\n",
        self.fluctuationPercent, self.stddevFrameMs];

    // 整机占比放首位：这是「这 App 吃了多少 CPU」的直觉答案，也是跨机型唯一可比的量。
    // 单核口径与核心数随后并出，需要和 Instruments 对照时用它们换算。
    const NSInteger cores = [BenchSystemMetrics processorCount];
    [text appendFormat:@"平均 CPU      : 整机 %.1f%% = %.0f%% 单核口径 = %.2f 核（本机 %ld 核）\n",
        self.cpuSharePercent, self.avgCPUPercent, self.avgCPUCores, (long)cores];
    [text appendFormat:@"峰值 CPU      : %.1f%% 单核口径 = %.2f 核\n",
        self.peakCPUPercent, self.peakCPUCores];

    // 内存：绝对值回答「会不会被杀」，增量回答「解码器自己占多少」
    BenchRoundMetrics *baselineSample = self.scoredRounds.firstObject;
    [text appendFormat:@"内存基线      : footprint %.1f MB（解码器初始化前）\n",
        baselineSample ? baselineSample.baselineFootprintMB : 0];
    [text appendFormat:@"内存 footprint: 峰 %.1f MB（含 App 常驻）\n", self.peakFootprintMB];
    [text appendFormat:@"解码器净开销  : %.1f MB  (%.1f KB/帧)  ← 横向对比看这个\n",
        self.footprintDeltaMB, self.footprintDeltaKBPerFrame];
    [text appendFormat:@"内存 resident : 峰 %.1f MB（交叉验证，噪声较大）\n", self.peakResidentMB];

    [text appendString:@"\n---------- 逐轮明细 ----------\n"];
    const NSInteger roundCores = [BenchSystemMetrics processorCount];
    for (BenchRoundMetrics *r in self.scoredRounds) {
        // 逐轮也用整机占比：明细和上方汇总必须是同一把尺子，
        // 否则同一份报告里两个百分数会互相矛盾。单核口径并列在括号里备查。
        [text appendFormat:@"#%lu  %.4f ms/f  P50 %.4f  P95 %.4f  "
                           @"CPU 整机 %.1f%%(%.1f%% 单核)  净内存 %.1fMB\n",
            (unsigned long)r.index, r.avgFrameMs, r.p50FrameMs, r.p95FrameMs,
            roundCores > 0 ? r.avgCPUPercent / (double)roundCores : 0,
            r.avgCPUPercent, r.footprintDeltaMB];
    }

    return text;
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
    const NSInteger threads = config.threads;
    const BenchSchedulePolicy schedulePolicy = config.schedulePolicy;
    BenchDecoder *decoder = config.decoder ?: [BenchDecoderLibrary preferredDecoder];
    NSString *streamPath = [config.streamPath copy];

    if (streamPath.length == 0) {
        self.running = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(@[], @"未选择码流文件");
        });
        return;
    }

    // 没有可用解码器时立即失败：继续跑只会得到一串空结果，
    // 让人误以为是性能问题而不是构建问题。
    if (!decoder.isUsable) {
        self.running = NO;
        NSString *reason = decoder.loadError ?: @"未找到可用的解码器动态库";
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(@[], reason);
        });
        return;
    }

    __weak typeof(self) weakSelf = self;

    dispatch_async(self.workQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

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
                                                       schedulePolicy:schedulePolicy
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
                         schedulePolicy:config.schedulePolicy
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
                               schedulePolicy:(BenchSchedulePolicy)schedulePolicy
                                      decoder:(BenchDecoder *)decoder {
    Txav1dBenchConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.input_file = path.UTF8String;
    cfg.limit = (unsigned)limitFrames;
    cfg.skip = (unsigned)skipFrames;
    cfg.threads = (int)threads;
    cfg.apply_grain = -1;   // 未显式指定时交由库默认
    cfg.wpp = -1;

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
    // 比拿一个空指针继续跑更容易定位问题。
    if (!decoder.isUsable) {
        os_unfair_lock_lock(&_sampleLock);
        self.samplingActive = NO;
        os_unfair_lock_unlock(&_sampleLock);
        return nil;
    }

    const int status = [decoder runBenchWithConfig:&cfg result:&result];

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

    metrics.peakCPUPercent = peakCPU;
    metrics.peakThreadCount = peakThreads;
    metrics.avgCPUPercent = cpuSamples > 0 ? cpuSum / (double)cpuSamples : 0;

    metrics.peakFootprintMB = peakFootprint;
    metrics.peakResidentMB = peakResident;
    // 记录空载基线（而非本轮基线），这样 footprintDeltaMB 在任何轮次都等于
    // 「相对 App 空载时的净增量」，跨轮、跨码流可直接比较。
    metrics.baselineFootprintMB = [BenchSystemMetrics idleBaselineFootprintMB];
    metrics.baselineResidentMB = baseline.residentMB;
    if (memorySamples > 0) {
        metrics.avgFootprintMB = footprintSum / (double)memorySamples;
        metrics.avgResidentMB = residentSum / (double)memorySamples;
    }

    // 逐帧数组由 dylib 内部 malloc 分配，必须由同一个库释放：
    // 换 App 侧释放或跨版本释放会破坏堆。
    [decoder freeBenchResult:&result];

    if (status != 0) return nil;
    return metrics;
}

#pragma mark - 采样

- (void)startSampling {
    if (self.sampleTimer) return;

    // 100ms 一次：足够捕捉解码过程中的负载起伏，又不会让采样本身产生明显开销
    const uint64_t intervalNanos = 100ULL * NSEC_PER_MSEC;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, intervalNanos),
                              intervalNanos,
                              10ULL * NSEC_PER_MSEC);

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
        self.currentRoundCPUSum += cpu;
        self.currentRoundCPUSamples += 1;
        if (cpu > self.currentRoundPeakCPU) self.currentRoundPeakCPU = cpu;

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
