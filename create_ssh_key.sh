#!/bin/bash

# 打印输出的函数
print_info() {
    echo "[信息] $1"
}

print_warning() {
    echo "[警告] $1"
}

print_error() {
    echo "[错误] $1"
}

# 验证密钥对是否匹配的函数
verify_key_pair() {
    local key_file="$1"
    local pub_file="${key_file}.pub"
    
    # 检查密钥文件是否存在
    if [ ! -f "$key_file" ] || [ ! -f "$pub_file" ]; then
        print_error "密钥文件不存在"
        return 1
    fi
    
    # 从私钥生成公钥并与其比较
    local generated_pub
    generated_pub=$(openssl rsa -in "$key_file" -pubout -outform PEM 2>/dev/null)
    local existing_pub
    existing_pub=$(cat "$pub_file")
    
    if [ "$generated_pub" = "$existing_pub" ]; then
        print_info "密钥对验证成功：公钥和私钥匹配"
        return 0
    else
        print_error "密钥对验证失败：公钥和私钥不匹配"
        return 1
    fi
}

# 检查SSH目录是否存在，如果不存在则创建
SSH_DIR="$HOME/.ssh"
if [ ! -d "$SSH_DIR" ]; then
    print_info "正在创建SSH目录..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# 检查SSH密钥是否已存在
KEY_FILE="$SSH_DIR/id_rsa"
if [ -f "$KEY_FILE" ]; then
    print_warning "在 $KEY_FILE 已存在SSH密钥"
    echo "您想要做什么？"
    echo "1) 备份现有密钥并创建新密钥"
    echo "2) 覆盖现有密钥"
    echo "3) 取消操作"
    echo "4) 验证现有密钥对是否匹配"
    
    # 循环直到用户做出有效选择
    while true; do
        read -p "请输入您的选择 (1/2/3/4): " choice
        case $choice in
            1)
                # 备份现有密钥
                BACKUP_FILE="${KEY_FILE}.bak"
                BACKUP_PUB_FILE="${KEY_FILE}.pub.bak"
                
                # 检查备份文件是否已存在
                if [ -f "$BACKUP_FILE" ]; then
                    print_warning "备份文件 $BACKUP_FILE 已存在"
                    print_warning "注意：如果您选择不替换备份文件，现有密钥将被直接覆盖！"
                    while true; do
                        read -p "是否要替换备份文件？(y/n): " replace_backup
                        case $replace_backup in
                            y|Y)
                                print_info "正在替换备份文件..."
                                print_info "正在备份现有密钥到 $BACKUP_FILE"
                                cp "$KEY_FILE" "$BACKUP_FILE"
                                cp "${KEY_FILE}.pub" "$BACKUP_PUB_FILE" 2>/dev/null || true
                                break
                                ;;
                            n|N)
                                print_warning "现有密钥将被直接覆盖！"
                                break
                                ;;
                            *)
                                print_error "无效选择。请输入 y 或 n。"
                                ;;
                        esac
                    done
                else
                    print_info "正在备份现有密钥到 $BACKUP_FILE"
                    cp "$KEY_FILE" "$BACKUP_FILE"
                    cp "${KEY_FILE}.pub" "$BACKUP_PUB_FILE" 2>/dev/null || true
                fi
                break
                ;;
            2)
                print_info "正在覆盖现有密钥..."
                break
                ;;
            3)
                print_info "操作已取消。"
                exit 0
                ;;
            4)
                print_info "正在验证现有密钥对..."
                if verify_key_pair "$KEY_FILE"; then
                    exit 0
                else
                    exit 1
                fi
                ;;
            *)
                print_error "无效选择。请输入 1、2、3 或 4。"
                ;;
        esac
    done
else
    print_info "未找到现有的SSH密钥。正在创建新密钥..."
fi

# 检查openssl是否可用
if ! command -v openssl &> /dev/null; then
    print_error "未安装openssl。请安装openssl以生成SSH密钥。"
    exit 1
fi

# 生成SSH密钥
print_info "正在生成新的SSH密钥..."
# 生成私钥
openssl genrsa -out "$KEY_FILE" 4096 >/dev/null 2>&1

# 检查私钥生成是否成功
if [ $? -ne 0 ]; 键，然后
    print_error "无法生成SSH私钥。"
    exit 1
fi

# 从私钥生成公钥
openssl rsa -in "$KEY_FILE" -pubout -out "${KEY_FILE}.pub" >/dev/null 2>&1

# 检查公钥生成是否成功
if [ $? -ne 0 ]; then
    print_error "无法生成SSH公钥。"
    exit 1
fi

# 设置正确的权限
chmod 600 "$KEY_FILE"
chmod 644 "${KEY_FILE}.pub"

print_info "SSH密钥生成成功！"
print_info "私钥: $KEY_FILE"
print_info "公钥: ${KEY_FILE}.pub"

# 验证生成的密钥对是否匹配
print_info "正在验证密钥对..."
if verify_key_pair "$KEY_FILE"; then
    print_info "密钥指纹:"
    # 生成指纹
    FINGERPRINT=$(openssl rsa -in "$KEY_FILE" -pubout -outform DER 2>/dev/null | openssl md5 -c)
    echo "$FINGERPRINT"
else
    print_error "密钥对验证失败，请检查密钥文件"
    exit 1
fi
