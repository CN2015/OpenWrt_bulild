# 🚀 OpenWrt 自动化编译系统

> 基于 GitHub Actions 的 LEDE 固件自动编译方案，支持多机型/智能配置/冲突预检/汉化定制

[![Build Status](https://github.com/USER/REPO/actions/workflows/build-openwrt.yml/badge.svg)](https://github.com/USER/REPO/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-LEDE-orange)](https://github.com/coolsnowwolf/lede)

---

## 📋 功能特性

✅ **多机型支持**：预置 TP-LINK XDR6088 / REDMI AX6000，支持自定义机型扩展  
✅ **智能配置**：自动主机名 + WiFi 前缀 + Banner 定制 + 汉化插件名  
✅ **冲突预检**：自动检测并解决 vsftpd/iptables 等常见包冲突  
✅ **编译加速**：ccache + 工具链缓存 + 失败自动重试  
✅ **灵活触发**：手动/自动/CI 多模式，支持工作流参数定制  
✅ **输出规范**：固件重命名 + SHA256 校验 + 配置备份 + 日志归档  

---

## 🗂️ 文件结构
