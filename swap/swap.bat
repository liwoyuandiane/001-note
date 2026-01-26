#!/usr/bin/env bash
# Linux VPS 一键Swap管理脚本（最终精简优化版）
# 功能特性：btrfs适配 | 自定义路径 | 路径自动补全 | 空间检测 | 开机自启 | 权限校验
# 适用系统：Debian/Ubuntu/CentOS/RHEL/Armbian等主流Linux发行版

# 终端颜色定义（确保所有终端解析）
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m" 
FONT="\033[0m"

# 全局配置
LOG_FILE="/var/log/swap_manager.log"
SLEEP_TIME=2
BACKUP_PREFIX="fstab.swap.bak"

# 日志函数
log_info(){
    local msg="$1"
    printf "[%s] [INFO] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE"
}
log_error(){
    local msg="$1"
    printf "[%s] [ERROR] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE"
}

# 退出恢复终端颜色
trap 'echo -e "${FONT}"; exit 0' EXIT INT TERM

# ===================== 工具函数 =====================
escape_path(){
    local path="$1"
    echo "$path" | sed 's/[\/&*.^$]/\\&/g'
}
normalize_path(){
    local path="$1"
    echo "$path" | sed 's/\/\+/\//g'
}
check_dir_writable(){
    local dir="$1"
    [ ! -w "$dir" ] && {
        echo -e "${RED}错误：目录${dir}不可写！${FONT}"
        log_error "目录${dir}无写入权限"
        return 1
    }
    return 0
}

# ===================== 基础校验 =====================
check_root(){
    [[ $EUID -ne 0 ]] && {
        echo -e "${RED}错误：请以root权限运行脚本！${FONT}"
        log_error "非root权限执行脚本"
        exit 1
    }
}
check_commands(){
    local required_cmds=("free" "dd" "mkswap" "swapon" "swapoff" "grep" "sed" "bc" "stat" "df" "chattr" "truncate" "dirname")
    for cmd in "${required_cmds[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo -e "${RED}错误：缺少必要命令${cmd}！${FONT}"
            log_error "缺少命令${cmd}"
            exit 1
        }
    done
}
check_ovz(){
    [[ -d "/proc/vz" ]] && {
        echo -e "${RED}错误：OpenVZ架构不支持创建Swap！${FONT}"
        log_error "检测到OpenVZ架构"
        exit 1
    }
}
check_abs_path(){
    local path="$1"
    [[ ! "$path" =~ ^/ ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对路径！${FONT}"
        log_error "输入非绝对路径：${path}"
        return 1
    }
    [[ -d "$path" ]] && {
        echo -e "${RED}错误：${path}是目录！请输入文件路径${FONT}"
        log_error "输入目录作为swap路径：${path}"
        return 1
    }
    local dir=$(dirname "$path")
    [[ ! -d "$dir" ]] && {
        echo -e "${RED}错误：目录${dir}不存在！${FONT}"
        log_error "目录${dir}不存在"
        return 1
    }
    check_dir_writable "$dir" || return 1
    [[ -f "$path" ]] && {
        echo -e "${YELLOW}警告：文件${path}已存在，将覆盖！${FONT}"
        log_info "文件${path}已存在，准备覆盖"
    }
    return 0
}

# ===================== 路径补全（核心修复根目录+颜色码） =====================
auto_complete_swap_path(){
    echo -e "\n${YELLOW}=== 路径自动补全 - 输入Swap存放目录 ===${FONT}"
    read -p "请输入Swap存放的绝对目录（以/开头）:" INPUT_DIR

    # 校验绝对目录格式
    [[ ! "$INPUT_DIR" =~ ^/ ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对目录！${FONT}"
        log_error "输入非绝对目录：${INPUT_DIR}"
        sleep "$SLEEP_TIME"
        return 1
    }

    # 标准化路径（关键：根目录/处理后仍为/）
    INPUT_DIR=$(normalize_path "$INPUT_DIR")
    # 校验目录存在
    [[ ! -d "$INPUT_DIR" ]] && {
        echo -e "${RED}错误：目录${INPUT_DIR}不存在！${FONT}"
        log_error "目录${INPUT_DIR}不存在"
        sleep "$SLEEP_TIME"
        return 1
    }
    # 校验目录可写
    check_dir_writable "$INPUT_DIR" || {
        sleep "$SLEEP_TIME"
        return 1
    }

    # 强制生成路径（核心：根目录/拼接后为/swapfile，必显示，无跳过）
    local SWAP_PATH="${INPUT_DIR}/swapfile"
    # 强制显示路径，颜色区分，适配所有目录（包括/）
    echo -e "\n${YELLOW}即将生成的Swap文件绝对路径：${FONT}${GREEN}${SWAP_PATH}${FONT}"
    
    # 修复颜色码乱码：拆分read和颜色提示，用echo -e解析转义
    echo -e -n "${YELLOW}输入y/Y确认，其他键返回主菜单：${FONT}"
    read CONFIRM

    # 确认逻辑
    [[ "$CONFIRM" =~ ^[yY]$ ]] || {
        echo -e "\n${YELLOW}取消操作，返回主菜单...${FONT}"
        log_info "用户取消路径确认"
        sleep 1
        return 1
    }

    echo -e "\n${GREEN}已确认路径：${SWAP_PATH}${FONT}"
    log_info "用户确认Swap路径：${SWAP_PATH}"
    echo "$SWAP_PATH"
    return 0
}

# ===================== 系统信息 =====================
get_mem_info(){
    MEM_TOTAL_BYTES=$(free -b | awk '/^Mem:/ || /^内存：/ {print $2}')
    MEM_TOTAL_GB=$(echo "scale=0; ($MEM_TOTAL_BYTES + 536870912) / 1073741824" | bc)
    RECOMMENDED_SWAP=$((MEM_TOTAL_GB * 2))
    [ $RECOMMENDED_SWAP -gt 8 ] && RECOMMENDED_SWAP=8
    [ $RECOMMENDED_SWAP -eq 0 ] && RECOMMENDED_SWAP=2

    SWAP_TOTAL_BYTES=$(free -b | awk '/^Swap:/ || /^交换：/ {print $2}')
    SWAP_TOTAL_GB=$(echo "scale=0; ($SWAP_TOTAL_BYTES + 536870912) / 1073741824" | bc)
}
get_fs_type(){
    local target_path="$1"
    FS_TYPE=$(df -T "$target_path" | awk 'NR>1 && $1 !~ /tmpfs/ {print $2; exit}')
    echo -e "${YELLOW}检测到文件系统：${FS_TYPE}${FONT}"
    log_info "目标路径文件系统：${FS_TYPE}"
}
clean_fstab_swap_custom(){
    local swap_path="$1"
    local ESCAPED_PATH=$(escape_path "$swap_path")
    local BACKUP_FILENAME="${BACKUP_PREFIX}.$(date +%Y%m%d%H%M%S)"
    cp /etc/fstab "/etc/${BACKUP_FILENAME}"
    sed -i "/${ESCAPED_PATH}/d" /etc/fstab
    echo -e "${GREEN}已清理fstab配置（备份：/etc/${BACKUP_FILENAME}）${FONT}"
    log_info "清理fstab中${swap_path}，备份：${BACKUP_FILENAME}"
}

# ===================== 核心功能 =====================
add_swap(){
    add_swap_core "/swapfile"
}
add_swap_advanced(){
    echo -e "\n${YELLOW}=== 高级模式 - 自定义路径添加Swap ===${FONT}"
    SWAP_PATH=$(auto_complete_swap_path)
    [[ -z "$SWAP_PATH" ]] && return 0
    add_swap_core "$SWAP_PATH"
}
add_swap_core(){
    local SWAP_PATH="$1"
    get_mem_info
    get_fs_type "$(dirname "$SWAP_PATH")"
    echo -e "\n${GREEN}=== 当前系统信息 ===${FONT}"
    echo -e "${GREEN}物理内存：${MEM_TOTAL_GB}GB | 当前Swap：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "${YELLOW}推荐Swap：${RECOMMENDED_SWAP}GB（内存2倍，最大8GB）${FONT}"
    
    read -t 30 -p "请输入Swap大小（GB，回车使用推荐值）:" SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

    [[ ! "$SWAP_SIZE" =~ ^[1-9][0-9]*$ ]] && {
        echo -e "${RED}错误：请输入有效正整数！${FONT}"
        log_error "无效Swap大小：${SWAP_SIZE}"
        sleep "$SLEEP_TIME"
        return 0
    }

    if [ "$SWAP_SIZE" -gt 8 ]; then
        echo -e "${YELLOW}警告：超过8GB推荐值，是否继续？(y/N)${FONT}"
        read -r CONFIRM_BIG
        [[ ! $CONFIRM_BIG =~ ^[Yy]$ ]] && SWAP_SIZE=8
        echo -e "${GREEN}最终Swap大小：${SWAP_SIZE}GB${FONT}"
    fi

    SWAP_SIZE_MB=$((SWAP_SIZE * 1024))
    BLOCK_SIZE=100
    BLOCK_COUNT=$((SWAP_SIZE_MB / BLOCK_SIZE))
    [ $((SWAP_SIZE_MB % BLOCK_SIZE)) -ne 0 ] && BLOCK_COUNT=$((BLOCK_COUNT + 1))

    local target_dir=$(dirname "$SWAP_PATH")
    AVAIL_SPACE_MB=$(df -BM "$target_dir" | awk 'NR>1 {print $4; gsub("M",""); print}')
    SAFE_SPACE_MB=$((AVAIL_SPACE_MB - 200))
    [ "$SAFE_SPACE_MB" -lt "$SWAP_SIZE_MB" ] && {
        echo -e "${RED}错误：${target_dir}空间不足！可用${AVAIL_SPACE_MB}MB，需要${SWAP_SIZE_MB}MB${FONT}"
        log_error "目标目录空间不足"
        sleep "$SLEEP_TIME"
        return 0
    }

    clean_fstab_swap_custom "$SWAP_PATH"

    echo -e "${GREEN}正在创建Swap文件...${FONT}"
    if [ "$FS_TYPE" = "btrfs" ]; then
        echo -e "${YELLOW}Btrfs适配：禁用COW属性...${FONT}"
        truncate -s 0 "$SWAP_PATH"
        chattr +C "$SWAP_PATH"
        log_info "Btrfs禁用COW：${SWAP_PATH}"
    fi

    echo -e "${YELLOW}分块创建${SWAP_SIZE}GB（每块${BLOCK_SIZE}M，共${BLOCK_COUNT}块）...${FONT}"
    dd if=/dev/zero of="$SWAP_PATH" bs=${BLOCK_SIZE}M count=${BLOCK_COUNT} status=progress

    [[ ! -f "$SWAP_PATH" ]] && {
        echo -e "${RED}错误：文件创建失败！${FONT}"
        log_error "Swap文件未生成：${SWAP_PATH}"
        sleep "$SLEEP_TIME"
        return 0
    }

    ACTUAL_SIZE_MB=$(( $(stat -c %s "$SWAP_PATH") / 1024 / 1024 ))
    MIN_ALLOWED=$((SWAP_SIZE_MB - 200))
    MAX_ALLOWED=$((SWAP_SIZE_MB + 200))
    if [ "$ACTUAL_SIZE_MB" -lt "$MIN_ALLOWED" ] || [ "$ACTUAL_SIZE_MB" -gt "$MAX_ALLOWED" ]; then
        echo -e "${RED}错误：文件大小偏差过大！目标${SWAP_SIZE_MB}MB，实际${ACTUAL_SIZE_MB}MB${FONT}"
        log_error "Swap大小不匹配"
        rm -f "$SWAP_PATH"
        sleep "$SLEEP_TIME"
        return 0
    fi
    [ "$ACTUAL_SIZE_MB" -ne "$SWAP_SIZE_MB" ] && echo -e "${YELLOW}提示：大小偏差为文件系统块对齐，不影响使用${FONT}"

    chmod 600 "$SWAP_PATH"
    [ "$(stat -c %a "$SWAP_PATH")" != "600" ] && {
        echo -e "${YELLOW}警告：权限异常，自动修复为600${FONT}"
        chmod 600 "$SWAP_PATH"
    }

    echo -e "${GREEN}格式化Swap文件...${FONT}"
    if ! mkswap "$SWAP_PATH"; then
        echo -e "${RED}错误：格式化失败！${FONT}"
        log_error "mkswap失败：${SWAP_PATH}"
        rm -f "$SWAP_PATH"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "${GREEN}启用Swap文件...${FONT}"
    if ! swapon "$SWAP_PATH"; then
        echo -e "${RED}错误：启用失败！${FONT}"
        log_error "swapon失败：${SWAP_PATH}"
        [ "$FS_TYPE" = "btrfs" ] && echo -e "${YELLOW}提示：执行 chattr +C ${SWAP_PATH} 重试${FONT}"
        echo -e "${YELLOW}文件已保留，请手动排查问题${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "${GREEN}配置开机自启...${FONT}"
    echo "${SWAP_PATH} none swap defaults 0 0" >> /etc/fstab
    if ! mount -a >/dev/null 2>&1; then
        echo -e "${YELLOW}警告：fstab验证失败，自动回滚！${FONT}"
        log_error "fstab验证失败"
        cp "/etc/${BACKUP_FILENAME}" /etc/fstab 2>/dev/null
        swapoff "$SWAP_PATH"
        rm -f "$SWAP_PATH"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "\n${GREEN}================ Swap创建成功 ================${FONT}"
    free -h | grep -E "Mem|Swap|内存|交换"
    log_info "Swap创建成功：${SWAP_PATH} ${SWAP_SIZE}GB"
    sleep $((SLEEP_TIME + 1))
}
del_swap(){
    echo -e "\n${YELLOW}=== 删除Swap（支持自定义路径） ===${FONT}"
    read -p "请输入Swap文件绝对路径（默认 /swapfile）:" SWAP_PATH
    SWAP_PATH=${SWAP_PATH:-/swapfile}

    check_abs_path "$SWAP_PATH" || {
        sleep "$SLEEP_TIME"
        return 0
    }

    if [ -f "$SWAP_PATH" ]; then
        echo -e "${GREEN}关闭并删除${SWAP_PATH}...${FONT}"
        swapoff "$SWAP_PATH" 2>/dev/null
        swapoff -a 2>/dev/null
        if rm -f "$SWAP_PATH"; then
            echo -e "${GREEN}文件删除成功${FONT}"
            log_info "删除Swap文件：${SWAP_PATH}"
        else
            echo -e "${RED}错误：删除失败！手动执行 rm -rf ${SWAP_PATH}${FONT}"
            log_error "删除Swap失败：${SWAP_PATH}"
            sleep "$SLEEP_TIME"
            return 0
        fi
    else
        echo -e "${YELLOW}未找到Swap文件${SWAP_PATH}${FONT}"
    fi

    if grep -q "$(escape_path "$SWAP_PATH")" /etc/fstab; then
        echo -e "${GREEN}清理fstab中${SWAP_PATH}配置...${FONT}"
        clean_fstab_swap_custom "$SWAP_PATH"
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo -e "${YELLOW}警告：缓存释放失败${FONT}"
        echo -e "\n${GREEN}================ Swap删除成功 ================${FONT}"
        free -h | grep -E "Mem|Swap|内存|交换"
        log_info "Swap删除成功：${SWAP_PATH}"
        sleep $((SLEEP_TIME + 1))
    else
        echo -e "${YELLOW}fstab中无${SWAP_PATH}配置${FONT}"
        sleep "$SLEEP_TIME"
    fi
}
show_swap_status(){
    echo -e "\n${GREEN}=== Swap详细状态 ===${FONT}"
    swapon --show || echo "暂无启用的Swap"
    echo -e "\n${GREEN}=== 内存/Swap总览 ===${FONT}"
    free -h
    echo -e "\n${GREEN}=== fstab中Swap配置 ===${FONT}"
    grep -E "swap|交换" /etc/fstab || echo "fstab中无Swap配置"
    echo -e "\n${GREEN}=== 根目录文件系统信息 ===${FONT}"
    df -T / | grep /
    echo ""
    log_info "用户查看Swap状态"
    sleep $((SLEEP_TIME + 1))
}

# ===================== 主菜单 =====================
main_menu(){
    check_root
    check_commands
    check_ovz
    clear
    get_mem_info
    echo -e "———————————————————————————————————————"
    echo -e "${GREEN}Linux VPS 一键Swap管理脚本${FONT}"
    echo -e "${GREEN}当前内存：${MEM_TOTAL_GB}GB | 当前Swap：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "———————————————————————————————————————"
    echo -e "${GREEN}1、添加Swap（默认 /swapfile）${FONT}"
    echo -e "${GREEN}2、删除Swap（支持自定义路径）${FONT}"
    echo -e "${GREEN}3、查看Swap状态${FONT}"
    echo -e "${GREEN}4、高级模式 - 自定义路径添加${FONT}"
    echo -e "${GREEN}0、退出${FONT}"
    echo -e "———————————————————————————————————————"
    read -t 60 -p "请输入数字 [0-4]（60秒超时返回菜单）:" CHOICE

    if [ -z "$CHOICE" ]; then
        echo -e "\n${YELLOW}超时未输入，返回主菜单...${FONT}"
        log_info "用户超时未输入"
        sleep 1
        main_menu
        return 0
    fi

    [[ ! "$CHOICE" =~ ^[0-4]$ ]] && {
        clear
        echo -e "${RED}错误：请输入0-4之间的有效数字！${FONT}"
        log_error "无效输入：${CHOICE}"
        sleep "$SLEEP_TIME"
        main_menu
        return 0
    }

    case "$CHOICE" in
        1) add_swap ;;
        2) del_swap ;;
        3) show_swap_status ;;
        4) add_swap_advanced ;;
        0) echo -e "${GREEN}脚本已退出${FONT}"; log_info "用户主动退出"; exit 0 ;;
    esac

    echo ""
    read -t 15 -p "是否返回主菜单？(Y/n，15秒默认返回):" BACK_MENU
    BACK_MENU=${BACK_MENU:-Y}
    [[ "$BACK_MENU" =~ ^[Yy]$ ]] && main_menu || {
        echo -e "${GREEN}脚本已退出${FONT}"
        log_info "用户选择不返回主菜单"
        exit 0
    }
}

# 初始化日志
touch "$LOG_FILE"
# 启动脚本
main_menu
