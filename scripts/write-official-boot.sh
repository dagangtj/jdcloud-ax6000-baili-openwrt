#!/bin/sh
# 京东云 AX6000 百里（RE-CP-03 / RE-CS-05）官方 GPT/BL2/FIP 写入脚本
# 在过渡系统（OpenWrt 4.1.0.r4005）的 /tmp 下执行。
# 执行前：三个官方文件已上传 /tmp 并核对 sha256（见 firmware/README.md）。
#
# 必须按本机修改两处：
#   1. SECTORS：64G = 119783424；128G = 241664000
#      现场读取：cat /sys/class/block/mmcblk0/size
#   2. FACTORY：本机 factory 分区（mmcblk0p3）的 SHA-256，一机一份，绝不跨机使用
#      现场读取：sha256sum /dev/mmcblk0p3
set -eu
cd /tmp
P=openwrt-25.12.5-mediatek-filogic-jdcloud_re-cp-03
SECTORS=119783424        # 64G；128G 改为 241664000
FACTORY=请替换成本机factory哈希

[ "$(cat /sys/class/block/mmcblk0/size)" = "$SECTORS" ]
[ "$(cat /sys/class/block/mmcblk0boot0/size)" = 8192 ]
grep -q 're-cp-03' /tmp/sysinfo/board_name
printf '%s\n' \
"6decc5e0ac9ef38bc78f4de8d4df825473a248898c24add4252cd74006f2fd20  $P-gpt.bin" \
"d1f272a3a5d474bafdc40bf4a99749304185f12dd799f87c414964b88dd3e72e  $P-preloader.bin" \
"52a5e4904488a35d680fbe379b8d90935c683628c3d082ae4823e44cd09c1724  $P-bl31-uboot.fip" | sha256sum -c -
[ "$(sha256sum /dev/mmcblk0p3 | cut -d' ' -f1)" = "$FACTORY" ]

# 1. GPT（34 扇区）→ 读回比对
dd if=$P-gpt.bin of=/dev/mmcblk0 bs=512 seek=0 count=34 conv=fsync
dd if=/dev/mmcblk0 bs=512 count=34 of=/tmp/gpt-readback.bin
cmp $P-gpt.bin /tmp/gpt-readback.bin && echo 'GPT READBACK VERIFIED'

# 2. BL2 → boot0（解锁只读 → 清零 → 写入 → 读回 → 重新锁）
echo 0 > /sys/block/mmcblk0boot0/force_ro
dd if=/dev/zero of=/dev/mmcblk0boot0 bs=512 count=8192 conv=fsync
dd if=$P-preloader.bin of=/dev/mmcblk0boot0 bs=512 conv=fsync
head -c 205204 /dev/mmcblk0boot0 > /tmp/bl2-readback.bin
cmp $P-preloader.bin /tmp/bl2-readback.bin && echo 'BL2 READBACK VERIFIED'
echo 1 > /sys/block/mmcblk0boot0/force_ro

# 3. FIP（扇区偏移 13312，64G/128G 相同）→ 读回比对
dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=13312 count=8192 conv=fsync
dd if=$P-bl31-uboot.fip of=/dev/mmcblk0 bs=512 seek=13312 conv=fsync
dd if=/dev/mmcblk0 bs=512 skip=13312 count=1557 of=/tmp/fip-rb.bin
head -c 797148 /tmp/fip-rb.bin > /tmp/fip-readback.bin
cmp $P-bl31-uboot.fip /tmp/fip-readback.bin && echo 'FIP READBACK VERIFIED'

# 4. factory 必须原样
[ "$(sha256sum /dev/mmcblk0p3 | cut -d' ' -f1)" = "$FACTORY" ] && echo 'FACTORY UNCHANGED VERIFIED'
sync
echo 'ALL WRITES VERIFIED; READY FOR POWER CYCLE'
