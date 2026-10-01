#!/bin/sh
# eMMC 健康采集脚本（collectd exec 插件用）
# 每 interval 秒输出一次：寿命消耗档（TYP_A/TYP_B）与寿命预警
# 值 = JEDEC 档位 × 10 = 该档寿命消耗上限百分比（如 0x01 → 10 表示消耗 0~10%）
INTERVAL="${COLLECTD_INTERVAL%%.*}"
[ -n "$INTERVAL" ] || INTERVAL=60
HOST="${COLLECTD_HOSTNAME:-localhost}"
LT=/sys/class/block/mmcblk0/device/life_time
PE=/sys/class/block/mmcblk0/device/pre_eol_info
while :; do
	a=$(awk '{print $1}' "$LT" 2>/dev/null)
	b=$(awk '{print $2}' "$LT" 2>/dev/null)
	p=$(cat "$PE" 2>/dev/null)
	a=$((a)); b=$((b)); p=$((p))
	echo "PUTVAL \"$HOST/exec-emmc/gauge-life_typ_a_pct\" interval=$INTERVAL N:$((a * 10))"
	echo "PUTVAL \"$HOST/exec-emmc/gauge-life_typ_b_pct\" interval=$INTERVAL N:$((b * 10))"
	echo "PUTVAL \"$HOST/exec-emmc/gauge-pre_eol\" interval=$INTERVAL N:$p"
	sleep "$INTERVAL"
done
