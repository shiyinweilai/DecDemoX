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

  lib="${version_dir}lib/libtxav1d.a"
  inc="${version_dir}include"
  vcs="${inc}/txav1d/vcs_version.h"

  # 还没放库的目录直接跳过，不算错误，方便先建目录后补文件
  if [ ! -f "${lib}" ]; then
    echo "warning: 跳过 ${version}（缺少 lib/libtxav1d.a）"
    continue
  fi
  if [ ! -f "${vcs}" ]; then
    echo "error: ${version} 缺少 include/txav1d/vcs_version.h，无法确定版本"
    FAILED=1
    continue
  fi

  header_ver="$(sed -n 's/.*TXAV1D_VERSION[[:space:]]*"\([^"]*\)".*/\1/p' "${vcs}" | head -1)"
  if [ "${header_ver}" != "${version}" ]; then
    echo "error: 版本不一致 —— 目录为 ${version}，但头文件声明 ${header_ver}"
    FAILED=1
    continue
  fi

  # 静态库里内嵌的版本串就是 txav1d_version() 的返回值，
  # 用它确认 .a 与头文件确实同源，而不是混了两个不同批次的产物。
  lib_ver="$(strings "${lib}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | head -1)"
  if [ -n "${lib_ver}" ] && [ "${lib_ver}" != "${version}" ]; then
    echo "error: 版本不一致 —— 目录为 ${version}，但静态库实际是 ${lib_ver}"
    FAILED=1
    continue
  fi

  out="${OUT_DIR}/libtxav1d_${version}.dylib"
  echo "note: 构建解码器动态库 ${version}"

  # shellcheck disable=SC2086
  "${CLANG}" -dynamiclib -arch arm64 \
    -target "arm64-apple-ios${DEPLOY_TARGET}" \
    -isysroot "${SYSROOT}" \
    -install_name "@rpath/libtxav1d_${version}.dylib" \
    -O2 -fPIC \
    -I"${inc}" -I"${inc}/txav1d" \
    -I"${TOOLS_DIR}" -I"${TOOLS_DIR}/tools" \
    -I"${TOOLS_DIR}/src" -I"${TOOLS_DIR}/config/ios" \
    -o "${out}" \
    ${SOURCES} \
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
