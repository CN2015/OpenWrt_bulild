#!/bin/bash
# ==========================================
# 🛠️ OpenWrt 编译前自定义脚本 (diy-lede.sh)
# 作用于 coolsnowwolf/lede 源码根目录
# ==========================================
set -e

echo "🔧 [DIY] 开始执行自定义配置..."

# 1. 设置默认 Web 主题为 Argon
sed -i 's/CONFIG_PACKAGE_luci-theme-bootstrap=y/# CONFIG_PACKAGE_luci-theme-bootstrap is not set/g' .config 2>/dev/null || true
sed -i 's/# CONFIG_PACKAGE_luci-theme-argon is not set/CONFIG_PACKAGE_luci-theme-argon=y/g' .config 2>/dev/null || true

# 2. 替换 Lean 源码默认设置中的 GitHub 地址为国内镜像（加速首次登录插件下载）
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
  sed -i 's|https://github.com/|https://gh-proxy.com/https://github.com/|g' package/lean/default-settings/files/zzz-default-settings
fi

# 3. 移除 Lean 源码内置的旧版插件（工作流已添加 kenzo/small 源，保留新版避免冲突）
rm -rf package/lean/luci-app-ssr-plus package/lean/luci-app-passwall package/lean/luci-app-adguardhome 2>/dev/null || true
echo "🗑️  [DIY] 已清理旧版 Lean 插件，将使用 kenzo/small 源的最新版本"

# 4. 预设主机名（避免多台路由器名称冲突）
sed -i 's/OpenWrt/My-OpenWrt/g' package/base-files/files/bin/config_generate 2>/dev/null || true

echo "✅ [DIY] 自定义脚本执行完成"
