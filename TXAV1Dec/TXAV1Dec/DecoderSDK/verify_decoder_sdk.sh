#!/bin/sh
#
# verify_decoder_sdk.sh
# TXAV1Dec
#
# 校验「版本目录名 / 头文件版本宏 / 静态库真实版本」三者一致。
#
# 为什么需要这一步：
# libtxav1d 的版本号同时存在于两处 —— 目录名（DecoderSDK/<版本>/）和
# include/txav1d/vcs_version.h 的 TXAV1D_VERSION 宏。换库时若只替换了
# lib/libtxav1d.a 而漏改目录名或头文件，就会得到「目录写 1.4.2、实际是 1.4.3」
# 的静默错配。txav1d_core.c 里的 strcmp 只在运行时比对头文件与库，
# 管不到目录名，而且如果两头都没更新，连它也不会报错。
#
# 这类错配的后果是数据被标错版本却完全看不出来，所以放在编译期拦掉。
#

set -e

SDK_DIR="${PROJECT_DIR}/TXAV1Dec/DecoderSDK/${TXAV1D_VERSION}"
VCS_H="${SDK_DIR}/include/txav1d/vcs_version.h"
LIB_A="${SDK_DIR}/lib/libtxav1d.a"

if [ -z "${TXAV1D_VERSION}" ]; then
  echo "error: TXAV1D_VERSION 未设置，请检查 DecoderSDK/Version.xcconfig"
  exit 1
fi

if [ ! -f "${VCS_H}" ]; then
  echo "error: 找不到头文件 ${VCS_H}"
  echo "       请确认 DecoderSDK/${TXAV1D_VERSION}/ 目录存在，与 Version.xcconfig 的 TXAV1D_VERSION 一致"
  exit 1
fi

if [ ! -f "${LIB_A}" ]; then
  echo "error: 找不到静态库 ${LIB_A}"
  exit 1
fi

# 头文件里声明的版本
HEADER_VER=$(sed -n 's/.*TXAV1D_VERSION[[:space:]]*"\([^"]*\)".*/\1/p' "${VCS_H}" | head -1)

if [ "${HEADER_VER}" != "${TXAV1D_VERSION}" ]; then
  echo "error: 版本不一致"
  echo "       目录/变量: ${TXAV1D_VERSION}"
  echo "       头文件声明: ${HEADER_VER}"
  exit 1
fi

# 静态库里内嵌的版本字符串（txav1d_version() 的返回值来源）
LIB_VER=$(strings "${LIB_A}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | head -1)

if [ -n "${LIB_VER}" ] && [ "${LIB_VER}" != "${TXAV1D_VERSION}" ]; then
  echo "error: 版本不一致"
  echo "       目录/变量: ${TXAV1D_VERSION}"
  echo "       静态库实际: ${LIB_VER}"
  exit 1
fi

echo "note: 解码器 SDK 版本校验通过 (${TXAV1D_VERSION})"
