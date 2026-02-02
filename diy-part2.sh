#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate
# =========================================================
# GL-MT300N-V2 16MB -> 32MB Flash 适配补丁
# =========================================================

# 1. 修改设备树 (DTS) 分区大小
# 原理：MT300N-V2 默认固件分区大小为 0xfb0000 (约16MB减去引导区)
# 我们需要将其改为 0x1fb0000 (32MB - 引导区保留空间)
# 使用 find 命令查找 dts 文件，兼容不同源码版本的路径差异
dts_file=$(find target/linux/ramips/dts/ -name "*gl-mt300n-v2.dts")
if [ -n "$dts_file" ]; then
    echo "Found DTS: $dts_file"
    sed -i 's/<0xfb0000>/<0x1fb0000>/g' "$dts_file"
    echo "DTS partition size patched to 32MB."
else
    echo "Error: DTS file not found!"
fi

# 2. 修改 Image Makefile 固件体积限制
# 原理：OpenWrt 默认限制该机型固件最大为 ~15.5MB
# 我们需要将其放宽到 ~31.5MB (32256k)
mk_file=$(find target/linux/ramips/image/ -name "mt76x8.mk")
if [ -n "$mk_file" ]; then
    echo "Found Makefile: $mk_file"
    # 使用 sed 区块匹配，只修改 gl-mt300n-v2 相关的 IMAGE_SIZE
    sed -i '/glinet_gl-mt300n-v2/,/endef/s/IMAGE_SIZE := .*k/IMAGE_SIZE := 32256k/' "$mk_file"
    echo "Image size limit patched to 32256k (32MB)."
else
    echo "Error: Image Makefile not found!"
fi

# 1. 强制将 git:// 协议替换为 https://
# 这是解决 ubus 等包下载失败的核心，因为 GitHub Actions 经常连不上 git:// 端口
git config --global url."https://".insteadOf git://

# 2. (可选) 针对 GitHub 域名的特殊处理
git config --global url."https://github.com/".insteadOf git@github.com:

# 3. 设置 OpenWrt 官方 CDN 镜像源 (作为下载失败时的备用)
# 当源码站下载失败时，编译系统会自动尝试这个地址
echo 'CONFIG_DOWNLOAD_MIRROR="https://downloads.openwrt.org/sources/"' >> .config
