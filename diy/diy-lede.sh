#!/bin/bash
# ============================================================================
# OpenWrt LEDE 自定义配置脚本 (完整修复版)
# 功能：系统检测 + 依赖安装 + 源码管理 + 智能配置 + 冲突预检 + 汉化 + WiFi定制
# 适配：TP-LINK XDR6088 / REDMI AX6000 / 自定义机型
# WiFi格式：${WIFI_PREFIX}${MAC后4位}_${频段}  例：TP-LINK_1234_5G
# ============================================================================
set -e

# 📋 接收环境变量（带默认值，确保本地调试兼容）
DEVICE="${DEVICE:-ax6000}"
DEVICE_NAME="${DEVICE_NAME:-OpenWrt}"
WIFI_PREFIX="${WIFI_PREFIX:-OpenWrt_}"
WIFI_PASSWORD="${WIFI_PASSWORD:-1234567890}"
ENABLE_TRANSLATE="${ENABLE_TRANSLATE:-true}"
ENABLE_KERNEL_SYNC="${ENABLE_KERNEL_SYNC:-false}"
SKIP_FEEDS_MODIFY="${SKIP_FEEDS_MODIFY:-false}"
CONFIG_VERSION="${CONFIG_VERSION:-full}"

# 📁 路径配置
OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.."; pwd)}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$GITHUB_WORKSPACE/diy/scripts}"
FILES_DIR="${FILES_DIR:-$GITHUB_WORKSPACE/diy/files}"

# 🔄 切换到源码目录
cd "$OPENWRT_PATH"

# 🎨 日志函数（彩色输出）
log_info()  { echo -e "\033[0;32m[✓]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[!]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $1"; }

# ============================================================================
# 🔧 模块 0: 加载辅助脚本（可选）
# ============================================================================
load_helpers() {
    log_info "🔧 加载辅助脚本..."
    if [ -f "$SCRIPTS_DIR/translate-map.sh" ]; then
        source "$SCRIPTS_DIR/translate-map.sh"
        log_info "  ✓ translate-map.sh"
    fi
    if [ -f "$SCRIPTS_DIR/conflict-resolver.sh" ]; then
        source "$SCRIPTS_DIR/conflict-resolver.sh"
        log_info "  ✓ conflict-resolver.sh"
    fi
}

# ============================================================================
# 🔧 模块 1: 配置 feeds 源
# ============================================================================
configure_feeds() {
    [ "$SKIP_FEEDS_MODIFY" = "true" ] && { log_info "⏭️ 跳过 feeds 配置"; return 0; }
    log_info "📡 配置插件源..."
    
    # 安全添加源（避免重复）
    safe_add_feed() {
        local name="$1" url="$2"
        if ! grep -q "^src-git $name " feeds.conf.default 2>/dev/null; then
            echo "src-git $name $url" >> feeds.conf.default
            log_info "  + $name"
        fi
    }
    
    # 📦 常用插件源
    safe_add_feed "nas" "https://github.com/linkease/nas-packages.git;master"
    safe_add_feed "small" "https://github.com/kenzok8/small;master"
    safe_add_feed "kenzo" "https://github.com/kenzok8/openwrt-packages;master"
    safe_add_feed "immortalwrt" "https://github.com/immortalwrt/packages;master"
    
    # 🔄 更新并安装 feeds
    log_info "🔄 更新 feeds 索引..."
    ./scripts/feeds update -a 2>&1 | tail -5
    log_info "📦 安装 feeds 包..."
    ./scripts/feeds install -a 2>&1 | tail -5
}

# ============================================================================
# 🔧 模块 2: 内核版本同步
# ============================================================================
sync_kernel() {
    [ "$ENABLE_KERNEL_SYNC" != "true" ] && return 0
    log_info "🔧 同步内核至 6.12..."
    
    local kernel_makefile="target/linux/mediatek/Makefile"
    if [ -f "$kernel_makefile" ]; then
        sed -i 's/KERNEL_PATCHVER[:=].*/KERNEL_PATCHVER:=6.12/' "$kernel_makefile"
        sed -i 's/KERNEL_TESTING_PATCHVER[:=].*/KERNEL_TESTING_PATCHVER:=6.12/' "$kernel_makefile" 2>/dev/null || true
        log_info "✓ 内核版本已锁定为 6.12"
    else
        log_warn "⚠️  未找到 $kernel_makefile，跳过内核同步"
    fi
}

# ============================================================================
# 🔧 模块 3: 基础系统配置
# ============================================================================
apply_base_config() {
    log_info "🔧 应用基础配置..."
    
    # 🏷️ 修改主机名/发行版标识
    local config_gen="package/base-files/files/bin/config_generate"
    local default_settings="package/lean/default-settings/files/zzz-default-settings"
    
    if [ -f "$config_gen" ]; then
        sed -i "s/['\"]LEDE['\"]/\'OpenWrt\'/g" "$config_gen"
        log_info "  ✓ 修改 config_generate"
    fi
    
    if [ -f "$default_settings" ]; then
        sed -i "s/['\"]LEDE['\"]/\'OpenWrt\'/g" "$default_settings"
        # 删除默认密码哈希（强制首次登录修改）
        sed -i '/V4UetPzk\$CYXluq4wUazHjmCDBCqXF/d' "$default_settings"
        log_info "  ✓ 修改 default-settings"
    fi
    
    # 🌐 设置默认时区
    echo "CONFIG_GENERAL_DEFAULT_TIMEZONE='CST-8'" >> .config 2>/dev/null || true
}

# ============================================================================
# 📶 模块 4: WiFi 配置（核心：机型_MAC_频段 格式）
# ============================================================================
setup_wifi() {
    log_info "📶 配置 WiFi (格式: ${WIFI_PREFIX}XXXX_2G/5G)..."
    local script="package/kernel/mac80211/files/lib/wifi/mac80211.sh"
    
    # 🔍 检查文件是否存在
    if [ ! -f "$script" ]; then
        log_warn "⚠️  未找到 $script，跳过 WiFi 配置"
        return 0
    fi
    
    # 📋 备份原文件（便于调试/回滚）
    cp "$script" "${script}.bak" 2>/dev/null || true
    
    # 🔧 写入完整模板（使用单引号 heredoc 防止变量提前展开）
    cat > "$script" << 'MAC80211_TEMPLATE'
#!/bin/sh
append DRIVERS "mac80211"

# 📦 编译时注入的变量（占位符，后续替换）
WIFI_PREFIX="__WIFI_PREFIX__"
WIFI_KEY="__WIFI_PASSWORD__"

detect_mac80211() {
    # ✅ 首次启动检测，避免重复配置
    [ -f "/etc/.wifi_customized" ] && return 0
    
    # 如果 wireless 配置为空，清除标记以便重新生成
    [ ! -s /etc/config/wireless ] && rm -f /etc/.wifi_customized
    
    local devidx=0
    config_load wireless
    
    # 统计现有 radio 配置数量
    while :; do
        config_get type "radio$devidx" type
        [ -n "$type" ] || break
        devidx=$((devidx + 1))
    done
    
    # 🔄 遍历物理无线设备
    for _dev in /sys/class/ieee80211/*; do
        [ -e "$_dev" ] || continue
        dev="${_dev##*/}"
        
        # 🎯 获取 MAC 地址（去冒号，取后4位作为标识）
        local mac=$(cat /sys/class/ieee80211/${dev}/macaddress 2>/dev/null | tr -d ':')
        local suffix="${mac: -4}"
        [ -z "$suffix" ] && suffix="0000"
        
        # 📡 判断频段：2G 或 5G
        local band="2G"
        iwinfo nl80211 info "$dev" 2>/dev/null | grep -q "5GHz" && band="5G"
        
        # 🏷️ 生成 SSID: 前缀 + MAC后4位 + _ + 频段
        # 示例: TP-LINK_1234_5G
        local ssid="${WIFI_PREFIX}${suffix}_${band}"
        
        # 📝 批量写入 UCI 配置
        uci -q batch << UCIEOF
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
UCIEOF
        devidx=$((devidx + 1))
    done
    
    # ✅ 标记已配置，避免下次启动重复执行
    touch /etc/.wifi_customized
}

# 仅当参数为 detect 时执行检测逻辑
[ "$1" = "detect" ] && detect_mac80211
MAC80211_TEMPLATE

    # 🔁 关键：替换占位符为实际值（确保变量正确注入）
    sed -i "s|__WIFI_PREFIX__|${WIFI_PREFIX}|g" "$script"
    sed -i "s|__WIFI_PASSWORD__|${WIFI_PASSWORD}|g" "$script"
    
    chmod +x "$script"
    log_info "✓ WiFi 配置完成 (示例: ${WIFI_PREFIX}XXXX_2G)"
}

# ============================================================================
# 🔤 模块 5: 插件汉化（可选）
# ============================================================================
apply_translate() {
    [ "$ENABLE_TRANSLATE" != "true" ] && { log_info "⏭️ 跳过汉化"; return 0; }
    log_info "🔤 应用插件汉化..."
    
    # 📦 优先使用辅助脚本（如果存在）
    if declare -f translate_file &>/dev/null; then
        find package feeds -type f \( -name "*.lua" -o -name "*.po" \) 2>/dev/null | while read -r f; do
            translate_file "$f" 2>/dev/null || true
        done
        log_info "✓ 汉化完成 (translate-map.sh)"
        return 0
    fi
    
    # 🔧 内联简化映射（常用插件名替换）
    local translate_rules=(
        "AdGuard Home:AdGuard"
        "PassWall:科学上网"
        "软件包:插件管理"
        "网络存储:NAS"
        "系统工具:系统"
    )
    
    for rule in "${translate_rules[@]}"; do
        local old="${rule%%:*}"
        local new="${rule##*:}"
        find package feeds -type f -name "*.lua" -exec sed -i "s|\"$old\"|\"$new\"|g" {} \; 2>/dev/null || true
    done
    
    log_info "✓ 汉化完成 (内联规则)"
}

# ============================================================================
# ⚔️ 模块 6: 包冲突预检与修复
# ============================================================================
resolve_conflicts() {
    log_info "⚔️ 执行包冲突预检..."
    [ ! -f ".config" ] && { log_warn "⚠️  .config 不存在，跳过冲突检查"; return 0; }
    
    # 📦 使用辅助脚本（如果存在）
    if declare -f resolve_conflicts_internal &>/dev/null; then
        resolve_conflicts_internal ".config"
        make defconfig >/dev/null 2>&1
        log_info "✓ 冲突预检完成 (conflict-resolver.sh)"
        return 0
    fi
    
    # 🔧 内联修复规则（高频冲突项）
    
    # 1️⃣ vsftpd 冲突拦截
    if grep -qE "^CONFIG_PACKAGE_vsftpd-alt=[ym]" .config 2>/dev/null; then
        log_info "  🔧 修复 vsftpd 冲突..."
        sed -i 's/^CONFIG_PACKAGE_vsftpd=[ym]/# CONFIG_PACKAGE_vsftpd is not set/' .config 2>/dev/null || true
        sed -i 's/^CONFIG_PACKAGE_luci-app-vsftpd=[ym]/# CONFIG_PACKAGE_luci-app-vsftpd is not set/' .config 2>/dev/null || true
    fi
    
    # 2️⃣ dnsmasq 基础版 vs 完整版
    if grep -qE "^CONFIG_PACKAGE_dnsmasq-full=[ym]" .config && grep -qE "^CONFIG_PACKAGE_dnsmasq=[ym]" .config; then
        log_info "  🔧 修复 dnsmasq 冲突..."
        sed -i 's/^CONFIG_PACKAGE_dnsmasq=[ym]/# CONFIG_PACKAGE_dnsmasq is not set/' .config 2>/dev/null || true
    fi
    
    # 3️⃣ firewall3 vs firewall4
    if grep -qE "^CONFIG_PACKAGE_firewall4=[ym]" .config && grep -qE "^CONFIG_PACKAGE_firewall=[ym]" .config; then
        log_info "  🔧 修复 firewall 冲突..."
        sed -i 's/^CONFIG_PACKAGE_firewall=[ym]/# CONFIG_PACKAGE_firewall is not set/' .config 2>/dev/null || true
    fi
    
    # 4️⃣ libustream SSL 后端冲突（保留 openssl）
    local ssl_count=$(grep -cE "^CONFIG_PACKAGE_libustream-(mbedtls|openssl|wolfssl)=[ym]" .config 2>/dev/null || echo 0)
    if [ "$ssl_count" -gt 1 ]; then
        log_info "  🔧 修复 libustream 多后端冲突..."
        sed -i 's/^CONFIG_PACKAGE_libustream-mbedtls=[ym]/# CONFIG_PACKAGE_libustream-mbedtls is not set/' .config 2>/dev/null || true
        sed -i 's/^CONFIG_PACKAGE_libustream-wolfssl=[ym]/# CONFIG_PACKAGE_libustream-wolfssl is not set/' .config 2>/dev/null || true
    fi
    
    # 🔄 重载配置使修复生效
    make defconfig >/dev/null 2>&1
    log_info "✓ 冲突预检完成 (内联规则)"
}

# ============================================================================
# 📁 模块 7: 复制预配置文件（可选）
# ============================================================================
copy_custom_files() {
    log_info "📁 处理预配置文件..."
    
    if [ ! -d "$FILES_DIR" ]; then
        log_warn "⚠️  $FILES_DIR 不存在，跳过预配置"
        return 0
    fi
    
    local dst="${OPENWRT_PATH}/package/base-files/files"
    mkdir -p "$dst"
    
    # 📋 复制所有文件（保留目录结构）
    cp -rf "$FILES_DIR"/. "$dst/" 2>/dev/null || true
    log_info "✓ 预配置文件已复制"
    
    # 🔐 确保脚本可执行
    find "$dst" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    # 🔄 注册 fix-wifi.sh 到 rc.local（如果存在）
    local fix_wifi="$dst/usr/bin/fix-wifi.sh"
    local rc_local="$dst/etc/rc.local"
    if [ -f "$fix_wifi" ] && [ -f "$rc_local" ]; then
        if ! grep -q "fix-wifi" "$rc_local"; then
            sed -i '/^exit 0/i\/usr/bin/fix-wifi.sh \&' "$rc_local"
            log_info "✓ 已注册 fix-wifi.sh 到 rc.local"
        fi
    fi
}

# ============================================================================
# 🚀 主流程入口
# ============================================================================
main() {
    log_info "🔧 开始配置 (设备: $DEVICE | 配置: $CONFIG_VERSION)"
    log_info "📶 WiFi前缀: $WIFI_PREFIX | 密码: ${WIFI_PASSWORD:0:4}****"
    
    # 📋 执行配置模块（按顺序）
    load_helpers
    configure_feeds
    sync_kernel
    apply_base_config
    setup_wifi              # 🔑 核心：WiFi 定制
    apply_translate
    resolve_conflicts
    copy_custom_files
    
    # ✅ 最终校验
    if [ -f ".config" ]; then
        local pkg_count=$(grep -c '^CONFIG_PACKAGE_.*=y' .config 2>/dev/null || echo 0)
        log_info "✅ 配置完成 | 已选插件: $pkg_count 个"
    else
        log_warn "⚠️  配置完成，但 .config 未生成（可能需手动 make defconfig）"
    fi
}

# 🎬 执行主函数
main "$@"
