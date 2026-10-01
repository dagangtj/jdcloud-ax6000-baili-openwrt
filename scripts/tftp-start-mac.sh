#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '请使用 sudo 运行；需要添加临时有线 IP 和启动系统 TFTP。'; exit 1; }
TASK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVE_DIR=/private/tmp/ax6000-recovery-tftp
PLIST=/private/tmp/ax6000-recovery-tftp.plist
IMAGE=openwrt-mediatek-filogic-jdcloud_re-cp-03-initramfs-recovery.itb
EXPECTED=ecd5b00a505ec57550bf1a4b92d7fda5a7b4944693768963c0c27ec8a054ba59
ACTUAL=$(/usr/bin/shasum -a 256 "$TASK_DIR/TFTP/$IMAGE" | /usr/bin/awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo '恢复镜像校验失败'; exit 1; }
/usr/bin/install -d -m 755 "$SERVE_DIR"
/usr/bin/install -m 444 "$TASK_DIR/TFTP/$IMAGE" "$SERVE_DIR/$IMAGE"
/sbin/ifconfig en0 alias 192.168.1.254 netmask 255.255.255.0
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.ax6000.recovery.tftp</string>
<key>ProgramArguments</key><array><string>/usr/libexec/tftpd</string><string>-i</string><string>-s</string><string>$SERVE_DIR</string></array>
<key>Sockets</key><dict><key>Listeners</key><dict><key>SockNodeName</key><string>192.168.1.254</string><key>SockServiceName</key><string>69</string><key>SockType</key><string>dgram</string></dict></dict>
<key>inetdCompatibility</key><dict><key>Wait</key><true/></dict>
<key>InitGroups</key><true/>
</dict></plist>
PLISTEOF
/bin/chmod 644 "$PLIST"
/usr/bin/plutil -lint "$PLIST"
/bin/launchctl bootstrap system "$PLIST"
echo '临时恢复服务已启动，仅绑定 192.168.1.254:69。'
