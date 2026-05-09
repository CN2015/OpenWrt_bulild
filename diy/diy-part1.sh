#!/bin/bash
# ============================================
# LEDE 编译脚本 - Part 1（配置 feeds 前）
# 作用：添加第三方插件源、清理冲突包
# ============================================
set -e

echo "🔧 [Part 1] 开始配置 feeds..."

# 1️⃣ 添加 kenzo 第三方源（常用插件集合）
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default
echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default

# 2️⃣ 清理 LEDE 内置的旧版插件（避免与第三方源冲突）
rm -rf package/lean/luci-app-ssr-plus
rm -rf package/lean/luci-app-passwall
rm -rf package/lean/luci-app-adguardhome
rm -rf package/lean/luci-app-openclash

echo "✅ [Part 1] feeds 配置完成"
