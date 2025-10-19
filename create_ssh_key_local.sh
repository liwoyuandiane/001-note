#!/bin/bash

# SSH密钥创建脚本
create_ssh_key() {
    local ssh_dir="$HOME/.ssh"
    local private_key="$ssh_dir/id_rsa"
    local public_key="$private_key.pub"
    
    # 检查SSH目录是否存在，不存在则创建
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
    
    # 检查密钥是否已存在
    if [[ -f "$private_key" || -f "$public_key" ]]; then
        echo "检测到已存在的SSH密钥: $private_key"
        
        while true; do
            echo ""
            echo "请选择操作:"
            echo "1) 备份现有密钥并创建新密钥"
            echo "2) 直接覆盖现有密钥"
            echo "3) 取消操作"
            read -p "请输入选择 [1-3]: " choice
            
            case $choice in
                1)
                    backup_and_create "$private_key" "$public_key"
                    return 0
                    ;;
                2)
                    overwrite_keys "$private_key" "$public_key"
                    return 0
                    ;;
                3)
                    echo "操作已取消"
                    return 1
                    ;;
                *)
                    echo "无效的选择，请重新输入"
                    ;;
            esac
        done
    else
        create_new_keys "$private_key"
        return 0
    fi
}

# 备份并创建新密钥
backup_and_create() {
    local private_key=$1
    local public_key=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$HOME/.ssh/backup_$timestamp"
    
    echo "正在备份现有密钥..."
    mkdir -p "$backup_dir"
    
    if [[ -f "$private_key" ]]; then
        mv "$private_key" "$backup_dir/"
        echo "已备份私钥: $backup_dir/id_rsa"
    fi
    
    if [[ -f "$public_key" ]]; then
        mv "$public_key" "$backup_dir/"
        echo "已备份公钥: $backup_dir/id_rsa.pub"
    fi
    
    create_new_keys "$private_key"
    echo "备份完成，旧密钥保存在: $backup_dir"
}

# 直接覆盖密钥
overwrite_keys() {
    local private_key=$1
    local public_key=$2
    
    echo "警告：这将永久删除现有的SSH密钥！"
    read -p "确认要覆盖吗？(y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$private_key" "$public_key"
        create_new_keys "$private_key"
        echo "已成功覆盖SSH密钥"
    else
        echo "操作已取消"
        return 1
    fi
}

# 创建新密钥
create_new_keys() {
    local private_key=$1
    
    echo ""
    read -p "请输入邮箱地址 (可选): " email
    read -p "请输入密钥保存路径 [默认为 $private_key]: " key_path
    
    key_path=${key_path:-$private_key}
    
    # 确保目录存在
    local key_dir=$(dirname "$key_path")
    mkdir -p "$key_dir"
    
    # 构建ssh-keygen命令
    local keygen_cmd="ssh-keygen -t rsa -b 4096 -f \"$key_path\""
    
    if [[ -n "$email" ]]; then
        keygen_cmd="$keygen_cmd -C \"$email\""
    else
        keygen_cmd="$keygen_cmd -C \"$(whoami)@$(hostname)\""
    fi
    
    echo "正在生成SSH密钥..."
    eval "$keygen_cmd"
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo "✅ SSH密钥创建成功！"
        echo "🔑 私钥位置: $key_path"
        echo "🔑 公钥位置: $key_path.pub"
        echo ""
        echo "公钥内容:"
        cat "$key_path.pub"
        echo ""
        echo "请妥善保管您的私钥文件！"
    else
        echo "❌ SSH密钥创建失败"
        return 1
    fi
}

# 主函数
main() {
    echo "=== SSH密钥生成工具 ==="
    
    # 检查ssh-keygen是否可用
    if ! command -v ssh-keygen &> /dev/null; then
        echo "错误: 未找到 ssh-keygen 命令，请先安装OpenSSH"
        exit 1
    fi
    
    create_ssh_key
}

# 设置错误处理
set -euo pipefail

# 运行主函数
main "$@"
