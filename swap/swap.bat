#!/usr/bin/env bash
# Linux VPS 一键Swap管理脚本（最终稳定版）
# 修复：fallocate创建稀疏文件导致swapon失败、回车退出、fstab重复条目等问题

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m" 
FONT="\033[0m"

# 日志配置（关键操作可追溯）
LOG_FILE="/var/log/swap_manager.log"
touch "$LOG_FILE"

# 日志函数
log_info(){
    local msg="$1"
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$LOG_FILE"
}
log_error(){
    local msg="$1"
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$LOG_FILE"
}

# 退出时恢复终端颜色（避免残留彩色）
trap 'echo -e "${FONT}"; exit 0' EXIT INT TERM

# ===================== 基础校验函数 =====================
# 检查root权限
check_root(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：该脚本必须以root权限运行！${FONT}"
        log_error "脚本运行失败：非root权限"
        exit 1
    fi
}

# 检查关键命令是否存在（避免精简系统报错）
check_commands(){
    local required_cmds=("free" "dd" "mkswap" "swapon" "swapoff" "grep" "sed" "bc" "stat" "df")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要命令${cmd}，请先安装！${FONT}"
            log_error "脚本运行失败：缺少必要命令${cmd}"
            exit 1
        fi
    done
}

# 检测OpenVZ架构（不支持swap）
check_ovz(){
    if [[ -d "/proc/vz" ]]; then
        echo -e "${RED}错误：你的VPS基于OpenVZ架构，不支持创建swap！${FONT}"
        log_error "脚本运行失败：VPS为OpenVZ架构，不支持swap"
        exit 1
    fi
}

# ===================== 系统信息函数 =====================
# 获取系统内存/swap信息（兼容中英文free输出）
get_mem_info(){
    # 兼容英文Mem/中文内存字段
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

# ===================== 辅助函数 =====================
# 彻底清理fstab中所有/swapfile条目
clean_fstab_swap(){
    # 备份fstab
    local BACKUP_FILENAME="fstab.清理swap备份.$(date +%Y%m%d%H%M%S)"
    cp /etc/fstab /etc/$BACKUP_FILENAME
    # 彻底删除所有包含/swapfile的行（不管格式）
    sed -i '/\/swapfile/d' /etc/fstab
    echo -e "${GREEN}已清理fstab中所有/swapfile相关条目（备份：/etc/$BACKUP_FILENAME）${FONT}"
    log_info "清理fstab中所有/swapfile条目，备份文件：/etc/$BACKUP_FILENAME"
}

# ===================== 核心功能函数 =====================
# 添加Swap（强制用dd创建，避免fallocate稀疏文件问题）
add_swap(){
    get_mem_info
    echo -e "\n${GREEN}=== 当前系统信息 ===${FONT}"
    echo -e "${GREEN}物理内存总大小：${MEM_TOTAL_GB}GB${FONT}"
    echo -e "${GREEN}当前SWAP大小：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "${YELLOW}推荐SWAP大小：${RECOMMENDED_SWAP}GB（内存2倍，最大8GB）${FONT}"
    
    # 交互输入（回车默认使用推荐值，不退出）
    read -t 30 -p "请输入要添加的SWAP数值（单位：GB，直接回车/超时使用推荐值）:" SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

    # 校验输入是否为正整数
    if ! [[ "$SWAP_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}错误：请输入有效的正整数！${FONT}"
        log_error "创建Swap失败：输入非有效正整数，输入值：${SWAP_SIZE}"
        sleep 2  # 让用户看到错误提示
        return 0 # 返回菜单，不退出
    fi

    # 超过8GB二次确认
    if [ "$SWAP_SIZE" -gt 8 ]; then
        echo -e "${YELLOW}警告：SWAP大小超过8GB（推荐最大值），是否继续？(y/N)${FONT}"
        read -r CONFIRM_BIG
        if [[ ! $CONFIRM_BIG =~ ^[Yy]$ ]]; then
            SWAP_SIZE=8
            echo -e "${GREEN}自动调整为最大推荐值：8GB${FONT}"
        fi
    fi

    # 转换为MB（dd创建用MB单位更稳定）
    SWAP_SIZE_MB=$((SWAP_SIZE * 1024))

    # 检查根目录可用空间（留100MB余量，避免磁盘满）
    AVAIL_SPACE_MB=$(df -BM / | awk '/\/$/ {print $4}' | sed 's/M//')
    SAFE_SPACE_MB=$((AVAIL_SPACE_MB - 100))
    if [ "$SAFE_SPACE_MB" -lt "$SWAP_SIZE_MB" ]; then
        echo -e "${RED}错误：根目录可用空间不足！可用：${AVAIL_SPACE_MB}MB（预留100MB后：${SAFE_SPACE_MB}MB），需要：${SWAP_SIZE_MB}MB${FONT}"
        log_error "创建Swap失败：根目录可用空间不足，可用${AVAIL_SPACE_MB}MB，需要${SWAP_SIZE_MB}MB"
        sleep 2  # 让用户看到错误提示
        return 0 # 返回菜单，不退出
    fi

    # 优先检查物理文件是否存在
    if [ -f "/swapfile" ]; then
        echo -e "${RED}错误：/swapfile文件已存在！请先删除后再创建。${FONT}"
        log_error "创建Swap失败：物理文件/swapfile已存在"
        sleep 2  # 让用户看到错误提示
        return 0 # 返回菜单，不退出
    fi

    # 创建前彻底清理fstab（避免重复条目）
    clean_fstab_swap

    # 核心修复：强制用dd创建swap文件（避免fallocate稀疏文件问题）
    echo -e "${GREEN}未发现swapfile，正在创建swap文件...${FONT}"
    echo -e "${YELLOW}使用dd创建${SWAP_SIZE}GB swap文件（确保兼容性，速度稍慢）...${FONT}"
    # 用dd创建连续空间的文件，显示进度
    if dd --version 2>&1 | grep -q "coreutils"; then
        dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB} status=progress
    else
        dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB}
    fi

    # 校验dd创建结果（文件是否存在+大小是否匹配）
    if [ ! -f "/swapfile" ]; then
        echo -e "${RED}错误：dd创建swap文件失败！文件未生成${FONT}"
        log_error "dd创建swap文件失败：/swapfile文件不存在"
        sleep 2
        return 0
    fi
    ACTUAL_SIZE_MB=$(( $(stat -c %s /swapfile) / 1024 / 1024 ))
    if [ "$ACTUAL_SIZE_MB" -ne "$SWAP_SIZE_MB" ]; then
        echo -e "${RED}错误：dd创建swap文件大小不匹配！目标：${SWAP_SIZE_MB}MB，实际：${ACTUAL_SIZE_MB}MB${FONT}"
        log_error "dd创建swap文件大小不匹配：目标${SWAP_SIZE_MB}MB，实际${ACTUAL_SIZE_MB}MB"
        rm -f /swapfile
        sleep 2
        return 0
    fi
    echo -e "${GREEN}使用dd创建swap文件成功（大小：${SWAP_SIZE}GB）${FONT}"

    # 设置安全权限（仅root可读写，必须600）
    chmod 600 /swapfile
    if [ "$(stat -c %a /swapfile)" != "600" ]; then
        echo -e "${YELLOW}警告：swap文件权限异常，自动修复为600${FONT}"
        chmod 600 /swapfile
        log_info "修复swap文件权限为600"
    fi

    # 格式化swap文件
    echo -e "${GREEN}正在格式化swap文件...${FONT}"
    if ! mkswap /swapfile; then
        echo -e "${RED}错误：格式化swap文件失败！${FONT}"
        log_error "mkswap /swapfile执行失败"
        rm -f /swapfile
        sleep 2
        return 0
    fi

    # 启用swap文件（核心校验，避免Invalid argument）
    echo -e "${GREEN}正在启用swap文件...${FONT}"
    if ! swapon /swapfile; then
        echo -e "${RED}错误：启用swap文件失败！常见原因：文件系统不支持/磁盘空间不足${FONT}"
        log_error "swapon /swapfile执行失败（Invalid argument）"
        rm -f /swapfile
        sleep 2
        return 0
    fi

    # 写入fstab（确保开机自启，此时已清理过fstab，无重复）
    echo -e "${GREEN}配置开机自动挂载swap...${FONT}"
    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
    log_info "写入swapfile条目到fstab：/swapfile none swap defaults 0 0"
    
    # 验证fstab配置（避免开机挂载失败）
    echo -e "${GREEN}验证fstab配置是否正确...${FONT}"
    if ! mount -a >/dev/null 2>&1; then
        echo -e "${YELLOW}警告：fstab配置验证失败！已自动回滚${FONT}"
        log_error "fstab配置验证失败，回滚fstab备份"
        cp /etc/fstab.清理swap备份.$(date +%Y%m%d%H%M%S) /etc/fstab 2>/dev/null
        swapoff /swapfile
        rm -f /swapfile
        sleep 2
        return 0
    else
        echo -e "${GREEN}fstab配置验证通过${FONT}"
    fi
    
    # 展示创建结果（直观看到swap已启用）
    echo -e "\n${GREEN}================ Swap创建成功 ================${FONT}"
    free -h | grep -E "Mem|Swap|内存|交换"
    log_info "Swap创建成功，大小：${SWAP_SIZE}GB，文件路径：/swapfile"
    sleep 3  # 让用户看清成功提示
}

# 删除Swap（彻底清理文件+fstab，强制校验结果）
del_swap(){
    # 优先检查并强制删除物理文件
    if [ -f "/swapfile" ]; then
        echo -e "${GREEN}发现swapfile文件，正在强制关闭并删除...${FONT}"
        # 强制关闭所有swap（忽略错误）
        swapoff /swapfile 2>/dev/null
        swapoff -a 2>/dev/null
        # 强制删除文件，校验结果
        if rm -f /swapfile; then
            echo -e "${GREEN}已成功删除/swapfile文件${FONT}"
            log_info "成功删除物理文件/swapfile"
        else
            echo -e "${RED}错误：无法删除/swapfile文件！请手动执行 rm -rf /swapfile${FONT}"
            log_error "删除/swapfile文件失败"
            sleep 2
            return 0
        fi
    fi

    # 彻底清理fstab中所有/swapfile条目
    if grep -q "/swapfile" /etc/fstab; then
        echo -e "${GREEN}发现fstab中swapfile条目，彻底清理...${FONT}"
        clean_fstab_swap
        # 释放缓存（容错）
        sync && echo 3 > /proc/sys/vm/drop_caches || {
            echo -e "${YELLOW}警告：缓存释放失败（不影响swap删除）${FONT}"
            log_error "释放缓存失败，但已清理swapfile文件和fstab条目"
        }
        # 展示删除结果
        echo -e "\n${GREEN}================ Swap删除成功 ================${FONT}"
        free -h | grep -E "Mem|Swap|内存|交换"
        log_info "Swap删除成功：文件和fstab条目均已彻底清理"
        sleep 3
    else
        # 既无文件也无fstab条目
        if [ ! -f "/swapfile" ]; then
            echo -e "${RED}错误：未发现swapfile文件和fstab条目！无需删除。${FONT}"
            log_error "删除Swap失败：无物理文件且fstab无相关条目"
            sleep 2
        fi
    fi
}

# 查看Swap详细状态（排版整洁）
show_swap_status(){
    echo -e "\n${GREEN}=== Swap详细状态 ===${FONT}"
    swapon --show || echo "暂无启用的Swap"
    echo -e "\n${GREEN}=== 内存/Swap总览 ===${FONT}"
    free -h
    echo -e "\n${GREEN}=== fstab中Swap配置 ===${FONT}"
    grep -E "swap|交换" /etc/fstab || echo "fstab中无Swap相关配置"
    echo ""  # 末尾换行，排版更整洁
    log_info "用户查看Swap详细状态"
    sleep 3  # 让用户看完状态再返回
}

# ===================== 主菜单函数 =====================
main_menu(){
    check_root
    check_commands
    check_ovz
    clear
    # 显示当前系统状态
    get_mem_info
    echo -e "———————————————————————————————————————"
    echo -e "${GREEN}Linux VPS 一键Swap管理脚本${FONT}"
    echo -e "${GREEN}当前内存：${MEM_TOTAL_GB}GB | 当前Swap：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "———————————————————————————————————————"
    echo -e "${GREEN}1、添加Swap${FONT}"
    echo -e "${GREEN}2、删除Swap${FONT}"
    echo -e "${GREEN}3、查看Swap详细状态${FONT}"
    echo -e "${GREEN}4、退出${FONT}"
    echo -e "———————————————————————————————————————"
    # 菜单输入超时（60秒，回车/超时返回菜单，不退出）
    read -t 60 -p "请输入数字 [1-4]（60秒超时返回菜单）:" CHOICE
    if [ -z "$CHOICE" ]; then
        echo -e "\n${YELLOW}超时未输入，返回主菜单...${FONT}"
        log_info "用户超时未输入，返回主菜单"
        sleep 1
        main_menu  # 重新调用菜单，不退出
        return 0
    fi
    # 菜单逻辑
    case "$CHOICE" in
        1)
        add_swap
        ;;
        2)
        del_swap
        ;;
        3)
        show_swap_status
        ;;
        4)
        echo -e "${GREEN}脚本已退出${FONT}"
        log_info "用户主动选择退出脚本"
        exit 0  # 仅手动选4才退出
        ;;
        *)
        clear
        echo -e "${RED}错误：请输入有效的数字 [1-4]${FONT}"
        log_error "用户输入无效数字：${CHOICE}"
        sleep 2
        main_menu  # 输入错误返回菜单，不退出
        ;;
    esac
    # 操作完成后返回菜单（修复多余换行，回车默认返回）
    echo ""
    read -t 15 -p "是否返回主菜单？(Y/n，15秒后默认返回):" BACK_MENU
    BACK_MENU=${BACK_MENU:-Y}
    if [[ $BACK_MENU =~ ^[Yy]$ ]]; then
        main_menu
    else
        echo -e "${GREEN}脚本已退出${FONT}"
        log_info "用户选择不返回菜单，脚本退出"
        exit 0
    fi
}

# 启动脚本
main_menu
