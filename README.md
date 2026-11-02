# TXAV1Dec

基于 txav1d（AV1 解码器）的 iOS 性能测试工程。把 txav1d 的解码链路裁剪进 App，用于在真机上测量 AV1 解码速度、CPU 占用与内存占用等指标。

工程内的解码库与源码全部来自参考仓库 `/Users/rbyang/Documents/UGit/codec/av1d/`，命名统一为 `txav1d` 前缀。

## 目录结构

```
DecDemoX/
├── .gitignore                     # 忽略 Xcode 用户数据、构建产物、系统垃圾文件
├── .gitattributes                 # 声明 .a 为二进制并走 LFS，避免换行符转换
└── TXAV1Dec/
    ├── TXAV1Dec.xcodeproj/
    │   ├── project.pbxproj
    │   └── xcshareddata/xcschemes/TXAV1Dec.xcscheme   # 共享 scheme（可直接 -scheme 构建）
    └── TXAV1Dec/
        ├── AppDelegate.{h,m} / SceneDelegate.{h,m} / main.m
        ├── ViewController.{h,mm}      # 主界面：设备信息、码流选择、参数配置、结果展示
        ├── Bench/                     # 测速业务层
        │   ├── BenchEngine.{h,m}      # 多轮调度、采样、统计汇总、码流库管理
        │   └── BenchSystemMetrics.{h,m}  # CPU / 内存 / 线程数 / 热状态采集
        ├── UI/                        # 界面层
        │   ├── BenchTheme.{h,m}       # 颜色、字体、间距令牌
        │   └── BenchComponents.{h,m}  # 卡片、指标块、紧凑输入格、输入行、分段行
        ├── streams/                   # 码流目录（构建时自动打包进 App）
        │   └── test3.stream
        ├── BuiltinStreams / Assets.xcassets / Base.lproj / Info.plist / TXAV1Dec.entitlements
        ├── DecoderSDK/                # 解码器版本快照，按版本号分目录
        │   ├── Version.xcconfig       # 当前测试哪个版本（只改这一行）
        │   ├── verify_decoder_sdk.sh  # 构建期校验版本一致性
        │   ├── 1.4.2/
        │   │   ├── include/           # 公共头文件（txav1d.h / picture.h / vcs_version.h 等）
        │   │   └── lib/libtxav1d.a    # 该版本的静态库（arm64, iphoneos）
        │   └── 1.4.3/
        │       ├── include/
        │       └── lib/libtxav1d.a
        └── DecoderTools/              # 各版本共用的测试代码（不随版本变化）
            ├── src/                   # cpu.h、arm/cpu.h（CPU 特性检测声明）
            ├── config/ios/            # config.h、cli_config.h（等价 Meson 生成物）
            └── tools/
                ├── txav1d_core.{c,h}  # CLI 风格入口 txav1d_lanuch()
                ├── txav1d_bench.{c,h} # 测速专用入口 txav1d_bench()（App 实际使用）
                ├── txav1d_cli_parse.{c,h}
                ├── input/             # 解封装：ivf / section5 / annexb
                └── output/            # 封装：md5 / yuv / yuv4mpeg2 / null
```

`DecoderSDK/<版本>/` 只放「随版本变化」的东西：静态库和公共头文件。`tools/`、`config/`、`src/` 由 Xcode 编译进 App，且各版本之间没有差异，所以放在 `DecoderTools/` 共用。两者分离还有一个硬约束：`DecoderSDK` 不能加入自动同步组，否则多个版本的 `tools/*.c` 会被重复编译、`lib/*.a` 会被同时链接，直接链接失败。

## 两个解码入口

`tools/txav1d_core.c` 的 `txav1d_lanuch()` 是 CLI 风格入口，内部走 `getopt_long` 解析参数，返回输入流总帧数。它保留下来便于和官方命令行工具对齐结果，但 App 不再使用，原因有两条：

- `getopt_long` 依赖 `optind`/`optreset` 这对进程级全局变量，进程内反复调用会互相污染，第二次调用即报「缺少输入文件」。
- 它只返回一个总帧数，无法区分 demux 与解码耗时，也没有逐帧数据，做不了分位数统计。

App 实际调用的是 `tools/txav1d_bench.c` 的 `txav1d_bench()`：直接接收配置结构体（绕开全局状态），分段计时，并返回逐帧耗时数组。

## 指标口径

| 指标 | 口径说明 |
| --- | --- |
| 单帧耗时 | 相邻两帧产出之间的墙钟间隔，已扣除期间读包时间 |
| 首帧耗时 | 从测试开始到第一帧产出，含解码器初始化成本 |
| P50 / P95 | 对逐帧耗时排序后按线性插值取分位，反映卡顿分布 |
| 轮间标准差 | 各轮平均单帧耗时的样本标准差（n-1），反映测试稳定性 |
| CPU 单核百分比 | 进程累计线程 CPU 时间差分 ÷ 墙钟间隔，100% = 占满 1 核，600% = 6 核全满 |
| CPU 核心数 | 单核百分比 ÷ 100，直观表示「吃了几个核」，如 2.35 核 |
| CPU 整机占比 | 单核百分比 ÷ (核心数 × 100)，便于跨设备横向比较 |
| 内存 footprint | `phys_footprint`，系统判定内存压力与 jetsam 的依据，与 Xcode 内存仪表一致 |
| 内存 resident | `resident_size`，实际驻留的物理页，更接近真实占用 |

CPU 同时给出三种表述是有意的：单核百分比便于和 Instruments、官方 CLI 工具对齐；核心数便于直观理解并发度；整机占比便于在不同核心数的设备之间比较。三者是同一数据的换算，不是三次独立测量。

内存之所以要看两个口径，是因为它们回答的是不同问题。`footprint` 是系统决定要不要杀掉 App 的依据，但其中包含被压缩的页面，会比真实物理占用偏低；`resident` 更接近真实内存压力。对比不同解码器时，若 `footprint` 明显低于 `resident`，说明有相当一部分页面被压缩过，此时单看任一数字都会产生误判。iOS 没有 Android 的 PSS 口径，这对字段是最接近的替代。

单帧耗时按「帧间隔」而非「取帧函数耗时」统计，是因为 av1d 的实际解码工作几乎都在 `txav1d_send_data()` 内完成，`txav1d_get_picture()` 多数时候只是从输出队列取走一帧、耗时接近 0。若只测后者，会得到 0.0000 ms/f 这种无效结果。

## 关于核绑定

工程提供了「核调度偏好」，但**iOS 上无法真正把线程绑定到指定核心**，这一点在实现前已核实：

- iOS SDK 不提供 `pthread_setaffinity_np`，也没有公开的 CPU 亲和位图接口，编译期即不存在。
- `THREAD_AFFINITY_POLICY` 的官方注释明确写着它是 experimental，作用只是让同 tag 的线程「尽量共享 L2 缓存」，是调度提示而非核心锁定。

所以界面里的四项是「偏好」而非「绑定」，可用手段只有两个：

- 性能核偏好：把线程 QoS 提到 `USER_INTERACTIVE`，系统倾向调度到性能核。
- 能效核偏好：把 QoS 降到 `BACKGROUND`，系统倾向调度到能效核。
- L2 亲和：保持默认 QoS，设置 affinity tag 减少跨簇迁移。

txav1d 内部用 `pthread_create` 派生工作线程，子线程继承创建时刻的 QoS，因此在解码线程上设置能间接影响到它们的工作线程。报告里会如实记录所选策略及其含义，避免把偏好误读成硬绑。

如果要严格隔离核心，只能换平台（Android 有 `sched_setaffinity`）或改用可指定 CPU 集合的测试框架，iOS 上做不到。

## 界面

单页纵向布局，自上而下依次是设备信息、测试配置、开始测试、测试结果。设计上刻意保持紧凑：

- 设备信息只有两行文本，直接作为页头，不套卡片边框。第二行显示大小核拓扑，例如「6 核 (2P + 4E)」，因为 CPU 按核心数折算时需要知道分母。
- 码流选择并入「测试配置」卡片的第一行，不再单独占一张卡。点击后弹出多选列表，可勾选多个码流批量测试，支持全选。
- 四个数值参数（每轮帧数、测量轮次、预热轮次、跳过包数）排成一行，标题压在输入框上方。
- 解码线程与核调度偏好各占一行分段控件，都是枚举值。
- 结果用 2 行 3 列的指标栅格：帧率、单帧耗时、相对源帧率、CPU 核心数、footprint、resident。
- 测试报告不在页面里展示，只保留结果卡片标题行右侧的「复制报告」按钮，点击即把完整文本报告写入剪贴板。

单码流时结果区显示详细指标；多码流时在指标下方追加一张对比表，行是指标、列是码流，便于一眼看出哪个码流更吃力。

像「码流放在工程 streams 目录」这类说明性文字已从界面移除，改由本文件的「添加码流」一节承载，避免占用首屏空间。

## 添加码流

把 `.stream` / `.ivf` / `.obu` 文件放进 `TXAV1Dec/TXAV1Dec/streams/`，重新构建即可。App 启动时会把包内置码流同步到沙盒 `Documents/Streams`，同步策略是「目标不存在或大小不同才复制」，因此重复启动不会重复拷贝 20MB 的文件。

也可通过「文件」App 直接往 `Documents/Streams` 里拖文件（`Info.plist` 已开启 `UIFileSharingEnabled`），界面上点「刷新」即可看到。

## 开发期自测

带 `--selftest` 启动参数时，App 会自动跑一轮最小配置测试，把结果同时写入 `Documents/selftest.log`，便于在无控制台时验证端到端链路：

```bash
xcrun devicectl device process launch --device <UDID> --terminate-existing \
  dev.rbyang.com --selftest --threads 4 --frames 400
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier dev.rbyang.com \
  --source Documents/selftest.log --destination /tmp/selftest.log
```

`--threads` 与 `--frames` 可覆盖自测的线程数与每轮帧数，正常启动时这些参数不生效。

另有三个参数用于验证新功能：

- `--all-streams`：自测时全选所有码流，覆盖多码流批量与对比表路径。
- `--policy N`：指定核调度偏好，0 默认 / 1 性能核 / 2 能效核 / 3 L2 亲和。
- `--ui-shot`：把整页按滚动内容实际尺寸渲染成 `Documents/shot_top.png`，用于核对布局（模拟器缺 arm64 切片无法构建，只能靠真机自渲染截图）。

```bash
xcrun devicectl device process launch --device <UDID> --terminate-existing \
  dev.rbyang.com --selftest --all-streams --policy 1 --frames 150 --ui-shot
xcrun devicectl device copy from --device <UDID> --user mobile \
  --domain-type appDataContainer --domain-identifier dev.rbyang.com \
  --source Documents/selftest.log --destination /tmp/selftest.log
```

## 构建

```bash
cd TXAV1Dec
xcodebuild -project TXAV1Dec.xcodeproj -scheme TXAV1Dec \
  -configuration Debug -sdk iphoneos \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO build
```

或用 Xcode 直接打开 `TXAV1Dec/TXAV1Dec.xcodeproj` 并运行。

## 依赖

- iOS 16.0+
- 仅支持真机 arm64（静态库不含模拟器切片，模拟器构建会失败）
- 解码库与头文件版本必须一致（当前 1.4.2），版本不匹配时解码入口会直接返回失败

## 验证

用同一套 `tools/` 源码在 macOS 上编译，配合 `codec/av1d/libtxav1d/macosx/arm64/lib/libtxav1d.a` 解码 `test3.stream`，与官方 `txav1d` 工具比对：

- 前 10 帧 md5：`2c42a39ad7cd01a27a810a680f305324`（一致）
- 全量 7739 帧 md5：`74c92aa1c4cb50699908267366eb51dc`（一致）
- `-i file --muxer null --limit 300 --quiet` 调用返回 `7739`，为总帧数

真机端到端自测（iPhone 17 Pro Max，test3.stream 1920x1080 8bit 25fps）：

| 配置 | 单帧耗时 | 解码帧率 | 平均 CPU | 峰值内存 |
| --- | --- | --- | --- | --- |
| 自动线程 / 200 帧 | 2.8217 ms/f | 354.40 fps | 100.3% | 46.2 MB |
| 4 线程 / 400 帧 | 1.5779 ms/f | 640.17 fps | 193.7% | 79.9 MB |

4 线程时 CPU 从 100% 升到 193.7%，说明采样确实反映多核并发，而非恒定饱和。

## 解码器多版本切换

版本目录与选择变量：

```
TXAV1Dec/TXAV1Dec/DecoderSDK/
├── Version.xcconfig      # TXAV1D_VERSION = 1.4.3  ← 切换版本只改这一行
├── verify_decoder_sdk.sh # 构建期校验，版本不一致直接编译失败
├── 1.4.2/{include,lib}
└── 1.4.3/{include,lib}
```

切换步骤只有一步：改 `DecoderSDK/Version.xcconfig` 里的 `TXAV1D_VERSION`。头文件搜索路径、库搜索路径、`-ltxav1d` 链接参数都由 `Version.xcconfig` 派生，工程配置不用再动。切换后 `txav1d_version()` 会返回对应版本，界面「被测解码器版本」一栏和报告里的 `解码器:` 行都会自动填成实际链接的版本，不需要手改。

**为什么库和头文件必须整套切换**

`vcs_version.h` 里的 `TXAV1D_VERSION` 宏参与编译，而 `txav1d_core.c` 里有 `strcmp(txav1d_version(), TXAV1D_VERSION)` 校验。只换 `.a` 不换头文件，运行时会直接因版本不匹配而失败；反过来只换头文件也没意义，因为版本号来自库本身。

**构建期校验**

`verify_decoder_sdk.sh` 在编译前比对三处：目录名（即 `TXAV1D_VERSION`）、`vcs_version.h` 的宏、静态库里内嵌的版本字符串。任一处不一致就中止构建。这道校验针对的是「换库时只替换了 `.a` 却忘了同步目录名或头文件」这类静默错配，`txav1d_core.c` 的运行时校验覆盖不到目录名。

**新增一个版本**

1. 新建 `DecoderSDK/<新版本>/`，放入 `include/`（整套头文件）和 `lib/libtxav1d.a`
2. 把 `Version.xcconfig` 的 `TXAV1D_VERSION` 改成新版本号

不需要改 `project.pbxproj`。如果新版本的头文件有结构体布局变化，需要先确认 `DecoderTools/tools/txav1d_bench.c` 仍然兼容，否则测速代码要跟着调整。

**同条件对比结果（iPhone18,2 六核，test3 1080p，200 帧 × 2 轮）**

| 版本 | fps | ms/f | CPU 整机 | 波动% | P95 ms |
| --- | --- | --- | --- | --- | --- |
| 1.4.2 | 364.85 | 2.741 | 16.74% | 1.73 | 16.65 |
| 1.4.3 | 365.30 | 2.737 | 16.73% | 1.09 | 16.40 |

两个版本差异在噪声范围内（0.12%），符合「同一实现换版本号」的预期。这也说明构建期校验确实把正确的库链接了进来，否则不会得到几乎一致的数字。真正的性能变化要看后续包含实际优化的版本。
