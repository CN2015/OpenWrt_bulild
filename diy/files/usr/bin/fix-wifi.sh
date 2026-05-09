#!/bin/sh
# /usr/bin/fix-wifi.sh - OpenWrt WiFi 首次启动修复脚本
# 功能: 清理锁文件 + 强制重新检测无线 + 应用自定义配置
# 调用: 通过 /etc/rc.local 或 luci-app-autoreboot 首次启动执行

set -e

LOG_FILE="/var/log/fix-wifi.log"
LOCK_FILE="/etc/.wifi_customized"
WIFI_CONFIG="/etc/config/wireless"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 🔍 检查是否已执行过
if [ -f "$LOCK_FILE" ] && [ -s "$WIFI_CONFIG" ]; then
    log "✅ WiFi 配置已存在，跳过修复"
    exit 0
fi

log "🔧 开始 WiFi 修复流程..."

# 🧹 步骤 1: 清理旧配置和锁文件
log "🧹 清理无线配置缓存..."
rm -f /etc/.wifi_mac80211_customized /etc/.wifi_customized 2>/dev/null || true
uci -q delete wireless.@wifi-device[-1] 2>/dev/null || true

# 🔄 步骤 2: 强制重新检测无线硬件
log "🔄 执行 wifi detect..."
if /sbin/wifi detect > /tmp/wireless.new 2>&1; then
    # 📋 合并新配置（保留手动修改部分）
    if [ -s /tmp/wireless.new ]; then
        log "📋 合并无线配置..."
        # 保留原有 network/ssid 配置，仅更新 device 部分
        grep -v '^config wifi-device' "$WIFI_CONFIG" > /tmp/wireless.old 2>/dev/null || true
        cat /tmp/wireless.new /tmp/wireless.old > "$WIFI_CONFIG" 2>/dev/null || cp /tmp/wireless.new "$WIFI_CONFIG"
        rm -f /tmp/wireless.new /tmp/wireless.old
    fi
else
    log "⚠️  wifi detect 失败，尝试重启 mac80211 模块..."
    rmmod mt7915e mt7981_wmac 2>/dev/null || true
    modprobe mt7915e 2>/dev/null || true
    /sbin/wifi detect > "$WIFI_CONFIG" 2>&1 || true
fi

# 📶 步骤 3: 应用自定义参数（如已定义）
if [ -n "$WIFI_PREFIX" ] && [ -n "$WIFI_PASSWORD" ]; then
    log "📶 应用自定义 WiFi 配置..."
    # 替换默认 SSID 和密码
    sed -i "s/OpenWrt_2G/${WIFI_PREFIX}XXXX_2G/g" "$WIFI_CONFIG"
    sed -i "s/OpenWrt_5G/${WIFI_PREFIX}XXXX_5G/g" "$WIFI_CONFIG"
    sed -i "s/option key '.*'/option key '${WIFI_PASSWORD}'/g" "$WIFI_CONFIG"
fi

# 🌐 步骤 4: 启用无线并设置国家码
log "🌐 启用无线 + 设置 CN 国家码..."
uci -q batch << EOF
set wireless.radio0.country='CN'
set wireless.radio1.country='CN'
set wireless.radio0.disabled='0'
set wireless.radio1.disabled='0'
set wireless.default_radio0.encryption='psk2'
set wireless.default_radio1.encryption='psk2'
EOF
uci -q commit wireless

# 🔄 步骤 5: 重载无线服务
log "🔄 重载无线服务..."
if /sbin/wifi reload 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ WiFi 重载成功"
    
    # 📋 显示当前 WiFi 状态
    log "📡 当前 WiFi 状态:"
    iwinfo 2>/dev/null | grep -E "SSID|Encryption" | head -6 | while read -r line; do
        log "   $line"
    done
else
    log "❌ WiFi 重载失败，请手动执行: wifi up"
    exit 1
fi

# ✅ 标记已完成
touch "$LOCK_FILE"
log "🎉 WiFi 修复完成！"

# 🔄 可选: 30 秒后自动重启网络（确保配置生效）
# (sleep 30 && /etc/init.d/network restart) &
exit 0
