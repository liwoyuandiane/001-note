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

# 检测是否存在密钥文件
key_exists=false
if [ -f "$PRIVATE_KEY" ] || [ -f "$PUBLIC_KEY" ]; then
    key_exists=true
    
    echo "⚠️  检测到当前目录已存在 SSH 密钥！"
    echo
    echo "现有密钥信息:"
    if [ -f "$PRIVATE_KEY" ]; then
        echo "  • 私钥: $(realpath "$PRIVATE_KEY")"
        echo "  • 大小: $(du -h "$PRIVATE_KEY" | cut - cut -f1)"
        echo "  • 修改时间: $(date -r "$PRIVATE_KEY" "+%Y-%m-%d %H:%M:%S")"
    fi
    if [ -f "$PUBLIC_KEY" ]; then
        echo "  • 公钥: $(realpath "$PUBLIC_KEY")"
        echo "  • 指纹: $(ssh-keygen -lf "$PUBLIC_KEY" 2>/dev/null | head -n1 || echo "无法读取指纹")"
    fi
    
    echo
    echo "请选择操作:"
    echo "1) 备份现有密钥并创建新密钥"
    echo "2) 直接覆盖现有密钥"
    echo "3) 退出脚本"
    echo
    
    while true; do
        read -p "请输入选择 (1/2/3): " choice
        case $choice in
            1)
                # 备份现有密钥
                BACKUP_DIR="${KEY_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
                mkdir -p "$BACKUP_DIR"
                
                echo
                echo "正在备份现有密钥..."
                if [ -f "$PRIVATE_KEY" ]; then
                    cp "$PRIVATE_KEY" "$BACKUP_DIR/"
                    echo "✓ 私钥备份到: $BACKUP_DIR/id_rsa"
                fi
                if [ -f "$PUBLIC_KEY" ]; then
                    cp "$PUBLIC_KEY" "$BACKUP_DIR/"
                    echo "✓ 公钥备份到: $BACKUP_DIR/id_rsa.pub"
                fi
                break
                ;;
            2)
                # 直接覆盖，无需备份
                echo
                echo "⚠️  警告：直接覆盖现有密钥！"
                read -p "确认继续吗？(输入 'yes' 继续): " confirm
                if [ "$confirm" != "yes" ]; then
                    echo "操作已取消。"
                    exit 0
                fi
                echo "正在删除现有密钥..."
                rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"
                break
                ;;
            3)
                echo "操作已取消。"
                exit 0
                ;;
            *)
                echo "无效选择，请重新输入 (1/2/3)"
                ;;
        esac
    done
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

if [ "$key_exists" = true ] && [ "$choice" = "1" ]; then
    echo "4. 旧密钥备份位置: $(realpath "$BACKUP_DIR")"
fi

echo "5. 请将上述公钥内容添加到需要访问的服务器"
echo "6. 使用示例: ssh -i $(realpath "$PRIVATE_KEY") user@hostname"
echo

# 显示使用说明
echo "使用说明:"
echo "1. 将上方公钥内容添加到目标服务器的 ~/.ssh/authorized_keys 文件中"
echo "2. 连接时使用: ssh -i '$PRIVATE_KEY' username@hostname"
echo "3. 对于 Play with Docker，请将公钥内容粘贴到平台的 SSH Keys 设置中"
echo

read -p "按回车键退出..."
