# 固件获取与校验

本仓库**不分发任何固件二进制**，请一律从以下来源自行下载，并逐项核对 SHA-256。

## 官方 OpenWrt 25.12.5（5 个文件）

发布目录：<https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/>

文件名前缀均为 `openwrt-25.12.5-mediatek-filogic-jdcloud_re-cp-03-`：

| 文件后缀 | 用途 | SHA-256 |
|---|---|---|
| `gpt.bin` | 分区表 | `6decc5e0ac9ef38bc78f4de8d4df825473a248898c24add4252cd74006f2fd20` |
| `preloader.bin` | BL2 | `d1f272a3a5d474bafdc40bf4a99749304185f12dd799f87c414964b88dd3e72e` |
| `bl31-uboot.fip` | U-Boot | `52a5e4904488a35d680fbe379b8d90935c683628c3d082ae4823e44cd09c1724` |
| `initramfs-recovery.itb` | TFTP 恢复镜像 | `ecd5b00a505ec57550bf1a4b92d7fda5a7b4944693768963c0c27ec8a054ba59` |
| `squashfs-sysupgrade.itb` | 正式系统 | `cfbe6baca9d2cede824632b9faca00a361871c480f23143a20e386e0cf535c7f` |

完整官方清单见本目录 `sha256sums-官方25.12.5.txt`（注意：清单未验签，以逐项核对为准）。

## 过渡迁移包（1 个文件）

| 文件 | SHA-256 |
|---|---|
| `openwrt-mediatek-mt7986-jdcloud_re-cp-03-vendor-migration.bin` | `c371601461c491489d2f28391ee3373e4605f95ff5d16cf7d142b9b2031a444c` |

来源说明：该迁移包出自 [OpenWrt 官方 RE-CP-03 支持提交](https://lists.infradead.org/pipermail/lede-commits/2024-July/021801.html)
中给出的链接；公开教程均使用同一文件、同一哈希。它**不在** OpenWrt 官方发布目录中，
刷入前请再次核对哈希与设备型号。

## 校验方法

- macOS / Linux：`shasum -a 256 文件名`
- Windows（PowerShell）：`Get-FileHash 文件名`

对不上就重新下载，不要硬刷。
