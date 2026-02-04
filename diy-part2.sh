#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#

# =========================================================
# GL-MT300N-V2 16MB -> 32MB Flash 适配补丁
# =========================================================

# 1. 修改 DTS 分区定义
# 使用 find 查找文件，增强兼容性
DTS_FILE=$(find target/linux/ramips -name "mt7628an_glinet_gl-mt300n-v2.dts" -type f | head -n 1)

if [ -n "$DTS_FILE" ]; then
    echo "1. Found DTS file: $DTS_FILE"
    # 替换 16MB 分区大小 (0xfb0000) 为 32MB 分区大小 (0x1fb0000)
    sed -i 's/0xfb0000/0x1fb0000/g' "$DTS_FILE"
    
    # 二次验证
    if grep -q "0x1fb0000" "$DTS_FILE"; then
        echo "   -> [Success] DTS partition size patched to 32MB (0x1fb0000)."
    else
        echo "   -> [Error] DTS patching failed! Check if original value is 0xfb0000."
    fi
else
    echo "1. [Error] DTS file not found!"
fi

# 2. 修改 Image Makefile 固件体积限制
MK_FILE=$(find target/linux/ramips/image/ -name "mt76x8.mk" -type f | head -n 1)
if [ -n "$MK_FILE" ]; then
    echo "2. Found Makefile: $MK_FILE"
    # 只修改 gl-mt300n-v2 相关的 IMAGE_SIZE
    if grep -q "glinet_gl-mt300n-v2" "$MK_FILE"; then
        sed -i '/glinet_gl-mt300n-v2/,/endef/s/IMAGE_SIZE := .*k/IMAGE_SIZE := 32256k/' "$MK_FILE"
        echo "   -> [Success] Image size limit patched to 32256k."
    else
        echo "   -> [Error] Target device not found in Makefile."
    fi
else
    echo "2. [Error] Image Makefile not found!"
fi

# =========================================================
# 网络与编译优化
# =========================================================

# 1. Git 协议替换 (解决 GitHub Actions 下载失败)
git config --global url."https://".insteadOf git://
git config --global url."https://github.com/".insteadOf git@github.com:

# 2. 设置 OpenWrt 镜像源 (注意：这会追加到 .config，建议配合 defconfig 使用)
if [ -f .config ]; then
    echo 'CONFIG_DOWNLOAD_MIRROR="https://downloads.openwrt.org/sources/"' >> .config
fi

