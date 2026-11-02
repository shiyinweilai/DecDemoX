//
//  BenchSystemMetrics.h
//  TXAV1Dec
//
//  设备与进程级运行时指标采集。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 调度策略

/**
 * 线程调度偏好。
 *
 * 先说结论：如果目的是**横向对比不同解码器版本**，这一项应当固定不变量，
 * 而不是当作可调参数来回试。换策略会同时改变测量条件，两个解码器的差异就
 * 无法归因到解码器本身。
 *
 * 再说 iOS 的现实：系统不提供 pthread_setaffinity_np，也没有公开的 CPU 亲和
 * 位图，无法把线程「硬绑」到某个核心。真正有意义的只有「跑在哪一簇」：
 *
 * - 性能核（P 核）：单核最快，适合测峰值吞吐。
 * - 能效核（E 核）：单核慢、功耗低，是后台解码、低发热场景的真实条件。
 *
 * 之前还提供过「L2 亲和」，已移除：affinity tag 按 task 命名空间分组，全 App
 * 只有一个 tag 时等于「所有线程同一组」，不构成任何约束，实测无差异，属于
 * 给出虚假确定性的无效选项。
 */
typedef NS_ENUM(NSInteger, BenchSchedulePolicy) {
    BenchSchedulePolicyDefault = 0,   ///< 不干预，交给系统（推荐，作为对比基线）
    BenchSchedulePolicyPerformance,   ///< 性能核偏好：QoS 提到 UserInteractive
    BenchSchedulePolicyEfficiency,    ///< 能效核偏好：QoS 降到 Background
};

#pragma mark - 内存快照

/**
 * 一次进程内存快照。
 *
 * iOS 没有 Android 的 PSS 口径，这里选 `phys_footprint` 作为主指标，理由：
 * 它是 Apple 官方口径，Xcode 内存仪表、Instruments 的 VM Tracker 和系统的
 * jetsam（低内存杀进程）判定用的都是它。
 *
 * `resident_size` 只作交叉验证，不建议单独看：它统计所有驻留物理页，包含
 * dyld 共享缓存、代码段这类「干净页」，而这些不计入 footprint。实测同一时刻
 * resident 约 82 MB、footprint 约 46 MB，差值几乎全部来自这部分共享页，
 * 与解码器实现无关，作为对比指标只会引入噪声。
 */
@interface BenchMemorySnapshot : NSObject

@property (nonatomic, assign) double footprintMB;   ///< phys_footprint，主指标
@property (nonatomic, assign) double residentMB;    ///< resident_size，交叉验证
@property (nonatomic, assign) double compressedMB;  ///< 被压缩的页
@property (nonatomic, assign) double internalMB;    ///< 匿名内存

/** 本次读取是否成功。失败时各字段为 0，不应作为有效数据统计。 */
@property (nonatomic, assign) BOOL valid;

+ (instancetype)currentSnapshot;

@end

#pragma mark - 采集器

/**
 * 进程级性能指标采集器。
 *
 * CPU 使用率基于「线程 CPU 时间差分」计算，单次调用只能得到「自上次调用以来」的
 * 平均值，因此必须在测试过程中按固定间隔反复采样，才能反映真实负载曲线。
 */
@interface BenchSystemMetrics : NSObject

#pragma mark 调度策略

/// 策略的中文名，用于界面与报告
+ (NSString *)schedulePolicyName:(BenchSchedulePolicy)policy;

/// 策略在报告里的一句话说明，写清它只是偏好
+ (NSString *)schedulePolicyNote:(BenchSchedulePolicy)policy;

/**
 * 把策略应用到当前线程。
 *
 * 必须在真正执行解码的线程上调用。txav1d 内部用 pthread_create 派生工作线程，
 * 子线程会继承创建时刻的 QoS，所以在父线程设置能间接影响到它们。
 *
 * @return 是否成功设置（默认策略恒为 YES）
 */
+ (BOOL)applySchedulePolicyToCurrentThread:(BenchSchedulePolicy)policy;

#pragma mark 设备

/// 机器标识，例如 "iPhone18,1"
+ (NSString *)machineIdentifier;

/// 设备名称，例如 "杨瑞的 iPhone"
+ (NSString *)deviceName;

/// 逻辑核心数
+ (NSInteger)processorCount;

/// 性能核数量，设备不区分大小核时返回 0
+ (NSInteger)performanceCoreCount;

/// 能效核数量，设备不区分大小核时返回 0
+ (NSInteger)efficiencyCoreCount;

/// 大小核描述，例如 "6 核 (2P + 4E)"；不区分大小核时只返回核心数
+ (NSString *)coreTopologyDescription;

/// 当前进程内存（phys_footprint），单位 MB
+ (double)currentMemoryMB;

/// 当前进程内存快照
+ (BenchMemorySnapshot *)currentMemorySnapshot;

/**
 * 记录「空载基线」：进程在**从未执行过解码**时的内存。
 *
 * 这是计算解码器净开销的唯一可靠基准，实测原因如下：av1d 的帧池、线程栈、
 * 熵解码表在第一次解码后长期驻留且不归还，因此「本轮开始前的内存」从第二轮起
 * 就已经包含了上一轮的解码占用，用它算增量会得到恒为 0 的假结果。
 *
 * 所以基线必须尽早取一次并全局缓存，之后所有轮次、所有码流都减这一个值。
 * 重复调用不会覆盖首次记录。
 */
+ (void)captureIdleBaselineIfNeeded;

/// 空载基线值（MB）。未捕获时返回 0。
+ (double)idleBaselineFootprintMB;

/// 空载基线是否已捕获
+ (BOOL)hasIdleBaseline;

/// 当前进程线程数
+ (NSInteger)currentThreadCount;

/// 当前热状态（Nominal / Fair / Serious / Critical）
+ (NSString *)thermalStateDescription;

/// 重置采样基线。每轮测量开始前必须调用一次。
- (void)reset;

/**
 * 采样自上次调用以来的 CPU 占用，单位为「单核百分比」。
 *
 * 返回值 100 表示占满一个核心，600 表示 6 核全部占满。
 * 这是「解码器占几个核」的唯一正确来源，界面与报告都基于它换算，
 * 不再单独采集一组相互独立的百分比，避免口径打架。
 */
- (double)sampleCPUPercentOfCore;

@end

NS_ASSUME_NONNULL_END
