# 京东云 AX6000（RE-CP-03）OpenWrt 优化配置方案

> 原则：**先稳定，再测性能，再增加功能**。每一步只改一类配置、改完验证，出问题能回退。
>
> 设备实测信息：MT7986A（Filogic 830，四核 A53 2.0GHz）+ 1GB 内存 + MT7976C 无线，
> 1 个 2.5GbE 口（eth1，WAN，PPPoE 拨号上网）+ 4 个千兆口（lan1–lan4，桥接 br-lan），
> 固件 OpenWrt 25.12.5（apk 包管理器），双频 Wi-Fi 正常广播，SQM 已启用。

---

## 教程阶段总览

> **目前所有已完成的操作都属于「第一阶段教程」**，本文档从阶段 0 到附录 L 即第一阶段的
> 完整记录（2026-09-30 全部实施并验收通过）。

### 第一阶段教程（✅ 已完成，本文档全部内容）

| 内容 | 位置 |
|---|---|
| 现状盘点与无线/上网基础 | 阶段 0、阶段 1 |
| 无线 WAN（热点过渡） | 附录 A |
| 中文界面设置 | 《京东云AX6000-OpenWrt设置中文教程》+ 附录 D1/D2 |
| 128GB eMMC 扩容与实测 | 附录 B |
| SMB 网络共享（NAS） | 附录 C |
| 实操问题集（12 条踩坑） | 附录 D |
| 社区最新经验与稳定性调整 | 附录 E |
| Argon 界面美化 | 附录 F |
| 重启存活验收 / 高负载稳定性 | 附录 G、H |
| 网口对应关系 | 附录 I |
| 宽带 PPPoE 接入 | 附录 K1 |
| 性能取舍（SQM 选定）与 Wi-Fi/有线对比 | 阶段 2、附录 K2、L |
| 总验收与配置备份 | 阶段 4、附录 G |

### 第二阶段（⏸ 预留，按需启动，见「阶段 3」章）

访客/IoT VLAN 隔离、WireGuard 组网、广告过滤、IPv6 应用、其他插件——
每加一类功能验证一次，不堆叠。另有随时可做的小项：更换 Wi-Fi/SMB 强密码、
断电 10 秒清 PPE 残留、iPhone 热点开「最大兼容性」恢复备用链路。

---

## 阶段 0：现状盘点（动手前必做）

当前实际配置（2026-09-30 实测读取）：

| 项目 | 现状 | 风险 |
|------|------|------|
| 2.4GHz（radio0） | **已启用**：SSID `ExampleWiFi`、WPA2/WPA3 混合、信道 6（跟随热点）、HE20；同时作 sta 连热点 | 正常运行 |
| 5GHz（radio1） | **已启用**：SSID `ExampleWiFi`、WPA2/WPA3 混合、信道 149、HE80 | 正常运行 |
| 国家码 | **已设置为 CN** | 正常 |
| WAN（eth1，2.5G 口） | DHCP 模式，**网线未插**（NO-CARRIER） | 路由器本身不能上网 |
| 无线 WAN（wwan） | **已配置**：2.4G 客户端模式连 iPhone 热点，获得 172.20.10.4 | 已联网（临时上行） |
| 系统时间/时区 | **已校正**：Asia/Shanghai（CST-8），NTP 用阿里/国内源 | 正常 |
| LAN（lan1–4） | 桥接 br-lan，192.168.1.1 | 正常 |
| 硬件卸载 / SQM | 均未配置 | 待测试 |

**WAN 现状**：有线 WAN 口未接线，已通过「无线 WAN」方案临时联网——2.4GHz 频段以客户端
模式连接手机热点（见附录 A），路由器可正常下载软件包（软件源 11137 个包可用）。
**长期仍建议 WAN 口接上级光猫/路由**，无线热点上行只作过渡。

> ⏩ **2026-09-30 更新**：当日已接入宽带（光猫桥接 + PPPoE 拨号，公网 61.181.x.x），
> 无线 WAN 转为备用链路，详见附录 K。

**重要：无线配置修复系统时间后才可正常下载**——路由器出厂时间停在 2026-06-29，
SSL 证书校验会失败（`wget: exited with error 5`），需先校正时间再 `apk update`。

---

## 阶段 1：稳定基础

### 1.1 无线基础

```bash
# 设置中国国家码（两个频段都要）
uci set wireless.radio0.country='CN'
uci set wireless.radio1.country='CN'

# 2.4GHz：20MHz 频宽，信道 1/6/11 中选干扰最少的（先扫一遍环境）
uci set wireless.radio0.htmode='HE20'
uci set wireless.radio0.channel='6'          # 按扫描结果调整

# 5GHz：80MHz 频宽，优先非 DFS 信道
uci set wireless.radio1.htmode='HE80'
uci set wireless.radio1.channel='149'        # 149–161 这段干扰通常更少、可用功率更高

# 加密：WPA2/WPA3 混合模式（兼容老设备，新设备自动用 WPA3）
uci set wireless.default_radio0.encryption='sae-mixed'
uci set wireless.default_radio0.key='<你的WiFi密码>'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio1.key='<你的WiFi密码>'

# 修改 SSID（建议 2.4G 和 5G 用不同名字，便于排查）
uci set wireless.default_radio0.ssid='<你的SSID>_2.4G'
uci set wireless.default_radio1.ssid='<你的SSID>_5G'

# 启用无线
uci set wireless.radio0.disabled='0'
uci set wireless.radio1.disabled='0'
uci commit wireless
wifi reload
```

**决策依据：**

- **信道**：国内 5GHz 非 DFS 信道为 36–48 和 149–165。52–64 属于 DFS 信道，检测到雷达会强制切换、造成短暂断网，附近若有机场/气象雷达要避开；149–161 可组成一个干净的 80MHz 块，通常是家用首选。2.4GHz 只有 1/6/11 三个不重叠信道。
- **频宽**：先 2.4G 20MHz + 5G 80MHz。**暂不开 160MHz**——160MHz 会占用更多信道、更容易踩到 DFS 和干扰，稳定性验证通过后再考虑。
- **加密**：纯 WPA3 会让部分老设备/IoT 设备连不上；`sae-mixed`（WPA2/WPA3 混合）是目前兼容性最好的方案。如果家里有很老的设备连混合模式也失败，再退回纯 `psk2`（WPA2-AES）。
- **发射功率**：默认即可，暂不手动调高。
- **802.11r 快速漫游**：**单台 AP 不要开**。它只对多 AP 漫游有意义，且部分客户端（尤其老款苹果设备、IoT 设备）对 802.11r 实现有兼容性问题。等以后明确要加第二台 AP 组漫游时，再连同 802.11k/v 一起测试开启。

**验证**：`iw dev` 查看接口状态；手机/电脑连接两个频段各测一次速；`logread -e wifi` 看有无报错。

### 1.2 网口利用

本机网口布局：**eth1 = 2.5GbE（当前 WAN）**，lan1–lan4 = 千兆（br-lan）。

- 宽带 ≤ 1000M：2.5G 口可作 WAN，也可改作 LAN 接 NAS/电脑（此时把 lan1 划为 WAN）
- 宽带 > 1000M：2.5G 口必须作 WAN 才不浪费带宽

**确认协商速率**（插好网线后执行）：

```bash
ethtool eth1 | grep -E 'Speed|Duplex|Link'    # 期望 2500Mb/s
ethtool lan1 | grep -E 'Speed|Duplex|Link'    # 期望 1000Mb/s
```

若协商速率低于预期（比如只有 100Mb/s），基本是网线或水晶头问题，换超五类以上成品线。

**改 2.5G 口为 LAN 的方法**（仅在有需求时做）：

```bash
# WAN 改到 lan1，2.5G 口 eth1 加入 LAN 桥
uci set network.wan.device='lan1'
uci set network.wan6.device='lan1'
uci del_list network.@device[0].ports='lan1'
uci add_list network.@device[0].ports='eth1'
uci commit network
service network restart
```

> 注意：执行后 WAN 网线要插到 LAN1 口，2.5G 口变成普通 LAN 口。

**阶段 1 验收**：WAN 正常获取地址、有网络；两个 Wi-Fi 频段可连、有密码；各网口协商速率达标。连续用一天观察有无断流。

---

## 阶段 2：性能测试与取舍（✅ 已完成，实测结果见附录 K/L 与性能记录表）

### 2.1 先记录基准（任何加速功能都不开）

```bash
# 路由器上装 iperf3（需要 WAN 已联网）
apk update && apk add iperf3

# 电脑上：iperf3 -c 192.168.1.1（路由器跑 iperf3 -s）
# 分别测：有线 LAN→WAN 吞吐、Wi-Fi 2.4G/5G 吞吐
```

同时跑一次波形测速（波形 bufferbloat 测试或 speedtest），记录：
**空载延迟、满载延迟、下载/上传吞吐、测试时路由器 CPU 占用（`top` 观察）**。
把数字记在本方案末尾的验收表里，后面所有改动都和它对比。

### 2.2 两条路线二选一（核心取舍）

| | 路线 A：极速转发 | 路线 B：低延迟优先 |
|---|---|---|
| 适合 | 千兆以上宽带、NAS 大文件互传、跑满带宽 | 游戏、视频会议、直播、多人共用 |
| 做法 | 开硬件流量卸载 + MediaTek WED | 开 SQM/CAKE，关闭硬件卸载 |
| 代价 | SQM 失效（卸载流量不过队列） | 吞吐略降，CPU 占用升高 |

**两者不兼容，先想清楚要什么。** 家用混合场景建议先试路线 B——MT7986 四核 A53 跑 CAKE 到 500M 左右没压力；如果宽带接近或超过千兆，再评估路线 A。

### 2.3 路线 B：SQM/CAKE（低延迟优先，推荐先做这个）

```bash
apk add luci-app-sqm sqm-scripts
```

LuCI：**网络 → SQM QoS**，关键参数：

- 接口：选**真正的出口设备**。DHCP/静态 IP 是 `wan`（eth1）；PPPoE 拨号是 `pppoe-wan`。可用 `ifstatus wan | jsonfilter -e '@.l3_device'` 确认
- 队列规则：`cake`，脚本：`piece_of_cake.qos`
- 下载/上传带宽：填**实测值的 90%**（单位 kbit/s）。若 ISP 有突发限速策略导致分数不稳，降到 85%
- 链路层适配：PPPoE 选 `pppoe` 相关项；不清楚就先默认

**必须同时关闭硬件流量卸载**（网络 → 防火墙 → 常规设置：取消勾选「硬件流量分流」；软件流量分流可保留，若发现 SQM 不达标再把它也关掉）。

验证队列真的生效：

```bash
tc -s qdisc show dev eth1        # 应看到 cake 的统计
uci show firewall | grep -i offload   # flow_offloading_hw 应为 '0'
logread | grep -i sqm
```

**已知坑**：个别版本 CAKE 在高带宽（>700M）长时间运行后吞吐衰减，重启恢复——若遇到，改 fq_codel + `simple.qos`（CPU 开销还低约 15%），或试 25.12 起自带的 cake-mq 多核队列。另外 MTK 平台改完卸载/SQM 配置后**断电 10 秒再开机**，避免 PPE 硬件表项残留导致 SQM 部分失效。

### 2.4 路线 A：硬件卸载 + WED（极速转发，仅实测需要时启用）

```bash
# LuCI：网络 → 防火墙 → 勾选「硬件流量分流」
# 或命令行：
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci commit firewall
service firewall restart
```

WED（Wireless Ethernet Dispatch，无线流量也走硬件加速）在 25.12 的 mt76 驱动上一般默认开启，确认：

```bash
cat /sys/module/mt7915e/parameters/wed_enable    # Y=已启用
```

**启用后必须验证稳定性**：连续大流量 Wi-Fi 传输 30 分钟以上，观察是否断流、`logread` 有无 mt76 报错、CPU 是否异常。WED 会绕过部分无线队列管理，若发现 Wi-Fi 满载延迟变差或偶发断连，就关掉回到路线 B。

**阶段 2 验收**：选定路线后，复测吞吐与满载延迟，和 2.1 基准对比；连续挂机 24 小时无异常。

---

## 阶段 3（第二阶段，预留未实施）：按需增加功能（一次只加一类）

> 本章内容属于**第二阶段**，第一阶段未做。稳定运行后再按需添加，
> **每加一类都回阶段 2 的测试方法验证一遍**：

| 优先级 | 功能 | 说明 |
|---|---|---|
| 1 | 访客网络 / IoT VLAN 隔离 | 新建独立网段 + 防火墙区域，IoT 设备只允许上网、不能访问内网 |
| 2 | IPv6 | 确认 wan6 获取到前缀，开 DHCPv6/RA；运营商支持就顺手开 |
| 3 | WireGuard | `apk add luci-proto-wireguard`，回家组网/远程访问用；MT7986 跑 WireGuard 单线程约几百 Mbps |
| 4 | 广告过滤 | adblock 或 AdGuard Home；eMMC 空间充足（可用 434M+），但会占内存和 DNS 路径，最后再加 |
| 5 | 其他插件 | ddns、UPnP、网络唤醒等，按需 |

**纪律**：不要一开始就堆插件。每加一个服务都会占用 CPU/内存、增加故障面；出问题时也能立刻定位到刚加的那一个。

---

## 阶段 4：总验收与备份（✅ 2026-09-30 已完成，详见附录 G/H/K/L）

### 验收清单

- [x] Wi-Fi 连续传输：满载 8 分钟 188GB 零错误（附录 H）
- [x] 重启验证：重启后全配置自动恢复（附录 G）
- [x] 网口速率：2.5G 口协商 2500Mbps、lan2 千兆（附录 I、K1）
- [x] 吞吐与满载延迟：宽带三路线对比完成，SQM 选定（附录 K/L）
- [x] 存储分区：`/data` 112.4G 自动挂载正常（附录 B/G）；U-Boot 网页刷机恢复入口确认
- [ ] 漫游（多 AP 时）：802.11k/v 实测——单 AP 暂不需要，归入第二阶段
- [x] 断电 10 秒重启（清 PPE 残留）：2026-09-30 20:31 完成，拨号/Wi-Fi/数据盘/SMB/SQM/主题全部自动恢复，公网延迟 11.0ms

### 备份配置（重要）

```bash
# 路由器上生成配置备份
sysupgrade -b /tmp/backup-$(date +%F).tar.gz
```

然后电脑上下载回来：

```bash
scp -O root@192.168.1.1:/tmp/backup-*.tar.gz ./
```

建议把备份文件存到本教程目录。以后每次大改配置前都重新备份一次。恢复方法：LuCI「系统 → 备份/升级」上传恢复，或 `sysupgrade -r`。

---

## 性能记录表（实测后填写）

| 测试项 | 基准（未优化） | 阶段 2 之后 | 备注 |
|---|---|---|---|
| 有线上行（Mac→路由器） | 945 Mbps（118 MB/s） | | dd/nc，256MB |
| 有线下行（路由器→Mac） | 933 Mbps（117 MB/s） | | HTTP 拉取，128MB |
| 5G Wi-Fi 下行（路由器→Mac） | **766 Mbps（95.7 MB/s）** | | SMB 读 512MB；802.11ax HE80，协商 1080 Mbps，信号 -11dBm |
| 5G Wi-Fi 上行（Mac→路由器） | **842 Mbps（105.3 MB/s）** | | SMB 写 512MB，同链路 |
| 2.4G Wi-Fi 下行（路由器→Mac） | **150 Mbps（18.7 MB/s）** | | SMB 读 256MB；802.11ax HE20，信道 6 |
| 2.4G Wi-Fi 上行（Mac→路由器） | **152 Mbps（19.0 MB/s）** | | SMB 写 256MB，同链路 |
| 空载延迟（到网关，有线） | <1 ms | | |
| 空载延迟（公网 223.5.5.5，经热点） | 约 35–60 ms | | 热点链路本身延迟 |
| 空载延迟（公网 223.5.5.5，经宽带 PPPoE） | **11.6 ms** | | 宽带接入后，远优于热点 |
| 宽带下行（PPPoE 拨号后） | 470 Mbps | 497 Mbps（卸载）/ 378 Mbps（SQM） | 500M 宽带；详见附录 K |
| 宽带上行 | 84 Mbps | 76 Mbps（SQM 塑形） | |
| 宽带满载延迟（bufferbloat） | 平均 24.8 / 峰值 74.9 ms | **SQM 后：平均 21.0 / 峰值 34.8 ms** | 卸载路线峰值 144.7ms，已弃用 |
| 满载延迟（bufferbloat，5G 满载时到网关） | 平均 9.5ms / 峰值 44ms | | 8 分钟持续满载实测，详见附录 H |
| 测速时 CPU 峰值 | 负载 2.6 / 4 核（约 65%） | | 温度峰值 56℃ |

> **Wi-Fi 测速方法警示（本次实测踩过）**：Mac 同时插着网线（Ethernet 也在 192.168.1.x 网段）时，
> 已建立的 SMB 会话会永远走最初建立连接的那块网卡——换 Wi-Fi 频段、甚至断开 Wi-Fi 重连都不会切换，
> 测出来的其实是网线速度。正确做法：切换频段后**先 `umount` 再重新挂载**，并用
> `netstat -an | grep 192.168.1.1.445` 确认源 IP 是 Wi-Fi 接口的地址（如 192.168.1.249），
> 才能保证测的是无线。上表 Wi-Fi 数据均按此法复测确认。

---

## 附录 A：无线 WAN（路由器连手机热点上网）实操记录

适用场景：WAN 口暂时无法接线时，用 2.4GHz 频段作为客户端连接手机热点，让路由器自身联网
（装软件包、时间同步等）。本次实操连接的是 iPhone 热点（2.4GHz 频段，信道 6）。

```bash
# 1. 创建 wwan 网络接口（DHCP）
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'

# 2. 在 2.4G 射频（radio0）上创建客户端（sta）接口
uci set wireless.radio0.disabled='0'
uci set wireless.sta0=wifi-iface
uci set wireless.sta0.device='radio0'
uci set wireless.sta0.mode='sta'
uci set wireless.sta0.network='wwan'
uci set wireless.sta0.ssid='<热点名称>'
uci set wireless.sta0.encryption='psk2'
uci set wireless.sta0.key='<热点密码>'

# 3. 把 wwan 加入防火墙 wan 区域（通常 @zone[1]，先确认）
uci show firewall | grep "\.name='wan'"        # 确认 wan 区域编号
uci add_list firewall.@zone[1].network='wwan'

# 4. 生效并验证
uci commit
wifi reload
ifstatus wwan          # "up": true 且有 ipv4-address 即成功
ping -c 2 223.5.5.5    # 验证能上网
```

**注意事项：**

- iPhone 热点建议开启「最大兼容性」（强制 2.4GHz），兼容性最好
- 同一射频做 sta 时信道跟随热点（本次自动落在信道 6），该射频若再发 AP 会共用此信道
- 路由器重启后只要热点开着会自动重连；热点关闭期间路由器断网，恢复后自动重连
- 若 `apk update` 报 SSL 错误，先检查系统时间是否正确（`date`），时间不对会导致证书校验失败
- **关键坑（本次实测踩过）**：`uci add_list` 把 wwan 加进 wan 区域后，**必须 `service firewall restart`**（或重启路由器）规则才真正生效。否则现象非常迷惑：路由器自己能上网、客户端能解析 DNS（dnsmasq 代查），但所有客户端的流量都出不去。验证方法：`nft list chain inet fw4 forward | grep iifname`，wan 区域一行里必须包含无线客户端接口（如 `phy0-sta0`）
- 停用无线 WAN：`uci set wireless.sta0.disabled='1'; uci commit; wifi reload`；
  彻底移除再删 `network.wwan` 和防火墙区域里的 wwan 成员（删后同样要重启防火墙）

---

## 参考来源

- OpenWrt SQM/CAKE 配置与带宽取值（实测 90% 原则、接口选择、卸载冲突）：恩山/社区实操帖与 [Jingqi 的 OpenWrt 笔记](https://192217.space/notebook/practice/lab/openwrt-router.html)、[X @kafkaup](https://x.com/bingwujinyi/status/2081936014990553579)
- 硬件卸载与 SQM 不兼容、WED 实验特性说明：[Fatjon Dauti 的 OpenWrt 博文](https://jondauti.wordpress.com/2025/07/29/intro-to-custom-router-firmware-with-openwrt/)、[LinkSpeed 游戏路由设置指南](https://www.linkspeed.co.uk/troubleshooting-guides/best-router-settings-for-gaming.php)
- CAKE 高带宽长时间运行衰减问题与 fq_codel 替代：[OpenWrt GitHub issue #21873](https://github.com/openwrt/openwrt/issues/21873)
- WED 在 mt7986 上的启用确认方式：[openwrt/mt76 issue #815](https://github.com/openwrt/mt76/issues/815)
- MTK 平台 PPE 残留需断电重启：[菊花博客 SQM 配置](https://wjarpg.fun/openwrt-%E9%85%8D%E7%BD%AEsqmai/)
- 国内 5GHz 信道/DFS/功率说明：[知乎信道讨论](https://www.zhihu.com/question/522986327)、[CSDN 企业 Wi-Fi 覆盖攻略](https://bbs.csdn.net/weixin_33326218/article/details/100380346)
- 本机硬件规格（MT7986A / RTL8221B 2.5G / MT7531AE / MT7976C）：[知乎刷机教程](https://zhuanlan.zhihu.com/p/714046317)

---

## 附录 B：启用 128GB eMMC 闲置空间（已实施，2026-09-30）

**背景**：官方镜像的分区表只覆盖约 500MB，128GB eMMC 剩余约 114.7 GiB 未分区闲置。
本次已新建第 6 分区（`/dev/mmcblk0p6`，ext4，卷标 `data`），挂载到 `/data` 并设置开机自动挂载。

**操作步骤回顾：**

```bash
apk add sgdisk e2fsprogs kmod-fs-ext4 block-mount

# 镜像 GPT 只声明了小磁盘：需先修复备份头并把分区表扩展到整盘
sgdisk -e /dev/mmcblk0
# 确认空闲空间出现：sgdisk -p /dev/mmcblk0 → "Total free space ... 114.8 GiB"

# 在空闲区域建分区（起始扇区 1048576 = 512MiB 处，即原镜像末尾）
sgdisk -n 6:1048576:0 -t 6:8300 -c 6:data /dev/mmcblk0

# 内核认不出新分区就重启一次
reboot

mkfs.ext4 -L data /dev/mmcblk0p6
mkdir -p /data && mount /dev/mmcblk0p6 /data

# 开机自动挂载
block detect > /etc/config/fstab
uci set fstab.@mount[0].enabled='1'
uci commit fstab
/etc/init.d/fstab enable
```

**实测结果：**

| 项目 | 数值 |
|---|---|
| 分区容量 | 112.4 GiB（可用 106.6 GiB） |
| 顺序写入 | **约 128 MB/s**（1GB，oflag=direct+fsync） |
| 顺序读取 | **约 171 MB/s**（1GB，清缓存后直读） |
| 原始直读（空区域） | 约 136 MB/s |
| 闪存健康度 | 寿命消耗 0–10%（life_time=0x01），无预警，接近全新 |

**注意**：修改 GPT 前确认 `sgdisk -p` 输出里原分区（ubootenv / factory / fip / recovery / production）
完整无重叠；本次只使用空闲区域，未触碰任何现有分区。`/data` 可用于 SMB 共享、Docker、
AdGuard Home 数据等，与系统分区互不影响。

### B2. 内置硬盘（eMMC）好坏自查方法

这台机器的 128GB 是 eMMC 闪存芯片，按 JEDEC 标准内置了健康寄存器，
**一条命令即可自查**（SSH 登录路由器执行）：

```bash
cat /sys/class/block/mmcblk0/device/life_time /sys/class/block/mmcblk0/device/pre_eol_info
cat /sys/class/block/mmcblk0/device/name /sys/class/block/mmcblk0/device/date
```

本机 2026-09-30 实测输出与解读：

```
life_time:    0x01 0x00      ← 寿命消耗
pre_eol_info: 0x01           ← 寿命预警
芯片:         SLD128（128GB），出厂 08/2022
```

**寿命消耗（life_time）两个值**分别对应主存储区（TYP_A）和增强区（TYP_B）：

| 值 | 含义 |
|---|---|
| 0x00 | 该区域未启用 |
| **0x01** | **寿命消耗 0–10%（本机当前值，接近全新）** |
| 0x02 | 10–20% |
| … | 每档 +10%，直到 0x0A = 90–100% |
| 0x0B | 已超过设计寿命 |

**寿命预警（pre_eol_info）**：

| 值 | 含义 |
|---|---|
| **0x01** | **正常（本机当前值）** |
| 0x02 | 警告：备用块已消耗 80% |
| 0x03 | 紧急：尽快备份数据 |

**判断口诀**：life_time 第一个值 ≤ 0x03 且 pre_eol = 0x01 → 健康，放心用；
life_time 逐年缓慢上升属正常（路由器写入量很小，十年都用不完）；
一旦 pre_eol 变成 0x02/0x03，立刻备份 `/data` 重要数据。

想看更详细的原始寄存器，可 `apk add mmc-utils` 后执行
`mmc extcsd read /dev/mmcblk0 | grep -iE "life|eol"`（效果相同，sysfs 方式更简便）。
建议每半年或大量写入后复查一次。


---

## 附录 C：SMB 网络共享（已实施，2026-09-30）

**目标**：把 `/data` 分区通过 SMB 协议共享出去，Mac / Windows / 手机都能直接访问路由器上的 112GB 空间。

**安装与配置：**

```bash
apk add ksmbd-server luci-app-ksmbd

# 共享配置（uci 方式，也可在 LuCI「服务 → Network Shares」里点鼠标完成）
uci add ksmbd share
uci set ksmbd.@share[-1].name='data'
uci set ksmbd.@share[-1].path='/data'
uci set ksmbd.@share[-1].read_only='no'
uci set ksmbd.@share[-1].guest_ok='no'
uci set ksmbd.@share[-1].users='share'
uci set ksmbd.@share[-1].force_root='1'      # 关键：不设则客户端写入 Permission denied
uci commit ksmbd

# 添加共享账号（一定要用 -p 非交互方式指定密码，交互式容易出错）
ksmbd.adduser -a share -p '<共享密码>'

/etc/init.d/ksmbd enable && /etc/init.d/ksmbd restart
```

**访问方式：**

| 平台 | 操作 |
|---|---|
| Mac | 访达按 `Cmd+K` → 输入 `smb://192.168.1.1/data` → 用户名 `share` |
| Windows | 资源管理器地址栏输入 `\\192.168.1.1\data` |
| iPhone / 安卓 | 「文件」App 或支持 SMB 的文件管理器，服务器填 `192.168.1.1` |

**实测结果（Mac 经千兆有线挂载）：** 挂载、读、写全部正常，64MB 文件写入约 **62.5 MB/s**
（受单连接 SMB 开销影响，低于裸盘 128 MB/s 属正常；大文件持续传输会更接近磁盘上限）。

**踩坑记录（本次实测）：**

- `ksmbd.adduser` 不带 `-p` 会进入交互式提问，脚本化操作务必用 `-p` 一次到位；设错了就
  `ksmbd.adduser -x share` 删掉重来。
- `ksmbd.adduser -s` 不是「查看状态」，而是关停 SMB 服务（stop）。查已有用户直接看
  `cat /etc/ksmbd/ksmbdpwd.db`。
- 共享目录属主是 root，不设 `force_root='1'` 时客户端能登录能看目录，但一写就
  Permission denied——现象迷惑，根源就是这一行。
- 安全提醒：共享密码请使用强密码，不要与 Wi-Fi 弱密码相同；`force_root` 意味着 SMB 写入
  以 root 身份落盘，共享账号务必只给信任的设备。


---

## 附录 D：本次实操问题集（踩坑大全，按出现顺序）

> 以下每一个问题都是本次配置过程中真实遇到并解决的，按「现象 → 原因 → 解决」整理，
> 复现或给他人做教程时可当故障排查手册用。

### D1. LuCI 语言设置后下拉框显示「自动」，界面不变中文

- **现象**：装好中文语言包后，系统设置里语言选了「zh-cn」但界面仍是英文，下拉框回显「自动」。
- **原因**：OpenWrt 的语言代码是 `zh_cn`（下划线），不是 `zh-cn`。代码写错等于没选。
- **解决**：`uci set luci.main.lang='zh_cn'; uci commit luci`；LuCI 界面上选「简体中文」。

### D2. 路由器没联网时装不了中文语言包

- **现象**：`apk add luci-i18n-base-zh-cn` 失败，因为配中文之前路由器还没上网。
- **解决**：在有网的电脑上下载对应版本的 `.apk` 离线包，`scp -O` 传到路由器 `/tmp` 后
  `apk add --allow-untrusted /tmp/xxx.apk`（注意 **scp 必须加 `-O`**：OpenWrt 的 SSH
  服务端没有 sftp 子系统，不加会报 "subsystem request failed"）。

### D3. apk 安装报 SSL 证书错误

- **现象**：路由器有网了，`apk update` 仍报 SSL 证书校验失败。
- **原因**：路由器断电后系统时间停在出厂日期（本次停在 2026 年 6 月），证书「还没生效」。
- **解决**：先 `date -s` 校正时间，再配 NTP 自动对时（本次用阿里源 `ntp.aliyun.com`），
  时区 `Asia/Shanghai`。**任何 SSL/下载异常，第一件事先看 `date`。**

### D4. 手机连上路由器 Wi-Fi 却无法上网（最迷惑的坑）

- **现象**：路由器自己能 ping 通公网，客户端能解析 DNS，但所有客户端流量都出不去。
- **原因**：用 `uci add_list` 把无线 WAN（wwan）加进 wan 防火墙区域后，只 `wifi reload` 了，
  **防火墙规则没有真正重建**。
- **解决**：改完防火墙区域成员必须 `service firewall restart`（或重启路由器）。
- **验证**：`nft list chain inet fw4 forward | grep oifname`，wan 区域的 oifname 里
  必须包含无线客户端接口（如 `phy0-sta0`）。

### D5. expect 脚本把路由器密码填进了别的提示框

- **现象**：脚本化执行 `ksmbd.adduser -a share`（交互式）时，路由器的 root 密码被
  当成 SMB 密码填了进去，账号密码设错。
- **原因**：expect 的 `(P|p)assword:` 正则会匹配任何密码提示，不只 SSH 的。
- **解决**：交互式命令一律改用非交互参数（`ksmbd.adduser -a share -p '<密码>'`）；
  设错了用 `ksmbd.adduser -x share` 删除重来。同类教训：Tcl 会把 uci 匿名段
  `@system[0]` 里的 `[0]` 当命令执行，要写 `\@system\[0\]` 转义。

### D6. `ksmbd.adduser -s` 把 SMB 服务停了

- **现象**：想查看 SMB 用户状态，执行后共享直接断线。
- **原因**：`-s` 是 stop（关停服务），不是 status。
- **解决**：查已有用户直接 `cat /etc/ksmbd/ksmbdpwd.db`；被停后
  `/etc/init.d/ksmbd restart` 拉起。

### D7. SMB 能登录、能看目录，但一写入就 Permission denied

- **现象**：Mac 挂载成功、目录列表正常，新建/粘贴文件全部失败。
- **原因**：共享目录 `/data` 属主是 root，SMB 用户 `share` 是无权写入的系统账号。
- **解决**：共享配置加 `force_root='1'`（写入以 root 身份落盘）。
  LuCI 里对应「Force Root」勾选框。

### D8. Mac 访达连接共享后右键没有「粘贴」

- **现象**：能打开共享、能复制进去的文件出来，但右键菜单没有粘贴选项。
- **原因**：连接时在登录框选了「**客人**」——访客身份只读。
- **解决**：推出已挂载的卷，重新 `Cmd+K` 连接，选「**注册用户**」，账号 `share`。
  若提示密码错误，先在「钥匙串访问」里删掉 192.168.1.1 的旧凭据。
- **附注**：`/Volumes` 下手动建挂载点需要 root 权限；挂到用户目录（如 `~/RouterData`）
  一样会在访达里显示为磁盘卷。

### D9. eMMC 认不出剩余 114GB 空间

- **现象**：`lsblk` 显示 128GB 盘，但分区表只有约 500MB，`sgdisk -p` 报备份头位置异常。
- **原因**：官方镜像的 GPT 是按小磁盘写的，备份头放在 500MB 处，剩余空间未被分区表覆盖。
- **解决**：先 `sgdisk -e /dev/mmcblk0` 把备份头移到盘尾，空闲空间才会出现；
  新建分区后内核若不识别（`/dev/mmcblk0p6` 不存在），**重启一次**再格式化。
- **安全前提**：操作前确认 `sgdisk -p` 里原有分区（ubootenv/factory/fip/recovery/production）
  完整无重叠，只在空闲区域动手。

### D10. Wi-Fi 测速测出了「不可能」的速度（900Mbps 的 2.4G）

- **现象**：2.4GHz 20MHz 跑出 900+ Mbps，远超物理上限。
- **原因**：Mac 同时插着网线（Ethernet 同网段），**已建立的 SMB 会话永远走最初建立连接的
  那块网卡**，换频段、断开重连 Wi-Fi 都不会切换——测的是网线。
- **解决**：切频段后先 `umount` 再重新挂载，并用
  `netstat -an | grep 192.168.1.1.445` 确认源 IP 是 Wi-Fi 接口地址（如 192.168.1.249）
  再开测。另外 Mac 的「自动加入热点」会抢占 Wi-Fi，测试前可用
  `networksetup -removepreferredwirelessnetwork en1 "<热点名>"` 暂停自动加入，测完恢复。

### D11. 路由器 busybox 版 nc 没有监听模式

- **现象**：`nc -l -p 8888` 直接打印用法说明，无法做吞吐测试服务端。
- **解决**：改用 SMB 真实文件传输测速（dd 读写共享上的大文件），结果更贴近实际使用；
  或 `apk add iperf3` 装专业工具。

### D12. 遗留安全提醒

- Wi-Fi 密码为 8 位纯数字弱密码（已脱敏）、SMB 密码同为弱密码，且 SMB 开了 `force_root`（写入即 root 落盘），
  **强烈建议尽快更换为强密码**，共享账号只给信任设备。
- 路由器管理员密码不要写进任何教程/文档（本教程统一用 `<你的密码>` 占位）。


---

## 附录 E：最新社区经验调研与针对性调整（2026-09-30）

**调研来源**：OpenWrt 25.12 官方发行说明与已知问题、OpenWrt GitHub issue、OpenWrt 论坛
mediatek/filogic 板块、社区 ksmbd 使用经验帖。结合本机（MT7986A / OpenWrt 25.12.5）现状筛选适用项。

### E1. 本次已实施的调整

| 调整项 | 原因 | 操作 |
|---|---|---|
| 禁用 `crypto_safexcel` 加密加速模块 | 同平台（GL-MT6000，同为 MT7986 filogic）在 25.12 上有实测报告：该模块与 ksmbd SMB3 共存会导致**整机冻结约 30 秒**（OpenWrt issue #21979）。本机不用 IPsec，该模块加载后无人使用，禁用零损失 | `rmmod crypto_safexcel`，并将 `/etc/modules.d/90-crypto-hw-safexcel` 改名为 `.disabled` 阻止开机加载。日后若用 IPsec VPN 需要它，把文件名改回并重启即可 |
| 开启包转向 packet steering | 免费的多核优化：网络中断分摊到 MT7986 的四个 A53 核，高负载时降低单核瓶颈 | `uci set network.globals.packet_steering='1'` + `service network restart` |
| ksmbd 显式绑定 `lan` 接口 | 社区经验：ksmbd 不指定监听接口时 Windows/Mac 重连容易出怪问题；且重启服务要用 stop/start 而非 restart | `uci set ksmbd.@globals[0].interface='lan'` |

调整后已回归验证：热点重连正常、双频 Wi-Fi 正常、SMB 读写正常。

### E2. 调研确认「不要动」的项（与我们的方案一致）

- **不开 802.11r**：25.12 已知问题——WPA3 + FT 会导致部分客户端连不上（issue #22200）。
  单台 AP 本来也用不到。
- **160MHz 频宽**：25.12 上本身有配置缺陷（issue #22481），且国内 160MHz 涉及 DFS 雷达检测，
  实测 80MHz 已跑满 842Mbps，维持现状。
- **不用 cake_mq**：25.12 已知问题——部分配置下吞吐异常偏低（issue #22344）。
  将来开 SQM 时用普通 `cake` 或 `fq_codel`。
- **WED 暂不开启**：mt76 驱动对 WED 的支持仍在活跃修复中，我们的热点链路瓶颈不在转发，
  保持关闭更稳。
- **无需升级固件**：25.12.5 已是当前最新稳定版，含内核 6.12.94 与 OpenSSL/Dropbear 安全修复。

### E3. 备用经验（将来按需启用）

- 将来若上 **SQM**：用 `cake` + `piece_of_cake`，带宽设为实测值 90%；避开 cake_mq；
  改完卸载/SQM 配置后断电 10 秒再开机，避免 PPE 表项残留。
- 将来若用 **IPsec VPN**：需重新启用 crypto_safexcel（见 E1 恢复方法），
  但注意它与 ksmbd SMB3 的共存风险，届时应把 ksmbd 协议上限锁到 SMB2
  （`uci set ksmbd.@globals[0].max_protocol='SMB2'`）或改用 samba4。
- 多台 AP 组网时再考虑 802.11k/v（单 AP 无意义），并避开 WPA3+r 的组合。


---

## 附录 F：界面美化——Argon 主题（已实施，2026-09-30）

默认 Bootstrap 主题字体小、样式陈旧。已换装 **Argon v2.4.7**（最流行的 LuCI 第三方主题：
大字卡片式布局、毛玻璃、深浅色跟随系统），并安装其中文语言包与设置面板。

**安装步骤：**

```bash
# 官方源里没有 Argon，从作者 GitHub Release 下载 apk 版（25.12 起用 apk 包管理器）：
# https://github.com/jerrykuku/luci-theme-argon/releases/latest
# 三个包：luci-theme-argon、luci-app-argon-config、luci-i18n-argon-config-zh-cn
scp -O *.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
cd /tmp && apk add --allow-untrusted luci-theme-argon*.apk luci-app-argon-config*.apk luci-i18n-argon-config*.apk

# 切换主题
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# 新装的页面打不开（404）时清 LuCI 缓存即可
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*
```

**设置入口**：「系统 → Argon Config」（中文界面），可调主色调、透明度、毛玻璃、深浅色模式。

**已做的调整**：壁纸来源从 Bing 在线改为**内置**——登录页不再每次从互联网拉图，
零热点流量消耗、打开更快。

**回退方法**：`uci set luci.main.mediaurlbase='/luci-static/bootstrap'; uci commit luci`
即可回到默认主题，无需卸载。

**效果对比（同一「状态概览」页）：**

| | 截图 |
|---|---|
| 美化前（默认 Bootstrap） | `02-状态概览页.png` |
| 美化后（Argon） | `11-界面美化-新主题概览.png` |
| Argon 设置面板 | `10-界面美化-Argon主题设置.png` |

差异要点：字体更大更清晰、紧凑表格改为大留白卡片、顶栏蓝紫主色调、按钮更大、
深色模式跟随系统自动切换。本目录早期截图（01–09）均为美化前的默认主题，
与当前界面对照即可看出变化。


---

## 附录 G：重启存活验收（2026-09-30 通过）

重启路由器后全项自动恢复（断电 40 秒即响应，约 1 分钟全部就绪）：

| 验收项 | 结果 |
|---|---|
| 无线 WAN 自动重连热点 | ✅ `up: true`，公网延迟 39ms |
| 双频 Wi-Fi ExampleWiFi 广播 | ✅ 2.4G/5G 均恢复 |
| `/data` 数据盘自动挂载 | ✅ 112.4G 就位（fstab 生效） |
| ksmbd SMB 服务 | ✅ 自动启动，Mac 读写实测正常 |
| 中文界面 + Argon 主题 | ✅ `zh_cn` + `argon` 保持 |
| packet steering | ✅ 保持开启 |
| 系统时间（NTP） | ✅ 开机自动对时正确 |
| 配置备份 | ✅ `backup-openwrt-2026-09-30.tar.gz` 已存档（41 个配置文件） |

**恢复方法**：配置损坏或误操作后，LuCI「系统 → 备份/刷写固件 → 恢复」上传该备份包，
或 SSH 执行 `sysupgrade -r /tmp/backup-openwrt-2026-09-30.tar.gz`。

**safexcel 说明（修正附录 E）**：实测发现该模块会被内核按需自动加载，单纯改
`/etc/modules.d` 文件名拦不住。已追加 `/etc/modprobe.d/blacklist-safexcel.conf`
黑名单作为双保险。更重要的是：本机在 25.12.5（内核 6.12.94）上经多轮 SMB3 大文件
传输均未出现 issue #21979 的冻结现象，推断该问题已在新内核修复。**若日后使用中
遇到 SMB 传输时整机卡死，执行 `rmmod crypto_safexcel` 即可即时恢复**，
长期方案可将 ksmbd 锁到 SMB2：`uci set ksmbd.@globals[0].max_protocol='SMB2'`。


---

## 附录 H：持续高负载稳定性测试（2026-09-30 通过）

**测试方法**：Mac 连 5G Wi-Fi（信道 149 / 80MHz，SMB 源地址确认为无线接口 192.168.1.249），
连续 **8 分钟**满负载读写路由器数据盘（每循环 = SMB 读 1GB + 写 256MB），
全程每秒 ping 网关记录满载延迟，分阶段记录路由器 CPU/内存/温度。纯内网流量，零热点消耗。

**结果：**

| 指标 | 数值 | 评价 |
|---|---|---|
| 传输总量 | 150 个循环 ≈ **150GB 读 + 38GB 写** | — |
| 传输错误 / 掉线 / 冻结 | **0 次** | 无 safexcel 冻结问题（附录 G 结论再获验证） |
| 满载延迟（Wi-Fi 到网关） | 最小 2.2ms / 平均 **9.5ms** / 最大 44ms | Wi-Fi 满载下正常水平；若打游戏仍偏高，可上 SQM 再降 |
| CPU 负载峰值 | 2.60（4 核） | 约 65%，有富余 |
| 内存 | 占用稳定在 100MB 左右，可用 >840MB | 无泄漏迹象 |
| 芯片温度 | 51℃（空闲）→ **56℃（满载峰值）** | 温升仅 5℃，散热良好 |
| 数据盘 / ksmbd | 测试后挂载、服务均正常 | — |

**结论**：满负载连续运行稳定，无冻结、无掉线、温度健康。剩余长期项仅为 24 小时挂机观察
（正常使用即可，无需专门测试）。性能记录表中「满载延迟」「测速时 CPU 峰值」两项
已由本次测试填补。


---

## 附录 I：网口对应关系确认（2026-09-30）

| 系统接口 | 物理口 | 现状 |
|---|---|---|
| `eth1` | **2.5GbE 口（WAN）** | 已配置为 wan/wan6，当前未插线（上网走无线 WAN）。日后接宽带网线插此口即可 |
| `lan1`–`lan4`（桥接 br-lan） | 4 个千兆 LAN 口 | lan2 接 Mac mini，协商 1000Mbps 正常；其余空闲 |
| `eth0` | SoC 内部交换机上联 | 系统内部使用，无需配置 |

无线 WAN 与有线 WAN 的关系：无线 WAN（wwan）在防火墙 wan 区域中，与 eth1 并存；
插上宽带后两者按路由 metric 自动选择，也可在 LuCI 接口页停用 wwan。


---

## 附录 J：阶段二（性能取舍）推迟说明（2026-09-30）

**决定**：硬件流量卸载 / WED / SQM 的对比测试**推迟到接入正规宽带后再做**。

**理由（工程判断）：**

- 当前互联网出口是手机热点（百兆级、延迟 30–50ms），硬件卸载只影响路由器转发性能，
  对热点链路没有任何可见收益，测不出真实差异；
- SQM 只能控制路由器→热点方向的队列（上传）；下载方向的缓冲队列在 iPhone/运营商侧，
  路由器管不到， hotspot 场景下 SQM 价值有限；
- 且验证 SQM 需要跑互联网测速，白白消耗热点流量。

**届时操作清单（接宽带后按序执行）：**

1. 网线插 2.5G 口（eth1，已配好 wan/wan6），按宽带类型设 PPPoE 或 DHCP；
2. 测宽带实际上下行（取 90% 作为 SQM 带宽值）；
3. 路线 A：`uci set firewall.@defaults[0].flow_offloading='1'` +
   `flow_offloading_hw='1'`，`service firewall restart`，复测吞吐/CPU；
4. 路线 B：`apk add luci-app-sqm`，wan 口 `cake` + `piece_of_cake`（**不要用 cake_mq**，
   25.12 已知问题），关硬件卸载，复测满载延迟；
5. 两条路线二选一后连续挂机 24 小时验证，结果填性能表「阶段 2 之后」列；
6. 改完卸载/SQM 类配置，**断电 10 秒再开机**，避免 PPE 表项残留。

**备注**：2026-09-30 曾短暂写入 offload 配置后按你的决定立即回滚并验证清除，
当前防火墙为未卸载的默认状态，联网正常。


---

## 附录 K：宽带接入与阶段二性能取舍（2026-09-30 完成）

### K1. 宽带接入

- 网线插 **2.5G 口（eth1）**，协商 **2500Mbps**；上级光猫为**桥接模式**，需路由器拨号
- 配置：`network.wan.proto='pppoe'` + 宽带账号密码 + `ipv6='auto'`（运营商同时下发 IPv6）
- 拨号成功获得公网 IP（联通，61.181.x.x），空载公网延迟从热点的 35–60ms 降到 **11.6ms**
- 客户端 NAT 自动生效（pppoe-wan 已在防火墙 wan 区域），手机连 ExampleWiFi 即可上宽带
- 无线 WAN（wwan）保留作备用链路；当前 iPhone 热点在 5GHz（信道 161）所以连不上，
  如需备用链路，在 iPhone 热点设置里打开「最大兼容性」（强制 2.4GHz）即可恢复

### K2. 三条路线实测对比（500M 宽带，满载下载时测公网延迟）

| 路线 | 下行 | 满载延迟（平均/峰值） | CPU | 结论 |
|---|---|---|---|---|
| 基准（无卸载无 SQM） | 470 Mbps | 24.8 / 74.9 ms | 低 | — |
| A：硬件卸载 + WED | 497 Mbps | 35.9 / **144.7 ms** | 最低 | 速度 +6%，但延迟尖峰严重 |
| **B：SQM CAKE（已采用）** | 378 Mbps | 21.0 / **34.8 ms** | 低 | 速度 -20%，换延迟始终平稳 |

**最终选择：路线 B（SQM）**。理由：378 Mbps 对日常使用绰绰有余，而满载时延迟峰值
被压在 35ms 以内——游戏、视频通话、抢红包不会再因下载占满而卡顿。卸载路线的 145ms
延迟尖峰正是「一下载就卡」的根源。

**SQM 配置（当前生效）：**

```bash
apk add luci-app-sqm
uci set sqm.@queue[0].enabled='1'
uci set sqm.@queue[0].interface='pppoe-wan'
uci set sqm.@queue[0].download='425000'    # 实测下行的 90%
uci set sqm.@queue[0].upload='80000'       # 实测上行的 95%（初值 76000，附录 L 调优）
uci set sqm.@queue[0].qdisc='cake'
uci set sqm.@queue[0].script='piece_of_cake.qos'
uci commit sqm && /etc/init.d/sqm enable && /etc/init.d/sqm start
# 硬件卸载保持关闭（与 SQM 不兼容）；勿用 cake_mq（25.12 已知吞吐异常）
```

LuCI 管理入口：「网络 → SQM QoS」。

**若日后想换回高速度路线**：停 SQM（`/etc/init.d/sqm stop; /etc/init.d/sqm disable`），
再按附录 J 清单开硬件卸载即可。改完卸载/SQM 类配置建议**断电 10 秒再开机**，
避免 PPE 表项残留（本次切换后建议方便时断电重启一次）。


---

## 附录 L：宽带环境 Wi-Fi / 有线对比测试（2026-09-30，SQM 生效中）

测试路径均为「Mac → 路由器 → PPPoE 宽带」，除上行外测速源为国内镜像/CDN。
此时 SQM CAKE 已启用（下行 425M / 上行 80M 塑形）。

| 测试项 | Wi-Fi（5G ExampleWiFi） | 有线（千兆网口） | 说明 |
|---|---|---|---|
| 空载延迟（到网关） | 3.5 ms | **0.53 ms** | 无线固有开销 |
| 空载延迟（公网 223.5.5.5） | 12–58 ms（有抖动） | **12.0 ms（极稳）** | Wi-Fi 省电机制导致偶发抖动 |
| 下行速度 | 363 Mbps | 369 Mbps | 均被 SQM 稳在 ~370M（宽带 470M 的 90% 塑形值，预期内） |
| **满载延迟（下载跑满时）** | 平均 19.8 / 峰值 29.9 ms | **平均 11.5 / 峰值 11.8 ms** | SQM 教科书级表现：有线满载延迟≈空载 |
| 上行速度 | 单流 27–36 Mbps，4 并发聚合 54 Mbps | 同左 | 远端 CDN 单连接 TCP 限制，非路由器瓶颈 |

**上行速度说明（重要）**：怀疑 SQM 把上行压坏时做了对照实验——临时摘除上行塑形后，
单流立即恢复 **84 Mbps**（ISP 实际上行），证明带宽和路由器都正常；CAKE 塑形下单个
TCP 流到远端服务器会因丢包退避只能跑 30–50%，多连接聚合正常。这是 AQM 的正常特性，
不影响日常（视频会议多流、微信传文件都正常）。上行塑形值最终定为 **80000 kbit**（95%）。

**结论**：
- 想极致稳定和延迟：插网线（满载延迟 11.5ms 几乎无感知）
- Wi-Fi 日常完全够用：363M 下行 + 满载 30ms 内延迟，看片/游戏/会议都行
- SQM 是本套配置的最大功臣，卸载路线（峰值 145ms）已彻底弃用


---

## 附录 M：宽带环境持续稳定性测试（2026-09-30 通过）

**测试方法**：Mac 经 5G Wi-Fi → 路由器 → PPPoE 宽带（SQM 生效中），
连续 **8 分钟**满速下载（约 20GB+ 互联网流量），全程每秒 ping 公网（223.5.5.5），
分段记录路由器负载/内存/温度/队列统计。

**结果：**

| 指标 | 数值 | 评价 |
|---|---|---|
| 持续满载时长 | 8 分钟（2×4 分钟阶段） | — |
| 公网延迟（满载中） | 平均 **17.4–18.2 ms**，峰值 34.5ms（仅 1 次 80ms 尖峰） | SQM 下极其平稳 |
| 丢包 | 479 次 ping 丢 1 个（0.2%） | 可忽略 |
| PPPoE 会话 | 全程在线未掉线 | ✅ |
| CAKE 队列 | 14.8GB 入向流量，丢包率 0.037%（AQM 正常工作） | ✅ |
| CPU 负载 | 0.16–0.35（4 核） | 大量富余（SQM 在 370M 下很轻松） |
| 内存 | 可用 >850MB | 无泄漏 |
| 温度 | 52–53℃ | 比 LAN 压测时还低，散热无忧 |

**结论**：宽带 + SQM 组合可长期满载运行，延迟平稳、无掉线、无过热。
第一阶段全部测试至此收官。

---

## 附录 N：LAN 网段切换 192.168.66.1 —— 失败根因与正确方法（2026-09-30 晚）

### 事件经过

第一次尝试把 LAN 从 192.168.1.1 改为 192.168.66.1 后，所有客户端拿不到 IP，
路由器看似"失联"，连续两次恢复出厂。经 IPv6 通道深入诊断，查明**两个独立的坑**。

### 坑 1：uci 只写 IP 不写掩码 → br-lan 变成 /32（根因）

```bash
uci set network.lan.ipaddr='192.168.66.1'   # ❌ 只写地址
```

新版 OpenWrt（25.x）下，如果 ipaddr 不带前缀、且配置里没有独立 netmask 选项，
netifd 会按 **/32** 处理：

```
inet 192.168.66.1/32 brd 255.255.255.255 scope global br-lan
```

/32 意味着"整个网段只有路由器自己"，于是：
- dnsmasq 启动时报 `network (192.168.66.1/32) too small`，**跳过生成 dhcp-range**，
  进程活着、53 端口 DNS 正常，但 67 端口 DHCP 完全不应答 → 客户端拿不到 IPv4
- 客户端自分配 169.254.x.x，表现为"路由器不分配地址"

**正确写法（二选一）：**

```bash
uci set network.lan.ipaddr='192.168.66.1/24'   # ✅ 推荐：地址带前缀
# 或
uci set network.lan.ipaddr='192.168.66.1'
uci set network.lan.netmask='255.255.255.0'    # ✅ 显式写掩码
```

### 坑 2：service network restart 热重启 → 2.5G WAN 口 PHY 起不来

这台 MT7986 机器的 2.5G 口（eth1）在 `service network restart` 热重启后，
物理链路可能直接 DOWN（灯灭、operstate=down），拨号自然失败。
**整机 reboot 后 PHY 恢复正常。** 因此：

> **凡是要动 network 配置（改网段、改 WAN），一律改完 `reboot`，不要热重启。**
> 只动 WAN 协议参数可以用 `ifup wan`（不碰 PHY）；无线配置用 `wifi reload`（不碰有线）。

### 诊断技巧：IPv4 断了走 IPv6

网段切换失败后，路由器 IPv6 服务（odhcpd）往往还活着。
看电脑网卡详情里的 DNS 服务器一栏，找到 `fdxx::1` 形式的 ULA 地址，即可：

```bash
ssh -6 root@fdb3:3ac8:a724::1    # 用实际看到的地址
```

进门后重点检查：
```bash
ip addr show br-lan | grep inet          # 掩码是不是 /24
netstat -ulnp | grep :67                 # dnsmasq 有没有听 DHCP
grep dhcp-range /var/etc/dnsmasq.conf.*  # 地址池有没有生成
```

### 客户端侧注意事项

- 切换后客户端必须重新 DHCP：拔插网线或重连 Wi-Fi 即可（reboot 造成的链路闪断会自动触发）
- macOS 在断网瞬间可能自动跳到其他已知 Wi-Fi（如手机热点），
  造成"路由器不分配地址"的假象，先看 Wi-Fi 图标连的是不是自己的路由器

### 切换成功后验收清单（本次全部通过）

| 项目 | 结果 |
|---|---|
| br-lan | 192.168.66.1/24 ✅ |
| DHCP 地址池 | 192.168.66.100–249，67 端口监听 ✅ |
| PPPoE | 61.181.237.178，公网 ping 11.4ms ✅ |
| /data 数据盘 | 112.4G 自动挂载，原文件完好 ✅ |
| SMB | 445 端口监听 ✅ |
| SQM | cake 80Mbit 在 pppoe-wan ✅ |
| Wi-Fi | ExampleWiFi / ExampleWiFi_5G 双频广播 ✅ |
| 主题/语言 | Argon + 中文 ✅ |
| 重启存活 | 全部服务自启 ✅ |

新配置备份：`backup-openwrt-2026-09-30-v3-66.tar.gz`（本目录）。

---

## 附录 O：Tailscale 远程访问（2026-09-30 配置）

路由器已安装 tailscale v1.98.3，以子网路由模式运行：

```bash
tailscale up --advertise-routes=192.168.66.0/24 --accept-dns=false
```

- 授权链接由 `tailscale status` 给出，浏览器打开用 Google/微软/GitHub 账号登录即完成绑定
- 手机/外地电脑装 Tailscale App 并登录同一账号后，
  在 Tailscale 管理后台批准 192.168.66.0/24 子网路由，
  即可直接访问 `http://192.168.66.1`（LuCI）和 `smb://192.168.66.1/data`（文件共享）
- 注意：路由器若再次恢复出厂，Tailscale 节点密钥会重新生成，
  需在管理后台删除旧节点、重新授权

### Tailscale 接入补充（2026-09-30 晚实际完成版）

**最终状态**：路由器已上线，Tailscale IP `100.72.158.90`，版本 1.102.4（官方静态包升级，
修复 1.98.3 已知安全漏洞；OpenWrt 源版本滞后时可用此法：
`curl -O https://pkgs.tailscale.com/stable/tailscale_<版本>_arm64.tgz`，
解压后用其中 tailscale/tailscaled 覆盖 /usr/sbin/ 同名文件并重启服务）。

**踩坑记录**：
1. 浏览器授权链接（/a/xxxx）在等待期间会**几分钟轮换一次**，旧链接立即 403
   「session expired」——取到链接必须马上打开，或从 LuCI Tailscale 页面点实时链接
2. 授权成功的瞬间，路由器上等待中的 `tailscale up` 进程**不能被杀**，
   否则凭证交接中断，后台留下"尸体节点"，本地仍显示 NeedsLogin
3. **最稳方式是 Auth Key**：管理后台 Settings → Keys 生成（若生成的是
   `tskey-api-` 开头的 API 令牌，可用它调 API 换 auth key：
   `curl -u "tskey-api-xxx:" -X POST https://api.tailscale.com/api/v2/tailnet/-/keys
   -d '{"capabilities":{"devices":{"create":{"preauthorized":true}}}}'`），
   然后 `tailscale up --authkey=tskey-auth-xxx --advertise-routes=192.168.66.0/24 --accept-dns=false`
4. 接入后还需在管理后台 Machines → 该设备 → Edit route settings
   **批准 192.168.66.0/24 子网路由**，手机端才能访问整个内网
5. 用过的 API 令牌记得在后台删除

---

## 附录 P：实用插件补充（2026-10-01）

配合 64G 新机入网（第二部教程），本机补充安装：

| 插件 | 用途 |
|---|---|
| `luci-app-watchcat` | 断网看护：每分钟 ping 223.5.5.5，持续 6 小时不通自动重启 WAN（重新 PPPoE 拨号） |
| `iperf3` / `htop` / `nano` | 测速 / 进程查看 / 文本编辑 |
| `luci-app-nlbwmon` | 按设备统计流量（状态 → 带宽监控），看谁占带宽 |

广告过滤、DDNS 按需未装。配置备份：`backup-openwrt-2026-10-01-128G-v5.tar.gz`（本目录，含监控系统）。
另：64G 二级路由（192.168.86.1）已上线运行，配置全过程见第二部教程。

### P2. 系统状态图形化监控（同日加装）

与 64G 完全相同的方案（详见第二部教程附录 A）：`luci-app-statistics` + collectd
（CPU/内存/负载/接口/无线/温度/磁盘/ping 延迟）+ 自制 eMMC 健康曲线
（`/usr/bin/emmc-health.sh`，64G 目录有备份）。RRD 历史数据存 `/data/rrd`，
重启不丢。入口：**状态 → 图表**。64G 踩过的三个坑（手改 collectd.conf 会被
重新生成、exec 脚本 sleep 小数、df 插件 FSType 误排）本次直接规避，一次通过。


---

## 附录 Q：宽带升级千兆实测与 SQM 重调（2026-10-01 清晨）

**起因**：双路由灌盘压测（见第二部附录 E）中双机合计只有约 320 Mbps，主人提出
「我的是千兆宽带」。排查确认：**SQM 的 425M/80M 是 9-30 按当时实测 470M 定的，
而联通线路已在不知不觉中升到了千兆**。

### Q1. 关闭 SQM 后的真实带宽（8 路并发 wget 拉清华 TUNA，各 20 秒）

| 被测机 | 下行 | 满载延迟表现 |
|---|---|---|
| 128G 直连（pppoe-wan 计数） | **142.9 MB/s ≈ 1199 Mbps** | 国际测速延迟尖峰冲到 326ms（bufferbloat 现身） |
| 64G 经二级路由 NAT（eth1 计数） | **114.6 MB/s ≈ 961 Mbps** | — |

结论：宽带确实是千兆（还多送了 20%）；64G 的 NAT 转发跑满千兆无压力；
关闭 SQM 的代价是满载延迟爆炸（实测 326ms 尖峰）。

### Q2. SQM 重调 950M/90M 实测（CAKE 塑形上限摸底）

| 被测机 | 下行（塑形后实测） | 满载 ping 223.5.5.5 | 判定 |
|---|---|---|---|
| 128G 直连 | 89.0 MB/s ≈ 746 Mbps | 平均 12.8ms / 峰值 16.0ms（空载基线 11.6ms） | ✅ 达标 |
| 64G 经 NAT | 71.6 MB/s ≈ 601 Mbps | 平均 14.5ms / 峰值 31.3ms | ✅ 可接受 |

- **CAKE 软整形在 MT7986 上的实际天花板约 730–750 Mbps**（设 950M 也只能跑出
  746M），与阶段 2 记录的「已知坑：CAKE >700M 吞吐受限」一致。继续调高参数无意义。
- 746M + 满载延迟仍压在 16ms 以内，是「速度与延迟」的最优平衡点；
  64G 双 NAT 路径 601M，作为下载机也够用。
- 上行 90M 塑形未单独压测，按 100M 上行的 90% 取值，后续如需可再调。

### Q3. 当前生效配置（2026-10-01 06:15 起）

```bash
sqm.eth1.enabled='1'  interface='pppoe-wan'
sqm.eth1.download='950000'   # 原 425000（500M 时代实测值），千兆时代上调
sqm.eth1.upload='90000'      # 原 80000
# qdisc='cake'  script='piece_of_cake.qos'  其余不变
uci commit sqm && /etc/init.d/sqm restart
```

**注意事项**：

1. 附录 K2 的 470/378 Mbps 数据是 **500M 时代**的实测，保留作历史记录，
   不再适用；判断 SQM 取值前先关 SQM 裸测真实带宽。
2. 若嫌 746M 不够、想跑满千兆：只能停 SQM 换硬件卸载路线（附录 J/K 清单），
   代价是满载延迟尖峰 145ms 级；或等 OpenWrt 后续版本改善 cake-mq 后再试多核队列。
3. 本次调整未动防火墙卸载开关，无需断电重启（改动不涉及 PPE 卸载开关切换）。

**新配置备份**：`backup-openwrt-2026-10-01-128G-v6.tar.gz`（已生成，本目录）。

---

*第一阶段教程完。*
