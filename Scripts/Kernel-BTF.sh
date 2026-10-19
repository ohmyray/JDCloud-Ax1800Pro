#!/bin/bash
# 开启 dae/daed 所需的 CO-RE eBPF 内核能力：BTF + tc-bpf
# 由 Settings.sh 在 make defconfig 之前调用，此时工作目录为 OpenWrt 源码根

set -e

if [ ! -d target/linux ]; then
	echo "!! 当前目录不是 OpenWrt 源码根: $(pwd)"
	exit 1
fi

KVER=$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/qualcommax/Makefile | tr -d '[:space:]')
[ -z "$KVER" ] && KVER=6.18
echo "==> 内核版本: $KVER"

CFGS=$(ls target/linux/qualcommax/config-$KVER target/linux/qualcommax/*/config-$KVER 2>/dev/null || true)
if [ -z "$CFGS" ]; then
	echo "==> target 片段不存在，退回 generic"
	CFGS=target/linux/generic/config-$KVER
fi

# 带后缀的符号不要误删，所以匹配时必须带上 = 或 " is not set"
SYMS="DEBUG_INFO DEBUG_INFO_REDUCED DEBUG_INFO_BTF NET_SCHED NET_CLS_ACT NET_CLS_BPF NET_ACT_BPF
      NET_SCH_INGRESS NFT_TPROXY VETH XDP_SOCKETS XDP_SOCKETS_DIAG"

for CFG in $CFGS; do
	if [ ! -f "$CFG" ]; then
		echo "!! 缺少 $CFG"
		exit 1
	fi
	echo "==> 修改 $CFG"

	# 先清掉同名旧行，否则追加的内容会被前面的 not set 压制
	for s in $SYMS; do
		sed -i -E "/^#?[[:space:]]*CONFIG_${s}(=| is not set)/d" "$CFG"
	done

	cat >> "$CFG" <<'EOF'
CONFIG_DEBUG_INFO=y
# CONFIG_DEBUG_INFO_REDUCED is not set
CONFIG_DEBUG_INFO_BTF=y
CONFIG_NET_SCHED=y
CONFIG_NET_CLS_ACT=y
CONFIG_NET_CLS_BPF=m
CONFIG_NET_ACT_BPF=m
CONFIG_NET_SCH_INGRESS=m
CONFIG_NFT_TPROXY=m
CONFIG_VETH=m
CONFIG_XDP_SOCKETS=y
CONFIG_XDP_SOCKETS_DIAG=m
EOF
done

echo "==> 内核 eBPF 选项已写入"
grep -hE '^CONFIG_(DEBUG_INFO_BTF|NET_CLS_BPF|NET_ACT_BPF)=' $CFGS || true
