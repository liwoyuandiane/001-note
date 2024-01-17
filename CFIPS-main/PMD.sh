#!/bin/bash

# 获取当前脚本的文件名（不包括路径）
script_name=$(basename "$0")

check_script_process(){
# 检测当前脚本的进程数量
script_process_count=$(pgrep -c -f "$script_name")

# 如果当前脚本的进程数量大于1，结束脚本
if [ $script_process_count -gt 1 ]; then
    #echo "当前脚本进程数量大于1，结束脚本。"
    exit 0
fi
}

check_script_process
# 计数器，用于在第30次循环时检测Python进程
counter=0

# 保存Python进程的PID的变量
python_pid0="null"

# 检测go.sh脚本是否在运行的函数
check_go_process() {
    local go_process_count=$(pgrep -c -f "go.sh")
    #echo "go.sh进程数量: $go_process_count"
    if [ $go_process_count -eq 0 ]; then
        #echo "go.sh脚本未在运行，结束脚本。"
        exit 0
    fi
}

# 检测"python3 TestCloudFlareIP.py"脚本是否在运行的函数
check_python_process() {
    local python_process_cmdline=$(pgrep -a -f "python3 TestCloudFlareIP.py")
    #echo "TestCloudFlareIP.py进程命令行: $python_process_cmdline"
    
    if [[ $python_process_cmdline == *"python3 TestCloudFlareIP.py"* ]]; then
        local python_pid=$(echo "$python_process_cmdline" | awk '{print $1}')
		if [ "$python_pid0" = "null" ]; then
		    python_pid0=$python_pid
		else
		    if [ "$python_pid0" = "$python_pid" ]; then
			echo "Killed unresponsive TestCloudFlareIP.py!  PID:$python_pid"
			kill $python_pid
			python_pid0="null"
		    else
		        python_pid0=$python_pid
		    fi
		fi

    else
        #echo "TestCloudFlareIP.py进程未找到"
        python_pid0="null"
    fi
}

# 每隔一分钟检测go.sh脚本是否在运行
while true; do
    check_go_process
	check_script_process
    sleep 60  # 等待60秒
    ((counter++))

    # 在第30次循环时检测Python进程
    if [ $counter -eq 40 ]; then
        check_python_process
        counter=0  # 重置计数器
    fi
done
