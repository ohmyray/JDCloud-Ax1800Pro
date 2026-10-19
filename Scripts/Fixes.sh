#!/bin/bash
# 修复上游 feed 与本项目配置的冲突，幂等可重复执行
# 工作目录必须是 OpenWrt 源码根（./wrt/），在 defconfig 之前调用
#   1. lm-sensors : 上游补丁在 $(shell ...) 里写了 '#'，make 当注释截断
#   2. sing-box   : naive outbound 是 def_bool y，强选 libcronet（源码在 Google 存储，抓不到）
#   3. miniupnpd  : 2.3.11 已合入 020/030/040 三个补丁，再打必然 FAILED
#   4. AX1800Pro  : 内核带 BTF 后 gzip 压完 7.14MB 超出 6MB 分区，改用 lzma（5.21MB）
set -u

[ -f rules.mk ] || { echo "[fixes] 当前目录不是 OpenWrt 源码根: $(pwd)"; exit 1; }

say() { echo "[fixes] $*"; }

# ---------- 1. lm-sensors ----------
LMS_PATCH=$(ls feeds/packages/utils/lm-sensors/patches/*iconv*.patch 2>/dev/null | head -1)
if [ -n "$LMS_PATCH" ]; then
    python3 - "$LMS_PATCH" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
if "'\\#include <iconv.h>'" in s:
    print('[fixes] lm-sensors 补丁已转义，跳过')
elif "'#include <iconv.h>'" in s:
    open(p, 'w').write(s.replace("'#include <iconv.h>'", "'\\#include <iconv.h>'"))
    print('[fixes] lm-sensors 补丁 # 已转义')
else:
    print('[fixes] lm-sensors 补丁结构已变化，跳过')
PYEOF
else
    say "未找到 lm-sensors iconv 补丁，跳过"
fi

# ---------- 2. sing-box / libcronet ----------
SB_MK=feeds/packages/net/sing-box/Makefile
if [ -f "$SB_MK" ]; then
    python3 - "$SB_MK" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = "  config SING_BOX_BUILD_NAIVE_OUTBOUND\n  def_bool y\n"
new = ('  config SING_BOX_BUILD_NAIVE_OUTBOUND\n'
       '  bool "Build with naive outbound support (requires libcronet)"\n'
       '  default n\n')
if new in s:
    print('[fixes] sing-box naive outbound 已改为可选，跳过')
elif old in s:
    open(p, 'w').write(s.replace(old, new, 1))
    print('[fixes] sing-box naive outbound 改为可选，libcronet 不再被强选')
else:
    print('[fixes] sing-box Kconfig 结构已变化，跳过')
PYEOF
else
    say "未找到 sing-box，跳过"
fi

# ---------- 3. miniupnpd ----------
MUP_DIR=$(ls -d feeds/packages/net/miniupnpd/patches 2>/dev/null | head -1)
if [ -n "$MUP_DIR" ]; then
    for p in 020-descr-filter-fix 030-allow-private-fix 040-improve-logging; do
        if [ -f "$MUP_DIR/$p.patch" ]; then
            mv "$MUP_DIR/$p.patch" "$MUP_DIR/$p.patch.skip"
            say "停用 miniupnpd 补丁 $p（2.3.11 已合入）"
        fi
    done
fi

# ---------- 4. AX1800Pro 内核镜像改用 lzma ----------
IPQ_MK=target/linux/qualcommax/image/ipq60xx.mk
if [ -f "$IPQ_MK" ] && grep -q "define Device/jdcloud_re-ss-01" "$IPQ_MK"; then
    python3 - "$IPQ_MK" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = "define Device/jdcloud_re-ss-01\n\t$(call Device/FitImage)\n"
new = "define Device/jdcloud_re-ss-01\n\t$(call Device/FitImageLzma)\n"
if new in s:
    print('[fixes] jdcloud_re-ss-01 已是 lzma 内核，跳过')
elif old in s:
    open(p, 'w').write(s.replace(old, new, 1))
    print('[fixes] jdcloud_re-ss-01 内核改为 lzma（gzip 装不下 BTF）')
else:
    print('[fixes] jdcloud_re-ss-01 定义结构异常，请人工确认')
PYEOF
else
    say "目标非 ipq60xx 或设备定义缺失，跳过 lzma 修正"
fi

say "完成"
