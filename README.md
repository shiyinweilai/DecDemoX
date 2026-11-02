# TXAV1Dec

基于 txav1d（AV1 解码器）的 iOS 演示工程，把 txav1d 的 CLI 工具链裁剪进 App，演示在 iOS 上解码 AV1 视频。

工程内的解码库与源码全部来自参考仓库 `/Users/rbyang/Documents/UGit/codec/av1d/`，命名统一为 `txav1d` 前缀。

## 目录结构

```
DecDemoX/
├── .gitignore                     # 忽略 Xcode 用户数据、构建产物、系统垃圾文件
├── .gitattributes                 # 声明 .a 为二进制，避免换行符转换
└── TXAV1Dec/
    ├── TXAV1Dec.xcodeproj/
    │   ├── project.pbxproj
    │   └── xcshareddata/xcschemes/TXAV1Dec.xcscheme   # 共享 scheme（可直接 -scheme 构建）
    └── TXAV1Dec/
        ├── AppDelegate.{h,m} / SceneDelegate.{h,m} / main.m
        ├── ViewController.{h,mm}      # 入口，调用 txav1d_lanuch() 启动解码
        ├── source/txav1d.{h,mm}       # 自定义 UIPickerView 控件
        ├── Assets.xcassets / Base.lproj / Info.plist / TXAV1Dec.entitlements
        └── libtxav1d_arm64/           # txav1d 的 iOS 集成目录
            ├── include/
            │   ├── txav1d/            # 公共头文件（txav1d.h / picture.h / data.h 等）
            │   └── common/            # CLI 源码依赖的 attributes.h、intops.h
            ├── src/                   # cpu.h、arm/cpu.h（CPU 特性检测声明）
            ├── config/ios/            # config.h、cli_config.h（等价 Meson 生成物）
            ├── tools/
            │   ├── txav1d_core.{c,h}  # App 入口 txav1d_lanuch()
            │   ├── txav1d_cli_parse.{c,h}
            │   ├── input/             # 解封装：ivf / section5 / annexb
            │   └── output/            # 封装：md5 / yuv / yuv4mpeg2 / null
            └── lib/libtxav1d.a        # 解码静态库（arm64, iphoneos）
```

## 关键说明

`libtxav1d_arm64` 在 Xcode 中是「文件夹自动同步组」（`PBXFileSystemSynchronizedRootGroup`），目录下所有源文件会自动参与编译、所有 `.a` 会被自动 `-l` 链接。因此该目录需要保持精简，只放真正需要的实现，新增文件无需手动改 pbxproj。

`tools/txav1d_core.c` 里的 `txav1d_lanuch()` 是 App 的入口函数，内部调用带 `txav1d_` 前缀的解码 API（`txav1d_open` / `txav1d_send_data` / `txav1d_get_picture` / `txav1d_close` 等），并复用 txav1d CLI 的参数解析、解封装与封装逻辑。函数返回值不是进程退出码，而是输入流报告的总帧数，供 App 计算 mspf。

`source/txav1d.h` 是与解码库无关的自定义 UI 控件（`MyPickerView`），因与库头文件 `include/txav1d/txav1d.h` 同名，App 侧改用 `#import "source/txav1d.h"` 显式相对路径引用，避免头文件映射冲突。

`config/ios/` 下两个头文件替代 Meson 自动生成物：`config.h` 声明 `ARCH_AARCH64=1`、`HAVE_CLOCK_GETTIME=1` 等平台宏；`cli_config.h` 关闭 `HAVE_XXHASH_H`，因此未引入 `xxhash.c`，`output.c` 也不会注册 md5 以外的 xxh3 封装。

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
- 解码库与头文件版本必须一致（当前 1.4.2），版本不匹配时 `txav1d_lanuch()` 会直接返回失败

## 验证

用同一套 `tools/` 源码在 macOS 上编译，配合 `codec/av1d/libtxav1d/macosx/arm64/lib/libtxav1d.a` 解码 `test3.stream`，与官方 `txav1d` 工具比对：

- 前 10 帧 md5：`2c42a39ad7cd01a27a810a680f305324`（一致）
- 全量 7739 帧 md5：`74c92aa1c4cb50699908267366eb51dc`（一致）
- `-i file --muxer null --limit 300 --quiet` 调用返回 `7739`，为总帧数

## 上游库更新

`lib/libtxav1d.a` 与 `include/txav1d/*.h` 来自参考仓库 `libtxav1d/ios/arm64/`。若重新编译库，需要同步更新这两处，并确认 `vcs_version.h` 中的版本号与库一致，否则运行时版本校验会失败。
