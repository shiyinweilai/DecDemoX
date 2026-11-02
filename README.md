# TXAV1Dec

基于 libav1d（AV1 解码器）的 iOS 演示工程，把 libav1d 的 CLI 工具链裁剪进 App，演示在 iOS 上解码 AV1 视频。

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
        └── libtxav1d_arm64/           # libav1d 的 iOS 集成目录
            ├── include/               # av1d 公共头文件（av1d/、common/）
            ├── src/arm_cpu.h
            ├── tools/                 # libav1d CLI 工具源码（av1d.cpp 提供 txav1d_lanuch）
            └── lib/libav1d.a          # 唯一的解码静态库（arm64, iphoneos）
```

## 关键说明

`libtxav1d_arm64` 在 Xcode 中是「文件夹自动同步组」（`PBXFileSystemSynchronizedRootGroup`），目录下所有源文件会自动参与编译、所有 `.a` 会被自动 `-l` 链接。因此该目录需要保持精简，只放真正需要的实现。

`tools/av1d.cpp` 里的 `txav1d_lanuch()` 是 App 的入口函数，它内部调用带 `av1d_` 前缀的 libav1d C API。库文件中只有 `libav1d.a` 导出这套无前缀符号，其余库均不匹配：

- `libav1d2.a` — 与 `libav1d.a` 符号集合完全相同（同符号重复，机器码略有差异），已移除
- `libtxav1d.a` — 导出 `txav1d_` 前缀的符号，与源码调用不匹配，已移除
- `libtxav1d3.a` — x86_64 架构（macOS），在 arm64 iOS 目标下无效，已移除

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

## 备份

清理过程中移除的静态库已备份到仓库外目录 `../DecDemoX_cleanup_backup_20261102/lib_backup/`，如需恢复可直接复制回 `libtxav1d_arm64/lib/`。
