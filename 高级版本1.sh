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

# =========================================================
# 自动开启 ZRAM 并优化配置 (适配 128MB 内存)
# =========================================================
mkdir -p files/etc/uci-defaults

# 注意：这里使用 'EOF' 防止变量被当前 Shell 提前解析
cat << 'EOF' > files/etc/uci-defaults/99-auto-zram-settings
#!/bin/sh

# 如果没有 zram 初始化文件（说明未安装 zram-swap），则退出
if [ ! -f /etc/init.d/zram ]; then
    exit 0
fi

# 1. 清理旧配置
uci -q delete system.@zram[0]
uci -q delete system.zram

# 2. 新建配置
uci set system.zram=zram
uci set system.zram.size_mb='64'       # 64MB for 128MB RAM
uci set system.zram.comp_algorithm='lzo-rle'
uci set system.zram.priority='100'

# 3. 提交并应用
uci commit system
/etc/init.d/zram enable
/etc/init.d/zram start

exit 0
EOF

chmod +x files/etc/uci-defaults/99-auto-zram-settings
echo "3. ZRAM auto-config script created."

# =========================================================
# 开启 I2C 接口
# =========================================================
if [ -n "$DTS_FILE" ]; then
    echo "4. Enabling I2C in DTS..."
    
    # 检查是否已经开启过，防止重复追加
    if grep -q "&i2c {" "$DTS_FILE"; then
        echo "   -> [Info] I2C node already modified or exists, skipping append."
    else
        cat << 'EOF' >> "$DTS_FILE"

&i2c {
    status = "okay";
};
EOF
        echo "   -> [Success] I2C enabled."
    fi
fi


# =========================================================
# 网络性能与速度优化设置 (适配 MT7628 + 128MB RAM)
# =========================================================

# 创建优化脚本
cat << 'EOF' > files/etc/uci-defaults/99-network-performance
#!/bin/sh

# 1. 开启 Turbo ACC 网络加速 (Flow Offloading)
# 对于 MT7628 这种弱 CPU，这是必选项！能显著降低 CPU 占用。
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1' 
# 注意：hw (硬件加速) 在某些 MT7628 驱动下可能不生效，但开启无害，系统会自动回退到软件加速。

# 2. 优化连接数限制 (利用你的 128MB 大内存)
# 默认通常只有 16384，跑 BT 容易满。改为 32768 (3万2连接数对 128MB 内存很轻松)
echo "net.netfilter.nf_conntrack_max=32768" >> /etc/sysctl.conf

# 3. 开启 BBR 拥塞控制算法 (如果内核模块已安装)
# BBR 能显著改善高丢包环境下的网络速度 (特别是科学上网)
# 即使没安装 kmod-tcp-bbr，写入这些也不会导致死机，只是不生效。
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

# 4. 优化 TCP Keepalive (加快死链清理)
# 默认时间太长，缩短有助于快速释放断掉的连接
echo "net.ipv4.tcp_keepalive_time=600" >> /etc/sysctl.conf
echo "net.ipv4.tcp_keepalive_intvl=30" >> /etc/sysctl.conf
echo "net.ipv4.tcp_keepalive_probes=5" >> /etc/sysctl.conf

# 5. 提交防火墙修改
uci commit firewall

exit 0
EOF

# 赋予脚本执行权限
chmod +x files/etc/uci-defaults/99-network-performance
echo "Network optimization script created."
