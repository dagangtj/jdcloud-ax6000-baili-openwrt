# 京东云 AX6000（RE-CP-03 · 64G 版）OpenWrt 优化配置教程 · 第二部

> 本文是系列教程的**第二部**：第一部（《京东云AX6000-OpenWrt优化配置方案》，
> 见 `AX6000-128G` 目录）完成了 128G 机型从零刷机到全功能优化的全过程。
> 本部针对 **64G 机型**（eMMC 57.1 GiB），已装好 OpenWrt 25.12.5 的前提下，
> 按 128G 的成熟方案做一次完整复刻，**仅两处按需求改动**：
>
> 1. **上网方式（WAN）：自动获取 IP（DHCP）** —— 128G 是 PPPoE 拨号
> 2. **LAN 网段：192.168.86.x** —— 128G 是 192.168.66.x
>
> 其余全部与 128G 保持一致。2026-09-30 全部实施并验收通过。

---

## 网络拓扑与定位

```
互联网 ── 光猫(桥接) ── 128G 主机（PPPoE 拨号，LAN 192.168.66.1，SQM/CAKE 已启用）
                            │ 网线（插 64G 的 2.5G WAN 口）
                            ▼
                    64G 本机（WAN 自动获取 IP → 192.168.66.223，
                              LAN 192.168.86.1，双频 Wi-Fi 同名广播）
                            │
                    Mac / 手机等客户端（192.168.86.x）
```

- 64G 作为**二级路由**：WAN 口从 128G 自动拿地址（实测拿到 192.168.66.223），
  自己再开一个独立的 192.168.86.x 内网。
- 两个网段（66 / 86）互不冲突，两台路由器的管理后台可以同时访问。
- 64G 实测公网延迟 **11.6 ms**（经 128G 的宽带出口），与直连宽带无异。

---

## 与 128G 配置的对照总表

| 项目 | 128G（第一部） | 64G（本部） | 说明 |
|---|---|---|---|
| WAN 上网方式 | PPPoE 拨号 | **DHCP 自动获取** | 本机上级是 128G，无需拨号 |
| LAN 网段 | 192.168.66.1/24 | **192.168.86.1/24** | 避免与上级网段冲突 |
| Wi-Fi SSID | ExampleWiFi / ExampleWiFi_5G | 相同 | 同名同密码，设备可在两台间自动切换 |
| Wi-Fi 信道/频宽 | 2.4G 信道6 HE20 / 5G 信道149 HE80 | 相同 | 见文末「注意事项」第 2 条 |
| 加密方式 | WPA2/WPA3 混合（sae-mixed） | 相同 | |
| 时区 / NTP | Asia/Shanghai + 阿里/国内 NTP | 相同 | |
| packet steering | 开启 | 相同 | |
| 中文界面 | zh_cn | 相同 | |
| Argon 主题 | v2.4.7 + 内置壁纸 | 相同 | |
| 数据盘 | eMMC 第6分区 → /data（112.4G） | eMMC 第6分区 → /data（**55.4G**） | 操作完全相同 |
| SMB 共享 | ksmbd，账号 share | 相同（账号密码直接复用） | |
| SQM/CAKE | 启用（pppoe-wan 950M/90M，2026-10-01 由 425M/80M 上调，见第一部附录 Q） | **不开**（原因见「注意事项」第 3 条） | |
| Tailscale | 已配置 | **暂不配**（需独立授权，见「注意事项」第 4 条） | |

---

## 步骤 0：接通与确认身份

电脑用网线插 64G 的任意千兆 LAN 口，确认能打开默认管理地址：

```bash
ping 192.168.1.1                    # 新刷 OpenWrt 默认地址
ssh root@192.168.1.1               # 新刷机 root 无密码，直接进
```

确认是 64G 机型（关键命令）：

```bash
cat /sys/class/block/mmcblk0/size
# 64G 输出约 119783424（×512 字节 ≈ 57.1 GiB）
# 128G 输出约 244277248（≈ 116.5 GiB）
```

> 本次实测：57.1 GiB、eMMC 芯片 SLD64G（2021 年 2 月出厂）、
> 寿命消耗 0–10%（life_time=0x01）、无预警（pre_eol=0x01），接近全新。
> 健康自查方法详见第一部附录 B2。

---

## 步骤 1：WAN 设为自动获取 IP（DHCP）

新刷的 OpenWrt **默认就是 DHCP**，一般无需改动，验证即可：

```bash
uci show network.wan
# 期望输出：
# network.wan.device='eth1'
# network.wan.proto='dhcp'
```

如果之前被改成过别的（如 PPPoE），改回 DHCP：

```bash
uci set network.wan.proto='dhcp'
uci del network.wan.username 2>/dev/null
uci del network.wan.password 2>/dev/null
uci commit network
ifup wan          # 只动 WAN 协议用 ifup，不用重启（第一部附录 N 的教训）
```

**验证联网**（WAN 网线已插到上级路由/光猫）：

```bash
ifstatus wan | grep -E '"up"|address'     # up:true 且拿到地址
ping -c 2 223.5.5.5                        # 通公网即成功
```

> 本次实测：从 128G 拿到 `192.168.66.223`，公网 ping 11.6 ms，一次通过。

---

## 步骤 2：LAN 网段改为 192.168.86.x（全教程最关键的一步）

> ⚠️ 这一步集中了第一部附录 N 用两次恢复出厂换来的教训，务必照做。

### 正确做法

```bash
# ① 地址必须带 /24 前缀（只写 IP 会被当成 /32，DHCP 直接瘫痪！）
uci set network.lan.ipaddr='192.168.86.1/24'
uci commit network

# ② 必须整机 reboot，不要 service network restart
#    （MT7986 热重启 network 可能导致 2.5G 口 PHY 起不来）
reboot
```

### 重启后电脑侧操作

- 拔插一次网线（或等链路闪断自动重连），电脑会拿到 `192.168.86.x` 新地址
- macOS 断网瞬间可能自动跳到别的已知 Wi-Fi，先看 Wi-Fi 图标连的是不是这台路由器
- 新管理地址：**http://192.168.86.1**

### 验证

```bash
ssh root@192.168.86.1
ip addr show br-lan | grep inet      # 必须是 192.168.86.1/24（不是 /32）
netstat -ulnp | grep ":67 "          # dnsmasq 在监听 DHCP
```

> 本次实测：重启后 Mac 自动拿到 192.168.86.157，DHCP 池 192.168.86.100–249 正常。

---

## 步骤 3：同步 128G 的其余设置

### 3.1 时区与 NTP

```bash
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
while uci del system.ntp.server 2>/dev/null; do :; done
uci add_list system.ntp.server='ntp.aliyun.com'
uci add_list system.ntp.server='cn.pool.ntp.org'
uci commit system
/etc/init.d/sysntpd restart
date    # 应显示 CST 北京时间
```

### 3.2 包转向（免费的多核优化）

```bash
uci set network.globals.packet_steering='1'
uci commit network
```

### 3.3 双频 Wi-Fi（与 128G 同名同密）

```bash
# 2.4G
uci set wireless.radio0.country='CN'
uci set wireless.radio0.channel='6'
uci set wireless.radio0.htmode='HE20'
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio0.ssid='ExampleWiFi'
uci set wireless.default_radio0.encryption='sae-mixed'
uci set wireless.default_radio0.key='<你的WiFi密码>'
uci set wireless.default_radio0.disabled='0'

# 5G
uci set wireless.radio1.country='CN'
uci set wireless.radio1.channel='149'
uci set wireless.radio1.htmode='HE80'
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.cell_density='0'
uci set wireless.default_radio1.ssid='ExampleWiFi_5G'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio1.key='<你的WiFi密码>'
uci set wireless.default_radio1.ocv='0'
uci set wireless.default_radio1.disabled='0'

uci commit wireless
wifi reload
```

验证：`iw dev` 应看到 phy0-ap0（信道 6）和 phy1-ap0（信道 149）都在广播。

### 3.4 中文界面

```bash
apk update
apk add luci-i18n-base-zh-cn
uci set luci.main.lang='zh_cn'      # 注意是下划线 zh_cn，不是 zh-cn
uci commit luci
```

浏览器刷新 http://192.168.86.1 即为中文。

### 3.5 Argon 主题（界面美化）

```bash
# 电脑上从作者 Release 下载三个 apk 包（v2.4.7）：
# https://github.com/jerrykuku/luci-theme-argon/releases/latest
#   luci-theme-argon / luci-app-argon-config / luci-i18n-argon-config-zh-cn
scp -O *.apk root@192.168.86.1:/tmp/        # 必须加 -O（路由器没有 sftp）

# 路由器上：
cd /tmp && apk add --allow-untrusted luci-theme-argon*.apk luci-app-argon-config*.apk luci-i18n-argon-config*.apk
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# 壁纸改内置（不消耗流量、打开更快）
# 注意：本机 argon 配置节是匿名的，用 @global[0]
uci set argon.@global[0].online_wallpaper='built-in'
uci commit argon

# 新页面 404 时清缓存
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*
```

> 踩坑记录：128G 的 argon 配置节名是 `global`，64G 新装包的默认是匿名节
> `@global[0]`，直接 `uci set argon.global.xxx` 会报 Invalid argument——
> 先 `uci show argon` 看一眼节名再动手。

---

## 步骤 4：启用 64G eMMC 闲置空间（约 55GB）

背景与 128G 完全相同：官方镜像分区表只覆盖约 500MB，备份 GPT 头位置异常，
剩余空间闲置。64G 修复后可得 **56.6 GiB** 空闲区域。

```bash
apk add sgdisk e2fsprogs kmod-fs-ext4 block-mount

# ① 把备份 GPT 头移到盘尾，空闲空间才会出现
sgdisk -e /dev/mmcblk0
sgdisk -p /dev/mmcblk0
# 确认："Total free space ... 56.6 GiB"
# 安全前提：原有分区 ubootenv/factory/fip/recovery/production 完整无重叠

# ② 在空闲区域建第 6 分区（起始扇区 1048576 = 512MiB 处）
sgdisk -n 6:1048576:0 -t 6:8300 -c 6:data /dev/mmcblk0

# ③ 内核认不出新分区就重启一次（128G 同样如此）
reboot

# ④ 格式化并挂载
mkfs.ext4 -L data /dev/mmcblk0p6
mkdir -p /data && mount /dev/mmcblk0p6 /data

# ⑤ 开机自动挂载
block detect > /etc/config/fstab
uci set fstab.@mount[0].enabled='1'
uci commit fstab
/etc/init.d/fstab enable
```

> 本次实测：`/data` 容量 **55.4 GiB**（可用 52.6 GiB），挂载正常。

---

## 步骤 5：SMB 网络共享（把 55GB 变成局域网网盘）

```bash
apk add ksmbd-server luci-app-ksmbd luci-i18n-ksmbd-zh-cn

# 共享配置（与 128G 一致）
uci set ksmbd.@globals[0].interface='lan'
uci add ksmbd share
uci set ksmbd.@share[-1].name='data'
uci set ksmbd.@share[-1].path='/data'
uci set ksmbd.@share[-1].read_only='no'
uci set ksmbd.@share[-1].guest_ok='no'
uci set ksmbd.@share[-1].users='share'
uci set ksmbd.@share[-1].force_root='1'      # 关键：不设则写入 Permission denied
uci commit ksmbd

# 共享账号（-p 非交互方式一次到位）
ksmbd.adduser -a share -p '<共享密码>'

/etc/init.d/ksmbd enable
/etc/init.d/ksmbd stop; /etc/init.d/ksmbd start    # ksmbd 用 stop/start，不用 restart
```

**访问方式：**

| 平台 | 操作 |
|---|---|
| Mac | 访达 `Cmd+K` → `smb://192.168.86.1/data` → 选「注册用户」→ 账号 `share` |
| Windows | 资源管理器地址栏 `\\192.168.86.1\data` |
| 手机 | 「文件」App / SMB 文件管理器，服务器 `192.168.86.1` |

> 本次实测（Mac 千兆有线）：写 62.6 MB/s、读 113 MB/s，与 128G 水平相当。
> 本次直接复制了 128G 备份里的 `/etc/ksmbd/ksmbdpwd.db` 密码哈希文件，
> 两台路由器共享账号密码完全一致，客户端不用记两套密码。

---

## 步骤 6：总验收与备份（2026-09-30 全部通过）

重启路由器后全项自动恢复：

| 验收项 | 结果 |
|---|---|
| LAN 网段 | 192.168.86.1/24，DHCP 正常发地址 ✅ |
| WAN（DHCP） | 自动获取 192.168.66.223，公网 11.6 ms ✅ |
| 双频 Wi-Fi | ExampleWiFi（信道6）/ ExampleWiFi_5G（信道149）广播 ✅ |
| `/data` 数据盘 | 55.4 GiB 自动挂载 ✅ |
| SMB 共享 | 445 端口监听，读写实测正常 ✅ |
| 中文界面 + Argon | zh_cn + argon 保持 ✅ |
| 时区 / NTP | CST 自动对时 ✅ |
| packet steering | 保持开启 ✅ |
| 配置备份 | 已存档（见下） ✅ |

**备份配置（每次大改前都做）：**

```bash
sysupgrade -b /tmp/backup-$(date +%F).tar.gz
# 电脑上取回：
scp -O root@192.168.86.1:/tmp/backup-*.tar.gz ./
```

本目录已存档：`backup-openwrt-2026-09-30-64G-86.tar.gz`
（恢复方法：LuCI「系统 → 备份/刷写固件 → 恢复」上传，或 `sysupgrade -r`）。

---

## 注意事项（与 128G 的差异及原因）

### 1. root 管理员密码（建议立即设置）

新刷机 root 无密码，LuCI 登录框直接留空即可进——**内网任何人都能进后台**。
请尽快在「系统 → 管理权」设置强密码。本教程不记录任何密码。

### 2. 两台路由器 Wi-Fi 同名同信道的影响

64G 完全复刻了 128G 的 SSID（ExampleWiFi / ExampleWiFi_5G）和信道（6 / 149）：

- **好处**：手机电脑在两台之间移动时自动切换，无需手动换 Wi-Fi
- **代价**：两台同信道会互相干扰，距离近时 2.4G 影响较明显
- **建议**：两台离得近就把 64G 的 2.4G 改到信道 1 或 11（与 128G 的信道 6 错开），
  5G 可改信道 36–48 之一；离得远则无需改动

### 3. 为什么 64G 不开 SQM

128G 上 SQM/CAKE 的职责是**在宽带出口**消除满载延迟。64G 的流量全部经过
128G 出口，已经被 CAKE 塑形过了——在 64G 上再叠一层 SQM 是**重复塑形**，
白白损失吞吐和 CPU，没有任何收益。

> 若日后 64G 改为直接拨号的主路由，再按第一部附录 K 配置 SQM，
> 接口选 `wan`（DHCP 模式是 eth1，不是 pppoe-wan），带宽填实测值的 90%。

### 4. Tailscale 远程访问（暂未配置）

Tailscale 节点密钥**不能从 128G 克隆**（两台设备共用一个身份会互相挤掉）。
需要时按第一部附录 O 独立安装授权，子网路由改为：

```bash
tailscale up --authkey=<新的AuthKey> --advertise-routes=192.168.86.0/24 --accept-dns=false
```

并在管理后台批准 192.168.86.0/24 子网路由。

### 5. 无线 WAN（热点备用链路）未复刻

128G 的 wwan（连手机热点备用）配置本次未复制——64G 的有线 WAN 已稳定联网，
且热点备用链路在 128G 上更有意义。需要时按第一部附录 A 操作，记得改完防火墙
区域后 `service firewall restart`（第一部附录 D4 的坑）。

---

## 故障排查速查

| 现象 | 首选排查 |
|---|---|
| 改网段后拿不到 IP | 检查 ipaddr 是否带 `/24`（第一部附录 N 坑 1） |
| 改完网络 WAN 口灯灭 | 整机 reboot，不要 service network restart（附录 N 坑 2） |
| 路由器有网、客户端没网 | 防火墙区域改动后要 `service firewall restart`（附录 D4） |
| apk 报 SSL 错误 | 先 `date` 看时间对不对（附录 D3） |
| SMB 能看不能写 | 共享加 `force_root='1'`（附录 D7） |
| scp 传文件失败 | 必须加 `-O` 参数（附录 D2） |
| 语言选了不变中文 | 语言代码是 `zh_cn` 下划线（附录 D1） |
| IPv4 全断时救场 | 走 IPv6 ULA 地址 SSH 进去（附录 N 诊断技巧） |

更完整的 12 条踩坑记录见第一部附录 D。

---

## 附录 A：系统状态图形化监控（已实施，2026-09-30）

**方案**：OpenWrt 官方 `luci-app-statistics`（collectd 采集 + RRD 历史曲线），
直接嵌在 LuCI 后台，极轻量（几 MB 内存）。**入口：状态 → 图表。**

**已启用的监控项**（采样间隔 30 秒，可回看 2 小时 / 1 天 / 1 周 / 1 月 / 1 年）：

| 图表 | 内容 |
|---|---|
| 处理器 | 4 核各自占用率 |
| 负载 / 内存 | 系统负载曲线、内存细分 |
| 接口 | br-lan 等各网口流量 |
| 无线 | 两个频段的信号/噪声/速率（iwinfo） |
| **温度** | 芯片温度曲线（thermal_zone0） |
| **磁盘用量** | /overlay 与 /data 占用百分比 |
| **Ping** | 到 223.5.5.5 的公网延迟 / 丢包率 / 抖动曲线 |
| **eMMC 健康** | 寿命消耗（TYP_A/B，档位×10=上限百分比）+ 寿命预警 |

**安装与配置：**

```bash
apk add luci-app-statistics luci-i18n-statistics-zh-cn collectd collectd-mod-rrdtool \
        collectd-mod-cpu collectd-mod-memory collectd-mod-load collectd-mod-interface \
        collectd-mod-df collectd-mod-thermal collectd-mod-iwinfo collectd-mod-ping \
        collectd-mod-exec rrdtool1

# RRD 数据目录改到 /data（默认 /tmp，重启即丢历史）
mkdir -p /data/rrd
uci set luci_statistics.collectd_rrdtool.DataDir='/data/rrd'

# 磁盘用量监控 /data；公网延迟盯阿里 DNS
uci set luci_statistics.collectd_df.enable='1'
uci add_list luci_statistics.collectd_df.MountPoints='/data'
uci set luci_statistics.collectd_df.ValuesPercentage='1'
uci set luci_statistics.collectd_ping.enable='1'
uci add_list luci_statistics.collectd_ping.Hosts='223.5.5.5'
uci set luci_statistics.collectd_thermal=statistics
uci set luci_statistics.collectd_thermal.enable='1'
uci commit luci_statistics
/etc/init.d/luci_statistics enable && /etc/init.d/luci_statistics restart
/etc/init.d/collectd enable && /etc/init.d/collectd restart
```

**eMMC 健康曲线（自制 exec 插件）**：采集脚本 `/usr/bin/emmc-health.sh`
（本目录有同款备份 `emmc-health.sh`），每 30 秒读一次 JEDEC 寿命寄存器喂给 collectd。
UCI 配置：

```bash
uci set luci_statistics.collectd_exec=statistics
uci set luci_statistics.collectd_exec.enable='1'
uci add luci_statistics collectd_exec_input
uci set luci_statistics.@collectd_exec_input[-1].cmdline='/usr/bin/emmc-health.sh'
uci set luci_statistics.@collectd_exec_input[-1].cmduser='nobody'
uci commit luci_statistics && /etc/init.d/luci_statistics restart && /etc/init.d/collectd restart
```

**踩坑记录（本次实测）：**

1. **不要手改 `/etc/collectd.conf`**——它是 `/var/etc/collectd.conf` 的软链，
   每次启动由 `stat-genconfig` 按 UCI 重新生成，手改必丢。一切走 `luci_statistics` UCI。
2. **exec 脚本里 `sleep $COLLECTD_INTERVAL` 会报错**：collectd 传的间隔是 `30.000`，
   busybox sleep 不认小数，脚本会变成死循环刷屏。必须取整：
   `INTERVAL="${COLLECTD_INTERVAL%%.*}"`。
3. **df 插件默认带 `FSType tmpfs` 选择器**，会把 ext4 的 `/data` 和 overlayfs 的
   `/overlay` 全部排除掉，表现为没有任何磁盘图表。删掉 `Devices`/`FSTypes`
   两个选择器、只留 `MountPoints` 才生效。
4. busybox 的 `rrdtool` 只支持 create/update/graph，不支持 `lastupdate`/`fetch`；
   验证数据有没有在写，看 rrd 文件的修改时间即可。

**eMMC 曲线读法**：`life_typ_a_pct` 显示 10 表示寿命消耗处于 0–10% 档
（JEDEC 每档 10%），变成 20 说明进入 10–20% 档；`pre_eol` 正常恒为 1，
跳成 2/3 就该立刻备份 `/data`。

**示例图**（装机 25 分钟实测，本目录 `系统状态监控示例.png`）：
红线温度约 52℃、蓝线公网延迟 11–12 ms、绿线 eMMC 寿命档位 10% 平稳。

---

## 附录 B：eMMC 20GB 实写校验压测（2026-10-01 通过）

**目的**：64G 机型曾长期跑京东云，寄存器读数（寿命 0–10%）只是参考，
用「真实写入 + 校验和比对」给闪存健康下最终结论。

**方法**：256MB 随机种子 → 复制 80 份共 **20GB** 写入 `/data` →
清页缓存 → 全部读回逐文件比对 MD5。纯路由器本地操作，不占网线带宽。

**结果：**

| 指标 | 数值 |
|---|---|
| 写入总量 | 20.0 GB（80 个文件） |
| 写入速度 | **约 137 MB/s**（两轮各 75 秒） |
| 校验结果 | **80 / 80 全部一致，0 错误** |
| 读回+校验速度 | 约 143 MB/s（MD5 计算占大头） |
| 温度 | 52.4℃ → 峰值 55.2℃（仅升 3℃） |
| 负载峰值 | 1.9（4 核，大量富余） |
| 压测后寿命寄存器 | life_time 0x01 不变、pre_eol 0x01 不变 |

**结论**：20GB 实写实校零错误，闪存颗粒无任何坏块/不稳定迹象，
「跑了多年京东云但寿命接近全新」的寄存器读数可信。
压测曲线见本目录 `压测监控曲线.png`（监控附录 A 的图表同步捕捉到了全过程）。

**复测方法**（建议每半年一次）：

```bash
dd if=/dev/urandom of=/tmp/seed.bin bs=1M count=256
mkdir -p /data/stresstest && cd /data/stresstest
md5sum /tmp/seed.bin > seed.md5
sh -c "for i in \$(seq 1 80); do cp /tmp/seed.bin f\$i.bin; done; sync"
echo 3 > /proc/sys/vm/drop_caches
md5sum f*.bin > readback.md5
grep -c "$(cut -d' ' -f1 seed.md5)" readback.md5   # 应输出 80
rm -rf /data/stresstest /tmp/seed.bin
```

---

## 附录 C：实用插件与 Tailscale 远程访问（2026-10-01 完成）

### C1. 已装实用插件

| 插件 | 用途 |
|---|---|
| `luci-app-watchcat` | 断网看护：每分钟 ping 223.5.5.5，持续 6 小时不通自动重启 WAN 接口（系统 → Watchcat） |
| `iperf3` | 内网测速（`iperf3 -s` 服务端 / 电脑端 `iperf3 -c 192.168.86.1`） |
| `htop` / `nano` | 进程查看 / 文本编辑 |

### C2. Tailscale（子网路由模式，已上线）

- 版本：**1.102.4 官方静态版**（源内 1.98.3 有已知安全漏洞，按第一部附录 O 的方法升级：
  `wget https://pkgs.tailscale.com/stable/tailscale_1.102.4_arm64.tgz`，解压覆盖 `/usr/sbin/` 同名文件）
- Tailscale IP：**100.108.240.49**，设备名 openwrt-1（控制台可改名）
- 广播子网路由 **192.168.86.0/24**（已在管理后台批准）；**已关闭密钥过期**
  （Disable key expiry，否则 180 天后远程访问失效）
- 与 128G（100.72.158.90）直连互通，延迟 1ms
- 手机/外地电脑登录同账号后可直接访问 `http://192.168.86.1`（LuCI）和
  `smb://192.168.86.1/data`（文件共享）

**防火墙配套（子网路由必须）**：新增 `tailscale` 区域（tailscale0 设备，
input/output/forward ACCEPT + masq），并加 tailscale↔lan 双向转发。
masq 开启后内网设备无需任何路由配置即可被远程访问。

**断线逃生通道（2026-10-01 凌晨补）**：为防止拔掉 LAN 网线后失联，
WAN 区加了一条仅放行 66 网段的 SSH 规则，并把 128G 的密钥加进了授权列表——
之后有三条独立控制路径：① Mac Tailscale → 100.108.240.49 或 192.168.86.1；
② Mac → 128G → 192.168.66.223（WAN 口）；③ 插回 LAN 网线/Wi-Fi。
注意：若 64G 的 WAN 网线也拔掉（彻底脱离上级），只剩第 ③ 条。

```bash
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-SSH-from-66'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].src_ip='192.168.66.0/24'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='22'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall && service firewall restart
```

```bash
uci set firewall.ts=zone
uci set firewall.ts.name='tailscale'
uci set firewall.ts.input='ACCEPT'
uci set firewall.ts.output='ACCEPT'
uci set firewall.ts.forward='ACCEPT'
uci set firewall.ts.masq='1'
uci set firewall.ts.mtu_fix='1'
uci add_list firewall.ts.device='tailscale0'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'
uci commit firewall && service firewall restart
```

**踩坑记录（本次实测）：**

1. busybox 无 `nohup`——后台跑 `tailscale up` 用 `命令 > /tmp/log 2>&1 < /dev/null &` 即可
2. 授权链接几分钟轮换一次，取到必须马上打开（第一部附录 O 已有记录）
3. `tailscale ping` 通但普通 ping 不通是正常的：前者由 tailscaled 直接应答，
   后者受对端防火墙 INPUT 策略影响，不代表业务流量不通
4. 路由器这类长期在线设备，务必在控制台 **Disable key expiry**

### C2.1 本次刻意不装的

广告过滤（adblock/AdGuard Home）、DDNS——主人明确不需要，需要时再按
第一部阶段 3 的方法单独添加，一次只加一类。

**新配置备份**：`backup-openwrt-2026-10-01-64G-v2.tar.gz`（本目录）。

---

## 附录 D：Aria2 下载器 + AriaNg 网页端（2026-10-01 完成）

**用途**：磁力链接 / BT 种子 / HTTP 直链下载电影等文件，落到 `/data/downloads`，
SMB 共享直接可见（电视、电脑即下即看）；出门在外经 Tailscale 也能远程加任务。

**安装与配置：**

```bash
apk add aria2-openssl luci-app-aria2 luci-i18n-aria2-zh-cn ariang

mkdir -p /data/downloads
chown -R aria2:aria2 /data/downloads        # 关键！否则沙箱里写入 Permission denied

uci set aria2.main.enabled='1'
uci set aria2.main.dir='/data/downloads'
uci set aria2.main.rpc_secret='<RPC密钥>'    # 任意随机串，AriaNg 连接要用
uci set aria2.main.ca_certificate='/etc/ssl/certs/ca-certificates.crt'  # 关键！否则HTTPS握手失败
uci set aria2.main.max_concurrent_downloads='5'
uci set aria2.main.max_connection_per_server='16'
uci set aria2.main.enable_dht='true'
uci set aria2.main.bt_enable_lpd='true'
uci set aria2.main.follow_torrent='true'
uci commit aria2
/etc/init.d/aria2 enable && /etc/init.d/aria2 restart
```

**使用入口：**

| 入口 | 地址 |
|---|---|
| AriaNg 网页（添加/管理任务） | http://192.168.86.1/ariang/ |
| LuCI 状态页 | 服务 → Aria2 |
| 下载目录（SMB） | `smb://192.168.86.1/data` → downloads |
| 远程使用（Tailscale） | http://100.108.240.49/ariang/ |

**AriaNg 首次使用（密钥配置）**：

AriaNg 是纯网页应用，**RPC 密钥存在浏览器 localStorage 里，不在路由器上**。
因此每台设备、每个浏览器首次打开都会弹「认证失败」，配一次密钥即永久记住。

方法一（一键链接，推荐）：浏览器地址栏直接打开下列链接，密钥自动写入并连接——

```text
64G:  http://192.168.86.1/ariang/#!/settings/rpc/set/http/192.168.86.1/6800/jsonrpc/ZDUyZmExYjZmOGZhOGYyMzMwNjkzZTBj
128G: http://192.168.66.1/ariang/#!/settings/rpc/set/http/192.168.66.1/6800/jsonrpc/NWExMTgyMjQ0ZGI1ZTA3OGU4YzFiNjJj
```

（链接末段是密钥的 Base64 编码，AriaNg 的 `#!/settings/rpc/set/协议/主机/端口/接口/Base64密钥` 约定格式。）

方法二（手动）：左侧「AriaNg 设置 → RPC」→ 地址 `192.168.86.1`、
端口 `6800`、密钥填 RPC 密钥，页面自动重连。

**密钥查询**（本教程不直接记录密钥明文，随时可查）：

```bash
ssh root@192.168.86.1 'uci get aria2.main.rpc_secret'   # 64G
ssh root@192.168.66.1 'uci get aria2.main.rpc_secret'   # 128G
```

手机浏览器同理：连家里 Wi-Fi 后打开对应一键链接即可，iOS/Android 通用。

**踩坑记录（本次实测，按出现顺序）：**

1. `SSL/TLS handshake failure`：aria2-openssl 不会自动找系统证书，
   必须显式设 `ca_certificate`（见上）。
2. **errorCode 16 "Download aborted"（最坑）**：真实原因是 OpenWrt 的 aria2
   init 脚本把 daemon 关进 procd 沙箱、以 `aria2` 用户运行，新建目录属主是
   root，写入即 Permission denied。`chown -R aria2:aria2 /data/downloads` 解决。
   日志里 `AbstractDiskWriter ... Permission denied` 是判据。
3. daemon 默认不输出日志，排查时临时 `uci set aria2.main.log='/var/etc/aria2/aria2.log'`
   + `log_level='debug'`（不要写到 /data/downloads，沙箱挂载时机问题会打不开），
   查完删掉这两项。
4. 通过 SMB 从电脑往 downloads 目录手动放文件属主是 root，aria2 管理（删除）会受限；
   建议一律经 AriaNg 添加/删除任务。
5. 路由器在 128G 下级、无公网端口映射：BT 下载靠主动连出没问题，做种上传能力弱。
   常玩 PT 的话再考虑在 128G 上装 miniupnpd 放行端口。

**新配置备份**：`backup-openwrt-2026-10-01-64G-v3.tar.gz`（本目录）。

---

## 附录 E：双路由灌盘压测实测（2026-10-01 凌晨通过）

64G 与 128G 两台同时用 aria2 批量下载 Debian/openSUSE 官方 ISO（清华 TUNA
镜像）+ Blender 开源电影 zip，把 /data 灌满至 100%，兼作网络+磁盘压力测试。
**填充文件全部是 GPL 自由软件镜像与 CC-BY 开源电影，可随时整体删除**
（`rm /data/downloads/*.iso` 即释放，电影 zip 留作 SMB 播放测试）。
完整报告见本目录《压测报告-双路由灌盘.md》，曲线图见
`压测曲线-64G.png` / `压测曲线-128G.png` / `压测对比.png`。

**实测数据（collectd rrd，5 分钟粒度）**：

| 指标 | 64G | 128G |
|---|---|---|
| 测试窗口 | 01:15 – 02:05 | 01:25 – 02:30 |
| 净写入 | 51.14 GiB（/data 满，52.6/55.4G） | 102.41 GiB（/data 满，106.6/112.4G） |
| 平均速度 | 18.3 MB/s | 28.2 MB/s（64G 退出后峰值 45.8 MB/s） |
| SoC 温度 | 峰 52.9 °C / 均 52.2 °C | 峰 55.0 °C / 均 54.1 °C |
| eMMC 磨损 | life 0x01/0x01，pre_eol 0x01 | life 0x01/0x00，pre_eol 0x01 |
| dmesg I/O 错误 | 无 | 无 |

**结论**：

1. 两台合计约 154 GiB 连续高强度写入后 eMMC 寿命计数纹丝不动、零 I/O
   错误——京东云这两颗 eMMC 健康度极佳，做下载机/轻量 NAS 无寿命顾虑。
2. 温度峰值仅 55 °C，被动散热足够，无需外挂风扇。
3. 双机同时全速合计约 40 MB/s（≈320 Mbps），瓶颈在 128G 的宽带出口
   （SQM 425M），不在路由器本体；64G 较慢还因二级路由 NAT 路径，属正常。
   **后续（2026-10-01 清晨）**：已确认宽带实为千兆（裸测 1199 Mbps），
   SQM 上调至 950M/90M 后实测 746 Mbps、满载延迟仍 ≤16ms——详见第一部附录 Q。
4. /data 写满后 aria2 报 *Write disk cache flush failure* 退出，属预期
   收尾现象；内核无 panic、无 remount-ro，文件系统完好。
5. 管理面（SSH/LuCI）全程可用，无 OOM、无软重启。

**后续收尾（同日 05:30）**：ext4 默认给 root 保留 5% 块，导致 df 在
真实用量 95% 时即显示 100%、5 个任务在收尾尾巴上失败且控制文件损坏
（0 字节，无法续传）。处理：`apk add tune2fs && tune2fs -m 1 /dev/mmcblk0p6`
把保留块降到 1%（数据盘无系统角色，保留块无意义），删除损坏残片后重新
下载补齐，最终 64G 落位约 95.3%、128G 约 96.1%，全部任务 complete。
**数据盘建议装机时就执行一次 `tune2fs -m 1`，把 5% 保留块还给可用空间。**

---

## 附录 F：远程看电影（SMB over Tailscale，2026-10-01 实测通过）

**原理**：影片在路由器 `/data/downloads`，ksmbd 提供 SMB 共享；Tailscale
组网后，无论在家还是在外，都能用同一地址挂载点播。实测远程读取
29.4 MB/s，4K 原画（码率约 10 Mbps）拖进度条无压力；出门在外瓶颈仅
家中上行 80M，仍是 4K 码率的 8 倍。

**关键配置（SMB 绑定 Tailscale 接口，本次踩坑记录）**：

ksmbd 默认只监听 `lan`，Tailscale 网段访问 445 端口不通。三步解决：

```bash
# 1. 把 tailscale0 注册为 UCI 网络接口（ksmbd 只认接口名，不认设备名）
uci set network.tailscale='interface'
uci set network.tailscale.proto='none'
uci set network.tailscale.device='tailscale0'
uci commit network

# 2. ksmbd 监听列表加上 tailscale
uci add_list ksmbd.@globals[0].interface='tailscale'
uci commit ksmbd
/etc/init.d/ksmbd restart        # 生成配置应变更为 interfaces = br-lan tailscale0
```

注意：`/etc/init.d/network reload` 会把 tailscale0 的 IP 抖掉（SSH 断线），
发生后用备用通道登录执行 `/etc/init.d/tailscale restart` 再重启一次 ksmbd
即可（ksmbd 的内核 socket 要在 tailscale0 有 IPv4 地址之后重建才生效）。

**观影方法**：

| 设备 | 步骤 |
|---|---|
| Mac | Finder → 前往 → 连接服务器 → `smb://100.108.240.49/data`（在家用 `smb://192.168.86.1/data`），输入共享账号密码 → 进 downloads 双击播放 |
| iPhone/iPad | 装 Tailscale 登录同一账号并开启 → 装 VLC → 打开 VLC →「网络」标签自动发现或手动添加 SMB 服务器 `100.108.240.49`，共享名 `data` → 输入账号密码 → 点播 |
| Android | Tailscale + VLC（或 nPlayer），同上添加 `smb://100.108.240.49/data` |
| Windows | Win+R 输入 `\\100.108.240.49\data`，输账号密码 |

**远程加下载任务**：AriaNg 面板 `http://100.108.240.49/ariang/`（密钥配置
见附录 D 一键链接），人在外面也能让家里路由器先下好，回家即看。

**128G 同理（已配置完成）**：地址换成 `100.72.158.90`（Tailscale IP）或
`192.168.66.1`（家中局域网）。128G 除 ksmbd 加 tailscale 接口绑定外，
还需补防火墙 tailscale 区域（input ACCEPT + tailscale↔lan 双向转发，
配置命令同附录 C2），否则 tailnet 内 TCP 全不通（tailscale ping 能通是
tailscaled 自己应答的，不代表防火墙放行）。

---

*第二部完。128G 第一阶段教程见 `AX6000-128G/京东云AX6000-OpenWrt优化配置方案.md`。*
