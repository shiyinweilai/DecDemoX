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
 * CPU 使用率基于「线程 CPU 时间差分」计算，单次调用只能得到「自上次调用以来」
 * 的平均值。这里提供两套互不干扰的口径，各自解决不同问题：
 *
 * 1. 整轮同步差分（beginCPUInterval / cpuPercentSinceIntervalBegin）
 *    在解码调用前后各取一次累计 CPU 时间，直接用「区间 CPU 时间 ÷ 区间墙钟时间」
 *    得到整轮平均占用。这是平均值的主口径：它精确覆盖整个解码区间，不会漏采，
 *    也不受单轮时长影响，因此在 60ms 这种短轮次下同样准确。
 *
 * 2. 定时器滚动采样（reset / sampleCPUPercentOfCore）
 *    每次调用推进一次滚动基线，得到相邻两次采样之间的瞬时占用，用于求峰值。
 *    它依赖调用频率，轮次短于采样间隔时会一次都采不到，所以只用来补峰值，
 *    不承担平均值职责。
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
 *
 * 注意：本方法只反映「自上次调用以来」的平均值，轮次短于采样间隔时会返回 0，
 * 因此仅用于求峰值曲线。整轮平均值请用下方 cpuPercentSinceIntervalBegin。
 */
- (double)sampleCPUPercentOfCore;

/**
 * 开始一个 CPU 统计区间，记录当前累计 CPU 时间与墙钟时刻。
 *
 * 与 cpuPercentSinceIntervalBegin 成对使用，把解码调用夹在中间，即可得到
 * 该区间的真实平均占用。区间方法完全独立于定时器与 reset，两者可并存：
 * 前者保证平均值完整覆盖整轮，后者只负责捕捉瞬时峰值。
 */
- (void)beginCPUInterval;

/**
 * 返回自 beginCPUInterval 以来整个区间的 CPU 平均占用（单核百分比）。
 *
 * 语义就是「这段时间里平均占满了几个核 ×  100」，因此与区间长短无关，
 * 短至几十毫秒的轮次也能得到稳定结果。
 *
 * @return 区间无效（未开始、墙钟时间为 0 或已发生过系统降频跳变）时返回负数，
 *         调用方据此判定「无采样」，而不是把 0 当成「几乎不占 CPU」。
 */
- (double)cpuPercentSinceIntervalBegin;

/**
 * 最近一次区间的墙钟时长与 CPU 时长（毫秒），仅用于诊断。
 *
 * 用途是把「CPU 均值偏低」拆成两种情况：区间本身很短（采样噪声占比高），
 * 还是区间被非解码开销（文件读取、线程池启停）拉长而稀释了占用率。
 */
@property (nonatomic, readonly) double lastIntervalWallMilliseconds;
@property (nonatomic, readonly) double lastIntervalCPUMilliseconds;

@end

NS_ASSUME_NONNULL_END
