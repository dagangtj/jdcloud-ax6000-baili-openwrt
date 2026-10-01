#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '请使用 sudo 运行'; exit 1; }
# 只处理恢复目的地址，保留 Wi-Fi 默认路由与其他网络。
/sbin/route -n delete -host 192.168.1.1 -ifscope en0 2>/dev/null || true
/sbin/route -n delete -host 192.168.1.1 2>/dev/null || true
/sbin/route -n add -net 192.168.1.0/24 -interface 192.168.1.254 -ifscope en0
/sbin/route -n get -ifscope en0 192.168.1.1
/sbin/ping -S 192.168.1.254 -c 3 -W 1000 192.168.1.1 || true
