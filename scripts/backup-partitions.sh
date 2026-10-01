#!/bin/sh
# 京东云 AX6000 百里：过渡系统分区备份脚本（在电脑上执行，Mac/Linux）
# 过渡系统无 sftp-server，scp 不可用，一律走 SSH 管道。
# 备份完成后务必逐项比对两侧哈希。
set -eu
BASE=backup-$(date +%Y%m%d)
mkdir -p "$BASE"

for dev in mmcblk0boot0 mmcblk0boot1 mmcblk0p2 mmcblk0p3 mmcblk0p4 \
           mmcblk0p5 mmcblk0p6 mmcblk0p7 mmcblk0p8; do
  ssh root@192.168.68.1 "sha256sum /dev/$dev" | tee -a "$BASE/设备端-sha256.txt"
  ssh root@192.168.68.1 "dd if=/dev/$dev bs=1048576 2>/dev/null" > "$BASE/$dev.bin"
done

# GPT 主表（34 扇区）
ssh root@192.168.68.1 'dd if=/dev/mmcblk0 bs=512 count=34 2>/dev/null' > "$BASE/gpt-primary.bin"

# GPT 末尾备份（33 扇区）：64G 用 skip=119783391；128G 用 skip=241663967
SKIP=119783391
ssh root@192.168.68.1 "dd if=/dev/mmcblk0 bs=512 skip=$SKIP count=33 2>/dev/null" > "$BASE/gpt-backup.bin"

shasum -a 256 "$BASE"/*.bin > "$BASE/电脑端-sha256.txt"
echo "备份完成：$BASE —— 请逐项比对 设备端-sha256.txt 与 电脑端-sha256.txt"
echo "注意：mmcblk0p3（factory）含本机无线校准与 MAC，一机一份，绝不跨机使用、勿公开。"
