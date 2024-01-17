# CloudFlareIPScan
白嫖总得来说不好，请不要公开传播，项目热度太高就删库


测试运行环境ubuntu-18.04-standard_18.04.1-1_amd64
``` bash
git clone "https://ghproxy.com/https://github.com/cmliu/CFIPS.git" && cd CFIPS && chmod +x CronJob.sh go.sh PMD.sh process_ip.py TestCloudFlareIP.py Pscan
```

后台运行,日志going.txt
``` bash
#默认测试443端口
nohup ./go.sh > going.txt 2>&1 &
#自定义测试2096端口
nohup ./go.sh 2096 > going.txt 2>&1 &
```

后台运行,telegramBot推送通知 [@CloudFlareIPScan_bot](https://t.me/CloudFlareIPScan_bot)
``` bash
nohup ./go.sh [port] [telegram UserId] > going.txt 2>&1 &
#例如
nohup ./go.sh 2096 712345678 > going.txt 2>&1 &
```

演示站点 [https://log.ssrc.cf](https://log.ssrc.cf)

定时任务或一键启动
``` bash
cd /CFIPS
#运行前一定要cd到脚本绝对路径下
./CronJob.sh
```

## 文件结构
运行脚本后会自动下载所需文件,所以推荐将脚本放在单独目录下运行
```
CFIPS
 ├─ ASN.zip             #AS库备份
 ├─ CloudFlareIP.txt    #扫描结果 汇总
 ├─ CronJob.sh          #定时启动这个脚本,将会自动对已扫过的端口IP库进行自动扫描并维护,定时任务如果需要TG推送请手动修改go.sh脚本内的telegramBotUserId和telegramBotToken
 ├─ go.sh               #脚本主体
 ├─ going.txt           #按上述运行方式会产生going.txt日志文件
 ├─ ip.txt              #单次扫描IP段产生的临时文件
 ├─ PMD.sh              #防止TestCloudFlareIP.py假死脚本
 ├─ process_ip.py       #将CIDR格式的IP段展开的python脚本
 ├─ Pscan               #端口扫描程序
 ├─ TestCloudFlareIP.py #验证是否是CFip的python脚本
 ├─ ip.zip              #扫描结束后自动打包扫描结果ip.zip
 ├─ ASN                 #扫描任务IP库,将需要扫描的IP段或IP写入txt文件后放入ASN文件夹即可,脚本运行就会自动扫描文件夹内的所有IP
 │   ├─ AS132203.txt
 │   ├─ AS31898.txt
 │  ...
 │   └─ AS45102.txt
 ├─ CloudFlareIP        #扫描结果 按AS整理存放
 │   ├─ AS132203.txt
 │   ├─ AS31898.txt
 │  ...
 │   └─ AS45102.txt
 ├─ php                 #一个简陋的前端,显示实时状态信息
 │   ├─ index.php
 │  ...
 │   
 ├─ ip                  #扫描结果 按地区整理存放
 │   ├─ HK-443.txt
 │   ├─ SG-443.txt
 │  ...
 │   └─ KR-443.txt
 └─ temp                #运行时产生的临时文件存放位置
     ├─ ip0.txt
     ├─ 80.txt
    ...
```
