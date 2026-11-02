//
//  BenchSystemMetrics.m
//  TXAV1Dec
//

#import "BenchSystemMetrics.h"

#import <UIKit/UIKit.h>

#include <mach/mach.h>
#include <mach/thread_policy.h>
#include <pthread/qos.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

/**
 * 单调时钟，统一换算为纳秒。
 *
 * 不能直接用 mach_absolute_time() 当纳秒用：它在不同设备上的时基不同
 * （Intel 设备的 numer/denom 并不等于 1），必须经 timebase 换算。
 */
static uint64_t BenchNowNanos(void) {
    static mach_timebase_info_data_t timebase = {0, 0};
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }
    return mach_absolute_time() * timebase.numer / timebase.denom;
}

/**
 * 汇总当前进程的累计 CPU 时间（纳秒）。
 *
 * 用 TASK_THREAD_TIMES_INFO 而不是遍历 task_threads：
 * 前者一次系统调用即返回整个 task 所有线程的累计用户态 + 系统态时间，
 * 后者需要为每个线程取 thread_info 再 deallocate 端口，开销大且
 * 在采样频率较高时容易丢失 mach port。
 */
static uint64_t BenchProcessCPUTimeNanos(void) {
    task_thread_times_info_data_t info;
    mach_msg_type_number_t count = TASK_THREAD_TIMES_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_THREAD_TIMES_INFO,
                  (task_info_t)&info, &count) != KERN_SUCCESS) {
        return 0;
    }

    uint64_t totalNanos = 0;
    totalNanos += (uint64_t)info.user_time.seconds * 1000000000ULL;
    totalNanos += (uint64_t)info.user_time.microseconds * 1000ULL;
    totalNanos += (uint64_t)info.system_time.seconds * 1000000000ULL;
    totalNanos += (uint64_t)info.system_time.microseconds * 1000ULL;
    return totalNanos;
}

/// 读取一个 sysctl 整数值，失败时返回 fallback
static int64_t BenchSysctlInt(const char *name, int64_t fallback) {
    // hw.perflevelN.physicalcpu 这类键返回的是 4 字节 int32，而不是 int64，
    // 因此不能只按 sizeof(int64_t) 校验长度，否则永远读不到值。
    int64_t value = 0;
    size_t size = sizeof(value);
    if (sysctlbyname(name, &value, &size, NULL, 0) != 0) {
        return fallback;
    }
    if (size == sizeof(int32_t)) {
        int32_t narrow = 0;
        memcpy(&narrow, &value, sizeof(narrow));
        return (int64_t)narrow;
    }
    if (size != sizeof(int64_t)) {
        return fallback;
    }
    return value;
}

/// 空载基线（MB）：进程从未执行解码时的 footprint，全局只记录一次
static double _benchIdleBaselineMB = 0;
static BOOL _benchIdleBaselineCaptured = NO;

@implementation BenchMemorySnapshot

+ (instancetype)currentSnapshot {
    BenchMemorySnapshot *snapshot = [[BenchMemorySnapshot alloc] init];

    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO,
                  (task_info_t)&info, &count) != KERN_SUCCESS) {
        // 读取失败时保持 valid = NO，调用方据此跳过本次采样，
        // 而不是把 0 当成真实内存值参与平均。
        return snapshot;
    }

    const double mb = 1024.0 * 1024.0;
    snapshot.footprintMB = (double)info.phys_footprint / mb;
    snapshot.residentMB = (double)info.resident_size / mb;
    snapshot.compressedMB = (double)info.compressed / mb;
    snapshot.internalMB = (double)info.internal / mb;
    snapshot.valid = YES;
    return snapshot;
}

@end

@implementation BenchSystemMetrics {
    // 上一次采样时的累计线程 CPU 时间（纳秒）
    uint64_t _lastCPUTimeNanos;
    // 上一次采样时刻（纳秒）
    uint64_t _lastSampleNanos;
    BOOL _hasBaseline;
}

#pragma mark - 调度策略

+ (NSString *)schedulePolicyName:(BenchSchedulePolicy)policy {
    switch (policy) {
        case BenchSchedulePolicyPerformance: return @"性能核偏好";
        case BenchSchedulePolicyEfficiency:  return @"能效核偏好";
        case BenchSchedulePolicyDefault:
        default:                             return @"不干预";
    }
}

+ (NSString *)schedulePolicyNote:(BenchSchedulePolicy)policy {
    switch (policy) {
        case BenchSchedulePolicyPerformance:
            return @"QoS 提到 UserInteractive，倾向调度到性能核；单核最快，用于测峰值吞吐";
        case BenchSchedulePolicyEfficiency:
            return @"QoS 降到 Background，倾向调度到能效核；单核较慢，对应后台解码场景";
        case BenchSchedulePolicyDefault:
        default:
            return @"不干预调度，系统按负载自行分配；横向对比解码器时应固定为此项";
    }
}

+ (BOOL)applySchedulePolicyToCurrentThread:(BenchSchedulePolicy)policy {
    if (policy == BenchSchedulePolicyDefault) return YES;

    // iOS 无法绑定到具体核心，只能通过 QoS 施加「倾向性」影响，
    // 系统最终仍可自由迁移线程，因此这里不返回失败判定。
    switch (policy) {
        case BenchSchedulePolicyPerformance:
            pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
            break;
        case BenchSchedulePolicyEfficiency:
            pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0);
            break;
        case BenchSchedulePolicyDefault:
        default:
            break;
    }
    return YES;
}

#pragma mark - 设备信息

+ (NSString *)machineIdentifier {
    static NSString *identifier = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct utsname systemInfo;
        if (uname(&systemInfo) == 0) {
            identifier = [NSString stringWithCString:systemInfo.machine
                                            encoding:NSUTF8StringEncoding];
        }
        if (identifier.length == 0) {
            identifier = @"unknown";
        }
    });
    return identifier;
}

+ (NSString *)deviceName {
    return [[UIDevice currentDevice] name] ?: @"iPhone";
}

+ (NSInteger)processorCount {
    return [NSProcessInfo processInfo].processorCount;
}

+ (NSInteger)performanceCoreCount {
    // Apple Silicon 用 hw.perflevelN 描述核心簇，perflevel0 固定是最高性能那簇。
    // 早期单簇设备读不到这些键，此时返回 0 表示「不区分大小核」。
    return (NSInteger)BenchSysctlInt("hw.perflevel0.physicalcpu", 0);
}

+ (NSInteger)efficiencyCoreCount {
    return (NSInteger)BenchSysctlInt("hw.perflevel1.physicalcpu", 0);
}

+ (NSString *)coreTopologyDescription {
    const NSInteger total = [self processorCount];
    const NSInteger performance = [self performanceCoreCount];
    const NSInteger efficiency = [self efficiencyCoreCount];

    // 只有两簇数量都能读到、且加起来对得上时，才认为设备区分大小核
    if (performance > 0 && efficiency > 0 && performance + efficiency == total) {
        return [NSString stringWithFormat:@"%ld 核 (%ldP + %ldE)",
                (long)total, (long)performance, (long)efficiency];
    }
    return [NSString stringWithFormat:@"%ld 核", (long)total];
}

+ (NSString *)thermalStateDescription {
    switch ([NSProcessInfo processInfo].thermalState) {
        case NSProcessInfoThermalStateNominal:  return @"Nominal";
        case NSProcessInfoThermalStateFair:     return @"Fair";
        case NSProcessInfoThermalStateSerious:  return @"Serious";
        case NSProcessInfoThermalStateCritical: return @"Critical";
        default:                                return @"Unknown";
    }
}

#pragma mark - 内存

+ (BenchMemorySnapshot *)currentMemorySnapshot {
    return [BenchMemorySnapshot currentSnapshot];
}

+ (double)currentMemoryMB {
    // phys_footprint 是 iOS 判定内存占用的口径，与 Xcode 内存仪表一致
    return [self currentMemorySnapshot].footprintMB;
}

+ (void)captureIdleBaselineIfNeeded {
    @synchronized (self) {
        if (_benchIdleBaselineCaptured) return;
        BenchMemorySnapshot *snapshot = [self currentMemorySnapshot];
        // 读取失败时不置位，留给下次调用重试，避免把 0 当成有效基线
        if (!snapshot.valid) return;
        _benchIdleBaselineMB = snapshot.footprintMB;
        _benchIdleBaselineCaptured = YES;
    }
}

+ (double)idleBaselineFootprintMB {
    [self captureIdleBaselineIfNeeded];
    // 未捕获成功时返回 0，调用方据此判断基线不可用，
    // 而不是拿当前占用冒充基线（那会让增量恒为 0）。
    return _benchIdleBaselineMB;
}

+ (BOOL)hasIdleBaseline {
    return [self idleBaselineFootprintMB] > 0;
}

+ (NSInteger)currentThreadCount {
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t threadCount = 0;
    if (task_threads(mach_task_self(), &threads, &threadCount) != KERN_SUCCESS) {
        return 0;
    }
    for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads,
                  threadCount * sizeof(thread_t));
    return (NSInteger)threadCount;
}

#pragma mark - CPU

- (void)reset {
    _lastCPUTimeNanos = BenchProcessCPUTimeNanos();
    _lastSampleNanos = BenchNowNanos();
    _hasBaseline = YES;
}

- (double)sampleCPUPercentOfCore {
    if (!_hasBaseline) {
        [self reset];
        return 0;
    }

    uint64_t nowNanos = BenchNowNanos();
    uint64_t cpuNanos = BenchProcessCPUTimeNanos();

    uint64_t wallDelta = nowNanos - _lastSampleNanos;
    uint64_t cpuDelta = cpuNanos - _lastCPUTimeNanos;

    _lastSampleNanos = nowNanos;
    _lastCPUTimeNanos = cpuNanos;

    if (wallDelta == 0) {
        return 0;
    }
    // cpuDelta/wallDelta 即「占用了几个核」，乘 100 得到单核百分比口径：
    // 100 = 占满 1 核，800 = 8 核全满
    return (double)cpuDelta * 100.0 / (double)wallDelta;
}

@end
