#!/bin/bash
# ============================================
# LEDE 编译脚本 - Part 2（配置完成后）
# 作用：设置主题、主机名、默认配置
# ============================================
set -e

echo "🔧 [Part 2] 开始应用自定义配置..."

# 1️⃣ 设置默认 Web 主题为 Argon
sed -i 's/CONFIG_PACKAGE_luci-theme-bootstrap=y/# CONFIG_PACKAGE_luci-theme-bootstrap is not set/g' .config
sed -i 's/# CONFIG_PACKAGE_luci-theme-argon is not set/CONFIG_PACKAGE_luci-theme-argon=y/g' .config

# 2️⃣ 设置默认主机名（避免多台路由器名称冲突）
sed -i 's/LEDE/OpenWrt/g' package/base-files/files/bin/config_generate

# 3️⃣ 替换默认下载源为国内镜像（加速首次登录插件安装）
[ -f "package/lean/default-settings/files/zzz-default-settings" ] && \
  sed -i 's|https://github.com/|https://gh-proxy.com/https://github.com/|g' \
  package/lean/default-settings/files/zzz-default-settings

# 4️⃣ 预设管理地址为 192.168.1.1（如需修改请调整此处）
# sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

echo "✅ [Part 2] 自定义配置完成"
