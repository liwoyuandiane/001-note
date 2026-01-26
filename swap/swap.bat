#!/usr/bin/env bash
# Linux VPS 一键Swap管理脚本（最终精简优化版）
# 功能特性：btrfs文件系统适配 | 路径自动补全与确认 | 自定义Swap路径 | 特殊字符兼容 | 权限校验 | 开机自启配置
# 适用系统：Debian/Ubuntu/CentOS/RHEL等主流Linux发行版

# 终端颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m" 
FONT="\033[0m"

# 全局配置参数 - 集中管理便于维护
LOG_FILE="/var/log/swap_manager.log"  # 日志文件路径
SLEEP_TIME=2                          # 统一提示延时时间（秒）
BACKUP_PREFIX="fstab.swap.bak"        # fstab备份文件前缀

# 日志输出函数 - 标准化日志格式
# $1: 日志消息内容
log_info(){
    local msg="$1"
    printf "[%s] [INFO] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE"
}

# 错误日志输出函数
# $1: 错误消息内容
log_error(){
    local msg="$1"
    printf "[%s] [ERROR] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE"
}

# 退出信号捕获 - 恢复终端默认颜色，避免残留彩色输出
trap 'echo -e "${FONT}"; exit 0' EXIT INT TERM

# ===================== 工具函数区 =====================
# 路径特殊字符转义函数 - 适配sed命令的正则匹配
# $1: 需要转义的原始路径
# 返回值: 转义后的路径字符串
escape_path(){
    local path="$1"
    echo "$path" | sed 's/[\/&*.^$]/\\&/g'
}

# 路径标准化函数 - 合并路径中连续的斜杠，生成规范路径
# $1: 原始路径
# 返回值: 标准化后的路径字符串
normalize_path(){
    local path="$1"
    echo "$path" | sed 's/\/\+/\//g'
}

# 目录可写性校验函数
# $1: 需要校验的目录路径
# 返回值: 0=可写 1=不可写
check_dir_writable(){
    local dir="$1"
    [ ! -w "$dir" ] && {
        echo -e "${RED}错误：目录${dir}不可写！${FONT}"
        log_error "目录${dir}无写入权限"
        return 1
    }
    return 0
}

# ===================== 基础校验函数区 =====================
# 管理员权限校验函数 - 脚本必须以root权限运行
check_root(){
    [[ $EUID -ne 0 ]] && {
        echo -e "${RED}错误：请以root权限运行脚本！${FONT}"
        log_error "非root权限执行脚本，退出"
        exit 1
    }
}

# 必要命令依赖校验函数 - 检查脚本运行所需的基础命令
check_commands(){
    local required_cmds=("free" "dd" "mkswap" "swapon" "swapoff" "grep" "sed" "bc" "stat" "df" "chattr" "truncate" "dirname")
    for cmd in "${required_cmds[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo -e "${RED}错误：缺少必要命令${cmd}！请先安装。${FONT}"
            log_error "缺少命令${cmd}，脚本无法运行"
            exit 1
        }
    done
}

# OpenVZ架构检测函数 - OpenVZ虚拟化不支持Swap功能
check_ovz(){
    [[ -d "/proc/vz" ]] && {
        echo -e "${RED}错误：OpenVZ架构不支持创建Swap！${FONT}"
        log_error "检测到OpenVZ架构，不支持Swap，退出"
        exit 1
    }
}

# Swap文件绝对路径有效性校验函数
# $1: 待校验的Swap文件路径
# 返回值: 0=有效 1=无效
check_abs_path(){
    local path="$1"
    # 校验是否为绝对路径（以/开头）
    [[ ! "$path" =~ ^/ ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对路径！${FONT}"
        log_error "输入路径${path}非绝对路径，校验失败"
        return 1
    }
    # 禁止输入目录作为文件路径
    [[ -d "$path" ]] && {
        echo -e "${RED}错误：${path}是目录！请输入文件路径。${FONT}"
        log_error "输入路径${path}为目录，非文件路径"
        return 1
    }
    local dir=$(dirname "$path")
    # 校验路径所在目录是否存在
    [[ ! -d "$dir" ]] && {
        echo -e "${RED}错误：路径所在目录${dir}不存在！${FONT}"
        log_error "目录${dir}不存在，路径校验失败"
        return 1
    }
    # 校验目录可写性
    check_dir_writable "$dir" || return 1
    # 文件已存在时给出覆盖提示
    [[ -f "$path" ]] && {
        echo -e "${YELLOW}警告：文件${path}已存在，执行操作将覆盖该文件！${FONT}"
        log_info "文件${path}已存在，准备覆盖"
    }
    return 0
}

# ===================== 交互功能函数区 =====================
# 路径自动补全函数 - 输入目录自动生成Swap文件路径，并要求用户确认
# 返回值: 确认后的Swap文件绝对路径（空值表示取消操作）
auto_complete_swap_path(){
    echo -e "\n${YELLOW}=== 路径自动补全 - 输入Swap存放目录 ===${FONT}"
    echo -e "${YELLOW}提示：输入绝对目录后，自动生成文件路径为 [目录]/swapfile${FONT}"
    read -p "请输入Swap存放的绝对目录（以/开头）:" INPUT_DIR

    # 校验绝对目录格式
    [[ ! "$INPUT_DIR" =~ ^/ ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对目录！${FONT}"
        log_error "输入目录${INPUT_DIR}非绝对路径"
        sleep "$SLEEP_TIME"
        return 1
    }

    # 标准化目录路径，合并连续斜杠
    INPUT_DIR=$(normalize_path "$INPUT_DIR")
    # 校验目录是否存在
    [[ ! -d "$INPUT_DIR" ]] && {
        echo -e "${RED}错误：目录${INPUT_DIR}不存在！${FONT}"
        log_error "目录${INPUT_DIR}不存在"
        sleep "$SLEEP_TIME"
        return 1
    }

    # 校验目录可写性
    check_dir_writable "$INPUT_DIR" || {
        sleep "$SLEEP_TIME"
        return 1
    }

    # 生成最终Swap文件路径
    local SWAP_PATH="${INPUT_DIR}/swapfile"
    # ========== 核心修改点：调整提示文本为你要求的样式 ==========
    echo -e "\n即将生成文件为：${GREEN}${SWAP_PATH}${FONT}"
    read -p "输入y/Y确认，其他键返回主菜单:" CONFIRM

    # 用户确认逻辑
    [[ "$CONFIRM" =~ ^[yY]$ ]] || {
        echo -e "${YELLOW}取消操作，返回主菜单...${FONT}"
        log_info "用户取消路径确认"
        sleep 1
        return 1
    }

    echo -e "${GREEN}确认路径：${SWAP_PATH}${FONT}"
    log_info "用户确认Swap文件路径：${SWAP_PATH}"
    echo "$SWAP_PATH"
    return 0
}

# ===================== 系统信息函数区 =====================
# 系统内存与Swap信息获取函数 - 兼容中英文free命令输出格式
get_mem_info(){
    # 获取物理内存总大小（字节）
    MEM_TOTAL_BYTES=$(free -b | awk '/^Mem:/ || /^内存：/ {print $2}')
    # 转换为GB（四舍五入）
    MEM_TOTAL_GB=$(echo "scale=0; ($MEM_TOTAL_BYTES + 536870912) / 1073741824" | bc)
    # 计算推荐Swap大小：内存的2倍，最大不超过8GB
    RECOMMENDED_SWAP=$((MEM_TOTAL_GB * 2))
    [ $RECOMMENDED_SWAP -gt 8 ] && RECOMMENDED_SWAP=8
    [ $RECOMMENDED_SWAP -eq 0 ] && RECOMMENDED_SWAP=2

    # 获取当前Swap总大小（字节）
    SWAP_TOTAL_BYTES=$(free -b | awk '/^Swap:/ || /^交换：/ {print $2}')
    # 转换为GB（四舍五入）
    SWAP_TOTAL_GB=$(echo "scale=0; ($SWAP_TOTAL_BYTES + 536870912) / 1073741824" | bc)
}

# 目标路径文件系统类型检测函数
# $1: 目标文件/目录路径
# 输出: 检测到的文件系统类型
get_fs_type(){
    local target_path="$1"
    # 过滤tmpfs，获取目标路径的文件系统类型
    FS_TYPE=$(df -T "$target_path" | awk 'NR>1 && $1 !~ /tmpfs/ {print $2; exit}')
    echo -e "${YELLOW}检测到文件系统：${FS_TYPE}${FONT}"
    log_info "目标路径${target_path}的文件系统类型：${FS_TYPE}"
}

# fstab配置清理函数 - 清理指定Swap路径的配置条目，支持特殊字符路径
# $1: 需要清理的Swap文件绝对路径
clean_fstab_swap_custom(){
    local swap_path="$1"
    local ESCAPED_PATH=$(escape_path "$swap_path")
    local BACKUP_FILENAME="${BACKUP_PREFIX}.$(date +%Y%m%d%H%M%S)"
    # 备份当前fstab配置
    cp /etc/fstab "/etc/${BACKUP_FILENAME}"
    # 清理指定路径的配置条目
    sed -i "/${ESCAPED_PATH}/d" /etc/fstab
    echo -e "${GREEN}已清理fstab中${swap_path}相关配置（备份文件：/etc/${BACKUP_FILENAME}）${FONT}"
    log_info "清理fstab中${swap_path}条目，备份文件为${BACKUP_FILENAME}"
}

# ===================== 核心功能函数区 =====================
# 默认路径添加Swap函数 - 使用默认路径/swapfile创建Swap
add_swap(){
    add_swap_core "/swapfile"
}

# 高级模式添加Swap函数 - 调用路径补全函数，支持自定义路径
add_swap_advanced(){
    echo -e "\n${YELLOW}=== 高级模式 - 自定义路径添加Swap ===${FONT}"
    SWAP_PATH=$(auto_complete_swap_path)
    [[ -z "$SWAP_PATH" ]] && return 0
    add_swap_core "$SWAP_PATH"
}

# Swap创建核心函数 - 兼容默认路径与自定义路径的通用创建逻辑
# $1: Swap文件的绝对路径
add_swap_core(){
    local SWAP_PATH="$1"
    get_mem_info
    get_fs_type "$(dirname "$SWAP_PATH")"
    echo -e "\n${GREEN}=== 当前系统信息 ===${FONT}"
    echo -e "${GREEN}物理内存：${MEM_TOTAL_GB}GB | 当前Swap：${SWAP_TOTAL_GB}GB${FONT}"
    echo -e "${YELLOW}推荐Swap：${RECOMMENDED_SWAP}GB（内存2倍，最大8GB）${FONT}"
    
    # 读取用户输入的Swap大小，超时或回车使用推荐值
    read -t 30 -p "请输入Swap大小（GB，回车使用推荐值）:" SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

    # 校验输入是否为正整数
    [[ ! "$SWAP_SIZE" =~ ^[1-9][0-9]*$ ]] && {
        echo -e "${RED}错误：请输入有效的正整数！${FONT}"
        log_error "输入的Swap大小${SWAP_SIZE}非有效正整数"
        sleep "$SLEEP_TIME"
        return 0
    }

    # Swap大小超过8GB时的二次确认
    if [ "$SWAP_SIZE" -gt 8 ]; then
        echo -e "${YELLOW}警告：Swap大小超过8GB推荐最大值，是否继续？(y/N)${FONT}"
        read -r CONFIRM_BIG
        [[ ! $CONFIRM_BIG =~ ^[Yy]$ ]] && SWAP_SIZE=8
        echo -e "${GREEN}最终Swap大小：${SWAP_SIZE}GB${FONT}"
    fi

    # 计算分块参数 - 分块创建避免dd命令被系统终止
    SWAP_SIZE_MB=$((SWAP_SIZE * 1024))
    BLOCK_SIZE=100
    BLOCK_COUNT=$((SWAP_SIZE_MB / BLOCK_SIZE))
    [ $((SWAP_SIZE_MB % BLOCK_SIZE)) -ne 0 ] && BLOCK_COUNT=$((BLOCK_COUNT + 1))

    # 检查目标目录磁盘空间 - 预留200MB余量
    local target_dir=$(dirname "$SWAP_PATH")
    AVAIL_SPACE_MB=$(df -BM "$target_dir" | awk 'NR>1 {print $4; gsub("M",""); print}')
    SAFE_SPACE_MB=$((AVAIL_SPACE_MB - 200))
    [ "$SAFE_SPACE_MB" -lt "$SWAP_SIZE_MB" ] && {
        echo -e "${RED}错误：${target_dir}可用空间不足！可用${AVAIL_SPACE_MB}MB，需要${SWAP_SIZE_MB}MB${FONT}"
        log_error "目标目录${target_dir}空间不足，可用${AVAIL_SPACE_MB}MB，需要${SWAP_SIZE_MB}MB"
        sleep "$SLEEP_TIME"
        return 0
    }

    # 清理fstab中残留的配置条目
    clean_fstab_swap_custom "$SWAP_PATH"

    # Btrfs文件系统适配 - 禁用写时复制（COW）属性，否则无法启用Swap
    echo -e "${GREEN}正在创建Swap文件...${FONT}"
    if [ "$FS_TYPE" = "btrfs" ]; then
        echo -e "${YELLOW}Btrfs适配：禁用COW属性...${FONT}"
        truncate -s 0 "$SWAP_PATH"
        chattr +C "$SWAP_PATH"
        log_info "为Btrfs文件系统的${SWAP_PATH}禁用COW属性"
    fi

    # 分块创建Swap文件，显示进度
    echo -e "${YELLOW}分块创建${SWAP_SIZE}GB Swap文件（每块${BLOCK_SIZE}M，共${BLOCK_COUNT}块）...${FONT}"
    dd if=/dev/zero of="$SWAP_PATH" bs=${BLOCK_SIZE}M count=${BLOCK_COUNT} status=progress

    # 校验文件是否创建成功
    [[ ! -f "$SWAP_PATH" ]] && {
        echo -e "${RED}错误：Swap文件创建失败！${FONT}"
        log_error "Swap文件${SWAP_PATH}未生成"
        sleep "$SLEEP_TIME"
        return 0
    }

    # 校验文件大小 - 允许±200MB误差（适配文件系统块对齐）
    ACTUAL_SIZE_MB=$(( $(stat -c %s "$SWAP_PATH") / 1024 / 1024 ))
    MIN_ALLOWED=$((SWAP_SIZE_MB - 200))
    MAX_ALLOWED=$((SWAP_SIZE_MB + 200))
    if [ "$ACTUAL_SIZE_MB" -lt "$MIN_ALLOWED" ] || [ "$ACTUAL_SIZE_MB" -gt "$MAX_ALLOWED" ]; then
        echo -e "${RED}错误：文件大小偏差过大！目标${SWAP_SIZE_MB}MB，实际${ACTUAL_SIZE_MB}MB${FONT}"
        log_error "Swap文件大小不匹配，目标${SWAP_SIZE_MB}MB，实际${ACTUAL_SIZE_MB}MB"
        rm -f "$SWAP_PATH"
        sleep "$SLEEP_TIME"
        return 0
    fi
    # 大小偏差提示（不影响使用）
    [ "$ACTUAL_SIZE_MB" -ne "$SWAP_SIZE_MB" ] && echo -e "${YELLOW}提示：大小偏差为文件系统块对齐导致，不影响使用${FONT}"

    # 设置文件权限 - 仅root可读写，权限必须为600
    chmod 600 "$SWAP_PATH"
    [ "$(stat -c %a "$SWAP_PATH")" != "600" ] && {
        echo -e "${YELLOW}警告：文件权限异常，自动修复为600${FONT}"
        chmod 600 "$SWAP_PATH"
    }

    # 格式化Swap文件
    echo -e "${GREEN}格式化Swap文件...${FONT}"
    if ! mkswap "$SWAP_PATH"; then
        echo -e "${RED}错误：Swap文件格式化失败！${FONT}"
        log_error "mkswap ${SWAP_PATH}执行失败"
        rm -f "$SWAP_PATH"
        sleep "$SLEEP_TIME"
        return 0
    fi

    # 启用Swap文件（失败保留文件供手动修复）
    echo -e "${GREEN}启用Swap文件...${FONT}"
    if ! swapon "$SWAP_PATH"; then
        echo -e "${RED}错误：Swap文件启用失败！${FONT}"
        log_error "swapon ${SWAP_PATH}执行失败"
        [ "$FS_TYPE" = "btrfs" ] && echo -e "${YELLOW}提示：尝试执行 chattr +C ${SWAP_PATH} 后重试${FONT}"
        echo -e "${YELLOW}文件已保留，请手动排查权限或文件系统问题${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    fi

    # 配置开机自启并验证
    echo -e "${GREEN}配置开机自启...${FONT}"
    echo "${SWAP_PATH} none swap defaults 0 0" >> /etc/fstab
    if ! mount -a >/dev/null 2>&1; then
        echo -e "${YELLOW}警告：fstab配置验证失败，自动回滚！${FONT}"
        log_error "fstab配置验证失败，执行回滚操作"
        cp "/etc/${BACKUP_FILENAME}" /etc/fstab 2>/dev/null
        swapoff "$SWAP_PATH"
        rm -f "$SWAP_PATH"
        sleep "$SLEEP_TIME"
        return 0
    fi

    # 展示创建结果
    echo -e "\n${GREEN}================ Swap创建成功 ================${FONT}"
    free -h | grep -E "Mem|Swap|内存|交换"
    log_info "Swap创建成功，路径：${SWAP_PATH}，大小：${SWAP_SIZE}GB"
    sleep $((SLEEP_TIME + 1))
}

# Swap删除函数 - 支持默认路径与自定义路径的Swap删除
del_swap(){
    echo -e "\n${YELLOW}=== 删除Swap（支持自定义路径） ===${FONT}"
    read -p "请输入Swap文件绝对路径（默认 /swapfile）:" SWAP_PATH
    SWAP_PATH=${SWAP_PATH:-/swapfile}

    # 校验路径有效性
    check_abs_path "$SWAP_PATH" || {
        sleep "$SLEEP_TIME"
        return 0
    }

    # 关闭并删除Swap文件
    if [ -f "$SWAP_PATH" ]; then
        echo -e "${GREEN}关闭并删除Swap文件${SWAP_PATH}...${FONT}"
        swapoff "$SWAP_PATH" 2>/dev/null
        swapoff -a 2>/dev/null
        if rm -f "$SWAP_PATH"; then
            echo -e "${GREEN}Swap文件删除成功${FONT}"
            log_info "成功删除Swap文件：${SWAP_PATH}"
        else
            echo -e "${RED}错误：Swap文件删除失败！请手动执行 rm -rf ${SWAP_PATH}${FONT}"
            log_error "删除Swap文件${SWAP_PATH}失败"
            sleep "$SLEEP_TIME"
            return 0
        fi
    else
        echo -e "${YELLOW}未找到Swap文件${SWAP_PATH}${FONT}"
    fi

    # 清理fstab中对应配置
    if grep -q "$(escape_path "$SWAP_PATH")" /etc/fstab; then
        echo -e "${GREEN}清理fstab中${SWAP_PATH}相关配置...${FONT}"
        clean_fstab_swap_custom "$SWAP_PATH"
        # 释放系统缓存（容错）
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo -e "${YELLOW}警告：系统缓存释放失败${FONT}"
        echo -e "\n${GREEN}================ Swap删除成功 ================${FONT}"
        free -h | grep -E "Mem|Swap|内存|交换"
        log_info "Swap删除成功，路径：${SWAP_PATH}"
        sleep $((SLEEP_TIME + 1))
    else
        echo -e "${YELLOW}fstab中无${SWAP_PATH}相关配置${FONT}"
        sleep "$SLEEP_TIME"
    fi
}

# Swap状态查看函数 - 展示详细的Swap与内存信息
show_swap_status(){
    echo -e "\n${GREEN}=== Swap详细状态 ===${FONT}"
    swapon --show || echo "暂无启用的Swap"
    echo -e "\n${GREEN}=== 内存/Swap总览 ===${FONT}"
    free -h
    echo -e "\n${GREEN}=== fstab中Swap配置 ===${FONT}"
    grep -E "swap|交换" /etc/fstab || echo "fstab中无Swap相关配置"
    echo -e "\n${GREEN}=== 根目录文件系统信息 ===${FONT}"
    df -T / | grep /
    echo ""
    log_info "用户查看Swap详细状态"
    sleep $((SLEEP_TIME + 1))
}

# ===================== 主菜单函数区 =====================
# 主菜单函数 - 脚本入口，处理用户交互逻辑
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

    # 超时未输入处理
    if [ -z "$CHOICE" ]; then
        echo -e "\n${YELLOW}超时未输入，返回主菜单...${FONT}"
        log_info "用户超时未输入，返回主菜单"
        sleep 1
        main_menu
        return 0
    fi

    # 输入合法性校验
    [[ ! "$CHOICE" =~ ^[0-4]$ ]] && {
        clear
        echo -e "${RED}错误：请输入0-4之间的有效数字！${FONT}"
        log_error "用户输入无效字符：${CHOICE}"
        sleep "$SLEEP_TIME"
        main_menu
        return 0
    }

    # 菜单功能分发
    case "$CHOICE" in
        1) add_swap ;;
        2) del_swap ;;
        3) show_swap_status ;;
        4) add_swap_advanced ;;
        0) echo -e "${GREEN}脚本已退出${FONT}"; log_info "用户主动退出脚本"; exit 0 ;;
    esac

    # 操作完成后返回菜单逻辑
    echo ""
    read -t 15 -p "是否返回主菜单？(Y/n，15秒默认返回):" BACK_MENU
    BACK_MENU=${BACK_MENU:-Y}
    [[ "$BACK_MENU" =~ ^[Yy]$ ]] && main_menu || {
        echo -e "${GREEN}脚本已退出${FONT}"
        log_info "用户选择不返回主菜单，脚本退出"
        exit 0
    }
}

# 初始化日志文件
touch "$LOG_FILE"
# 启动主菜单
main_menu
