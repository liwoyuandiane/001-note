#!/usr/bin/env bash
VERSION="1.7"
DEFAULT_SWAP_PATH="/swapfile"
# Swap管理脚本 ARM/LVM 系统修复版本（终极版 - 简化路径处理）

# 终端颜色定义
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
# 简化的路径标准化函数
normalize_path(){
    local path="$1"
    # 移除重复的斜杠
    echo "$path" | tr -s '/'
}

# 检查目录是否可写
check_dir_writable(){
    local dir="$1"
    [ ! -w "$dir" ] && {
        echo -e "${RED}错误：目录${dir}不可写！${FONT}"
        log_error "目录${dir}无写入权限"
        return 1
    }
    return 0
}

# 检查目录是否存在且可访问（增强版 - 支持LVM/RAID）
check_dir_accessible(){
    local dir="$1"
    
    # 首先检查目录是否存在
    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}错误：目录${dir}不存在！${FONT}"
        log_error "目录${dir}不存在"
        return 1
    fi
    
    # 检查目录是否可写
    if [[ ! -w "$dir" ]]; then
        echo -e "${RED}错误：目录${dir}不可写！${FONT}"
        log_error "目录${dir}无写入权限"
        return 1
    fi
    
    # 检查目录是否可读
    if [[ ! -r "$dir" ]]; then
        echo -e "${RED}错误：目录${dir}不可读！${FONT}"
        log_error "目录${dir}无读取权限"
        return 1
    fi
    
    # 在目录中尝试创建临时文件以确认实际写入权限
    local test_file="$dir/.swap_test_$$.tmp"
    if ! touch "$test_file" 2>/dev/null; then
        echo -e "${RED}错误：无法在目录${dir}中创建文件！可能存在权限或存储限制${FONT}"
        log_error "无法在目录${dir}中创建文件"
        return 1
    else
        rm -f "$test_file" 2>/dev/null
    fi
    
    return 0
}

# 检查Swap是否已激活
check_swap_active(){
    local path="$1"
    if swapon --show 2>/dev/null | grep -qF "$path"; then
        echo -e "${YELLOW}警告：${path}已是活动的Swap${FONT}"
        return 1
    fi
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
    local required_cmds=("free" "dd" "mkswap" "swapon" "swapoff" "grep" "bc" "stat" "df" "chattr" "truncate" "dirname")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要命令${cmd}！${FONT}"
            log_error "缺少命令${cmd}"
            exit 1
        fi
    done
}

check_ovz(){
    [[ -d "/proc/vz" ]] && {
        echo -e "${RED}错误：OpenVZ架构不支持创建Swap！${FONT}"
        log_error "检测到OpenVZ架构"
        exit 1
    }
}

# 获取文件系统类型（增强版 - 支持LVM/RAID等复杂存储）
get_fs_type(){
    local target_path="$1"
    FS_TYPE="ext4"  # 默认ext4

    # 尝试多种方法获取文件系统类型
    if [[ -d "$target_path" ]]; then
        # 方法1: 使用stat获取文件系统类型
        local dev_num
        dev_num=$(stat -c %d "$target_path" 2>/dev/null)
        
        # 方法2: 通过df命令获取
        local df_line
        df_line=$(df -T "$target_path" 2>/dev/null | grep -E "^(/dev|/dev/mapper|/dev/md)")
        
        if [[ -n "$df_line" ]]; then
            FS_TYPE=$(echo "$df_line" | awk '{print $2}')
        else
            # 方法3: 使用findmnt获取
            local fs_from_findmnt
            fs_from_findmnt=$(findmnt -n -o FSTYPE -T swap "$target_path" 2>/dev/null || findmnt -n -o FSTYPE "$target_path" 2>/dev/null)
            if [[ -n "$fs_from_findmnt" ]]; then
                FS_TYPE="$fs_from_findmnt"
            fi
        fi
    elif [[ -f "$target_path" ]]; then
        # 如果是文件，获取其所在目录的文件系统
        local parent_dir
        parent_dir=$(dirname "$target_path")
        local df_line
        df_line=$(df -T "$parent_dir" 2>/dev/null | grep -E "^(/dev|/dev/mapper|/dev/md)")
        
        if [[ -n "$df_line" ]]; then
            FS_TYPE=$(echo "$df_line" | awk '{print $2}')
        else
            # 方法3: 使用findmnt获取
            local fs_from_findmnt
            fs_from_findmnt=$(findmnt -n -o FSTYPE "$parent_dir" 2>/dev/null)
            if [[ -n "$fs_from_findmnt" ]]; then
                FS_TYPE="$fs_from_findmnt"
            fi
        fi
    fi
    
    # 确保FS_TYPE不是空的
    [[ -z "$FS_TYPE" || "$FS_TYPE" == "unknown" ]] && FS_TYPE="ext4"
    
    echo -e "${YELLOW}检测到文件系统：${FS_TYPE}${FONT}"
    log_info "目标路径文件系统：${FS_TYPE} (路径: $target_path)"
}

# 清理fstab配置
clean_fstab_swap_custom(){
    local swap_path="$1"
    local backup_file temp_fstab

    backup_file="${BACKUP_PREFIX}.$(date +%Y%m%d%H%M%S)"
    temp_fstab="/tmp/fstab_clean.$$"

    if ! cp /etc/fstab "/etc/${backup_file}"; then
        echo -e "${RED}错误：无法备份fstab！${FONT}"
        log_error "备份fstab失败"
        echo ""
        return 1
    fi

    # 使用最简单的方法：grep -v 过滤
    if grep -F "$swap_path" /etc/fstab >/dev/null 2>&1; then
        grep -v -F "$swap_path" /etc/fstab > "$temp_fstab" 2>/dev/null
        if [ $? -eq 0 ] && [ -s "$temp_fstab" ]; then
            cp "$temp_fstab" /etc/fstab
            rm -f "$temp_fstab"
        else
            echo -e "${YELLOW}警告：清理fstab配置失败，已保留备份${FONT}"
            log_error "清理fstab失败"
            rm -f "$temp_fstab"
            return 1
        fi
    else
        echo -e "${YELLOW}fstab中未找到${swap_path}配置${FONT}"
    fi

    echo -e "${GREEN}已清理fstab配置（备份：/etc/${backup_file}）${FONT}"
    log_info "清理fstab中${swap_path}，备份：${backup_file}"
    echo "$backup_file"
    return 0
}

# ===================== 路径补全 =====================
auto_complete_swap_path(){
    local input_path swap_path confirm

    echo -e "\n${YELLOW}=== 高级模式 - 指定完整文件路径添加 ===${FONT}"

    # 使用IFS读取整行
    IFS= read -r -p "请输入Swap文件的绝对路径（包括文件名，如 /vol1/swap/swapfile）:" input_path

    # 检查是否为空输入
    [[ -z "$input_path" ]] && {
        echo -e "${RED}错误：输入不能为空！${FONT}"
        log_error "用户输入为空"
        sleep "$SLEEP_TIME"
        return 1
    }

    # 校验绝对路径格式
    [[ "${input_path:0:1}" != "/" ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对路径！${FONT}"
        log_error "输入非绝对路径：${input_path}"
        sleep "$SLEEP_TIME"
        return 1
    }

    # 标准化路径
    input_path=$(normalize_path "$input_path")

    # 提取目录路径
    local dir_path="${input_path%/*}"
    # 如果提取的目录为空或者是文件本身（没有路径分隔符），则使用根目录
    [[ "$dir_path" == "" || "$dir_path" == "$input_path" ]] && dir_path="/"
    
    # 检查目录是否可访问
    check_dir_accessible "$dir_path" || {
        # 如果是根目录不可写，提供建议
        if [[ "$dir_path" == "/" ]]; then
            echo -e "${YELLOW}提示：根目录/通常不可写，建议使用以下路径：${FONT}"
            echo -e "${GREEN}  - $HOME/swapfile${FONT}"
            if [[ -d "/vol1" ]]; then
                echo -e "${GREEN}  - /vol1/swapfile${FONT}"
            fi
            if [[ -d "/vol2" ]]; then
                echo -e "${GREEN}  - /vol2/swapfile${FONT}"
            fi
            echo -e "${YELLOW}请重新运行脚本并选择合适的路径${FONT}"
        fi
        sleep "$SLEEP_TIME"
        return 1
    }

    swap_path="$input_path"
    echo -e "\n${YELLOW}即将生成的Swap文件绝对路径：${FONT}${GREEN}${swap_path}${FONT}"

    # 确认
    echo -e -n "${YELLOW}输入y/Y确认，其他键返回主菜单：${FONT}"
    read confirm

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

    # 获取内存信息
    if free -b >/dev/null 2>&1; then
        mem_total_bytes=$(free -b | awk '/^Mem:/ {print $2}')
        swap_total_bytes=$(free -b | awk '/^Swap:/ {print $2}')
    else
        mem_total_bytes=$(free | awk '/^Mem:/ {print $2*1024}')
        swap_total_bytes=$(free | awk '/^Swap:/ {print $2*1024}')
    fi

    # 防止空值
    [[ -z "$mem_total_bytes" || "$mem_total_bytes" -eq 0 ]] && {
        mem_total_bytes=4294967296  # 默认4GB
        echo -e "${YELLOW}警告：无法检测内存大小，使用默认值4GB${FONT}"
    }

    MEM_TOTAL_GB=$(echo "scale=0; ($mem_total_bytes + 536870912) / 1073741824" | bc)
    RECOMMENDED_SWAP=$((MEM_TOTAL_GB * 2))
    [ $RECOMMENDED_SWAP -gt 8 ] && RECOMMENDED_SWAP=8
    [ $RECOMMENDED_SWAP -eq 0 ] && RECOMMENDED_SWAP=2

    SWAP_TOTAL_GB=$(echo "scale=0; ($swap_total_bytes + 536870912) / 1073741824" | bc)
}

# ===================== 核心功能 =====================
add_swap(){
    # 版本1.6：默认路径保留为 /swapfile，直接执行默认路径的创建逻辑
    add_swap_core "$DEFAULT_SWAP_PATH"
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
    local confirm_big backup_file df_output

    echo -e "${YELLOW}Swap路径：${swap_path}${FONT}"

    # 直接获取swap文件所在目录，使用参数展开避免变量问题
    local dir_path
    dir_path="${swap_path%/*}"
    # 如果提取的目录为空或者是文件本身（没有路径分隔符），则使用根目录
    [[ -z "$dir_path" || "$dir_path" == "$swap_path" ]] && dir_path="/"

    # 路径容错：若根目录不可写，尝试回退到 HOME 或已存在的卷挂载点
    if ! check_dir_accessible "$dir_path"; then
        if [[ -d "$HOME" && -w "$HOME" ]]; then
            echo -e "${YELLOW}根目录不可写，回退到 HOME 目录：${HOME}${FONT}"
            swap_path="$HOME/swapfile"
            dir_path="$HOME"
        else
            echo -e "${RED}错误：根目录及 HOME 目录均不可写，无法创建 Swap${FONT}"
            log_error "根目录及 HOME 均不可写"
            exit 1
        fi
    fi

    echo -e "${YELLOW}目录路径：${dir_path}${FONT}"

    # 检查Swap是否已激活
    check_swap_active "$swap_path" || {
        echo -e "${YELLOW}警告：${swap_path}已是活动的Swap，如需重建请先删除${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    }

    get_mem_info
    get_fs_type "$dir_path"
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

    echo -e "${YELLOW}正在检测${dir_path}的可用空间...${FONT}"

    # 磁盘空间检测 - 增强版，支持LVM/RAID存储
    df_output=$(timeout 10 df -BM "$dir_path" 2>&1)
    
    # 解析df输出，查找包含目标路径的行（可能有多行输出）
    if [[ "$df_output" != *"timeout"* ]] && [[ "$df_output" != *"error"* ]]; then
        # 尝试获取最后一行有效的输出（通常是正确的挂载点信息）
        avail_space_mb=$(echo "$df_output" | grep -v "df:" | grep "$dir_path" | tail -n 1 | awk '{print $4}' | sed 's/M//')
        if [[ -n "$avail_space_mb" ]] && [[ "$avail_space_mb" =~ ^[0-9]+$ ]]; then
            echo -e "${GREEN}可用空间：${avail_space_mb}MB${FONT}"
        else
            # 如果上面的方法失败，尝试其他解析方法
            df_output_simple=$(timeout 10 df "$dir_path" 2>&1)
            avail_space_mb=$(echo "$df_output_simple" | grep -v "df:" | grep "$dir_path" | tail -n 1 | awk '{print int($4/1024)}')
            if [[ -n "$avail_space_mb" ]] && [[ "$avail_space_mb" =~ ^[0-9]+$ ]]; then
                echo -e "${GREEN}可用空间：${avail_space_mb}MB${FONT}"
            else
                # 最后的备选方案：使用findmnt获取磁盘空间信息
                echo -e "${YELLOW}使用备选方案检测磁盘空间...${FONT}"
                local mount_point
                mount_point=$(df "$dir_path" 2>/dev/null | tail -n 1 | awk '{print $6}' 2>/dev/null)
                if [[ -n "$mount_point" ]]; then
                    avail_space_mb=$(df -BM "$mount_point" 2>/dev/null | grep -v "Mounted on" | awk '{print $4}' | sed 's/M//' | tail -n 1)
                    if [[ -n "$avail_space_mb" ]] && [[ "$avail_space_mb" =~ ^[0-9]+$ ]]; then
                        echo -e "${GREEN}可用空间：${avail_space_mb}MB${FONT}"
                    else
                        echo -e "${RED}错误：无法检测${dir_path}的可用空间！${FONT}"
                        log_error "无法检测磁盘空间"
                        sleep "$SLEEP_TIME"
                        return 0
                    fi
                else
                    echo -e "${RED}错误：无法检测${dir_path}的可用空间！${FONT}"
                    log_error "无法检测磁盘空间"
                    sleep "$SLEEP_TIME"
                    return 0
                fi
            fi
        fi
    else
        echo -e "${RED}错误：无法检测${dir_path}的可用空间！${FONT}"
        log_error "无法检测磁盘空间"
        sleep "$SLEEP_TIME"
        return 0
    fi

    safe_space_mb=$((avail_space_mb - 200))
    [ "$safe_space_mb" -lt "$swap_size_mb" ] && {
        echo -e "${RED}错误：${dir_path}空间不足！可用${avail_space_mb}MB，需要${swap_size_mb}MB${FONT}"
        log_error "目标目录空间不足"
        sleep "$SLEEP_TIME"
        return 0
    }

    # 备份fstab
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
    if ! dd if=/dev/zero of="$swap_path" bs=${block_size}M count=${block_count} status=progress 2>&1; then
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

    # 获取文件大小
    actual_size_mb=$(( $(stat -c %s "$swap_path" 2>/dev/null || stat -f %z "$swap_path" 2>/dev/null || ls -l "$swap_path" 2>/dev/null | awk '{print $5}') / 1024 / 1024 ))

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

    # 设置文件权限
    if ! chmod 600 "$swap_path"; then
        echo -e "${RED}错误：无法设置文件权限！${FONT}"
        log_error "chmod失败：${swap_path}"
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi

    # 格式化Swap文件
    echo -e "${GREEN}格式化Swap文件...${FONT}"
    if ! mkswap "$swap_path" 2>&1; then
        echo -e "${RED}错误：格式化失败！${FONT}"
        log_error "mkswap失败：${swap_path}"
        rm -f "$swap_path"
        sleep "$SLEEP_TIME"
        return 0
    fi

    # 启用Swap文件
    echo -e "${GREEN}启用Swap文件...${FONT}"
    if ! swapon "$swap_path" 2>&1; then
        echo -e "${RED}错误：启用失败！${FONT}"
        log_error "swapon失败：${swap_path}"
        [ "$FS_TYPE" = "btrfs" ] && echo -e "${YELLOW}提示：执行 chattr +C ${swap_path} 重试${FONT}"
        echo -e "${YELLOW}文件已保留，请手动排查问题${FONT}"
        sleep "$SLEEP_TIME"
        return 0
    fi

    # 配置开机自启
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
    free -h | head -n 3
    log_info "Swap创建成功：${swap_path} ${swap_size}GB"
    sleep $((SLEEP_TIME + 1))
}

del_swap(){
    local swap_path

    echo -e "\n${YELLOW}=== 删除Swap（支持自定义路径） ===${FONT}"
    read -p "请输入Swap文件绝对路径（默认 /swapfile）:" swap_path
    swap_path=${swap_path:-/swapfile}

    [[ ! "$swap_path" =~ ^/ ]] && {
        echo -e "${RED}错误：请输入以/开头的绝对路径！${FONT}"
        log_error "输入非绝对路径：${swap_path}"
        sleep "$SLEEP_TIME"
        return 0
    }

    [[ -d "$swap_path" ]] && {
        echo -e "${RED}错误：${swap_path}是目录！请输入文件路径${FONT}"
        log_error "输入目录作为swap路径：${swap_path}"
        sleep "$SLEEP_TIME"
        return 0
    }

    local dir
    dir=$(dirname "$swap_path")
    check_dir_accessible "$dir" || {
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

    # 检查fstab中是否有配置
    if grep -F "$swap_path" /etc/fstab >/dev/null 2>&1; then
        echo -e "${GREEN}清理fstab中${swap_path}配置...${FONT}"
        clean_fstab_swap_custom "$swap_path" >/dev/null
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo -e "${YELLOW}警告：缓存释放失败${FONT}"
        echo -e "\n${GREEN}================ Swap删除成功 ================${FONT}"
        free -h | head -n 3
        log_info "Swap删除成功：${swap_path}"
        sleep $((SLEEP_TIME + 1))
    else
        echo -e "${YELLOW}fstab中无${swap_path}配置${FONT}"
        sleep "$SLEEP_TIME"
    fi
}

show_swap_status(){
    echo -e "\n${GREEN}=== Swap详细状态 ===${FONT}"
    swapon --show 2>/dev/null || echo "暂无启用的Swap"
    echo -e "\n${GREEN}=== 内存/Swap总览 ===${FONT}"
    free -h
    echo -e "\n${GREEN}=== fstab中Swap配置 ===${FONT}"
    if grep -i swap /etc/fstab 2>/dev/null; then
        : # 找到了
    else
        echo "fstab中无Swap配置"
    fi
    echo -e "\n${GREEN}=== 根目录文件系统信息 ===${FONT}"
    df -T / 2>/dev/null | tail -n +2 || df -h /
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
            clear
            echo -e "${RED}错误：请输入0-4之间的有效数字！${FONT}"
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

# 初始化日志
touch "$LOG_FILE" 2>/dev/null && chmod 600 "$LOG_FILE" 2>/dev/null || {
    echo -e "${YELLOW}警告：无法创建/设置日志文件权限，继续执行...${FONT}"
}

# 启动脚本
main_menu
