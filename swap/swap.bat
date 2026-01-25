#!/bin/bash
set -euo pipefail

# 定义颜色输出（增强交互体验）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：必须以 root 权限运行此脚本！${NC}"
        exit 1
    fi
}

# 检测系统发行版（适配不同 Linux 系统）
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        OS_VERSION=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
        OS_VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS="RedHat/CentOS"
        OS_VERSION=$(sed 's/[^0-9.]//g' /etc/redhat-release)
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
    fi
    echo -e "${GREEN}检测到系统：$OS $OS_VERSION${NC}"
}

# 核心函数：获取系统内存、SWAP信息并计算推荐值（修复中文环境+数值转换）
get_memory_info() {
    # 修复1：兼容中文/英文free输出（匹配Mem/内存、Swap/交换）
    # 获取物理内存总字节数（优先英文，再中文）
    MEM_TOTAL_BYTES=$(free -b | awk '/^Mem:/ {print $2}')
    if [ -z "$MEM_TOTAL_BYTES" ]; then
        MEM_TOTAL_BYTES=$(free -b | awk '/^内存：/ {print $2}')
    fi

    # 获取SWAP总字节数（优先英文，再中文）
    SWAP_TOTAL_BYTES=$(free -b | awk '/^Swap:/ {print $2}')
    if [ -z "$SWAP_TOTAL_BYTES" ]; then
        SWAP_TOTAL_BYTES=$(free -b | awk '/^交换：/ {print $2}')
    fi

    # 修复2：数值转换（避免空值/小数导致的0GB问题，四舍五入取整）
    # 物理内存转换为GB（1GB=1024*1024*1024=1073741824字节）
    if [ -n "$MEM_TOTAL_BYTES" ] && [ "$MEM_TOTAL_BYTES" -gt 0 ]; then
        # 四舍五入计算（比如3.8Gi≈4GB，1.9Gi≈2GB）
        MEM_TOTAL_GB=$(echo "scale=0; ($MEM_TOTAL_BYTES + 536870912) / 1073741824" | bc)
    else
        MEM_TOTAL_GB=0
    fi

    # SWAP转换为GB（无则0GB）
    if [ -n "$SWAP_TOTAL_BYTES" ] && [ "$SWAP_TOTAL_BYTES" -gt 0 ]; then
        SWAP_TOTAL_GB=$(echo "scale=0; ($SWAP_TOTAL_BYTES + 536870912) / 1073741824" | bc)
    else
        SWAP_TOTAL_GB=0
    fi

    # 修复3：推荐值计算（内存2倍，最多8GB，避免0GB推荐）
    RECOMMENDED_SWAP=$((MEM_TOTAL_GB * 2))
    # 兜底：如果内存检测异常（0GB），默认推荐2GB
    if [ "$RECOMMENDED_SWAP" -eq 0 ]; then
        RECOMMENDED_SWAP=2
    elif [ "$RECOMMENDED_SWAP" -gt 8 ]; then
        RECOMMENDED_SWAP=8
    fi

    # 清晰展示信息
    echo -e "\n${YELLOW}=== 系统内存/SWAP 信息 ===${NC}"
    echo -e "${GREEN}📊 物理内存总大小：${MEM_TOTAL_GB}GB${NC}"
    echo -e "${GREEN}📊 当前SWAP总大小：${SWAP_TOTAL_GB}GB${NC}"
    echo -e "${YELLOW}💡 推荐SWAP配置值：${RECOMMENDED_SWAP}GB（内存2倍，最大8GB）${NC}"
}

# 查看当前 SWAP 详细状态（兼容中文环境）
check_swap() {
    echo -e "\n${YELLOW}=== SWAP 详细状态 ===${NC}"
    # 检查是否有启用的SWAP（兼容中英文）
    if swapon --show | grep -q "swap" || swapon --show | grep -q "交换"; then
        swapon --show
    else
        echo "暂无启用的 SWAP 分区/文件"
    fi
    echo -e "\n${YELLOW}=== 内存与 SWAP 总览 ===${NC}"
    free -h
}

# 安装 SWAP
install_swap() {
    # 检查是否已有 SWAP
    if [ "$SWAP_TOTAL_GB" -gt 0 ]; then
        echo -e "${YELLOW}警告：检测到已有 ${SWAP_TOTAL_GB}GB SWAP，是否覆盖？(y/N)${NC}"
        read -r confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "取消安装操作"
            return 0
        fi
        # 先关闭现有 SWAP
        swapoff -a
        # 清理 fstab 中的旧 SWAP 条目
        sed -i '/swapfile/d' /etc/fstab
    fi

    # 交互选择 SWAP 大小（默认使用推荐值）
    echo -e "\n${YELLOW}=== 配置 SWAP 大小 ===${NC}"
    echo "推荐 SWAP 大小：${RECOMMENDED_SWAP}GB（最大不超过8GB）"
    read -rp "请输入要创建的 SWAP 大小（单位：GB，直接回车使用推荐值）：" SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

    # 验证输入是否为数字且不超过8GB
    if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误：请输入有效的数字！${NC}"
        exit 1
    fi
    if [ "$SWAP_SIZE" -gt 8 ]; then
        echo -e "${YELLOW}提示：SWAP 大小建议不超过8GB，是否继续使用 ${SWAP_SIZE}GB？(y/N)${NC}"
        read -r confirm_big
        if [[ ! $confirm_big =~ ^[Yy]$ ]]; then
            SWAP_SIZE=8
            echo "自动调整为最大推荐值：8GB"
        fi
    fi

    # 检查磁盘空间
    AVAIL_SPACE=$(df -BG / | awk '/\/$/ {print $4}' | sed 's/G//')
    if [ "$AVAIL_SPACE" -lt "$SWAP_SIZE" ]; then
        echo -e "${RED}错误：根目录可用空间不足（仅 ${AVAIL_SPACE}GB），无法创建 ${SWAP_SIZE}GB 的 SWAP 文件！${NC}"
        exit 1
    fi

    # 创建 SWAP 文件（默认路径 /swapfile）
    SWAP_FILE="/swapfile"
    echo -e "\n${GREEN}正在创建 ${SWAP_SIZE}GB 的 SWAP 文件...${NC}"
    # 优先使用 fallocate（更快），失败则用 dd（兼容性更好）
    if fallocate -l "${SWAP_SIZE}G" "$SWAP_FILE"; then
        echo "使用 fallocate 创建 SWAP 文件成功"
    else
        echo "fallocate 失败，使用 dd 创建（速度较慢）..."
        dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$SWAP_SIZE" status=progress
    fi

    # 设置安全权限（仅 root 可读写）
    chmod 600 "$SWAP_FILE"
    # 格式化 SWAP 文件
    mkswap "$SWAP_FILE"
    # 启用 SWAP
    swapon "$SWAP_FILE"

    # 写入 /etc/fstab 确保开机自启
    echo -e "\n${GREEN}配置开机自动挂载 SWAP...${NC}"
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    # 验证 fstab 配置
    mount -a

    echo -e "\n${GREEN}=== SWAP 安装完成 ===${NC}"
    # 重新获取内存/SWAP信息并展示
    get_memory_info
    check_swap
}

# 卸载 SWAP
uninstall_swap() {
    # 检查是否有 SWAP
    if [ "$SWAP_TOTAL_GB" -eq 0 ]; then
        echo -e "${YELLOW}暂无启用的 SWAP，无需卸载${NC}"
        return 0
    fi

    echo -e "${YELLOW}=== 卸载 SWAP ===${NC}"
    read -rp "确定要卸载 ${SWAP_TOTAL_GB}GB SWAP 吗？(y/N)：" confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "取消卸载操作"
        return 0
    fi

    # 关闭所有 SWAP
    swapoff -a
    # 删除 SWAP 文件（默认 /swapfile）
    if [ -f "/swapfile" ]; then
        rm -f /swapfile
        echo "已删除 SWAP 文件：/swapfile"
    fi
    # 清理 /etc/fstab 中的 SWAP 条目
    sed -i '/swapfile/d' /etc/fstab
    echo -e "\n${GREEN}=== SWAP 卸载完成 ===${NC}"
    # 重新获取内存/SWAP信息并展示
    get_memory_info
    check_swap
}

# 主菜单
main_menu() {
    echo -e "\n${GREEN}=====================================${NC}"
    echo -e "${GREEN}      Linux SWAP 一键管理脚本        ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo "1. 安装 SWAP（默认使用推荐值 ${RECOMMENDED_SWAP}GB）"
    echo "2. 卸载 SWAP（清理所有相关配置）"
    echo "3. 重新查看内存/SWAP 信息"
    echo "4. 退出"
    echo -e "${GREEN}=====================================${NC}"
    read -rp "请选择操作（1-4）：" choice

    case $choice in
        1)
            install_swap
            ;;
        2)
            uninstall_swap
            ;;
        3)
            get_memory_info
            check_swap
            ;;
        4)
            echo "脚本退出"
            exit 0
            ;;
        *)
            echo -e "${RED}错误：无效的选择！${NC}"
            sleep 2
            main_menu
            ;;
    esac
}

# 全局变量（存储内存/SWAP信息）
MEM_TOTAL_GB=0
SWAP_TOTAL_GB=0
RECOMMENDED_SWAP=0

# 脚本执行流程
check_root
detect_os
# 第一步：获取并展示内存/SWAP信息+推荐值
get_memory_info
# 停顿2秒让用户看清信息
sleep 2
# 进入主菜单
main_menu