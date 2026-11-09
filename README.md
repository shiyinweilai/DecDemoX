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
        ├── DecoderSDK/                # 解码器版本快照，按目录名分版本
        │   ├── Version.xcconfig       # 头文件路径派生（不再选择版本）
        │   ├── build_decoder_dylibs.sh # 构建期把每个版本编成独立动态库
        │   ├── txav1d_c01c1623/       # txav1d 自研版，目录名取 commit 前 8 位
        │   │   ├── include/           # 公共头文件（txav1d.h / picture.h / vcs_version.h 等）
        │   │   ├── lib/libtxav1d.a    # 该版本的静态库（arm64, iphoneos）
        │   │   └── SOURCE.txt         # 记录来源 commit，便于回溯
        │   └── dav1d155/              # 上游 dav1d，与 txav1d 不是同一套 API
        │       ├── include/dav1d/     # 上游公共头
        │       ├── include/txav1d/    # 兼容层：把 txav1d_* 映射到 dav1d_*
        │       ├── src/txav1d_shim.c  # 兼容层里需要真实包装的两个函数
        │       └── lib/libdav1d.a
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
- 解码库与头文件版本必须一致，版本不匹配时解码入口会直接返回失败。构建期会做这项校验，目录名、头文件宏、库内嵌版本串三者必须指向同一版本

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

## 解码器多版本

界面上的「解码器版本（可多选）」与码流选择是同一套交互：点开弹出列表，勾选一个或多个版本。**版本列表直接来自 `DecoderSDK` 下的子目录名**，新增版本只需放一个目录并重新编译，界面自动多出一项，不需要改任何代码。

目录名就是界面上显示的版本标识，目前有两项：

```
TXAV1Dec/TXAV1Dec/DecoderSDK/
├── txav1d_c01c1623/{include, lib/libtxav1d.a, SOURCE.txt}
├── dav1d155/{include, src, lib/libdav1d.a}
├── Version.xcconfig            # 头文件与路径派生
└── build_decoder_dylibs.sh     # 构建期把每个版本编成独立动态库
```

目录名不必是三点式版本号。构建脚本会从头文件的 `TXAV1D_VERSION` / `DAV1D_VERSION` 宏取出真实版本串，再与目录名里的数字做压缩比对：`dav1d155` ↔ `"1.5.5"`、`txav1d143` ↔ `"1.4.3"` 都算一致。这样换库漏改目录名时仍会中止构建，而不会安静地跑错版本。以 commit 命名的目录（如 `txav1d_c01c1623`）则跳过数字比对，因为 txav1d 的版本宏长期停在 1.4.3 不跟提交走，改用「静态库内嵌版本串与头文件声明是否一致」来拦真正的错配，目录对应的完整 commit 记在同目录的 `SOURCE.txt`。

两个现存版本来自不同代码线，数值不可直接比较：`txav1d_c01c1623` 是 txav1d 自研分支（`master_speed` 的 `c01c1623`，版本宏 1.4.3，带 `use_wpp` 私有扩展），`dav1d155` 是上游 VideoLAN dav1d 的 1.5.5，经兼容层把 `dav1d_*` 映射到 `txav1d_*`。前者代表自研优化方向，后者是对齐官方基线的参照物。

### 解码器的惰性加载

启动路径只做目录扫描（`BenchDecoderLibrary scanDecoders`），读版本名与文件修改时间，不执行 `dlopen`。真正的加载推迟到点「开始测试」时，由引擎在后台队列对**被勾选的版本**逐个 `loadIfNeeded`。

这样拆分的原因是启动成本：早先 `availableDecoders` 把「枚举有哪些版本」和「把库加载进来」揉在一起，界面一出现就要把所有版本全部 `dlopen(RTLD_NOW)` 一遍；而 `BenchRunConfig` 的 `init` 为了填一个解码器名字段，还会顺着 `preferredDecoder` 把整套流程再走一遍，两轮下来十几 MB 的库被反复加载又卸载，其中绝大多数最终用不上。

由此带来的行为约定：

- 界面上未勾选的版本不会被加载，内存占用按需增长而非固定常驻。
- 版本列表里「不可用」的判断只在**已尝试加载**后成立；未加载的版本一律可勾选，因为此刻无从判断好坏。加载失败会在开始测试时以弹窗告知具体原因，不会静默跳过。
- `BenchRunConfig` 的初始化是纯内存操作，不再有 I/O 或动态库加载副作用；`decoderName` 留空，由引擎在 `dlopen` 成功后回填，这样「库自报版本与目录名是否一致」这项交叉校验才不会丢失。
- `availableDecoders` 仍然保留，语义是「扫描并全部加载」，仅供确需全量已知可用性的场景（如自测全版本覆盖）使用，界面启动路径不得调用。

### 接入上游 dav1d

`dav1d155` 是上游 VideoLAN dav1d 的 1.5.5，它与 txav1d 有两个实质差异：

- **API 前缀不同**：上游是 `dav1d_` / `Dav1d`，txav1d 是 `txav1d_` / `Txav1d`。
- **`Dav1dSettings` 没有 `use_wpp`**：那是 txav1d 的私有扩展，上游没有对应开关。

上游 1.5.x 各版本的 `Dav1dSettings` 字段与顺序相同，`DAV1D_API_VERSION` 均为 7.0.0，公开头文件差异只在内联注释格式，因此共用同一套兼容层，只有版本号不同。将来再接入 1.5.x 的其它 tag 时，直接复用现有兼容层即可。

工程没有为此复制一份 tools 源码，而是在 `<版本>/include/txav1d/` 下放了一层名字映射头：共用源码原样编译，`txav1d_open`、`Txav1dPicture` 等由宏解析到 `dav1d_*` / `Dav1d*`。真正需要包装的只有 `txav1d_default_settings` 与 `txav1d_open` 两个（因为设置结构体多了 `use_wpp`，必须逐字段搬运），实现放在 `<版本>/src/txav1d_shim.c`。

这样共用代码路径始终只有一份。若复制源码改名，将来每加一个解码器族都要再复制一次，迟早出现「改了一份漏了另一份」的静默错配。

### 自己接入一个新版本

新增 txav1d 版本不需要改任何代码，只有文件搬运和一次编译。以 `txav1d_c01c1623` 为例：

```
# 1. 建目录并放入产物（目录名决定界面上的版本标识）
cd TXAV1Dec/TXAV1Dec/DecoderSDK
mkdir -p txav1dNNNNNNNN/lib txav1dNNNNNNNN/include
cp <产物>/lib/libtxav1d.a            txav1dNNNNNNNN/lib/
cp -R <产物>/include/*               txav1dNNNNNNNN/include/

# 2. 补上 common/ 头（共用 bench 源码依赖它，产物包通常不带）
cp <源码>/include/common/{attributes,intops}.h  txav1dNNNNNNNN/include/common/

# 3. 记录来源 commit（便于日后回溯是哪份代码）
printf 'ref    %s\ncommit %s\n' <ref> <完整commit> > txav1dNNNNNNNN/SOURCE.txt

# 4. 直接 Xcode 编译即可，构建脚本会自动发现并产出 libtxav1d_txav1dNNNNNNNN.dylib
```

三个容易踩的点：

- **目录命名有两种模式，校验规则不同**。用三点式版本号命名（如 `txav1d143`）时，构建脚本会交叉校验目录名数字、`include/txav1d/vcs_version.h` 的宏、静态库里 `strings` 出来的版本串，三者对不上就中止构建。用 commit 前 8 位命名（如 `txav1d_c01c1623`）时跳过目录名比对，因为 txav1d 的版本宏长期停在 1.4.3 不跟提交走，此时靠「头文件声明与静态库内嵌串是否一致」来拦真正的错配。这是故意设计的：换库漏改目录名会造成「界面写 A、实际跑 B」，而这种错配从性能数据上完全看不出来。
- **`common/` 不能忘**。它是 `DecoderTools` 共用源码的编译依赖，库的发布包里通常没有这一层，缺了会在编译 dylib 时报找不到 `common/attributes.h`。
- **版本串可能和你想的不一样**。txav1d 的版本号写在 `CMakeLists.txt` 的 `TXAV1D_API_VERSION_*` 里，由 `python cmake_build.py -v X.Y.Z` 同步到各处；只更新 `src/` 而不升版本号，产物内嵌的仍是旧版本串。给库起目录名前先跑一次 `strings libtxav1d.a | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'` 确认它自报的版本。

接入完成后建议跑一次全版本自测确认新库真能解出数据：

```
xcrun devicectl device process launch --device <UDID> --terminate-existing <bundleID> \
  -- --selftest --all-decoders --frames 30 --rounds 1
```

日志写在 App 容器 `Documents/selftest.log`，用 `devicectl device copy from` 取回。

`use_wpp` 在 dav1d 侧固定填 -1 并忽略任何非 -1 值，因为上游始终启用 WPP。若填 0，共用源码会以为「已关闭」，报告里就会写下与实际不符的配置。

上游库的版本串由 `git describe` 生成，直接构建会得到 commit hash 而不是 `1.5.1`。做法是拷贝源码到无 `.git` 的目录再构建，`vcs_tag` 便回退到 `project()` 里声明的版本号：

```bash
meson setup <build> --cross-file package/crossfiles/arm64-iPhoneOS.meson \
  --default-library=static -Denable_tools=false -Denable_tests=false \
  -Denable_examples=false -Denable_asm=true -Dbitdepths=8,16 --buildtype=release
ninja -C <build>
```

### 为什么必须编成动态库

`libtxav1d.a` 各版本导出的全局符号几乎完全相同——实测 1.4.2 与 1.4.3 有 **885 个同名符号**。静态链接进同一个 App 必然重定义冲突。所以「一个 App 内同时测多个版本」在技术上只有动态库一条路：每个版本编成一个 dylib，符号表与全局变量各自独立，互不干扰。

加载使用 `RTLD_LOCAL` 而非默认的 `RTLD_GLOBAL`。这一点很关键：RTLD_GLOBAL 会把符号并入全局符号表，第二个版本加载时其内部调用可能被第一个版本的同名符号抢先解析，结果两个「不同版本」实际共用同一份全局变量，测出来的数据自相矛盾且极难发现。

### bench 代码也被编进 dylib

`txav1d_bench` 及其 demux/mux 依赖全部编进每个 dylib，而不是留在 App 里。这样跨 dylib 边界传递的只有 `Txav1dBenchConfig`、`Txav1dBenchResult` 这两个我们自己定义的结构体，App 完全不接触 `Txav1dContext`、`Txav1dPicture` 等库内部结构体。将来新版本改了内部内存布局，也不会造成 App 侧野指针崩溃。

`Txav1dBenchResult.frame_ms` 由 dylib 内部 malloc 分配，必须由同一个库释放，所以释放走 `[decoder freeBenchResult:]` 而不是 App 侧 free。

### 测试与报告

勾选 N 个版本、M 个码流时，会展开成 N×M 个组合依次执行（外层版本、内层码流），互不中断。报告包含三部分：

- **对比表**：每个「版本 × 码流」一行，列出 fps、ms/f、CPU%、波动%、P95、净内存
- **跨版本提升**：以最旧版本为基准，算出各版本在同一码流上的 fps 与 CPU 变化百分比；变化幅度在测量波动内标为「持平」
- **逐组合明细**：每个组合的完整指标

单个组合失败不会中断整批，失败信息会带上版本号，便于定位是哪个版本的问题。

### 新增一个版本

1. 新建 `DecoderSDK/<名字>/`，放入 `include/`（整套头文件）和 `lib/`
2. 库文件名按来源取：txav1d 系用 `libtxav1d.a`，上游 dav1d 用 `libdav1d.a`，脚本按存在性自动识别
3. 直接编译

构建脚本会校验三处一致：目录名里的数字、`vcs_version.h` 的版本宏、静态库内嵌的版本串。任一处不符即中止构建。版本号同时存在于目录名和头文件两处，换库时漏改会造成「目录写 A、实际跑 B」的静默错配，而这种错配从数据上完全看不出来。

唯一的例外是 commit 命名（`txav1d_` + 8 位十六进制）：这类目录跳过目录名比对，改由「头文件宏与静态库内嵌串一致」把关，并在 `SOURCE.txt` 里记下完整 commit。自研分支的版本宏不跟提交走，多个提交共用同一个版本串，所以只能用 commit 区分身份。

若新版本来自与 txav1d API 不同的分支（如上游 dav1d），需要在该版本目录的 `include/txav1d/` 下放一层名字映射头，并把无法用宏表达的适配实现在 `src/` 里，脚本会自动把它一起编进 dylib。

单个版本加载失败不会影响其他版本，界面会把它标为不可用并显示原因。

### 实测结果（云真机 iPhone18,2 六核 2P+4E，test3 1920×1080，60 帧）

两个版本在同一 App 内同时加载，各自报告正确版本号并独立解码：

| 版本 | fps | ms/f | 帧率倍速 | CPU 整机占比 | 内存峰值 |
| --- | --- | --- | --- | --- | --- |
| dav1d155 | 941.53 | 1.0621 | 37.661x | 64.06% | 93 MB |
| txav1d_c01c1623 | 1076.78 | 0.9287 | 43.071x | 81.84% | 101.44 MB |

txav1d_c01c1623 相对 dav1d155 快约 14.4%，代价是多消耗约 17.8 个百分点的 CPU 整机占比、多占约 8.4 MB 内存。

这组数据的采集设备是 WeTest 云真机 `00008160-00127CD83C400036`（iPhone 18 Pro / iOS 27.0），属于同批内顺序执行，两版本之间仍存在先后带来的热状态差异。若要严格量化版本差异，应反序再跑一轮，或对同一版本重复多批观察轮间波动。
