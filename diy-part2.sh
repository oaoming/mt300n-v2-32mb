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

# 1. 修改 DTS 分区定义
# 目标文件名我们已经确定是 mt7628an_glinet_gl-mt300n-v2.dts
DTS_FILE=$(find . -name "mt7628an_glinet_gl-mt300n-v2.dts" -type f | head -n 1)

if [ -n "$DTS_FILE" ]; then
    echo "1. 定位到 DTS 文件: $DTS_FILE"
    # 直接替换数值，不带尖括号，防止匹配失败
    sed -i 's/0xfb0000/0x1fb0000/g' "$DTS_FILE"
    
    # 验证
    if grep -q "0x1fb0000" "$DTS_FILE"; then
        echo "   -> [成功] DTS 分区已改为 32MB (0x1fb0000)"
    else
        echo "   -> [失败] DTS 修改未生效，请检查 sed 命令"
    fi
else
    echo "1. [错误] 无法找到 mt7628an_glinet_gl-mt300n-v2.dts 文件！"
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

# =========================================================
# 自动开启 ZRAM 并优化配置 (适配 128MB 内存)
# =========================================================
# 创建存放自动配置脚本的目录
mkdir -p files/etc/uci-defaults

# 生成自动配置脚本
cat << 'EOF' > files/etc/uci-defaults/99-auto-zram-settings
#!/bin/sh

# 检查是否存在 zram 初始化文件，如果没安装包则直接退出，避免报错
if [ ! -f /etc/init.d/zram ]; then
    exit 0
fi

# 1. 清理旧配置 (同时尝试删除 匿名配置 和 命名配置，加 -q 忽略错误)
uci -q delete system.@zram[0]
uci -q delete system.zram

# 2. 新建配置 (创建一个名为 zram 的节点)
uci set system.zram=zram
uci set system.zram.size_mb='64'          # 64MB 是 128MB 内存的最佳甜点
uci set system.zram.comp_algorithm='lzo-rle'
uci set system.zram.priority='100'        # 优先级高于 Flash swap

# 3. 提交修改
uci commit system

# 4. 启用并启动服务
# 注意：uci-defaults 运行较晚，直接 start 可能会因内核模块未加载完成报错
# 更好的做法是 enable 它，依赖系统引导流程启动。
# 但为了确保即时生效，可以尝试 start，失败也不影响下次重启。
/etc/init.d/zram enable
/etc/init.d/zram start

exit 0
EOF

# 赋予脚本执行权限
chmod +x files/etc/uci-defaults/99-auto-zram-settings

# =========================================================
# 开启 I2C 接口 (MT7628 硬件 I2C)
# =========================================================
# 这里的 DTS_FILE 变量复用上面定义的路径
# 如果上面没有定义，请取消下面这行的注释:
# DTS_FILE=$(find . -name "mt7628an_glinet_gl-mt300n-v2.dts" -type f | head -n 1)

if [ -n "$DTS_FILE" ]; then
    echo "Enabling I2C in DTS..."
    
    # 向 DTS 文件末尾追加 I2C 启用配置
    # &i2c 引用的是芯片原本定义的 i2c 节点
    cat << 'EOF' >> "$DTS_FILE"

&i2c {
    status = "okay";
};
EOF

    echo "I2C node set to 'okay'."
else
    echo "Error: DTS file not found for I2C patching!"
fi
