### 创建SSH密钥脚本
```shell
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/create_ssh_key.sh)"
```

或者使用两步过程：
```shell
curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/create_ssh_key.sh -o create_ssh_key.sh && chmod +x create_ssh_key.sh && ./create_ssh_key.sh
```


### 001-autodisk.sh   磁盘自动挂载(来自宝塔的自动挂载磁盘脚本)
```shell
wget -N https://raw.githubusercontent.com/liwoyuandiane/001-note/main/autodisk.sh && chmod +x autodisk.sh && bash autodisk.sh
```

### cfddns脚本
```shell
wget -N https://raw.githubusercontent.com/liwoyuandiane/001-note/main/cfddns.sh && chmod +x cfddns.sh && bash cfddns.sh
```

