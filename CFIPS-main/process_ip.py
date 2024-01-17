import ipaddress

# 清空或创建ip0.txt文件
with open("temp/ip0.txt", "w") as output_file:
    pass

# 定义一个空列表用于存储唯一的IP地址
unique_ips = []

# 函数：展开CIDR格式的IP地址范围并保存到unique_ips列表中
def expand_cidr(cidr):
    ip_range = ipaddress.IPv4Network(cidr, strict=False)
    for ip in ip_range:
        unique_ips.append(str(ip))

# 读取ip.txt文件的每一行
with open("ip.txt", "r") as input_file:
    for line in input_file:
        line = line.strip()  # 移除额外的空白字符
        # 判断行是否包含IP段
        if "/" in line:
            expand_cidr(line)
        else:
            # 直接将IP添加到unique_ips列表中
            unique_ips.append(line)

# 去重并排序
unique_ips = list(set(unique_ips))
unique_ips.sort(key=lambda ip: ipaddress.ip_address(ip))

# 将唯一的IP地址写回到ip0.txt文件中
with open("temp/ip0.txt", "a") as output_file:
    for ip in unique_ips:
        output_file.write(ip + "\n")

#print("处理完成，去重并排序的结果保存在temp/ip0.txt中")
