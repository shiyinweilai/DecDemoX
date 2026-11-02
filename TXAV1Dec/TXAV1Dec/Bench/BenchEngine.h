//
//  BenchEngine.h
//  TXAV1Dec
//
//  测速引擎：负责组织多轮解码测试、实时采样系统指标、汇总统计结果。
//

#import <Foundation/Foundation.h>

#import "BenchSystemMetrics.h"

@class BenchDecoder;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 码流

/** 描述一个可测试的码流文件 */
@interface BenchStream : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) unsigned long long sizeBytes;

/** 人类可读的大小，例如 "19.5 MB" */
@property (nonatomic, readonly) NSString *sizeDescription;

/** 用于下拉菜单的摘要，例如 "19.5 MB" */
@property (nonatomic, readonly) NSString *menuDescription;

+ (instancetype)streamAtPath:(NSString *)path;

@end

#pragma mark - 配置

/** 一轮测试的配置 */
@interface BenchRunConfig : NSObject

@property (nonatomic, copy, nullable) NSString *streamPath;
@property (nonatomic, copy, nullable) NSString *streamName;

/** 每轮最多解码多少帧，0 表示整个码流 */
@property (nonatomic, assign) NSUInteger limitFrames;

/** 正式计分轮次 */
@property (nonatomic, assign) NSUInteger rounds;

/** 预热轮次，结果不计入统计，用于排除冷启动与首次加载文件的影响 */
@property (nonatomic, assign) NSUInteger warmupRounds;

/** 每轮开始时跳过的包数，用于聚焦稳定状态 */
@property (nonatomic, assign) NSUInteger skipFrames;

/** 解码线程数，0 表示由库自动决定 */
@property (nonatomic, assign) NSInteger threads;

/** 线程调度偏好，见 BenchSchedulePolicy 里关于 iOS 限制的说明 */
@property (nonatomic, assign) BenchSchedulePolicy schedulePolicy;

/**
 * 被测解码器标识，例如 "av1d 1.4.1" / "新解码器 v2"。
 *
 * 横向对比的本质是「同一码流、同一参数，只换解码器」，所以结果必须带上
 * 解码器名字，否则过几天就看不出这组数字属于哪个版本。
 */
@property (nonatomic, copy, nullable) NSString *decoderName;

/**
 * 本次测试使用哪个解码器版本（动态库实例）。
 *
 * 为空时退回 preferredDecoder（最新的可用版本）。多版本轮测时为每个组合
 * 显式指定，保证结果与真实执行的库严格对应。
 */
@property (nonatomic, strong, nullable) BenchDecoder *decoder;

@end

/**
 * 当前链接进来的解码器版本描述，形如 "txav1d 1.4.3"。
 *
 * 取自 txav1d_version() 而非编译期宏，反映的是实际参与链接的库版本。
 * 多版本切换时用它标注结果，避免手填导致的版本错标。
 */
FOUNDATION_EXPORT NSString *BenchDecoderVersionDescription(void);

#pragma mark - 单轮结果

/** 一轮测试的全部指标 */
@interface BenchRoundMetrics : NSObject

/** 轮次序号（从 1 开始，包含预热轮） */
@property (nonatomic, assign) NSUInteger index;
/** 是否为预热轮，预热轮不计入汇总统计 */
@property (nonatomic, assign) BOOL isWarmup;

@property (nonatomic, assign) NSUInteger decodedFrames;
@property (nonatomic, assign) NSUInteger totalFrames;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, assign) int bpc;
@property (nonatomic, assign) unsigned fpsNum;
@property (nonatomic, assign) unsigned fpsDen;

/** 毫秒 */
@property (nonatomic, assign) double totalMs;
@property (nonatomic, assign) double demuxMs;
@property (nonatomic, assign) double decodeMs;
@property (nonatomic, assign) double firstFrameMs;
@property (nonatomic, assign) double avgFrameMs;
@property (nonatomic, assign) double minFrameMs;
@property (nonatomic, assign) double maxFrameMs;
@property (nonatomic, assign) double p50FrameMs;
@property (nonatomic, assign) double p95FrameMs;

/** 解码帧率 = 1000 / avgFrameMs */
@property (nonatomic, readonly) double decodeFPS;
/** 相对码流原始帧率的倍速，如 3.25 表示 3.25 倍速 */
@property (nonatomic, readonly) double speedRatio;
/** 码流原始帧率，fps 缺失时返回 0 */
@property (nonatomic, readonly) double sourceFPS;
/** 分辨率描述，如 "1920x1080 10bit" */
@property (nonatomic, readonly) NSString *resolutionDescription;

#pragma mark CPU

/**
 * CPU 占用，单核百分比口径：100 = 占满 1 核，600 = 6 核全满。
 *
 * 这是主指标。之所以不直接存「核心数」，是因为百分比是线性可加的原始量，
 * 进均值、峰值、比值都无需还原；核心数、整机占比都由它换算，见下方只读属性。
 */
@property (nonatomic, assign) double avgCPUPercent;
@property (nonatomic, assign) double peakCPUPercent;

/** 核心等价占用 = avgCPUPercent / 100，如 2.35 表示平均占满 2.35 个核 */
@property (nonatomic, readonly) double avgCPUCores;
@property (nonatomic, readonly) double peakCPUCores;

/** 占设备总算力的比例 = 核心数 / 逻辑核数 * 100% */
@property (nonatomic, readonly) double cpuSharePercent;

/**
 * 每秒解码消耗的核心·秒数 = avgCPUCores / decodeFPS。
 *
 * 这是横向对比解码器最关键的指标：它把「快」和「省」合成一个数。
 * 解码器 A 跑 60 fps 吃 2 核、B 跑 50 fps 吃 1 核，谁的 fps 更高一目了然，
 * 但谁更高效只能靠这个值判断——B 每帧只要 0.020 核·秒，A 要 0.033。
 * 数值越低越好，与分辨率、帧率无关，可直接跨码流比较。
 */
@property (nonatomic, readonly) double cpuSecondsPerFrame;

#pragma mark 内存

/**
 * 内存主指标用 footprint，并区分绝对值与增量。
 *
 * 绝对值里混着 UIKit、字体、运行时这几十 MB 的常驻部分，两个解码器相差不多时
 * 根本看不出区别。真正能体现解码器自身开销的是「峰值 - 基线」这个增量：
 *
 * - footprintMB：峰值 footprint 绝对值，反映「会不会 memory warning」
 * - footprintDeltaMB：解码器净开销，横向对比看这个
 */
@property (nonatomic, assign) double baselineFootprintMB;
@property (nonatomic, assign) double peakFootprintMB;
@property (nonatomic, assign) double avgFootprintMB;

/** 解码器自身内存开销 = peakFootprintMB - baselineFootprintMB，不小于 0 */
@property (nonatomic, readonly) double footprintDeltaMB;

/** resident 仅作交叉验证：受 page cache 回收时机影响大，噪声高于信号 */
@property (nonatomic, assign) double baselineResidentMB;
@property (nonatomic, assign) double peakResidentMB;
@property (nonatomic, assign) double avgResidentMB;

/** 每解码一帧的净内存成本，单位 KB。小码流下可忽略，大分辨率下能看出实现差异。 */
@property (nonatomic, readonly) double footprintDeltaKBPerFrame;

@property (nonatomic, assign) NSInteger peakThreadCount;

@end

#pragma mark - 汇总

/** 多轮结果的统计汇总，只统计非预热轮 */
@interface BenchSummary : NSObject

@property (nonatomic, readonly) NSArray<BenchRoundMetrics *> *scoredRounds;
@property (nonatomic, readonly) NSUInteger scoredCount;

@property (nonatomic, readonly) double avgFrameMs;      ///< 各轮平均单帧耗时的均值
@property (nonatomic, readonly) double minAvgFrameMs;   ///< 最好一轮
@property (nonatomic, readonly) double maxAvgFrameMs;   ///< 最差一轮
@property (nonatomic, readonly) double stddevFrameMs;   ///< 轮间标准差，反映稳定性
@property (nonatomic, readonly) double fluctuationPercent; ///< 标准差 / 均值
@property (nonatomic, readonly) double decodeFPS;
@property (nonatomic, readonly) double speedRatio;

@property (nonatomic, readonly) double avgCPUPercent;   ///< 单核百分比
@property (nonatomic, readonly) double peakCPUPercent;
@property (nonatomic, readonly) double avgCPUCores;     ///< 核心等价
@property (nonatomic, readonly) double peakCPUCores;
@property (nonatomic, readonly) double cpuSharePercent;  ///< 占设备总算力的比例
@property (nonatomic, readonly) double cpuSecondsPerFrame; ///< 每帧核心·秒，越低越高效

@property (nonatomic, readonly) double avgFootprintMB;
@property (nonatomic, readonly) double peakFootprintMB;
@property (nonatomic, readonly) double avgResidentMB;
@property (nonatomic, readonly) double peakResidentMB;

/** 解码器净内存开销（峰值 - 基线），横向对比主要看这个 */
@property (nonatomic, readonly) double footprintDeltaMB;
@property (nonatomic, readonly) double footprintDeltaKBPerFrame;

/**
 * 相对基准解码器的提升倍数（fps 之比）。
 *
 * 只在一批测试里指定了基准后才有意义，由调用方传入基准 fps。
 * 返回 0 表示无基准或无法计算。
 */
- (double)relativeSpeedupAgainstFPS:(double)baselineFPS;

+ (instancetype)summaryWithRounds:(NSArray<BenchRoundMetrics *> *)rounds;

/** 生成纯文本报告，便于复制粘贴给他人 */
- (NSString *)textReportWithConfig:(nullable BenchRunConfig *)config;

@end

#pragma mark - 引擎

typedef NS_ENUM(NSInteger, BenchEngineState) {
    BenchEngineStateIdle = 0,
    BenchEngineStateRunning,
};

/**
 * 测速引擎。
 *
 * 解码在私有串行队列上执行：既避免阻塞主线程（否则会触发系统手势判定超时、
 * 界面完全无响应），又保证同一时刻只有一轮在跑——txav1d 内部有大量静态/全局
 * 状态，并发调用会互相破坏。
 *
 * 采样定时器以固定间隔读取进程 CPU 与内存，因此 CPU 反映的是「整个 App 进程」
 * 的占用，包含界面线程，这与 Instruments 的口径一致。
 */
@interface BenchEngine : NSObject

@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSUInteger completedRounds;
@property (nonatomic, readonly) NSUInteger plannedRounds;

/**
 * 启动测试。
 *
 * @param config     测试配置
 * @param onProgress 进度回调（主线程），fraction 为 0~1
 * @param onCompletion 完成回调（主线程），rounds 为全部轮次（含预热轮），
 *                     error 非 nil 表示测试失败
 */
- (void)startWithConfig:(BenchRunConfig *)config
               onProgress:(nullable void (^)(NSString *stage, double fraction))onProgress
             onCompletion:(void (^)(NSArray<BenchRoundMetrics *> *rounds,
                                    NSString *_Nullable error))onCompletion;

/** 请求取消。当前这一轮无法中断，会在轮次间生效。 */
- (void)cancel;

@end

#pragma mark - 码流库

/**
 * 码流目录管理。
 *
 * 工程内置目录 `TXAV1Dec/streams` 会作为 App 资源打包，启动时同步到
 * `Documents/Streams`。这样新增码流只需把文件放进工程目录，无需再手工拖拽。
 */
@interface BenchStreamLibrary : NSObject

/** Documents/Streams 的绝对路径，目录不存在时会被创建 */
+ (NSString *)streamsDirectory;

/** 扫描 Documents/Streams，按文件名排序返回 */
+ (NSArray<BenchStream *> *)availableStreams;

/**
 * 把 App 包内置的码流同步到 Documents/Streams。
 *
 * 仅在目标文件不存在或大小不同时复制，因此重复调用很廉价。
 *
 * @return 新复制的文件数量
 */
+ (NSUInteger)syncBundledStreams;

/** 删除某个码流，返回是否成功 */
+ (BOOL)removeStream:(BenchStream *)stream error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
