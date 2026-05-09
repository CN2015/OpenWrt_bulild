#!/bin/bash
# ============================================================================
# OpenWrt LEDE 自定义配置脚本 (GitHub Actions 专用)
# 功能：源码配置 + 插件源 + 主机名 + WiFi + Banner + 汉化 + 冲突预检
# ============================================================================
set -e

# 📋 接收环境变量
DEVICE="${DEVICE:-xdr6088}"
WIFI_PREFIX="${WIFI_PREFIX:-OpenWrt_}"
WIFI_PASSWORD="${WIFI_PASSWORD:-1234567890}"
ENABLE_TRANSLATE="${ENABLE_TRANSLATE:-true}"
ENABLE_KERNEL_SYNC="${ENABLE_KERNEL_SYNC:-false}"
SKIP_FEEDS_MODIFY="${SKIP_FEEDS_MODIFY:-false}"
CONFIG_VERSION="${CONFIG_VERSION:-full}"

OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"
cd "$OPENWRT_PATH"

info() { echo -e "\033[0;32m[✓]\033[0m $1"; }
warn() { echo -e "\033[1;33m[!]\033[0m $1"; }
error() { echo -e "\033[0;31m[✗]\033[0m $1"; }

# ============================================================================
# 🔧 步骤 1: 配置自定义 feeds（安全追加）
# ============================================================================
configure_feeds() {
    [ "$SKIP_FEEDS_MODIFY" = "true" ] && { info "⏭️  跳过 feeds 配置"; return 0; }
    
    info "📡 配置自定义插件源..."
    local feeds_file="feeds.conf.default"
    
    # 📋 备份原文件
    cp "$feeds_file" "${feeds_file}.bak.$(date +%H%M%S)"
    
    # 🔍 安全添加函数（避免重复）
    safe_add_feed() {
        local name="$1" url="$2"
        if ! grep -q "^src-git $name " "$feeds_file" 2>/dev/null; then
            echo "src-git $name $url" >> "$feeds_file"
            info "  + 添加: $name"
        else
            info "  ✓ 已存在: $name"
        fi
    }
    
    # 📦 添加第三方源
    safe_add_feed "nas" "https://github.com/linkease/nas-packages.git;master"
    safe_add_feed "nas_luci" "https://github.com/linkease/nas-packages-luci.git;main"
    safe_add_feed "turboacc" "https://github.com/chenmozhijin/turboacc.git;luci"
    safe_add_feed "small" "https://github.com/kenzok8/small;master"
    safe_add_feed "kenzo" "https://github.com/kenzok8/openwrt-packages;master"
    
    # 🔄 更新并安装
    info "🔄 更新 feeds 索引..."
    ./scripts/feeds update -a 2>&1 | tail -5
    ./scripts/feeds install -a 2>&1 | tail -5
}

# ============================================================================
# 🔧 步骤 2: 内核版本同步（可选）
# ============================================================================
sync_kernel() {
    [ "$ENABLE_KERNEL_SYNC" != "true" ] && { info "⏭️  跳过内核同步"; return 0; }
    
    info "🔧 强制同步最新内核 (6.12)..."
    local kernel_makefile="target/linux/mediatek/Makefile"
    
    if [ -f "$kernel_makefile" ]; then
        sed -i 's/KERNEL_PATCHVER[:=].*/KERNEL_PATCHVER:=6.12/' "$kernel_makefile"
        sed -i 's/KERNEL_TESTING_PATCHVER[:=].*/KERNEL_TESTING_PATCHVER:=6.12/' "$kernel_makefile" 2>/dev/null || true
        info "✓ 内核版本已设置为 6.12"
    fi
}

# ============================================================================
# 🔧 步骤 3: 应用基础配置（主机名 + 账号）
# ============================================================================
apply_base_config() {
    info "🔧 应用基础配置..."
    
    # 🏷️ 修改主机名: LEDE → OpenWrt
    local config_gen="package/base-files/files/bin/config_generate"
    [ -f "$config_gen" ] && sed -i "s/['\"]LEDE['\"]/\'OpenWrt\'/g" "$config_gen"
    
    local zzz="package/lean/default-settings/files/zzz-default-settings"
    [ -f "$zzz" ] && sed -i "s/['\"]LEDE['\"]/\'OpenWrt\'/g" "$zzz"
    
    # 🔐 首次登录强制改密（移除默认密码哈希）
    [ -f "$zzz" ] && sed -i '/V4UetPzk\$CYXluq4wUazHjmCDBCqXF/d' "$zzz" 2>/dev/null || true
    
    info "✓ 主机名 + 账号配置完成"
}

# ============================================================================
# 🎨 步骤 4: 生成自定义 Banner
# ============================================================================
generate_banner() {
    info "🎨 生成自定义 Banner..."
    
    # 📋 机型映射
    declare -A DEVICE_INFO=(
        ["xdr6088"]="TP-LINK XDR6088|192.168.1.1|CN2014"
        ["ax6000"]="Redmi AX6000|192.168.1.1|CN2014"
        ["custom"]="OpenWrt|192.168.1.1|Custom"
    )
    
    IFS='|' read -r dev_name mgmt_ip author <<< "${DEVICE_INFO[$DEVICE]:-${DEVICE_INFO[custom]}}"
    
    cat > package/base-files/files/etc/banner << EOF
  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
 -----------------------------------------------------
 %D %V, %C
 -----------------------------------------------------
 
 🎯 ${dev_name} 定制固件 | BY: ${author}
 🔗 管理地址：${mgmt_ip} | 用户：root | 密码：首次登录强制修改
 
 -----------------------------------------------------
EOF
    info "✓ Banner 已生成"
}

# ============================================================================
# 📶 步骤 5: 生成智能 WiFi 配置
# ============================================================================
generate_wifi_config() {
    info "📶 生成 WiFi 配置 (前缀: ${WIFI_PREFIX})..."
    
    local wifi_script="package/kernel/mac80211/files/lib/wifi/mac80211.sh"
    mkdir -p "$(dirname "$wifi_script")"
    
    # 📋 生成配置脚本（精简版，保留核心逻辑）
    cat > "$wifi_script" << 'WIFI_EOF'
#!/bin/sh
append DRIVERS "mac80211"

WIFI_PREFIX="__WIFI_PREFIX__"
WIFI_KEY="__WIFI_KEY__"

detect_mac80211() {
    [ -f "/etc/.wifi_customized" ] && return 0
    [ ! -s /etc/config/wireless ] && rm -f /etc/.wifi_customized
    
    local devidx=0
    config_load wireless
    while :; do config_get type "radio$devidx" type; [ -n "$type" ] || break; devidx=$(($devidx + 1)); done

    for _dev in /sys/class/ieee80211/*; do
        [ -e "$_dev" ] || continue
        dev="${_dev##*/}"
        
        # 📋 获取频段和 MAC
        local mac=$(cat /sys/class/ieee80211/${dev}/macaddress 2>/dev/null | tr -d ':')
        local mac_suffix="${mac: -4}"
        [ -z "$mac_suffix" ] && mac_suffix="0000"
        
        # 📡 生成 SSID
        local band="2G"
        iwinfo nl80211 info "$dev" 2>/dev/null | grep -q "5GHz" && band="5G"
        local ssid="${WIFI_PREFIX}${mac_suffix}_${band}"
        
        # 📋 生成配置
        uci -q batch << EOF
set wireless.radio${devidx}=wifi-device
set wireless.radio${devidx}.type=mac80211
set wireless.radio${devidx}.channel=auto
set wireless.radio${devidx}.band=${band%G}g
set wireless.radio${devidx}.htmode=HE80
set wireless.radio${devidx}.disabled=0
set wireless.radio${devidx}.country=CN

set wireless.default_radio${devidx}=wifi-iface
set wireless.default_radio${devidx}.device=radio${devidx}
set wireless.default_radio${devidx}.network=lan
set wireless.default_radio${devidx}.mode=ap
set wireless.default_radio${devidx}.ssid=$ssid
set wireless.default_radio${devidx}.encryption=psk2
set wireless.default_radio${devidx}.key=$WIFI_KEY
EOF
        devidx=$(($devidx + 1))
    done
    touch /etc/.wifi_customized
}

[ "$1" = "detect" ] && detect_mac80211
WIFI_EOF

    # 🔧 替换变量
    sed -i "s|__WIFI_PREFIX__|${WIFI_PREFIX}|g" "$wifi_script"
    sed -i "s|__WIFI_KEY__|${WIFI_PASSWORD}|g" "$wifi_script"
    chmod +x "$wifi_script"
    
    info "✓ WiFi 配置已生成: ${WIFI_PREFIX}XXXX_2G/5G"
}

# ============================================================================
# 🔤 步骤 6: 应用插件汉化（可选）
# ============================================================================
apply_translate() {
    [ "$ENABLE_TRANSLATE" != "true" ] && { info "⏭️  跳过汉化"; return 0; }
    
    info "🔤 应用插件名称汉化..."
    
    # 📋 汉化映射表（精简核心项）
    declare -A TRANSLATE_MAP=(
        ["进程"]="系统进程" ["软件包"]="插件管理" ["启动项"]="启动管理"
        ["挂载点"]="挂载设置" ["终端"]="TTYD 终端" ["USB 打印服务器"]="打印服务"
        ["Turbo ACC 网络加速"]="网络加速" ["实时流量监测"]="实时流量"
        ["AdGuard Home"]="AdGuard" ["ShadowSocksR Plus+"]="SSR Plus+"
        ["PassWall"]="科学上网" ["Alist"]="网盘管理" ["FileBrowser"]="文件管理"
        ["Argon 主题设置"]="主题设置" ["UU 游戏加速器"]="游戏加速"
    )
    
    local count=0
    for old_name in "${!TRANSLATE_MAP[@]}"; do
        new_name="${TRANSLATE_MAP[$old_name]}"
        # 🔍 精准替换（仅 .lua/.po/zh-cn 文件）
        find package feeds -type f \( -name "*.lua" -o -name "*.po" -o -name "*zh-cn*" \) \
            -exec grep -l "\"$old_name\"" {} \; 2>/dev/null | while read -r file; do
            sed -i "s|\"$old_name\"|\"$new_name\"|g" "$file"
            ((count++)) || true
        done
        [ $count -gt 0 ] && info "  『$old_name』→ 『$new_name』"
    done
    
    info "✓ 汉化完成"
}

# ============================================================================
# 🧭 步骤 7: LuCI 菜单自定义调整
# ============================================================================
adjust_luci_menu() {
    info "🧭 调整 LuCI 菜单位置..."
    
    # 📦 TTYD → 系统菜单
    find package feeds -name "ttyd.lua" -path "*/controller/*" 2>/dev/null | while read -r f; do
        sed -i 's|"admin", "services", "ttyd"|"admin", "system", "ttyd"|g' "$f"
    done
    
    # 🔐 Tailscale → VPN 菜单
    find package feeds -name "tailscale.lua" -path "*/controller/*" 2>/dev/null | while read -r f; do
        sed -i 's|"admin", "services", "tailscale"|"admin", "vpn", "tailscale"|g' "$f"
    done
    
    info "✓ 菜单调整完成"
}

# ============================================================================
# ⚔️ 步骤 8: 包冲突预检 + 自动解决
# ============================================================================
resolve_conflicts() {
    info "⚔️ 执行包冲突预检..."
    
    # 🎯 核心：vsftpd 冲突链切断
    if grep -qE "^CONFIG_PACKAGE_vsftpd-alt=[ym]" .config 2>/dev/null; then
        info "🔧 检测到 vsftpd-alt，禁用冲突包..."
        sed -i 's/^CONFIG_PACKAGE_vsftpd=[ym]/# CONFIG_PACKAGE_vsftpd is not set/' .config
        sed -i 's/^CONFIG_PACKAGE_luci-app-vsftpd=[ym]/# CONFIG_PACKAGE_luci-app-vsftpd is not set/' .config
        sed -i 's/^CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=[ym]/# CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn is not set/' .config
        info "✓ vsftpd 冲突已解决"
    fi
    
    # 📦 常见冲突对处理
    declare -A conflicts=(
        ["dnsmasq"]="dnsmasq-full"
        ["iptables"]="iptables-nft"
        ["libustream-mbedtls"]="libustream-openssl"
    )
    
    for pkg in "${!conflicts[@]}"; do
        alt="${conflicts[$pkg]}"
        if grep -qE "^CONFIG_PACKAGE_${pkg}=[ym]" .config 2>/dev/null && \
           grep -qE "^CONFIG_PACKAGE_${alt}=[ym]" .config 2>/dev/null; then
            warn "⚠️  冲突: $pkg ↔ $alt，禁用 $pkg"
            sed -i "s/^CONFIG_PACKAGE_${pkg}=[ym]/# CONFIG_PACKAGE_${pkg} is not set/" .config
        fi
    done
    
    # 🔄 重载配置
    make defconfig >/dev/null 2>&1
    info "✓ 冲突预检完成"
}

# ============================================================================
# 🚀 主执行流程
# ============================================================================
main() {
    echo "🔧 开始执行自定义配置 (设备: $DEVICE)"
    
    configure_feeds          # 1. 插件源配置
    sync_kernel              # 2. 内核同步（可选）
    apply_base_config        # 3. 基础配置
    generate_banner          # 4. Banner 定制
    generate_wifi_config     # 5. WiFi 配置
    apply_translate          # 6. 汉化（可选）
    adjust_luci_menu         # 7. 菜单调整
    # ⚠️  注意：冲突预检需在 .config 生成后执行，放在编译前步骤
    
    echo "✅ 自定义配置完成"
}

# 🎯 执行
main "$@"
