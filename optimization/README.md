# 优化配置篇：刷完官方 OpenWrt 之后

> 本目录是「刷机篇」（仓库根目录教程）的续篇：两台京东云 AX6000 百里（128G RE-CP-03 + 64G RE-CS-05）
> 刷入官方 OpenWrt 25.12.5 之后，**全部优化配置同样由 AI 代理在用户授权下全程实操完成**，
> 文档按实操记录整理，所有数字均来自真机验收。
>
> 恩山论坛第二帖（2026-10-02 发布）：https://www.right.com.cn/forum/thread-8491638-1-1.html
>
> 脱敏说明：文档中的 Wi-Fi SSID（`ExampleWiFi` / `ExampleWiFi_5G`）、密码等均为占位/脱敏值；
> 配置备份（含密码哈希与密钥）不随仓库公开。

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/京东云AX6000-OpenWrt优化配置方案.md](docs/京东云AX6000-OpenWrt优化配置方案.md) | **主文档**：LuCI 中文、eMMC 扩容出 114GB 数据盘、SMB 网络共享（NAS）、PPPoE 拨号、SQM/CAKE 调优、Argon 美化、12 条踩坑实录、验收清单 |
| [docs/京东云AX6000-OpenWrt设置中文教程.md](docs/京东云AX6000-OpenWrt设置中文教程.md) | 单独成篇的 LuCI 简体中文设置教程（25.12 起用 apk） |
| [docs/京东云AX6000-OpenWrt加强方案.md](docs/京东云AX6000-OpenWrt加强方案.md) | 第三阶段进阶方案（安全加固 / DDNS / WireGuard，预留待做） |
| [docs/京东云AX6000-64G-OpenWrt配置教程-第二部.md](docs/京东云AX6000-64G-OpenWrt配置教程-第二部.md) | 64G 复刻 128G 配置（DHCP WAN、192.168.86.x 网段、双机同名 Wi-Fi 漫游） |
| [docs/压测报告-双路由灌盘.md](docs/压测报告-双路由灌盘.md) | 双路由互灌压测：128G 写入 102.41 GiB（峰值 45.8 MB/s）、64G 写入 51.14 GiB，温度与负载曲线 |

## 脚本

| 脚本 | 用途 |
|---|---|
| [scripts/emmc-health.sh](scripts/emmc-health.sh) | eMMC 寿命监控（collectd exec 插件）：采集 life_time 寿命消耗档与 pre_eol 预警 |

## 图片

`images/`：LuCI 实操截图（已逐张复核脱敏，含真实 Wi-Fi 名称的两张无线设置页截图未收录）与压测曲线图。
