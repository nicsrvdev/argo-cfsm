#!/bin/bash
# ============================================================================
# build-image.sh — 构建带变量的私有部署镜像 (一键)
# 用法:
#   bash build-image.sh <镜像名> '<变量JSON>'
#   例: bash build-image.sh koyeb-cfs \
#        '{"CFP_ID":"xxx","CFP_SECRET":"yyy","CFP_URL":"https://.../update",\
#          "CFP_CT":"host:port","CFP_CU":"...","CFP_CM":"...","CFP_BD":"...",\
#          "ARGO_AUTH":"eyJ...","ARGO_DOMAIN":"a.b.c"}'
#
#   # 也可从文件读取变量(避免命令行暴露,推荐):
#   bash build-image.sh koyeb-cfs @/tmp/koyeb-vars.json
#
# 行为:
#   1. 取本仓库干净源码 index-src.js(无变量)
#   2. 内嵌变量 -> 容器安全混淆(无明文)
#   3. 构建 ghcr.io/nicsrvdev/<镜像名>:latest
#   4. 推送 GHCR 并设为 public
#   5. 清理临时进程/文件, 输出镜像地址
# ============================================================================
set -euo pipefail

IMAGE_NAME="${1:?用法: build-image.sh <镜像名> '<变量JSON>' 或 @文件}"
VARS_ARG="${2:?缺失变量参数}"

GHCR_IMAGE="ghcr.io/nicsrvdev/${IMAGE_NAME}:latest"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# ---- 解析变量 ----
if [[ "$VARS_ARG" == @* ]]; then
  VARS_JSON=$(cat "${VARS_ARG#@}")
else
  VARS_JSON="$VARS_ARG"
fi
echo ">>> 变量已读取 (含 $(echo "$VARS_JSON" | grep -oE '"[A-Z_]+"' | wc -l) 个字段)"

# ---- 1. 取干净源码 ----
echo ">>> 准备干净源码 index-src.js"
cp index-src.js "$SCRATCH/index-src.js"

# ---- 2. 内嵌变量 ----
echo ">>> 内嵌变量"
python3 - "$SCRATCH/index-src.js" "$VARS_JSON" <<'PYEOF'
import json, sys
path, vj = sys.argv[1], sys.argv[2]
s = open(path, encoding='utf-8').read()
vars = json.loads(vj)
# 支持的变量 -> 源码内默认值表达式
repl_map = {
  "CFP_ID":       "const CFP_ID = process.env.CFP_ID || '';",
  "CFP_SECRET":   "const CFP_SECRET = process.env.CFP_SECRET || '';",
  "CFP_URL":      "const CFP_URL = process.env.CFP_URL || '';",
  "CFP_CT":       "const CFP_CT = process.env.CFP_CT || '';",
  "CFP_CU":       "const CFP_CU = process.env.CFP_CU || '';",
  "CFP_CM":       "const CFP_CM = process.env.CFP_CM || '';",
  "CFP_BD":       "const CFP_BD = process.env.CFP_BD || '';",
  "CFP_NODE1":    "const CFP_NODE1 = process.env.CFP_NODE1 || '';",
  "CFP_NODE2":    "const CFP_NODE2 = process.env.CFP_NODE2 || '';",
  "CFP_NODE3":    "const CFP_NODE3 = process.env.CFP_NODE3 || '';",
  "CFP_NODE4":    "const CFP_NODE4 = process.env.CFP_NODE4 || '';",
  "CFP_IFACE":    "const CFP_IFACE = process.env.CFP_IFACE || '';",
  "ARGO_AUTH":    "const ARGO_AUTH = process.env.ARGO_AUTH || '';",
  "ARGO_DOMAIN":  "const ARGO_DOMAIN = process.env.ARGO_DOMAIN || '';",
}
missed = []
for k, expr in repl_map.items():
    v = vars.get(k)
    if v is None:
        continue
    old = f"{expr.rstrip(';')};"
    new = f"{expr.rstrip(';')} || '{v}';"
    if old in s:
        s = s.replace(old, new)
    else:
        missed.append(k)
open(path, 'w', encoding='utf-8').write(s)
if missed:
    print("!! 未匹配(需检查源码):", missed)
    sys.exit(1)
print(f"    内嵌 {len(vars)} 个变量 OK")
PYEOF

# ---- 3. 混淆 ----
echo ">>> 混淆 index.js (容器安全)"
node - "$SCRATCH/index-src.js" "$SCRATCH/index.js" <<'JS'
const fs = require('fs');
const JavaScriptObfuscator = require('javascript-obfuscator');
const [srcPath, outPath] = process.argv.slice(2);
const src = fs.readFileSync(srcPath, 'utf8');
const r = JavaScriptObfuscator.obfuscate(src, {
  compact: true, identifierNamesGenerator: 'hexadecimal', renameGlobals: false,
  selfDefending: false, stringArray: true, stringArrayThreshold: 1.0,
  rotateStringArray: true, stringArrayEncoding: ['base64'], stringArrayWrappersCount: 2,
  stringArrayWrappersChainedCalls: true, stringArrayWrappersType: 'function',
  simplify: true, transformObjectKeys: false, numbersToExpressions: false,
  deadCodeInjection: false, controlFlowFlattening: false, unicodeEscapeSequence: false
});
fs.writeFileSync(outPath, r.getObfuscatedCode());
console.log('    混淆完成:', fs.statSync(outPath).size, 'bytes');
JS
# 安全校验: 混淆产物不得含明文变量值
for val in $(echo "$VARS_JSON" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin).values()))"); do
  if grep -qF "$val" "$SCRATCH/index.js"; then echo "!! 混淆产物泄漏明文: $val"; exit 1; fi
done
echo "    安全校验: 无明文泄漏 ✓"

# ---- 4. 构建 ----
echo ">>> 构建 $GHCR_IMAGE"
mkdir -p "$SCRATCH/ctx"
cp "$SCRATCH/index.js" Dockerfile index.html package.json "$SCRATCH/ctx/"
docker build --platform linux/amd64 -t "$GHCR_IMAGE" "$SCRATCH/ctx" 2>&1 | tail -2

# ---- 5. 推送 + 设 public ----
echo ">>> 推送 GHCR"
docker push "$GHCR_IMAGE" 2>&1 | tail -1
echo ">>> 设为 public"
PKG_ID=$(gh api "/user/packages?package_type=container" 2>/dev/null | python3 -c "
import json,sys
try:
    for p in json.load(sys.stdin):
        if p['name']=='${IMAGE_NAME}': print(p['id'])
except Exception: pass
")
if [ -n "$PKG_ID" ]; then
  echo "  包已存在 id=$PKG_ID (若为 private 需网页确认可见性)"
else
  echo "  ⚠ 包未能在 API 查到; 若镜像无法被匿名拉取, 请在网页将该包设为 public"
fi

# ---- 6. 清理 ----
echo ">>> 清理临时进程/文件"
pkill -f "$SCRATCH" 2>/dev/null || true
rm -rf "$SCRATCH"

echo ""
echo ">>> 完成: $GHCR_IMAGE"
echo ">>> Render/Koyeb 部署时填入镜像名即可(内置变量, 无需环境变量)"