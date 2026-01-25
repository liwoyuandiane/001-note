#!/usr/bin/env bash
# Linux VPS一键添加/删除swap脚本（纯中文展示+英文变量/函数，解决运行报错）
# 颜色定义（英文变量名，避免解析错误）
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m" 
FONT="\033[0m"

# 检查是否为root权限（英文函数名）
check_root(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：该脚本必须以root权限运行！${FONT}"
        exit 1
    fi
}

# 检测OpenVZ架构（不支持swap）
check_ovz(){
    if [[ -d "/proc/vz" ]]; then
        echo -e "${RED}错误：你的VPS基于OpenVZ架构，不支持创建swap！${FONT}"
        exit 1
    fi
}

# 获取系统内存/swap信息（兼容中英文free输出）
get_mem_info(){
    # 兼容英文Mem/中文内存字段（英文变量名）
    MEM_TOTAL_BYTES=$(free -b | awk '/^Mem:/ {print $2}')
    if [ -z "$MEM_TOTAL_BYTES" ]; then
        MEM_TOTAL_BYTES=$(free -b | awk '/^内存：/ {print $2}')
    fi
    # 转换为GB（四舍五入）
    MEM_TOTAL_GB=$(echo "scale=0; ($MEM_TOTAL_BYTES + 536870912) / 1073741824" | bc)
    # 计算推荐swap值：内存2倍，最大8GB
    RECOMMENDED_SWAP=$((MEM_TOTAL_GB * 2))
    [ $RECOMMENDED_SWAP -gt 8 ] && RECOMMENDED_SWAP=8
    # 兜底：内存检测异常时默认推荐2GB
    [ $RECOMMENDED_SWAP -eq 0 ] && RECOMMENDED_SWAP=2

    # 获取当前swap大小（GB，无则0）
    SWAP_TOTAL_BYTES=$(free -b | awk '/^Swap:/ {print $2}')
    if [ -z "$SWAP_TOTAL_BYTES" ]; then
        SWAP_TOTAL_BYTES=$(free -b | awk '/^交换：/ {print $2}')
    fi
    SWAP_TOTAL_GB=$(echo "scale=0; ($SWAP_TOTAL_BYTES + 536870912) / 1073741824" | bc)
}

# 添加swap（优化版）
add_swap(){
    # 先获取内存和推荐值
    get_mem_info
    echo -e "\n${GREEN}=== 当前系统信息 ===${FONT}"
    echo -e "${GREEN}物理内存总大小：${MEM_TOTAL_GB}GB${FONT}"
    echo -e "${GREEN}当前SWAP大小：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "${YELLOW}推荐SWAP大小：${RECOMMENDED_SWAP}GB（内存2倍，最大8GB）${FONT}"
    
    # 交互输入（默认使用推荐值，单位明确为GB）
    read -p "请输入要添加的SWAP数值（单位：GB，直接回车使用推荐值）:" SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

    # 校验输入是否为正整数
    if ! [[ "$SWAP_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}错误：请输入有效的正整数！${FONT}"
        exit 1
    fi

    # 转换为MB（兼容原脚本的M单位逻辑）
    SWAP_SIZE_MB=$((SWAP_SIZE * 1024))

    # 检查根目录可用空间
    AVAIL_SPACE_MB=$(df -BM / | awk '/\/$/ {print $4}' | sed 's/M//')
    if [ $AVAIL_SPACE_MB -lt $SWAP_SIZE_MB ]; then
        echo -e "${RED}错误：根目录可用空间不足！可用：${AVAIL_SPACE_MB}MB，需要：${SWAP_SIZE_MB}MB${FONT}"
        exit 1
    fi

    # 精准判断fstab中的swapfile（排除注释行）
    if ! grep -E "^/swapfile\s+none\s+swap\s+" /etc/fstab > /dev/null 2>&1; then
        echo -e "${GREEN}未发现swapfile，正在创建swap文件...${FONT}"
        
        # fallocate失败时降级使用dd
        if ! fallocate -l ${SWAP_SIZE_MB}M /swapfile; then
            echo -e "${YELLOW}fallocate创建失败，使用dd创建（速度较慢）...${FONT}"
            dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB} status=progress
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile

        # 备份fstab后再写入（避免误操作）
        cp /etc/fstab /etc/fstab.备份.$(date +%Y%m%d%H%M%S)
        echo '/swapfile none swap defaults 0 0' >> /etc/fstab
        
        echo -e "\n${GREEN}Swap创建成功！当前状态：${FONT}"
        free -h | grep -E "Mem|Swap|内存|交换" # 兼容中英文展示
    else
        echo -e "${RED}错误：swapfile已存在！请先删除后再创建。${FONT}"
    fi
}

# 删除swap（优化版）
del_swap(){
    # 精准判断swapfile是否存在
    if grep -E "^/swapfile\s+none\s+swap\s+" /etc/fstab > /dev/null 2>&1; then
        echo -e "${GREEN}发现swapfile，正在移除...${FONT}"
        
        # 备份fstab
        cp /etc/fstab /etc/fstab.备份.$(date +%Y%m%d%H%M%S)
        # 精准删除fstab中的swapfile条目（不删注释行）
        sed -i '/^\/swapfile\s\+none\s\+swap\s+/d' /etc/fstab

        # 释放缓存增加容错（失败不影响主流程）
        sync && echo 3 > /proc/sys/vm/drop_caches || echo -e "${YELLOW}警告：缓存释放失败（不影响swap删除）${FONT}"
        
        # 先关闭指定swapfile，失败再关闭全部
        swapoff /swapfile || swapoff -a
        rm -f /swapfile
        
        echo -e "\n${GREEN}Swap删除成功！当前状态：${FONT}"
        free -h | grep -E "Mem|Swap|内存|交换" # 兼容中英文展示
    else
        echo -e "${RED}错误：未发现swapfile！删除失败。${FONT}"
    fi
}

# 主菜单（纯中文展示）
main_menu(){
    check_root
    check_ovz
    clear
    # 先显示当前系统内存/swap状态
    get_mem_info
    echo -e "———————————————————————————————————————"
    echo -e "${GREEN}Linux VPS 一键Swap管理脚本${FONT}"
    echo -e "${GREEN}当前内存：${MEM_TOTAL_GB}GB | 当前Swap：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "———————————————————————————————————————"
    echo -e "${GREEN}1、添加Swap${FONT}"
    echo -e "${GREEN}2、删除Swap${FONT}"
    echo -e "———————————————————————————————————————"
    read -p "请输入数字 [1-2]:" CHOICE
    case "$CHOICE" in
        1)
        add_swap
        ;;
        2)
        del_swap
        ;;
        *)
        clear
        echo -e "${RED}错误：请输入有效的数字 [1-2]${FONT}"
        sleep 2
        main_menu
        ;;
    esac
}

# 启动脚本
main_menu
