# suoha-x.sh - 一键部署 x-tunnel + Cloudflare Argo 代理服务

一个自动化部署脚本，用于在 Linux 系统上快速搭建基于 **x-tunnel** + **Cloudflare Argo Tunnel** 的代理服务，支持临时隧道/持久化隧道切换、地区代理（opera-proxy）、token 验证等功能，全程无需交互，纯命令行参数驱动。

## 🌟 功能特性
- 自动适配主流 Linux 发行版（Debian/Ubuntu/CentOS/Fedora/Alpine）
- 自动检测 CPU 架构（x86_64/i386/arm64），下载对应版本程序
- 支持临时 Argo 隧道（默认）和持久化隧道（通过 `-t` 参数绑定令牌）
- 可选启用 opera-proxy 前置代理（支持 AM/AS/EU 地区）
- 支持 x-tunnel 身份令牌验证（`-x` 参数）
- 支持 IPv4/IPv6 双栈模式（`-c` 参数）
- 提供服务启停、状态查看、缓存清理功能

## 🚀 快速开始

### 1. 一键下载并执行脚本
```bash
# 方式1：使用 curl 下载
curl -L https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/x-tunnel/suoha-x.sh && chmod +x suoha-x.sh

# 方式2：使用 wget 下载（若系统无 curl）
wget https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/x-tunnel/suoha-x.sh && chmod +x suoha-x.sh
