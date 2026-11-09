#!/bin/sh
#
# build_decoder_dylibs.sh
# TXAV1Dec
#
# 把 DecoderSDK 下每个版本目录编成一个独立动态库，输出到 App 的 Frameworks。
#
# 为什么必须做成动态库：
# libtxav1d.a 各版本导出的全局符号几乎完全相同（实测 1.4.2 与 1.4.3 共 885 个
# 同名符号），静态链接进同一个 App 必然重定义冲突，所以「多版本共存」只能靠
# 动态库。每个 dylib 有独立的符号表与全局变量副本，天然互不干扰。
#
# 为什么把 bench 代码也编进 dylib：
# 如果 dylib 只装解码库、bench 逻辑留在 App 里，那么 App 就要直接持有
# Txav1dContext / Txav1dPicture 等库内部结构体，一旦新版本改了内存布局，
# 就会变成静默的野指针崩溃。把 bench 一起编进去之后，跨 dylib 边界传递的
# 只有 Txav1dBenchConfig / Txav1dBenchResult 这两个我们自己定义的结构体，
# 库内部怎么改都不会影响 App。
#
# 版本来源于目录名，且会与头文件宏、静态库内嵌版本串三者交叉校验：
# 版本号同时存在于目录名与 vcs_version.h 两处，换库漏改任一处都会造成
# 「目录写 A、实际跑 B」的静默错配，而这种错配从数据上完全看不出来。
#

set -e

SDK_DIR="${PROJECT_DIR}/TXAV1Dec/DecoderSDK"
TOOLS_DIR="${PROJECT_DIR}/TXAV1Dec/DecoderTools"
OUT_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ -z "${BUILT_PRODUCTS_DIR}" ] || [ -z "${FRAMEWORKS_FOLDER_PATH}" ]; then
  echo "error: 缺少 BUILT_PRODUCTS_DIR / FRAMEWORKS_FOLDER_PATH，本脚本必须在 Xcode 构建阶段中运行"
  exit 1
fi

if [ ! -d "${TOOLS_DIR}/tools" ]; then
  echo "error: 找不到 ${TOOLS_DIR}/tools，无法编译解码器动态库"
  exit 1
fi

mkdir -p "${OUT_DIR}"

SYSROOT="${SDKROOT}"
if [ ! -d "${SYSROOT}" ]; then
  SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
fi
CLANG="$(xcrun --sdk iphoneos --find clang)"
DEPLOY_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"

# bench 入口及其依赖的解封装/封装模块。故意不含 txav1d_core.c：
# 那条路径依赖 getopt 与 CLI 参数解析，测速用不上。
SOURCES="
${TOOLS_DIR}/tools/txav1d_bench.c
${TOOLS_DIR}/tools/input/input.c
${TOOLS_DIR}/tools/input/ivf.c
${TOOLS_DIR}/tools/input/section5.c
${TOOLS_DIR}/tools/input/annexb.c
${TOOLS_DIR}/tools/output/output.c
${TOOLS_DIR}/tools/output/null.c
${TOOLS_DIR}/tools/output/md5.c
${TOOLS_DIR}/tools/output/yuv.c
${TOOLS_DIR}/tools/output/y4m2.c
"

BUILT=0
FAILED=0

# 清掉上次构建残留：删掉版本目录后旧 dylib 不能继续留在包里，
# 否则界面上会出现一个已经不存在于源码树的版本。
rm -f "${OUT_DIR}"/libtxav1d_*.dylib

for version_dir in "${SDK_DIR}"/*/; do
  [ -d "${version_dir}" ] || continue
  version="$(basename "${version_dir}")"
  case "${version}" in
    .*|include|lib|tools|config|src) continue ;;
  esac

  inc="${version_dir}include"

  # 库文件名有两种：txav1d 系是 libtxav1d.a，上游 dav1d 是 libdav1d.a。
  # 按存在性选择，而不是按目录名猜 —— 目录名由人起，随时可能改成别的，
  # 文件名则是构建产物的固定约定。dav1d 目录里还带一层 txav1d/ 兼容头，
  # 那层负责把共用源码里的 txav1d_* 名字映射到 dav1d_*。
  if [ -f "${version_dir}lib/libtxav1d.a" ]; then
    lib="${version_dir}lib/libtxav1d.a"
  elif [ -f "${version_dir}lib/libdav1d.a" ]; then
    lib="${version_dir}lib/libdav1d.a"
  else
    # 还没放库的目录直接跳过，不算错误，方便先建目录后补文件
    echo "warning: 跳过 ${version}（缺少 lib/libtxav1d.a 或 lib/libdav1d.a）"
    continue
  fi

  vcs="${inc}/txav1d/vcs_version.h"
  if [ ! -f "${vcs}" ]; then
    echo "error: ${version} 缺少 include/txav1d/vcs_version.h，无法确定版本"
    FAILED=1
    continue
  fi

  # 目录名不再要求等于三点式版本号：dav1d 的目录叫 dav1d151，而版本串是 1.5.1。
  # 但仍然要求头文件里存在版本宏，且宏值必须能以压缩形式对上目录名里的数字，
  # 例如 dav1d151 ↔ "1.5.1"、txav1d143 ↔ "1.4.3"。
  # 这样换库漏改目录名时依然会中止构建，而不是安静地跑错版本。
  #
  # 注意这里不能用 sed 的 \(A\|B\) 交替：BSD sed（macOS 自带）不认这个语法，
  # 会静默匹配不到任何内容，表现成「头文件里没有版本宏」这种误导性报错。
  header_ver=""
  for macro in TXAV1D_VERSION DAV1D_VERSION; do
    v="$(sed -n "s/.*${macro}[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${vcs}" | head -1)"
    if [ -n "${v}" ]; then
      header_ver="${v}"
      break
    fi
  done
  if [ -z "${header_ver}" ]; then
    echo "error: ${version} 的 vcs_version.h 里没有版本宏"
    FAILED=1
    continue
  fi

  compact_header="$(printf '%s' "${header_ver}" | tr -d '.')"
  case "${version}" in
    # commit 命名（txav1d_4fe45527）：此时目录的身份是提交而不是版本号。
    # txav1d 仓库的版本宏长期停在 1.4.3 不跟提交走，几个相邻提交往往共用
    # 同一个版本串，用版本号反查目录必然失配，因此这类目录跳过数字比对，
    # 改由下面的「头文件声明 vs 静态库内嵌串」一致性来拦真正的错配。
    # SOURCE.txt 记录该目录对应的完整 commit，用于人工追溯。
    *_*[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *"${compact_header}") ;;
    *)
      echo "error: 版本不一致 —— 目录为 ${version}，但头文件声明 ${header_ver}"
      FAILED=1
      continue
      ;;
  esac

  # 静态库里内嵌的版本串就是 version() 的返回值，
  # 用它确认 .a 与头文件确实同源，而不是混了两个不同批次的产物。
  lib_ver="$(strings "${lib}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | head -1)"
  if [ -n "${lib_ver}" ] && [ "${lib_ver}" != "${header_ver}" ]; then
    echo "error: 版本不一致 —— 头文件声明 ${header_ver}，但静态库实际是 ${lib_ver}"
    FAILED=1
    continue
  fi

  # 版本目录下若有 src/*.c，说明这是需要额外适配源码的库（dav1d 的兼容层）。
  # 没有就为空，不影响 txav1d 那几个纯静态库版本。
  shim_sources=""
  if [ -d "${version_dir}src" ]; then
    for f in "${version_dir}"src/*.c; do
      [ -f "$f" ] && shim_sources="${shim_sources} $f"
    done
  fi

  out="${OUT_DIR}/libtxav1d_${version}.dylib"
  echo "note: 构建解码器动态库 ${version}（${lib##*/}${shim_sources:+ + shim}）"

  # shellcheck disable=SC2086
  "${CLANG}" -dynamiclib -arch arm64 \
    -target "arm64-apple-ios${DEPLOY_TARGET}" \
    -isysroot "${SYSROOT}" \
    -install_name "@rpath/libtxav1d_${version}.dylib" \
    -O2 -fPIC \
    -I"${inc}" -I"${inc}/txav1d" -I"${inc}/.." \
    -I"${TOOLS_DIR}" -I"${TOOLS_DIR}/tools" \
    -I"${TOOLS_DIR}/src" -I"${TOOLS_DIR}/config/ios" \
    -o "${out}" \
    ${SOURCES} ${shim_sources} \
    "${lib}"

  # 必须在这里单独签名：Frameworks 里由脚本产出的 dylib 不在 Xcode
  # 的签名单里，App 主签不会覆盖它，未签名会导致真机 dlopen 失败。
  # 显式给 -i：codesign 默认从文件名推导标识符，而
  # libtxav1d_1.4.2.dylib 与 libtxav1d_1.4.3.dylib 会被推导成同一个
  # 标识符 libtxav1d_1（遇到点号截断），两个不同版本共用一个签名标识
  # 会让审核与诊断信息难以区分。
  if [ "${CODE_SIGNING_ALLOWED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      --identifier "libtxav1d-${version}" \
      --timestamp=none "${out}"
  fi

  BUILT=$((BUILT + 1))
done

if [ "${FAILED}" -ne 0 ]; then
  echo "error: 存在无法构建的解码器版本，请修正后重试"
  exit 1
fi

if [ "${BUILT}" -eq 0 ]; then
  echo "error: DecoderSDK 下没有任何可用版本（需要 <版本>/lib/libtxav1d.a）"
  exit 1
fi

echo "note: 共构建 ${BUILT} 个解码器动态库"
