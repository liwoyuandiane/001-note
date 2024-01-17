import requests
from concurrent.futures import ThreadPoolExecutor
import datetime
import sys

# 获取命令行参数
TestCFIPDet = int(sys.argv[1])
TestCFIPThreads = int(sys.argv[2])
InputPath = 'temp/{}.txt'.format(sys.argv[3])
httpport = [80, 8080, 8880, 2052, 2082, 2086, 2095]

# 检查是否有第4个参数，如果没有则port为443，如果有则port为第4个参数
port = int(sys.argv[4]) if len(sys.argv) > 4 else 443
asnname = 'CloudFlareIP/{}.txt'.format(sys.argv[3])

# 读取ip.txt中的每个IP地址并执行测试
def test_ip(ip):
    max_retries = TestCFIPDet  # 验证次数2~3
    retries = 0
    while retries < max_retries:
        try:
            response = requests.get(f"http://{ip}:{port}", headers={"Host": "testcfip.ssrc.cf"}, timeout=1, allow_redirects=False)
            #print(response.text)
            # 检查是否是301跳转并且Server是cloudflare
            if port in httpport and response.status_code == 301 and 'cloudflare' in response.headers.get('Server', '').lower():
                print(f"{datetime.datetime.now().strftime('[%Y-%m-%d %H:%M:%S]')} IP {ip}:{port} is CloudflareIP.")
                with open(f'{asnname}', 'a') as cf_file:
                    cf_file.write(f"{ip}\n")
            # 检查是否是400 或者301并且Server是cloudflare
            elif port not in httpport and (response.status_code == 400 or response.status_code == 301) and 'cloudflare' in response.headers.get('Server', '').lower():
                print(f"{datetime.datetime.now().strftime('[%Y-%m-%d %H:%M:%S]')} IP {ip}:{port} is CloudflareIP.")
                with open(f'{asnname}', 'a') as cf_file:
                    cf_file.write(f"{ip}\n")
            break  # 如果测试成功，退出循环
        except Exception as e:
            #print(f"IP {ip} 第 {retries + 1} 次测试出错: {str(e)}")
            retries += 1

#print("开始测试。")

# 使用多线程执行测试
with ThreadPoolExecutor(max_workers=TestCFIPThreads) as executor:  # 这里设置线程池的最大线程数
    with open(f'{InputPath}', 'r') as ip_file:
        ips = [ip.strip() for ip in ip_file]
        executor.map(test_ip, ips)

#print("测试完成。")
