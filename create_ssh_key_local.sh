#!/bin/bash

echo "========================================"
echo "         SSH 密钥生成工具"
echo "========================================"

read -p "请输入您的邮箱地址（用于标识密钥）: " email

echo
echo "正在检查当前目录是否已存在 SSH 密钥..."

# 定义密钥文件路径（当前目录）
KEY_DIR="./ssh_keys"
PRIVATE_KEY="$KEY_DIR/id_rsa"
PUBLIC_KEY="$KEY_DIR/id_rsa.pub"

# 创建密钥目录
mkdir -p "$KEY_DIR"

if [ -f "$PRIVATE_KEY" ]; then
    echo "检测到当前目录已存在 SSH 密钥！"
    read -p "是否覆盖现有密钥？(y/N): " overwrite
    if [[ ! $overwrite =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
    # 备份旧密钥
    BACKUP_DIR="${KEY_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    mv "$PRIVATE_KEY" "$PUBLIC_KEY" "$BACKUP_DIR/" 2>/dev/null
    echo "旧密钥已备份到: $BACKUP_DIR"
fi

echo
echo "正在生成新的 SSH 密钥对..."
ssh-keygen -t rsa -b 4096 -C "$email" -f "$PRIVATE_KEY" -N ""

if [ $? -ne 0 ]; then
    echo "错误：SSH 密钥生成失败！"
    exit 1
fi

# 设置适当的权限
chmod 700 "$KEY_DIR"
chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

echo
echo "✓ SSH 密钥已成功生成！"
echo

echo "========================================"
echo "          您的公钥内容"
echo "========================================"
cat "$PUBLIC_KEY"

echo
echo "========================================"
echo "          重要信息"
echo "========================================"
echo "1. 私钥位置: $(realpath "$PRIVATE_KEY")"
echo "2. 公钥位置: $(realpath "$PUBLIC_KEY")"
echo "3. 密钥目录: $(realpath "$KEY_DIR")"
echo "4. 请将公钥内容添加到需要访问的服务器"
echo "5. 使用示例: ssh -i $(realpath "$PRIVATE_KEY") user@hostname"
echo

# 尝试复制到剪贴板
if command -v pbcopy >/dev/null 2>&1; then
 then
    # macOS
    cat "$PUBLIC_KEY" | pbcopy
    echo "✓ 公钥已复制到剪贴板 (macOS)"
elif command -v xclip >/dev/null 2>&1; then
    # Linux with xclip
    cat "$PUBLIC_KEY" | xclip -selection clipboard
    echo "✓ 公钥已复制到剪贴板 (Linux)"
elif command -v xsel >/dev/null 2>&1; then
 then
    # Linux with xsel
    cat "$PUBLIC_KEY" | xsel --clipboard --input
    echo "✓ 公钥已复制到剪贴板 (Linux)"
else
    echo "提示：安装 xclip 或 xsel 可自动复制公钥到剪贴板"
fi

# 显示使用说明
echo
echo "使用说明:"
echo "1. 将上方公钥内容添加到目标服务器的 ~/.ssh/authorized_keys 文件中"
echo "2. 连接时使用: ssh -i '$PRIVATE_KEY' username@hostname"
echo "3. 对于 Play with Docker，请将公钥内容粘贴到平台的 SSH Keys 设置中"
echo

read -p "按回车键继续..."
