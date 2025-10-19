#!/bin/bash

set -euo pipefail
trap 'echo -e "\033[31m❌ 脚本执行失败，请检查错误信息\033[0m"' ERR

DEFAULT_KEY_PATH="$HOME/.ssh/id_rsa"
KEY_TYPE="rsa"
KEY_BITS="4096"

if [ ! -t 0 ]; then
    echo -e "\033[31m错误：请在交互式终端中运行此脚本\033[0m"
    exit 1
fi

if ! command -v ssh-keygen &> /dev/null; then
    echo -e "\033[31m错误：未找到ssh-keygen命令，请先安装OpenSSH\033[0m"
    exit 1
fi

create_ssh_key() {
    local ssh_dir="$(dirname "$DEFAULT_KEY_PATH")"
    local private_key="$DEFAULT_KEY_PATH"
    local public_key="${private_key}.pub"

    mkdir -p -m 700 "$ssh_dir" || { echo -e "\033[31m❌ 无法创建目录：$ssh_dir\033[0m"; exit 1; }

; }

    if [ -f "$private_key" ] || [ -f "$public_key" ]; then
        echo -e "\033[33m⚠️⚠️ 检测到已存在的SSH密钥：\033[0m$private_key"
        while true; do
            echo -e "\n\033[1m请选择操作：\033[0m"
            echo "1) 备份现有密钥并创建新密钥"
            echo "2) 直接覆盖现有密钥"
            echo "3) 取消操作"
            read -r -p "请输入选择 [1-3]: " choice </dev/tty

            case "$choice" in
                1)
                    backup_and_create "$private_key" "$public_key"
                    return 0
                    ;;
                2)
                    overwrite_keys "$private_key" "$public_key"
                    return 0
                    ;;
                3)
                    echo -e "\033[32m✅ 操作已取消\033[0m"
                    return 1
                    ;;
                *)
                    echo -e "\033[31m❌ 无效选择，请输入1-3之间的数字\033[0m"
                    ;;
            esac
        done
    else
        create_new_keys "$private_key"
        return 0
    fi
}

backup_and_create() {
    local private_key="$1"
    local public_key="$2"
    local ssh_dir="$(dirname "$private_key")"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${ssh_dir}/backup_${timestamp}"

    echo -e "\033[34mℹ️ 正在备份现有密钥...\033[0m"
    mkdir -p -m 700 "$700 "$backup_dir" || { echo -e "\033[31m❌ 无法 无法创建备份目录：$backup_dir\033[0m"; exit 1; }

    [ -f "$private_key" ] && mv -v "$private_key" "$backup_dir/"
    [ -f "$public_key" ] && mv -v "$public_key" "$backup_dir/"

    create_new_keys "$private_key"
    echo -e "\033[32m✅ 备份完成！旧密钥保存在：\033[0m$backup_dir"
}

overwrite_keys() {
    local private_key="$1"
    local public_key="$2"

    echo -e "\033[31m⚠️ 警告：此操作将永久删除现有SSH密钥，无法恢复！\033[0m"
    read -r -p "确认要覆盖吗？(y/N): " confirm </dev/tty

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -f -v "$private_key" "$public_key"
        create_new_keys "$private_key"
        echo -e "\033[32m✅ 已成功覆盖SSH密钥\033[0m"
    else
        echo -e "\033[32m✅ 操作已取消\033[0m"
        return 1
    fi
}

create_new_keys() {
    local private_key="$1"
    local email=""
    local key_path="$private_key"

    read -r -p "请输入邮箱地址（可选）: " email </dev/tty
    read -r -p "请输入密钥保存路径 [默认为 $private_key]: " key_path_input </dev/tty

    key_path="${key_path_input:-$private_key}"
    key_path="$(realpath -s "$key_path")"

    local keygen_opts=(
        -t "$KEY_TYPE"
        -b "$KEY_BITS"
        -f "$key_path"
        -C "${email:-$(whoami)@$(hostname -s)}"
    )

    echo -e "\n\033[34mℹ️ 正在生成SSH密钥...\033[0m"
    ssh-keygen "${keygen_opts[@]}" || { echo -e "\033[31m❌ 密钥生成失败\033[0m"; exit 1; }

    chmod 600 "$key_path" || { echo -e "\033[31m❌ 无法设置私钥权限\033[0m"; exit 1; }

    echo -e "\n\033[32m✅ SSH密钥创建成功！\033[0m"
    echo -e "🔑 私钥位置：\033[1m$key_path\033[0m"
    echo -e "🔑 公钥位置：\033[1m$key_path.pub\033[0m"
    echo -e "\n\033[34mℹ️ 公钥内容：\033[0m"
    cat "$key_path.pub"
    echo -e "\n\033[33m⚠️ 提示：请将公钥添加到远程服务器的~/.ssh/authorized_keys文件中\033[0m"
}

main() {
    echo -e "\033[1m=== SSH密钥生成工具 ===\033[0m"
    create_ssh_key
    echo -e "\n\033[32m✅ 脚本执行完成\033[0m"
}

main "$@"
