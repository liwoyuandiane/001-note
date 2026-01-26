#!/usr/bin/env bash
# Linux VPS 一键Swap管理脚本（最终精简优化版） v1.0
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
# 检查Swap是否已激活
check_swap_active(){
    local path="$1"
    swapon --show | grep -q "$path" && {
        echo -e "${YELLOW}警告：${path}已是活动的Swap${FONT}"
        return 1
    }
    return 0
}
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
    local input_dir swap_path confirm

    echo -e "\n${YELLOW}=== 路径自动补全 - 输入Swap存放目录 ===${FONT}"
    read -p "请输入Swap存放的绝对目录（以/开头）:" input_dir

    # 校验绝对目录格式（使用更高效的方式）
    [[ "${input_dir:0:1}" != "/" ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对目录！${FONT}"
        log_error "输入非绝对目录：${input_dir}"
        sleep "$SLEEP_TIME"
        return 1
    }

    # 标准化路径（关键：根目录/处理后仍为/）
    input_dir=$(normalize_path "$input_dir")
    # 校验目录存在
    [[ ! -d "$input_dir" ]] && {
        echo -e "${RED}错误：目录${input_dir}不存在！${FONT}"
        log_error "目录${input_dir}不存在"
        sleep "$SLEEP_TIME"
        return 1
    }
    # 校验目录可写
    check_dir_writable "$input_dir" || {
        sleep "$SLEEP_TIME"
        return 1
    }

    # 强制生成路径（核心：根目录/拼接后为/swapfile，必显示，无跳过）
    swap_path="${input_dir}/swapfile"
    # 强制显示路径，颜色区分，适配所有目录（包括/）
    echo -e "\n${YELLOW}即将生成的Swap文件绝对路径：${FONT}${GREEN}${swap_path}${FONT}"

    # 修复颜色码乱码：拆分read和颜色提示，用echo -e解析转义
    echo -e -n "${YELLOW}输入y/Y确认，其他键返回主菜单：${FONT}"
    read confirm

    # 确认逻辑
    [[ "$confirm" =~ ^[yY]$ ]] || {
        echo -e "\n${YELLOW}取消操作，返回主菜单...${FONT}"
        log_info "用户取消路径确认"
        sleep 1
        return 1
    }

    echo -e "\n${GREEN}已确认路径：${swap_path}${FONT}"
    log_info "用户确认Swap路径：${swap_path}"
    echo "$swap_path"
    return 0
}

# ===================== 系统信息 =====================
get_mem_info(){
    local mem_total_bytes swap_total_bytes

    # 使用更兼容的方式获取内存信息
    if free -b >/dev/null 2>&1; then
        mem_total_bytes=$(free -b | awk '/^Mem:/ || /^内存：/ {print $2}')
        swap_total_bytes=$(free -b | awk '/^Swap:/ || /^交换：/ {print $2}')
    else
        mem_total_bytes=$(free | awk '/^Mem:/ || /^内存：/ {print $2*1024}')
        swap_total_bytes=$(free | awk '/^Swap:/ || /^交换：/ {print $2*1024}')
    fi

    MEM_TOTAL_GB=$(echo "scale=0; ($mem_total_bytes + 536870912) / 1073741824" | bc)
    RECOMMENDED_SWAP=$((MEM_TOTAL_GB * 2))
    [ $RECOMMENDED_SWAP -gt 8 ] && RECOMMENDED_SWAP=8
    [ $RECOMMENDED_SWAP -eq 0 ] && RECOMMENDED_SWAP=2

    SWAP_TOTAL_GB=$(echo "scale=0; ($swap_total_bytes + 536870912) / 1073741824" | bc)
}
get_fs_type(){
    local target_path="$1"
    FS_TYPE=$(df -T "$target_path" 2>/dev/null | awk 'NR>1 && $1 !~ /tmpfs/ {print $2; exit}')
    [[ -z "$FS_TYPE" ]] && FS_TYPE="unknown"
    echo -e "${YELLOW}检测到文件系统：${FS_TYPE}${FONT}"
    log_info "目标路径文件系统：${FS_TYPE}"
}
clean_fstab_swap_custom(){
    local swap_path="$1"
    local escaped_path backup_file

    escaped_path=$(escape_path "$swap_path")
    backup_file="${BACKUP_PREFIX}.$(date +%Y%m%d%H%M%S)"

    if ! cp /etc/fstab "/etc/${backup_file}"; then
        echo -e "${RED}错误：无法备份fstab！${FONT}"
        log_error "备份fstab失败"
        echo ""
        return 1
    fi

    if ! sed -i "/${escaped_path}/d" /etc/fstab; then
        echo -e "${YELLOW}警告：清理fstab配置失败，已保留备份${FONT}"
        log_error "清理fstab失败"
    fi

    echo -e "${GREEN}已清理fstab配置（备份：/etc/${backup_file}）${FONT}"
    log_info "清理fstab中${swap_path}，备份：${backup_file}"
    echo "$backup_file"
    return 0
}

# ===================== 核心功能 =====================
add_swap(){
    add_swap_core "/swapfile"
}
add_swap_advanced(){
    local swap_path
    echo -e "\n${YELLOW}=== 高级模式 - 自定义路径添加Swap ===${FONT}"
    swap_path=$(auto_complete_swap_path)
    [[ -z "$swap_path" ]] && return 0
    add_swap_core "$swap_path"
}
add_swap_core(){
    local swap_path="$1"
    local swap_size swap_size_mb block_size block_count
    local target_dir avail_space_mb safe_space_mb
    local actual_size_mb min_allowed max_allowed
    local confirm_big backup_file

    # 检查Swap是否已激活
    check_swap_active "$swap_path" || {
        echo -e "${YELLOW}警告：${swap_path}已是活动的Swap，如需重建请先删除${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    }

    get_mem_info
    get_fs_type "$(dirname "$swap_path")"
    echo -e "\n${GREEN}=== 当前系统信息 ===${FONT}"
    echo -e "${GREEN}物理内存：${MEM_TOTAL_GB}GB | 当前Swap：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "${YELLOW}推荐Swap：${RECOMMENDED_SWAP}GB（内存2倍，最大8GB）${FONT}"

    read -p "请输入Swap大小（GB，回车使用推荐值）:" swap_size
    swap_size=${swap_size:-$RECOMMENDED_SWAP}

    [[ ! "$swap_size" =~ ^[1-9][0-9]*$ ]] && {
        echo -e "${RED}错误：请输入有效正整数！${FONT}"
        log_error "无效Swap大小：${swap_size}"
        sleep "$SLEEP_TIME"
        return 0
    }

    if [ "$swap_size" -gt 8 ]; then
        echo -e "${YELLOW}警告：超过8GB推荐值，是否继续？(y/N)${FONT}"
        read -r confirm_big
        [[ ! $confirm_big =~ ^[Yy]$ ]] && swap_size=8
        echo -e "${GREEN}最终Swap大小：${swap_size}GB${FONT}"
    fi

    swap_size_mb=$((swap_size * 1024))
    block_size=100
    block_count=$((swap_size_mb / block_size))
    [ $((swap_size_mb % block_size)) -ne 0 ] && block_count=$((block_count + 1))

    target_dir=$(dirname "$swap_path")
    avail_space_mb=$(df -BM "$target_dir" | awk 'NR>1 {print $4; gsub("M",""); print}')
    safe_space_mb=$((avail_space_mb - 200))
    [ "$safe_space_mb" -lt "$swap_size_mb" ] && {
        echo -e "${RED}错误：${target_dir}空间不足！可用${avail_space_mb}MB，需要${swap_size_mb}MB${FONT}"
        log_error "目标目录空间不足"
        sleep "$SLEEP_TIME"
        return 0
    }

    # 备份fstab并获取备份文件名
    backup_file=$(clean_fstab_swap_custom "$swap_path")
    [[ -z "$backup_file" ]] && {
        echo -e "${RED}错误：无法备份fstab！${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    }

    echo -e "${GREEN}正在创建Swap文件...${FONT}"
    if [ "$FS_TYPE" = "btrfs" ]; then
        echo -e "${YELLOW}Btrfs适配：禁用COW属性...${FONT}"
        truncate -s 0 "$swap_path"
        if ! chattr +C "$swap_path" 2>/dev/null; then
            echo -e "${YELLOW}警告：无法设置无COW属性，继续尝试...${FONT}"
        fi
        log_info "Btrfs禁用COW：${swap_path}"
    fi

    echo -e "${YELLOW}分块创建${swap_size}GB（每块${block_size}M，共${block_count}块）...${FONT}"
    if ! dd if=/dev/zero of="$swap_path" bs=${block_size}M count=${block_count} status=progress; then
        echo -e "${RED}错误：dd命令执行失败！${FONT}"
        log_error "dd命令失败：${swap_path}"
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi

    [[ ! -f "$swap_path" ]] && {
        echo -e "${RED}错误：文件创建失败！${FONT}"
        log_error "Swap文件未生成：${swap_path}"
        sleep "$SLEEP_TIME"
        return 0
    }

    # 使用更兼容的文件大小获取方式
    if command -v stat >/dev/null 2>&1; then
        actual_size_mb=$(( $(stat -c %s "$swap_path" 2>/dev/null || stat -f %z "$swap_path" 2>/dev/null) / 1024 / 1024 ))
    else
        actual_size_mb=$(ls -l "$swap_path" | awk '{print $5/1024/1024}')
    fi

    min_allowed=$((swap_size_mb - 200))
    max_allowed=$((swap_size_mb + 200))
    if [ "$actual_size_mb" -lt "$min_allowed" ] || [ "$actual_size_mb" -gt "$max_allowed" ]; then
        echo -e "${RED}错误：文件大小偏差过大！目标${swap_size_mb}MB，实际${actual_size_mb}MB${FONT}"
        log_error "Swap大小不匹配"
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi
    [ "$actual_size_mb" -ne "$swap_size_mb" ] && echo -e "${YELLOW}提示：大小偏差为文件系统块对齐，不影响使用${FONT}"

    # 设置文件权限并验证
    if ! chmod 600 "$swap_path"; then
        echo -e "${RED}错误：无法设置文件权限！${FONT}"
        log_error "chmod失败：${swap_path}"
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "${GREEN}格式化Swap文件...${FONT}"
    if ! mkswap "$swap_path"; then
        echo -e "${RED}错误：格式化失败！${FONT}"
        log_error "mkswap失败：${swap_path}"
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "${GREEN}启用Swap文件...${FONT}"
    if ! swapon "$swap_path"; then
        echo -e "${RED}错误：启用失败！${FONT}"
        log_error "swapon失败：${swap_path}"
        [ "$FS_TYPE" = "btrfs" ] && echo -e "${YELLOW}提示：执行 chattr +C ${swap_path} 重试${FONT}"
        echo -e "${YELLOW}文件已保留，请手动排查问题${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "${GREEN}配置开机自启...${FONT}"
    echo "${swap_path} none swap defaults 0 0" >> /etc/fstab
    if ! mount -a >/dev/null 2>&1; then
        echo -e "${YELLOW}警告：fstab验证失败，自动回滚！${FONT}"
        log_error "fstab验证失败"
        cp "/etc/${backup_file}" /etc/fstab 2>/dev/null
        swapoff "$swap_path" 2>/dev/null
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi

    echo -e "\n${GREEN}================ Swap创建成功 ================${FONT}"
    free -h | grep -E "Mem|Swap|内存|交换"
    log_info "Swap创建成功：${swap_path} ${swap_size}GB"
    sleep $((SLEEP_TIME + 1))
}
del_swap(){
    local swap_path

    echo -e "\n${YELLOW}=== 删除Swap（支持自定义路径） ===${FONT}"
    read -p "请输入Swap文件绝对路径（默认 /swapfile）:" swap_path
    swap_path=${swap_path:-/swapfile}

    check_abs_path "$swap_path" || {
        sleep "$SLEEP_TIME"
        return 0
    }

    if [ -f "$swap_path" ]; then
        echo -e "${GREEN}关闭并删除${swap_path}...${FONT}"
        swapoff "$swap_path" 2>/dev/null
        swapoff -a 2>/dev/null
        if rm -f "$swap_path"; then
            echo -e "${GREEN}文件删除成功${FONT}"
            log_info "删除Swap文件：${swap_path}"
        else
            echo -e "${RED}错误：删除失败！手动执行 rm -rf ${swap_path}${FONT}"
            log_error "删除Swap失败：${swap_path}"
            sleep "$SLEEP_TIME"
            return 0
        fi
    else
        echo -e "${YELLOW}未找到Swap文件${swap_path}${FONT}"
    fi

    if grep -q "$(escape_path "$swap_path")" /etc/fstab; then
        echo -e "${GREEN}清理fstab中${swap_path}配置...${FONT}"
        clean_fstab_swap_custom "$swap_path" >/dev/null
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo -e "${YELLOW}警告：缓存释放失败${FONT}"
        echo -e "\n${GREEN}================ Swap删除成功 ================${FONT}"
        free -h | grep -E "Mem|Swap|内存|交换"
        log_info "Swap删除成功：${swap_path}"
        sleep $((SLEEP_TIME + 1))
    else
        echo -e "${YELLOW}fstab中无${swap_path}配置${FONT}"
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
    local choice back_menu

    check_root
    check_commands
    check_ovz

    # 使用循环代替递归，避免递归深度过大
    while true; do
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
        read -t 60 -p "请输入数字 [0-4]（60秒超时返回菜单）:" choice

        if [ -z "$choice" ]; then
            echo -e "\n${YELLOW}超时未输入，返回主菜单...${FONT}"
            log_info "用户超时未输入"
            sleep 1
            continue
        fi

        [[ ! "$choice" =~ ^[0-4]$ ]] && {
            echo -e "\n${RED}错误：请输入0-4之间的有效数字！${FONT}"
            log_error "无效输入：${choice}"
            sleep "$SLEEP_TIME"
            continue
        }

        case "$choice" in
            1) add_swap ;;
            2) del_swap ;;
            3) show_swap_status ;;
            4) add_swap_advanced ;;
            0) echo -e "${GREEN}脚本已退出${FONT}"; log_info "用户主动退出"; exit 0 ;;
        esac

        echo ""
        read -t 15 -p "是否返回主菜单？(Y/n，15秒默认返回):" back_menu
        back_menu=${back_menu:-Y}
        [[ "$back_menu" =~ ^[Yy]$ ]] || {
            echo -e "${GREEN}脚本已退出${FONT}"
            log_info "用户选择不返回主菜单"
            exit 0
        }
    done
}

# 初始化日志（设置安全权限）
touch "$LOG_FILE" 2>/dev/null && chmod 600 "$LOG_FILE" 2>/dev/null || {
    echo -e "${YELLOW}警告：无法创建/设置日志文件权限，继续执行...${FONT}"
}

# 启动脚本
main_menu
