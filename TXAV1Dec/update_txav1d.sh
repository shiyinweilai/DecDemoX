#!/bin/bash
# update_txav1d.sh — 拉取 txav1d 源码、编译 iOS arm64 静态库、装配进 DecoderSDK
#
# 用法：
#   ./update_txav1d.sh                                  # 默认 origin/master_speed
#   ./update_txav1d.sh origin/at_rbyang/fixed           # 指定分支
#   ./update_txav1d.sh 394951a8                         # 指定 commit
#   ./update_txav1d.sh origin/master_speed --prune      # 同时清掉其它 txav1d_* 目录
#
# 这个脚本把四个必须做对、但很容易漏掉的步骤固化下来：
#   1. 用 git worktree 在独立目录里编译，不污染主仓库工作区；
#   2. cmake_build.py 不拷贝 include/common，必须手工补 attributes.h / intops.h，
#      否则后续编 dylib 时 input.c / output.c 会报 'common/attributes.h' not found；
#   3. 目录名用 txav1d_<commit前8位>，因为 txav1d 的版本宏长期停在 1.4.3，
#      多个提交版本串完全相同，用版本号命名分不清谁是谁；
#   4. 写 SOURCE.txt 记录完整 commit，否则过几天没人知道这个目录是哪份代码。
#
# 装配完还要回 Xcode 编一次 App：dylib 是 build_decoder_dylibs.sh 在 Xcode
# 构建阶段生成的，不重新编 App 就不会进包。

set -euo pipefail

SRC_REPO="/Users/rbyang/Documents/UGit/codec/av1d"
SDK_DIR="/Users/rbyang/Documents/UGit/private/DecDemoX/TXAV1Dec/TXAV1Dec/DecoderSDK"
WORK_ROOT="/Users/rbyang/Documents/UGit/codec"

REF="${1:-origin/master_speed}"
PRUNE=0
[ "${2:-}" = "--prune" ] && PRUNE=1

[ -d "$SRC_REPO" ] || { echo "error: 找不到源码仓库 $SRC_REPO"; exit 1; }
[ -d "$SDK_DIR" ]  || { echo "error: 找不到 DecoderSDK $SDK_DIR"; exit 1; }

cd "$SRC_REPO"

echo "=== 1/5 拉取远程更新 ==="
git fetch origin --prune

echo "=== 2/5 解析 $REF ==="
SHA=$(git rev-parse --verify "${REF}^{commit}")
SHORT=$(printf '%s' "$SHA" | cut -c1-8)
DIR_NAME="txav1d_${SHORT}"
echo "    commit : $SHA"
echo "    目录名 : $DIR_NAME"
git log -1 --format='    date   : %ad%n    subject: %s' --date=short "$SHA"

echo "=== 3/5 创建独立 worktree ==="
WT="${WORK_ROOT}/_wt_update"
git worktree remove --force "$WT" 2>/dev/null || true
rm -rf "$WT"
git worktree add --detach "$WT" "$SHA" >/dev/null
echo "    $WT @ $(cd "$WT" && git rev-parse --short HEAD)"

echo "=== 4/5 编译 iOS arm64 静态库（约 3 分钟）==="
cd "$WT"
python3 cmake_build.py -s IOS -a arm64 -t Release > /tmp/txav1d_update_build.log 2>&1 || {
  echo "error: 编译失败，日志尾部："
  tail -30 /tmp/txav1d_update_build.log
  exit 1
}
LIB="${WT}/libtxav1d/ios/arm64/lib/libtxav1d.a"
[ -f "$LIB" ] || { echo "error: 未生成 $LIB"; exit 1; }
echo "    libtxav1d.a  $(stat -f%z "$LIB") 字节  md5=$(md5 -q "$LIB")"

echo "=== 5/5 装配到 DecoderSDK ==="
if [ "$PRUNE" = "1" ]; then
  for old in "$SDK_DIR"/txav1d_*; do
    [ -d "$old" ] || continue
    [ "$(basename "$old")" = "$DIR_NAME" ] && continue
    bk="/tmp/txav1d_prune_$(date +%Y%m%d%H%M%S)_$(basename "$old")"
    cp -R "$old" "$bk"
    rm -rf "$old"
    echo "    已删除 $(basename "$old")（备份 $bk）"
  done
fi

DST="${SDK_DIR}/${DIR_NAME}"
rm -rf "$DST"
mkdir -p "$DST/lib" "$DST/include/common"
cp "$LIB" "$DST/lib/"
cp -R "${WT}/libtxav1d/ios/arm64/include/txav1d" "$DST/include/"
cp "${WT}/include/common/attributes.h" "${WT}/include/common/intops.h" "$DST/include/common/"
{
  printf 'ref    %s\n' "$REF"
  printf 'commit %s\n' "$SHA"
  git log -1 --format='date   %ad%nsubject %s' --date=short "$SHA"
} > "$DST/SOURCE.txt"
echo "    已装配 $DST"

echo "=== 清理 worktree ==="
cd "$SRC_REPO"
git worktree remove --force "$WT" 2>/dev/null || true
git worktree prune

echo
echo "完成。接下来手动做两件事："
echo "  1. 回 Xcode 编译 App（或 xcodebuild），构建脚本会把 $DIR_NAME 编成 dylib；"
echo "  2. 签名打包："
echo "     - 云真机 / 任意设备（企业 In-House 签名，免 UDID）："
echo "         ~/Documents/UGit/rbyang/DecoderX/scripts/ks_sign.sh <未签名.ipa> [输出目录]"
echo "     - 只装自己手机（Development 证书，profile 需含该机 UDID）："
echo "         ./sign_ipa.sh <产物>/TXAV1Dec.app <输出>.ipa"
