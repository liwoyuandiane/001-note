#!/bin/bash

if [ -z "$TTYD_CREDENTIAL" ]; then
    echo "错误: 必须设置 TTYD_CREDENTIAL 环境变量才能启动服务"
    echo "请在 Hugging Face Spaces Settings 中设置 TTYD_CREDENTIAL 环境变量"
    echo "格式: 用户名:密码 (例如: admin:MySecurePassword123!)"
    exit 1
fi

if [ -n "$url_sh" ] && [ -z "$home" ]; then
    echo "错误: 设置了 url_sh 但未设置 home 环境变量"
    echo "请同时设置 url_sh 和 home 环境变量"
    exit 1
fi

mkdir -p "$home"
cd "$home"

echo "正在下载脚本: $url_sh"
SCRIPT_NAME=$(basename "$url_sh")
curl -L -o "$SCRIPT_NAME" "$url_sh"

echo "启动 ttyd 服务..."
ttyd -p 7860 -c "$TTYD_CREDENTIAL" --writable -q bash &
TTYD_PID=$!

echo "ttyd 已启动 (PID: $TTYD_PID)"

sleep 2

echo "正在执行自定义脚本: $SCRIPT_NAME"
if [ -n "$script_args" ]; then
    echo "使用参数: $script_args"
    . "$SCRIPT_NAME" $script_args
else
    echo "无参数，直接执行"
    . "$SCRIPT_NAME"
fi

for script in "$home"/*.sh; do
    if [ -f "$script" ]; then
        echo "执行脚本: $script"
        if [ -n "$script_args" ]; then
            . "$script" $script_args
        else
            . "$script"
        fi
    done

wait $TTYD_PID
