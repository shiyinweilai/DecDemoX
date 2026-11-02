//
//  BenchDecoderLoader.m
//  TXAV1Dec
//

#import "BenchDecoderLoader.h"

#include <dlfcn.h>

#pragma mark - 函数指针签名

typedef int (*BenchFn)(const Txav1dBenchConfig *, Txav1dBenchResult *);
typedef void (*FreeResultFn)(Txav1dBenchResult *);
typedef const char *(*VersionFn)(void);

#pragma mark - BenchDecoder

@interface BenchDecoder ()

@property (nonatomic, copy, readwrite) NSString *version;
@property (nonatomic, copy, readwrite) NSString *libraryPath;
@property (nonatomic, copy, readwrite) NSString *libraryReportedVersion;
@property (nonatomic, copy, readwrite) NSString *buildStamp;
@property (nonatomic, copy, readwrite, nullable) NSString *loadError;

@end

@implementation BenchDecoder {
    void *_handle;
    BenchFn _benchFn;
    FreeResultFn _freeResultFn;
}

- (void)dealloc {
    // dylib 必须等到所有测试结束后才能卸载，否则函数指针立刻失效。
    // BenchDecoder 的生命周期由调用方持有，这里只负责在对象销毁时释放句柄。
    if (_handle) {
        dlclose(_handle);
        _handle = NULL;
    }
}

/// 去掉点号后的版本形式，用于跨命名风格比较。
/// 目录名 txav1d143 对应头文件 "1.4.3"，压缩后都是 143，视为一致。
+ (NSString *)compactVersion:(NSString *)version {
    return [version stringByReplacingOccurrencesOfString:@"." withString:@""];
}

- (NSString *)displayName {
    // 目录名本身就是版本标识（txav1d142 / dav1d151），直接用它。
    // 早先这里拼成 "txav1d 1.4.3"，改成目录名之后会变成
    // "txav1d txav1d143" 这种重复，所以必须换掉前缀拼接。
    NSString *name = self.version;

    // 库自报版本与目录名不一致时才追加提示。比较用压缩形式，
    // 因为目录名是 txav1d143、库自报是 1.4.3，写法不同但指向同一版本；
    // 只有压缩后仍不相等才是真正的错配（换了库漏改目录名），
    // 这种错配从数据上完全看不出来，必须让它可见。
    if (self.libraryReportedVersion.length > 0 &&
        ![[BenchDecoder compactVersion:self.libraryReportedVersion]
          isEqualToString:[BenchDecoder compactVersion:self.version]]) {
        return [NSString stringWithFormat:@"%@（库自报 %@）",
                name, self.libraryReportedVersion];
    }
    return name;
}

- (BOOL)isUsable {
    return self.loadError == nil && _handle != NULL && _benchFn != NULL;
}

- (int)runBenchWithConfig:(const Txav1dBenchConfig *)config
                   result:(Txav1dBenchResult *)result {
    if (!self.isUsable || !_benchFn) return TXAV1D_BENCH_ERROR;
    return _benchFn(config, result);
}

- (void)freeBenchResult:(Txav1dBenchResult *)result {
    // 必须由同一个 dylib 释放：分配发生在该库内部的 malloc 堆上，
    // 由 App 或另一个版本释放会破坏堆，症状是随机的野指针崩溃。
    if (_freeResultFn && result) {
        _freeResultFn(result);
    }
}

@end

#pragma mark - 内部构造

@interface BenchDecoder (Internal)

- (BOOL)loadWithVersion:(NSString *)version
                   path:(NSString *)path
                  error:(NSString **)error;

@end

@implementation BenchDecoder (Internal)

- (BOOL)loadWithVersion:(NSString *)version
                   path:(NSString *)path
                  error:(NSString **)error {
    self.version = version;
    self.libraryPath = path;

    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path
                                                                          error:NULL];
    NSDate *mtime = attrs[NSFileModificationDate];
    if (mtime) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd HH:mm";
        self.buildStamp = [fmt stringFromDate:mtime];
    } else {
        self.buildStamp = @"";
    }

    // RTLD_LOCAL 是这里的要点：默认的 RTLD_GLOBAL 会把符号并入全局符号表，
    // 于是第二个版本加载时，它的内部调用可能被第一个版本的同名符号抢先解析，
    // 结果两个「不同版本」实际共用同一份全局变量，测出来的数据自相矛盾。
    _handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_handle) {
        const char *err = dlerror();
        self.loadError = [NSString stringWithFormat:@"加载失败：%s", err ? err : "未知原因"];
        if (error) *error = self.loadError;
        return NO;
    }

    _benchFn = (BenchFn)dlsym(_handle, "txav1d_bench");
    _freeResultFn = (FreeResultFn)dlsym(_handle, "txav1d_bench_free_result");
    VersionFn versionFn = (VersionFn)dlsym(_handle, "txav1d_version");

    if (!_benchFn || !_freeResultFn) {
        self.loadError = @"动态库缺少 txav1d_bench 符号，可能编译时漏了 bench 源码";
        dlclose(_handle);
        _handle = NULL;
        if (error) *error = self.loadError;
        return NO;
    }

    if (versionFn) {
        const char *raw = versionFn();
        self.libraryReportedVersion = raw ? @(raw) : @"";
    } else {
        self.libraryReportedVersion = @"";
    }
    return YES;
}

@end

#pragma mark - 版本库

@implementation BenchDecoderLibrary

/// App 包内的 Frameworks 目录。dylib 由构建脚本输出到这里。
+ (NSString *)frameworksDirectory {
    NSString *path = NSBundle.mainBundle.privateFrameworksPath;
    if (path.length > 0) return path;
    // privateFrameworksPath 在设计上就指向 App.app/Frameworks，
    // 但为了不依赖该行为，兜底手工拼一次。
    return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
}

/// 按版本从新到旧比较。
///
/// 目录名有两种风格：旧的三点式（1.4.3）和新命名的压缩式（txav1d143、
/// dav1d151）。原来按 "." 切分再比数字，遇到 txav1d143 这种没有点号的
/// 名字会全部落到同一段，排序退化成不稳定、结果不可预期。
/// 这里改为：先按名字里的数字序列比较（把 txav1d143 抽出 143），
/// 数字相同再按字面比较，保证排序稳定。
+ (NSComparisonResult)compareVersion:(NSString *)a with:(NSString *)b {
    NSString *da = [self digitsOf:a];
    NSString *db = [self digitsOf:b];
    if (da.length > 0 && db.length > 0 && ![da isEqualToString:db]) {
        // 位数不同时先比位数：1.5.1→151 与 1.4.3→143 都是三位可直接比，
        // 但 2.0.0→200 与 1.10.0→1100 位数不同，必须按数值而非字面比。
        if (da.length != db.length) {
            return da.length > db.length ? NSOrderedAscending : NSOrderedDescending;
        }
        const NSComparisonResult r = [da compare:db];
        return r == NSOrderedSame ? NSOrderedSame
                                  : (r == NSOrderedDescending ? NSOrderedAscending
                                                              : NSOrderedDescending);
    }
    // 数字相同（或都抽不出数字）时按字面倒序，让结果稳定可预期
    return [b compare:a];
}

/// 抽出字符串里的全部数字，用于跨命名风格比较版本高低。
+ (NSString *)digitsOf:(NSString *)text {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        const unichar c = [text characterAtIndex:i];
        if (c >= '0' && c <= '9') [out appendFormat:@"%C", c];
    }
    return out;
}

+ (NSArray<BenchDecoder *> *)availableDecoders {
    NSString *dir = [self frameworksDirectory];
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir
                                                                                  error:NULL];
    if (names.count == 0) return @[];

    NSMutableArray<BenchDecoder *> *decoders = [NSMutableArray array];
    NSString *const prefix = @"libtxav1d_";
    NSString *const suffix = @".dylib";

    for (NSString *name in names) {
        if (![name hasPrefix:prefix] || ![name hasSuffix:suffix]) continue;

        // 文件名里去掉前后缀就是版本号 —— 版本号来自构建产物而非硬编码，
        // 所以新增版本只要往 DecoderSDK 放目录并重新编译，界面自动多一项。
        NSRange range = NSMakeRange(prefix.length, name.length - prefix.length - suffix.length);
        NSString *version = [name substringWithRange:range];
        if (version.length == 0) continue;

        NSString *path = [dir stringByAppendingPathComponent:name];
        BenchDecoder *decoder = [[BenchDecoder alloc] init];
        NSString *error = nil;
        [decoder loadWithVersion:version path:path error:&error];
        // 加载失败也收进列表：让用户在界面上看到「某版本不可用」，
        // 比静默消失更容易发现问题。
        [decoders addObject:decoder];
    }

    [decoders sortUsingComparator:^NSComparisonResult(BenchDecoder *a, BenchDecoder *b) {
        return [self compareVersion:a.version with:b.version];
    }];
    return decoders;
}

+ (nullable BenchDecoder *)preferredDecoder {
    for (BenchDecoder *decoder in [self availableDecoders]) {
        if (decoder.isUsable) return decoder;
    }
    return nil;
}

@end
