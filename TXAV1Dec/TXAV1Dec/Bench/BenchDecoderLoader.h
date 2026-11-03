//
//  BenchDecoderLoader.h
//  TXAV1Dec
//
//  解码器动态库的运行时加载与版本枚举。
//
//  背景：libtxav1d.a 各版本导出的全局符号几乎完全相同（实测 1.4.2 与 1.4.3
//  有 885 个同名符号）。静态链接进同一个 App 必然重定义冲突，所以「一个 App
//  内同时测多个版本」只能走动态库：每个版本编成一个 dylib，符号表与全局变量
//  各自独立，近年来的实现再怎么改也不会互相踩。
//
//  关键设计：bench 代码（txav1d_bench）被一起编进每个 dylib，而不是留在 App 里。
//  这样跨 dylib 边界传递的只有 Txav1dBenchConfig / Txav1dBenchResult 这两个
//  我们自己定义的结构体。App 完全不接触 Txav1dContext、Txav1dPicture 等库内部
//  结构体，因此新版本改了内部内存布局也不会造成 App 侧野指针崩溃。
//
//  加载用 RTLD_LOCAL：每个 dylib 的符号不进入全局符号表，避免第二个版本加载时
//  被第一个版本的同名符号抢先解析（否则两版会共用同一份全局变量，测出来的
//  数据毫无意义）。
//

#import <Foundation/Foundation.h>

#import "txav1d_bench.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 单个解码器版本

/**
 * 一个解码器版本。
 *
 * 生命周期分两段：
 *   1. 扫描阶段（scanDecoders）只读目录与文件属性，建立轻量对象，不碰 dlopen；
 *   2. 加载阶段（loadIfNeeded）在真正要跑测试时才对这一个版本 dlopen + 解析符号。
 *
 * 这么拆的原因是启动成本：早期实现把两件事揉在 availableDecoders 里，
 * 界面一出现就要把 Frameworks 下所有版本全部 dlopen(RTLD_NOW) 一遍，
 * 而用户往往只想测其中一个。启动只需要「有哪些版本」，不需要「把库装进来」。
 *
 * 持有 dlopen 句柄，dealloc 时自动 dlclose。句柄必须活到该版本所有测试结束，
 * 否则函数指针会立即失效。
 */
@interface BenchDecoder : NSObject

/** 版本标识，取自 DecoderSDK 下的目录名，例如 "txav1d143" / "dav1d151" */
@property (nonatomic, copy, readonly) NSString *version;

/** dylib 的绝对路径 */
@property (nonatomic, copy, readonly) NSString *libraryPath;

/** 库自报的版本号（txav1d_version），用于交叉校验目录名 */
@property (nonatomic, copy, readonly) NSString *libraryReportedVersion;

/** 该版本的构建时间，取自 dylib 文件修改时间，用于区分同名重编 */
@property (nonatomic, copy, readonly) NSString *buildStamp;

/** 用于界面与报告展示的名称，例如 "txav1d143" / "dav1d151" */
@property (nonatomic, copy, readonly) NSString *displayName;

/** 加载失败的原因，成功时为 nil；未加载时为 nil */
@property (nonatomic, copy, readonly, nullable) NSString *loadError;

/**
 * 是否已经加载完成（无论成功还是失败）。
 *
 * 界面用它区分「还没试过」和「试过但不可用」：未加载的版本在列表里
 * 显示构建时间且可以勾选，加载失败的版本才置灰并给出原因。
 */
@property (nonatomic, readonly) BOOL isLoaded;

/**
 * 是否可执行测试。
 *
 * 只有已加载且符号齐全时才为真。注意本属性不会触发加载：
 * 界面上的可用性判断一律用 isLoaded / loadIfNeeded，不能靠它。
 */
@property (nonatomic, readonly) BOOL isUsable;

/**
 * 按需加载本版本的动态库，已加载（含失败）则直接返回缓存结果。
 *
 * 线程安全，可从后台队列调用。dlopen 在真机上约几十毫秒，
 * 因此必须在后台队列执行，不要放在主线程的界面构建路径里。
 *
 * @return 是否可用
 */
- (BOOL)loadIfNeeded;

/**
 * 执行一次完整解码测速。
 *
 * 阻塞调用，必须在后台队列执行。返回 0 表示测试完成（即使解码中途出错
 * 也会填充 error 字段），非 0 表示参数非法或无法打开输入。
 */
- (int)runBenchWithConfig:(const Txav1dBenchConfig *)config
                   result:(Txav1dBenchResult *)result;

/** 释放 result 内部由 dylib 分配的内存。必须调用本版本的方法释放，不能混用。 */
- (void)freeBenchResult:(Txav1dBenchResult *)result;

@end

#pragma mark - 版本枚举

/**
 * 解码器版本库。
 *
 * 扫描 App 包内 Frameworks 目录下的 libtxav1d_<版本>.dylib。
 * 版本列表来自构建产物而不是硬编码，所以往 DecoderSDK 里加一个目录、
 * 重新编译就能多出一个可选版本，界面代码不需要改动。
 */
@interface BenchDecoderLibrary : NSObject

/**
 * 扫描出所有解码器版本，按版本号降序排列（最新在前）。
 *
 * 只读 Frameworks 目录与文件属性，不执行 dlopen —— 启动路径用它，
 * 成本是一次目录遍历，与版本数量无关。返回的对象需要时再逐个加载。
 */
+ (NSArray<BenchDecoder *> *)scanDecoders;

/**
 * 扫描并立即加载所有版本。
 *
 * 仅在确实需要「所有版本都可用性已知」的场景使用（如自测全版本覆盖）。
 * 界面启动路径不得调用，否则又退回到启动期全量 dlopen。
 */
+ (NSArray<BenchDecoder *> *)availableDecoders;

/** 兜底版本：列表为空时返回 nil，界面据此提示用户去检查构建 */
+ (nullable BenchDecoder *)preferredDecoder;

/**
 * 版本比较器，供界面与版本库共用同一套排序规则。
 *
 * 单独公开是因为界面按点击顺序维护选中列表，也要排序；
 * 如果两处各写一份，排序基准一旦分叉，勾选顺序与列表顺序就会不一致。
 */
+ (NSComparisonResult)compareVersion:(NSString *)a with:(NSString *)b;

@end

NS_ASSUME_NONNULL_END
