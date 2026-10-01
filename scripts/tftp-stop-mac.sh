#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '请使用 sudo 运行'; exit 1; }
/bin/launchctl bootout system/local.ax6000.recovery.tftp
/sbin/ifconfig en0 -alias 192.168.1.254
echo '临时 TFTP 已关闭，恢复网段附加 IP 已移除。'
