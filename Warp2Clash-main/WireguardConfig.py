import csv
import sys

# 获取命令行参数
private_key = sys.argv[1]
public_key = sys.argv[2]

if len(sys.argv) >= 4:
    ipv6 = sys.argv[3]

def process_csv(file_path):
    with open(file_path, 'r') as file:
        reader = csv.reader(file)

        next(reader)

        with open('Warp2Clash.yaml', 'w') as output_file:
            for i, row in enumerate(reader, start=1):
                ip_port = row[0].strip()
                ip, port = ip_port.split(":")
                warp_name = f"Warp{i:02d}"
                
                if len(sys.argv) >= 4:
                    new_line = f"- name: {warp_name}\n  type: wireguard\n  server: {ip}\n  port: {port}\n  ip: 172.16.0.2\n  ipv6: {ipv6}\n  private-key: {private_key}\n  public-key: {public_key}\n  udp: true\n  mtu: 1280\n  remote-dns-resolve: true\n  dns: [ 1.1.1.1, 1.0.0.1 ]\n\n"
                else:
                    new_line = f"- name: {warp_name}\n  type: wireguard\n  server: {ip}\n  port: {port}\n  ip: 172.16.0.2\n  private-key: {private_key}\n  public-key: {public_key}\n  udp: true\n  mtu: 1280\n  remote-dns-resolve: true\n  dns: [ 1.1.1.1, 1.0.0.1 ]\n\n"
                
                output_file.write(new_line)

    print("结果已保存到 Warp2Clash.yaml 文件")

file_path = 'result.csv'

process_csv(file_path)
