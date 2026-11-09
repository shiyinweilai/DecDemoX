#!/bin/bash
# sign_ipa.sh — 把未签名的 TXAV1Dec.app 手动签成「有效签名」的 ipa
#
# ⚠️ 场景已收窄：本脚本用本机 Apple Development 证书 + Development 描述文件签名，
#    profile 里带 ProvisionedDevices 白名单，只能装到白名单内的设备（目前仅你自己的手机）。
#    装到云真机等其它设备会报 0xe8008015。云真机 / 任意设备请改用企业签名脚本：
#        ~/Documents/UGit/rbyang/DecoderX/scripts/ks_sign.sh <未签名.ipa> [输出目录]
#
# 有效签名的 4 个要件，缺一不可：
#   1. 每个 Mach-O（主可执行 + Frameworks 下所有 dylib）都有 codesign 签名
#   2. .app 内有 embedded.mobileprovision
#   3. 签名用的私钥与 provision 里 DeveloperCertificates 的公钥匹配
#   4. provision 覆盖目标设备的 UDID（或 ProvisionsAllDevices=true），entitlements 与 provision 一致
#
# 用法：
#   ./sign_ipa.sh <未签名.app> <输出.ipa> [mobileprovision]
# 不传 profile 时自动取 Xcode UserData 里 dev.rbyang.com 的 Team Provisioning Profile。
#
# 注意：Development profile 只绑定了指定设备 UDID。要装到别的设备（例如云真机
# 00008160-00127CD83C400036），必须先在 developer.apple.com 把该 UDID 注册进
# profile 并重新下载，否则设备会报 0xe8008015 / "device not in provision"。

set -euo pipefail

APP="${1:?用法: sign_ipa.sh <.app> <out.ipa> [mobileprovision]}"
OUT="${2:?缺少输出 ipa 路径}"
PROV="${3:-}"

# 证书：必须是在钥匙串里带私钥的那个 identity
IDENTITY="Apple Development: 739277193@qq.com (XZRJM4K9T8)"

if [ -z "$PROV" ]; then
  PROVDIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  # 优先挑名字含 dev.rbyang.com 且未过期的 profile
  for p in "$PROVDIR"/*.mobileprovision; do
    [ -f "$p" ] || continue
    if security cms -D -i "$p" 2>/dev/null | grep -q "dev.rbyang.com"; then
      EXP=$(security cms -D -i "$p" 2>/dev/null | \
            python3 -c "import sys,re;d=sys.stdin.read();m=re.search(r'ExpirationDate.*?<date>([^<]+)',d,re.S);print(m.group(1) if m else '')")
      echo "[profile] 候选 $(basename "$p")  过期: $EXP"
      PROV="$p"
    fi
  done
fi
[ -f "$PROV" ] || { echo "error: 找不到 mobileprovision，请显式传入第 3 个参数"; exit 1; }
echo "[profile] 使用: $PROV"

# 1) 从 provision 导出 entitlements（不要手写，必须和 provision 完全一致）
ENT=$(mktemp /tmp/ent.XXXXXX.plist)
python3 - "$PROV" "$ENT" <<'PY'
import plistlib, subprocess, sys
raw = subprocess.check_output(["security", "cms", "-D", "-i", sys.argv[1]])
d = plistlib.loads(raw)
ent = d.get("Entitlements", {})
plistlib.dump(ent, open(sys.argv[2], "wb"))
print("[entitlements] " + ", ".join(ent.keys()))
PY

# 2) 自内向外签：先签所有 dylib / framework，再签主 bundle
find "$APP" -type f \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null | while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  echo "[sign] $f"
  codesign --force --sign "$IDENTITY" --timestamp=none "$f"
done

# Frameworks 目录下的动态库
if [ -d "$APP/Frameworks" ]; then
  find "$APP/Frameworks" -type f -perm +111 -print0 | while IFS= read -r -d '' f; do
    echo "[sign] $f"
    codesign --force --sign "$IDENTITY" --entitlements "$ENT" --timestamp=none "$f"
  done
fi

# 3) 放入 embedded.mobileprovision（签名前放，会被 seal 进 CodeResources）
cp "$PROV" "$APP/embedded.mobileprovision"

# 4) 签主 bundle
echo "[sign] 主 bundle $APP"
codesign --force --sign "$IDENTITY" --entitlements "$ENT" \
         --timestamp=none --generate-entitlement-der "$APP"

# 5) 验证
echo "=== 验证签名 ==="
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -10
echo "--- 签名摘要 ---"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature|Authority|Expiration" | head -8
echo "--- provision 绑定的设备 ---"
security cms -D -i "$PROV" 2>/dev/null | sed -n '/ProvisionedDevices/,/\/array/p' | head -10

# 6) 打成 ipa
STAGE=$(mktemp -d /tmp/ipa.XXXXXX)
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
(cd "$STAGE" && zip -qr -X "$OUT" Payload)
rm -rf "$STAGE" "$ENT"
echo "=== 完成: $OUT ($(du -h "$OUT" | cut -f1)) ==="
