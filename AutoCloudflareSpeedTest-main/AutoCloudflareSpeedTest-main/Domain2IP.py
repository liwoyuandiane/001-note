import os
import socket
import subprocess
import ipaddress

# 清除本机DNS缓存
def clear_dns_cache():
    try:
        if os.name == 'posix':  # 如果是Linux或macOS
            subprocess.run(["sudo", "systemctl", "restart", "systemd-resolved"])
        elif os.name == 'nt':  # 如果是Windows
            subprocess.run(["ipconfig", "/flushdns"], shell=True)
        else:
            print("不支持的操作系统")
    except Exception as e:
        print(f"清除DNS缓存时发生错误: {e}")

# 定义输入文件和输出文件的路径
input_file = 'Domain.txt'
output_file = 'temp/Domain2IP.txt'

# 定义要使用的DNS服务器
dns_servers = ['114.114.114.114', '119.28.28.28', '223.5.5.5', '8.8.8.8', '208.67.222.222']

# 清除本机DNS缓存
clear_dns_cache()

# 设置默认的DNS服务器
socket.setdefaulttimeout(5)  # 设置解析超时时间为5秒

# 打开输入文件以读取域名
try:
    with open(input_file, 'r') as f:
        lines = f.readlines()
except FileNotFoundError:
    print(f"找不到文件 {input_file}")
    exit()

# 准备一个用于存储解析后IP的列表
ip_addresses = []

# 遍历每行域名并解析IP
for line in lines:
    # 去除行首和行尾的空白字符
    domain = line.strip()
    
    # 如果行为空白，则跳过
    if not domain:
        continue

    # 禁用DNS缓存
    socket.setdefaulttimeout(0)
    ips0 = []
    print(f"解析域名: {domain}")
    # 遍历DNS服务器进行解析
    for dns_server in dns_servers:
        try:
            ips = socket.gethostbyname_ex(domain)[2]
            ips0.extend(ips)  # 将解析得到的所有IP添加到列表中
            ip_addresses.extend(ips)  # 将解析得到的所有IP添加到列表中
        except socket.gaierror as e:
            print(f"DNS服务器 {dns_server}无法解析域名 : {e}")
        except Exception as e:
            print(f"DNS服务器 {dns_server}发生未知错误 : {e}")

    # 去重
    ips0 = list(set(ips0))
    # 输出解析结果
    print(f"IP地址: {ips0}")

    # 恢复默认的解析超时
    socket.setdefaulttimeout(5)

# 去重
ip_addresses = list(set(ip_addresses))

# 定义删除CF官方IP地址段
ip_ranges_to_delete = [
    '173.245.48.0/20',
    '103.21.244.0/22',
    '103.22.200.0/22',
    '103.31.4.0/22',
    '141.101.64.0/18',
    '108.162.192.0/18',
    '190.93.240.0/20',
    '188.114.96.0/20',
    '197.234.240.0/22',
    '198.41.128.0/17',
    '162.158.0.0/15',
    '104.16.0.0/12',
    '172.64.0.0/17',
    '172.64.128.0/18',
    '172.64.192.0/19',
    '172.64.224.0/22',
    '172.64.229.0/24',
    '172.64.230.0/23',
    '172.64.232.0/21',
    '172.64.240.0/21',
    '172.64.248.0/21',
    '172.65.0.0/16',
    '172.66.0.0/16',
    '172.67.0.0/16',
    '131.0.72.0/22',
    '192.203.230.0/24',
    '5.226.179.0/24',
    '5.226.181.0/24',
    '8.12.10.0/24',
    '12.221.133.0/24',
    '23.141.168.0/24',
    '23.178.112.0/24',
    '23.247.163.0/24',
    '31.12.75.0/24',
    '31.22.116.0/24',
    '31.43.179.0/24',
    '38.67.242.0/24',
    '44.31.142.0/24',
    '45.8.104.0/22',
    '45.8.211.0/24',
    '45.12.30.0/23',
    '45.14.174.0/24',
    '45.80.109.0/24',
    '45.80.111.0/24',
    '45.84.59.0/24',
    '45.85.118.0/23',
    '45.87.175.0/24',
    '45.94.169.0/24',
    '45.95.241.0/24',
    '45.131.4.0/22',
    '45.131.208.0/22',
    '45.133.247.0/24',
    '45.137.99.0/24',
    '45.142.120.0/24',
    '45.145.28.0/24',
    '45.145.29.0/24',
    '45.158.56.0/24',
    '45.159.216.0/22',
    '45.194.53.0/24',
    '45.195.62.0/24',
    '45.205.0.0/24',
    '46.8.199.0/24',
    '65.205.150.0/24',
    '66.81.247.0/24',
    '66.81.255.0/24',
    '66.94.36.0/23',
    '66.94.39.0/24',
    '67.131.109.0/24',
    '72.52.113.0/24',
    '80.94.83.0/24',
    '83.118.224.0/23',
    '83.118.226.0/23',
    '85.209.179.0/24',
    '89.47.56.0/23',
    '89.116.180.0/24',
    '89.116.250.0/24',
    '89.207.18.0/24',
    '91.192.106.0/23',
    '91.193.58.0/23',
    '91.195.110.0/24',
    '91.199.81.0/24',
    '91.221.116.0/24',
    '93.114.64.0/23',
    '94.140.0.0/24',
    '95.214.178.0/23',
    '103.11.212.0/24',
    '103.11.214.0/24',
    '103.19.144.0/23',
    '103.31.6.0/23',
    '103.31.7.0/24',
    '103.79.228.0/23',
    '103.112.176.0/24',
    '103.121.59.0/24',
    '103.156.22.0/23',
    '103.160.204.0/24',
    '103.168.172.0/24',
    '103.169.142.0/24',
    '103.172.110.0/23',
    '103.204.13.0/24',
    '103.235.4.0/24',
    '103.244.116.0/22',
    '104.254.140.0/24',
    '108.165.48.0/24',
    '108.165.216.0/24',
    '123.253.174.0/24',
    '138.5.248.0/24',
    '141.11.194.0/23',
    '141.193.213.0/24',
    '145.36.144.0/24',
    '146.19.21.0/24',
    '146.19.22.0/24',
    '147.78.121.0/24',
    '147.78.140.0/24',
    '147.185.161.0/24',
    '154.51.129.0/24',
    '154.51.160.0/24',
    '154.83.2.0/24',
    '154.83.22.0/23',
    '154.83.30.0/23',
    '154.84.14.0/23',
    '154.84.16.0/21',
    '154.84.24.0/22',
    '154.84.175.0/24',
    '154.85.8.0/22',
    '154.85.99.0/24',
    '154.92.9.0/24',
    '154.94.8.0/23',
    '154.194.2.0/24',
    '154.219.2.0/23',
    '155.46.213.0/24',
    '156.225.72.0/24',
    '156.229.48.0/24',
    '156.237.4.0/23',
    '156.238.14.0/23',
    '156.238.18.0/23',
    '156.239.152.0/22',
    '156.252.2.0/23',
    '159.112.235.0/24',
    '159.246.55.0/24',
    '160.153.0.0/24',
    '162.44.32.0/22',
    '162.44.104.0/22',
    '162.44.118.0/23',
    '162.44.208.0/23',
    '162.120.94.0/24',
    '163.231.14.0/24',
    '164.38.155.0/24',
    '167.1.148.0/24',
    '167.1.149.0/24',
    '167.1.150.0/24',
    '167.1.181.0/24',
    '167.68.5.0/24',
    '167.68.11.0/24',
    '168.100.6.0/24',
    '170.114.45.0/24',
    '170.114.46.0/24',
    '170.114.52.0/24',
    '172.83.72.0/24',
    '172.83.73.0/24',
    '172.83.76.0/24',
    '174.136.134.0/24',
    '176.126.206.0/23',
    '181.214.1.0/24',
    '185.7.190.0/23',
    '185.18.250.0/24',
    '185.38.135.0/24',
    '185.59.218.0/24',
    '185.72.49.0/24',
    '185.109.21.0/24',
    '185.135.9.0/24',
    '185.148.104.0/24',
    '185.148.105.0/24',
    '185.148.106.0/24',
    '185.148.107.0/24',
    '185.162.228.0/23',
    '185.162.230.0/23',
    '185.170.166.0/24',
    '185.174.138.0/24',
    '185.176.24.0/24',
    '185.176.26.0/24',
    '185.193.28.0/23',
    '185.193.30.0/23',
    '185.201.139.0/24',
    '185.207.92.0/24',
    '185.209.154.0/24',
    '185.213.240.0/24',
    '185.213.243.0/24',
    '185.221.160.0/24',
    '185.234.22.0/24',
    '185.238.228.0/24',
    '185.244.106.0/24',
    '188.42.88.0/24',
    '188.42.89.0/24',
    '188.42.145.0/24',
    '188.244.122.0/24',
    '192.65.217.0/24',
    '192.133.11.0/24',
    '193.9.49.0/24',
    '193.16.63.0/24',
    '193.17.206.0/24',
    '193.67.144.0/24',
    '193.188.14.0/24',
    '193.227.99.0/24',
    '194.1.194.0/24',
    '194.36.49.0/24',
    '194.36.55.0/24',
    '194.36.216.0/24',
    '194.36.217.0/24',
    '194.36.218.0/24',
    '194.36.219.0/24',
    '194.40.240.0/24',
    '194.40.241.0/24',
    '194.53.53.0/24',
    '194.59.5.0/24',
    '194.87.58.0/23',
    '194.113.223.0/24',
    '194.152.44.0/24',
    '194.169.194.0/24',
    '195.82.109.0/24',
    '195.85.23.0/24',
    '195.85.59.0/24',
    '195.137.167.0/24',
    '195.245.221.0/24',
    '195.250.46.0/24',
    '196.13.241.0/24',
    '196.207.45.0/24',
    '199.33.230.0/24',
    '199.33.231.0/24',
    '199.33.232.0/24',
    '199.33.233.0/24',
    '199.60.103.0/24',
    '199.181.197.0/24',
    '199.212.90.0/24',
    '202.82.250.0/24',
    '203.13.32.0/24',
    '203.17.126.0/24',
    '203.19.222.0/24',
    '203.22.223.0/24',
    '203.23.103.0/24',
    '203.23.104.0/24',
    '203.23.106.0/24',
    '203.24.102.0/24',
    '203.24.103.0/24',
    '203.24.108.0/24',
    '203.24.109.0/24',
    '203.28.8.0/24',
    '203.28.9.0/24',
    '203.29.52.0/24',
    '203.29.53.0/24',
    '203.29.54.0/23',
    '203.30.188.0/22',
    '203.32.120.0/23',
    '203.34.28.0/24',
    '203.34.80.0/24',
    '203.55.107.0/24',
    '203.89.5.0/24',
    '203.107.173.0/24',
    '203.193.21.0/24',
    '204.62.141.0/24',
    '204.68.111.0/24',
    '205.233.181.0/24',
    '206.196.23.0/24',
    '207.189.149.0/24',
    '208.100.60.0/24',
    '209.46.30.0/24',
    '212.24.127.0/24',
    '212.110.134.0/23',
    '212.239.86.0/24',
    '216.116.134.0/24',
    '216.120.180.0/23',
    '216.154.208.0/20',
    '223.27.176.0/23'
]

# 过滤掉要删除的IP地址段
filtered_ip_addresses = []
for ip in ip_addresses:
    is_in_ranges = False
    for ip_range in ip_ranges_to_delete:
        if ipaddress.IPv4Address(ip) in ipaddress.IPv4Network(ip_range, strict=False):
            is_in_ranges = True
            break
    if not is_in_ranges:
        filtered_ip_addresses.append(ip)

# 追加解析后的IP到输出文件
try:
    with open(output_file, 'a') as f:  # 使用 'a' 模式以追加方式打开文件
        for ip in filtered_ip_addresses:
            f.write(ip + '\n')
except FileNotFoundError:
    print(f"找不到文件 {output_file}")
else:
    print(f"解析完成，IP地址已追加到 {output_file}")