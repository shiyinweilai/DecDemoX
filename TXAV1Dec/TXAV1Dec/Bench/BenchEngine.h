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
 * 是否按 PlayerCore 口径下发线程参数。
 *
 * NO（默认）：解码器能力口径，txav1d 写 reserved[0]，填几个线程就真跑几个，
 *     用于线程扩展性对比。
 * YES：复刻 FFmpeg libtxav1d / libdav1d 封装，frame delay 按封装公式推导。
 *     自动档取 CPU 核数且不写 reserved[0]（txav1d 按线上截断）；
 *     手动指定线程时写 reserved[0]，两个解码器线程数一致生效。
 */
@property (nonatomic, assign) BOOL playerCoreThreading;

/**
 * 定速解码（pacing）。
 *
 * 对应解码库命令行里的 `--realtime`：按目标帧率对齐每帧的产出时刻，
 * 用于模拟实时播放时的解码压力，而不是让解码器跑满算力。
 *
 * 它只是解码循环里的节流，不改变解码器任何内部参数，因此同一版本可以在
 * 定速 / 不定速两种模式下反复对照，两边数据仍然可比。
 */
@property (nonatomic, assign) BOOL pacingEnabled;

/**
 * 是否按码流标称帧率定速。
 *
 * YES 时用码流头里的 fps 作为目标（对应 CLI 的 `--realtime`，不带参数）；
 * NO 时用 pacingFPS 指定的帧率（对应 `--realtime $fract`）。码流头缺帧率时
 * 按码流定速无法成立，会退回不定速，实际生效值以结果里的字段为准。
 */
@property (nonatomic, assign) BOOL pacingUseSourceFPS;

/** 自定义目标帧率，仅在 pacingEnabled 且 !pacingUseSourceFPS 时有效 */
@property (nonatomic, assign) double pacingFPS;

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

/**
 * 实际生效的定速状态。
 *
 * 取自解码库回填的值而不是配置：选了「按码流帧率」但码流头缺帧率时会
 * 静默退回不定速，只有看结果才知道这一轮到底有没有定速。
 */
@property (nonatomic, assign) BOOL pacingApplied;
/** 实际目标帧率，未定速时为 0 */
@property (nonatomic, assign) double pacingFPS;
/** 本轮累计节流等待时长（毫秒），用于核对 totalMs 的构成 */
@property (nonatomic, assign) double pacingWaitMs;

/**
 * 定速缓冲观测，反映「解码跟不跟得上目标帧率」。非定速时均为 0。
 *
 * bufferStarveEvents 大于 0 是最关键的信号：出帧线程到点却取不到帧，
 * 说明解码产能撑不住目标帧率，实时播放会卡顿。bufferFullEvents 大说明
 * 解码轻松跑在目标帧率之上（缓冲常满、触发背压）。
 */
@property (nonatomic, assign) NSInteger bufferCapacity;
@property (nonatomic, assign) NSUInteger bufferFullEvents;
@property (nonatomic, assign) NSUInteger bufferStarveEvents;

/**
 * 实际产帧率 = 解码帧数 / 端到端墙钟时长。
 *
 * 与 decodeFPS 的区别是本属性包含定速等待：定速 75fps 时它应趋近 75，
 * 而 decodeFPS 反映的是解码器真实能力（通常远高于目标值）。
 * 这是唯一能直接证明「定速是否真的生效」的指标，缺了它就只能靠
 * decodeFPS 猜，而那个数字在定速与不定速下都可以很高，看不出区别。
 */
@property (nonatomic, readonly) double actualFPS;

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
 *
 * avgCPUPercent 由整轮同步差分得出，精确覆盖解码区间，不受轮次长短影响。
 */
@property (nonatomic, assign) double avgCPUPercent;
@property (nonatomic, assign) double peakCPUPercent;

/**
 * 本轮是否真的采到了 CPU 数据。
 *
 * 短轮次下若区间统计也失效（极端时钟跳变），该值为 NO。此时必须显示「无采样」
 * 而不是 0%——0% 会被读成「几乎不占 CPU」，与「没测到」是完全不同的结论，
 * 混在横向对比表里会直接导致选错版本。
 */
@property (nonatomic, assign) BOOL cpuSampled;

/**
 * 本轮 CPU 统计区间的墙钟时长与 CPU 时长（毫秒），仅用于诊断。
 *
 * 二者比值即 avgCPUPercent。当它与解码器自报的 totalMs 相差很大时，
 * 说明区间里混入了大量非解码开销，此时 CPU 均值会被系统性稀释。
 */
@property (nonatomic, assign) double cpuIntervalWallMs;
@property (nonatomic, assign) double cpuIntervalCPUMs;

/**
 * 峰值是否为真实峰值。
 *
 * YES 表示定时器在轮内至少命中一次，峰值可信；NO 表示轮次短于采样间隔，
 * 峰值退化为平均值，只能当参考，不应用于「谁的瞬时峰值更省」这类判断。
 */
@property (nonatomic, assign) BOOL peakCPUSampled;

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

/**
 * 本轮是否采到内存数据。
 *
 * 定时器未命中时会用轮末快照兜底，此时 peakFootprintMB 是「下界」而非全程峰值，
 * 但比显示 0 MB 更接近事实：解码结束后帧池与线程栈仍然驻留，快照包含这些开销。
 */
@property (nonatomic, assign) BOOL memorySampled;

/** 解码器自身内存开销 = peakFootprintMB - baselineFootprintMB，不小于 0 */
@property (nonatomic, readonly) double footprintDeltaMB;

/** resident 仅作交叉验证：受 page cache 回收时机影响大，噪声高于信号 */
@property (nonatomic, assign) double baselineResidentMB;
@property (nonatomic, assign) double peakResidentMB;
@property (nonatomic, assign) double avgResidentMB;

/** 每解码一帧的净内存成本，单位 KB。小码流下可忽略，大分辨率下能看出实现差异。 */
@property (nonatomic, readonly) double footprintDeltaKBPerFrame;

@property (nonatomic, assign) NSInteger peakThreadCount;

/**
 * 实际下发给解码器的线程参数（取库回填值，而非配置值）。
 * appliedThreadOverride 为 0 表示未写 reserved[0]，txav1d 库内部可能截断线程数。
 */
@property (nonatomic, assign) BOOL appliedPlayerCoreThreading;
@property (nonatomic, assign) NSInteger appliedNThreads;
@property (nonatomic, assign) NSInteger appliedThreadOverride;
@property (nonatomic, assign) NSInteger appliedFrameDelay;

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
@property (nonatomic, readonly) double decodeFPS;       ///< 均值口径：1000 / avgFrameMs

/**
 * 峰值解码帧率：用最快的一轮（轮内均帧耗时最小）换算。
 *
 * 与 decodeFPS 的区别只在口径：平均值被慢轮拖低，峰值反映这批测试里该版本
 * 跑得最好的一次。汇总表按峰值展示时必须与 minAvgFrameMs 配对使用，
 * 否则同一行的 fps 与 ms/f 会来自不同轮次，互相矛盾。
 */
/**
 * 平均实际产帧率：各计分轮 actualFPS 的均值。
 *
 * 定速跑时它应接近 pacingFPS，这是判断定速是否生效的主要依据。
 */
@property (nonatomic, readonly) double actualFPS;

/**
 * 实际产帧率相对目标帧率的偏差百分比，未定速或缺少目标时返回 0。
 *
 * 定速生效时该值通常在小数点后，偏差明显（如超过 5%）说明目标帧率
 * 高于这台设备的能力：解码器跑不到那么快，节流自然无从等待。
 * 这个区分很重要——「定速 300fps 但实际只有 200」不代表定速失效，
 * 而是设备算力不足，此时定速设置本身没有意义。
 */
@property (nonatomic, readonly) double pacingDeviationPercent;

/** 各计分轮的目标帧率，取第一个真正生效的轮次；未定速返回 0 */
@property (nonatomic, readonly) double pacingTargetFPS;

@property (nonatomic, readonly) double peakDecodeFPS;

@property (nonatomic, readonly) double speedRatio;

@property (nonatomic, readonly) double avgCPUPercent;   ///< 单核百分比
@property (nonatomic, readonly) double peakCPUPercent;
@property (nonatomic, readonly) double avgCPUCores;     ///< 核心等价
@property (nonatomic, readonly) double peakCPUCores;
@property (nonatomic, readonly) double cpuSharePercent;  ///< 占设备总算力的比例
@property (nonatomic, readonly) double cpuSecondsPerFrame; ///< 每帧核心·秒，越低越高效

/**
 * 是否有任一计分轮采到了 CPU 数据。
 *
 * 为 NO 时，avgCPUPercent、cpuSharePercent、cpuSecondsPerFrame 全都是占位值 0，
 * 展示层必须显示「无采样」，否则会把「没测到」误读成「几乎不占 CPU」。
 */
@property (nonatomic, readonly) BOOL avgCPUSampled;

/// 峰值是否为真实峰值（任一轮定时器命中即可）
@property (nonatomic, readonly) BOOL peakCPUSampled;

/// 是否有任一计分轮采到内存数据
@property (nonatomic, readonly) BOOL memorySampled;

@property (nonatomic, readonly) double avgFootprintMB;
@property (nonatomic, readonly) double peakFootprintMB;
@property (nonatomic, readonly) double avgResidentMB;
@property (nonatomic, readonly) double peakResidentMB;

/** 解码器净内存开销（峰值 - 基线），横向对比主要看这个 */
@property (nonatomic, readonly) double footprintDeltaMB;
@property (nonatomic, readonly) double footprintDeltaKBPerFrame;

+ (instancetype)summaryWithRounds:(NSArray<BenchRoundMetrics *> *)rounds;

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
