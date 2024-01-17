#!/bin/bash
port=443

# 创建一个空变量来存储最老的文件的端口号
oldest_port=""
# 创建一个变量来存储最老的文件的修改时间，初始值设为未来的一个时间
oldest_time="3000-01-01 00:00:00"

# 检查go.sh是否在运行
if pgrep -f "go.sh" > /dev/null
then
    echo "CloudFlareIPScan正在运行"
else
    echo "CloudFlareIPScan没有运行，开始执行"

	if ls ./CloudFlareIP-*.txt 1> /dev/null 2>&1; then
    	# 创建一个空数组来存储端口号
        declare -a ports

        # 遍历当前目录下所有匹配CloudFlareIP-*.txt模式的文件
        for file in CloudFlareIP-*.txt
        do
            # 使用basename和cut命令来提取文件名中的端口号
            port=$(basename $file .txt | cut -d '-' -f 2)
        # 将端口号添加到数组中
            ports+=($port)
        done
	
		# 检查数组是否为空
		if [ ${#ports[@]} -eq 0 ]; then
  		    echo "执行CloudFlareIPScan 扫描443端口"
			nohup ./go.sh 443 > going.txt 2>&1 &
		else
		
		# 遍历ports数组中的所有端口号
		for port in "${ports[@]}"
		do
		    # 获取文件CloudFlareIP-${port}.txt的修改时间
 		   file_time=$(stat -c %y "CloudFlareIP-${port}.txt")
 		   # 如果这个文件的修改时间比当前最老的文件的修改时间还要早，那么更新最老的文件的端口号和修改时间
 		   if [[ "$file_time" < "$oldest_time" ]]
 		   then
  		      oldest_port=$port
  		      oldest_time=$file_time
  		  fi
		done
		
		# 检查最老的文件的端口号是否为空
		if [[ -z "$oldest_port" ]]
		then
		    echo "执行CloudFlareIPScan 扫描443端口"
			nohup ./go.sh 443 > going.txt 2>&1 &
		else
 		    echo "执行CloudFlareIPScan 扫描${oldest_port}端口"
			nohup ./go.sh ${oldest_port} > going.txt 2>&1 &
		fi

	fi
	
	else
	    echo "执行CloudFlareIPScan 扫描443端口"
		nohup ./go.sh 443 > going.txt 2>&1 &
	fi
fi
