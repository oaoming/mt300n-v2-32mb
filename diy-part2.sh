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
# -------------------------------------------------------------------------
# 修改 GL-MT300N-V2 Flash 大小为 32MB
# -------------------------------------------------------------------------

# 1. 修改设备树 (DTS) 中的分区大小
# 原理：找到 mt7628an_glinet_gl-mt300n-v2.dts 文件
# 将固件分区(firmware)的大小从 0xfb0000 (约16MB减去引导区) 修改为 0x1fb0000 (32MB减去引导区)
# 注意：不同源码版本路径可能微调，但通常都在 target/linux/ramips/dts/ 下

dt_file=$(find target/linux/ramips/dts/ -name "*gl-mt300n-v2.dts")
if [ -f "$dt_file" ]; then
    echo "Found DTS file: $dt_file"
    sed -i 's/<0xfb0000>/<0x1fb0000>/g' "$dt_file"
    echo "DTS partition size patched to 32MB."
else
    echo "Error: DTS file not found!"
fi

# 2. 修改 Image Makefile 中的固件体积限制
# 原理：OpenWrt 编译时会检查生成的固件是否超过预设大小（通常设为 15872k 或 16064k）
# 我们需要将其改为约 32MB (例如 32256k)

# 搜索包含 gl-mt300n-v2 定义的 .mk 文件
mk_file=$(grep -rl "glinet_gl-mt300n-v2" target/linux/ramips/image/)

if [ -n "$mk_file" ]; then
    echo "Found Image Makefile: $mk_file"
    # 将 15872k 或 16064k 修改为 32256k (适配32MB Flash)
    # 使用通配符匹配常见的16MB定义
    sed -i 's/IMAGE_SIZE := 15872k/IMAGE_SIZE := 32256k/g' "$mk_file"
    sed -i 's/IMAGE_SIZE := 16064k/IMAGE_SIZE := 32256k/g' "$mk_file"
    echo "Image size limit patched to 32MB."
else
    echo "Error: Image Makefile not found!"
fi
