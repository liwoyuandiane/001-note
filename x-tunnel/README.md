# suoha x-tunnel

一个使用 Cloudflare Argo Quick Tunnel 的快速隧道管理脚本，支持自动化部署和管理 x-tunnel 服务。

## 项目简介

本项目提供了一套完整的 Linux 服务器隧道解决方案，通过 Cloudflare Argo Quick Tunnel 技术快速创建安全的隧道连接。脚本支持多种 Linux 发行版和 CPU 架构，能够自动下载和配置所需的二进制文件，并提供灵活的代理选项。

### 核心特性

- **一键部署**: 自动化安装和配置，无需手动操作
- **多平台支持**: 支持 Debian、Ubuntu、CentOS、Fedora、Alpine 等主流 Linux 发行版
- **多架构支持**: 支持 x86_64、i386、arm64 等 CPU 架构
- **Opera 代理**: 可选使用 Opera 代理作为前置代理，提供额外的匿名性
- **双重模式**: 支持交互式菜单和命令行参数两种操作方式
- **自动端口分配**: 智能分配可用端口，避免端口冲突
- **状态监控**: 实时查看服务运行状态
- **三种隧道模式**: Quick Tunnel、固定隧道、API 自动创建模式
- **完全自动化**: API 模式支持一键创建隧道、配置 ingress、绑定域名

## 功能说明

### 1. 隧道模式

脚本支持三种隧道模式，各有不同特点：

#### Quick Tunnel 模式 (梭哈模式)

使用 Cloudflare Argo Quick Tunnel 自动创建临时隧道连接：

- **特点**: 无需预先配置域名，随机分配域名
- **适用场景**: 临时测试、快速验证
- **持久性**: 服务重启或脚本再次运行后失效
- **优势**: 最简单快捷，无需任何额外配置
- **劣势**: 域名随机，无法自定义

#### 固定隧道模式

使用预先在 Cloudflare 后台创建的固定隧道：

- **特点**: 需要在 Cloudflare 控制台手动创建隧道
- **适用场景**: 长期使用、需要固定域名
- **持久性**: 隧道永久存在，重启后无需重新创建
- **优势**: 可以在 Cloudflare 后台管理
- **劣势**: 需要手动创建和配置

#### API 自动创建模式 ⭐

使用 Cloudflare API 完全自动化创建和管理隧道：

- **特点**: 通过 API 自动创建隧道、配置 ingress、绑定域名
- **适用场景**: 自动化部署、批量管理、CI/CD 集成
- **持久性**: 隧道永久存在，重启后无需重新创建
- **优势**:
  - 完全自动化，无需手动操作
  - 支持自定义域名
  - 支持动态端口配置
  - 自动清理远程资源
  - 隧道信息本地持久化
- **劣势**: 需要配置 API Token 权限

### 2. 服务管理

- **启动服务**: 下载并配置所需的二进制文件，启动所有后台服务
- **停止服务**: 优雅地停止所有运行中的服务
- **清理缓存**: 停止服务并删除所有下载的二进制文件
- **状态查看**: 查看服务运行状态和文件存在情况

### 3. 代理选项

- **Opera 前置代理**: 可选启用 Opera 代理，支持北美 (AM)、亚太 (AS)、欧洲 (EU) 三个地区
- **IPv4/IPv6**: 选择 Cloudflare 连接使用的 IP 版本
- **Token 认证**: 可选设置 x-tunnel 身份令牌，增强安全性

### 4. API 自动创建模式详细说明

#### 前置准备

1. **获取 Cloudflare API Token**:
   - 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
   - 进入 `My Profile` → `API Tokens`
   - 点击 `Create Token` → `Create Custom Token`
   - 配置以下权限:
     ```
     Account:
       - Cloudflare Tunnel: Edit

     Zone:
       - DNS: Edit
       - Zone: Read

     Zone Resources:
       - Include → Specific zone → [选择你的域名]
     ```
   - 点击 `Continue to summary` → `Create Token`
   - 复制生成的 API Token

2. **获取 Zone ID**:
   - 在 Cloudflare Dashboard 选择你的域名
   - 在右侧边栏找到 `Zone ID`
   - 复制 Zone ID

3. **准备域名**:
   - 确保域名已添加到 Cloudflare
   - 选择或创建一个子域名用于隧道 (例如: `tunnel.example.com`)

#### 命令行使用

**基本命令**:
```bash
./suoha-x.sh install \
    -a "YOUR_API_TOKEN" \
    -z "YOUR_ZONE_ID" \
    -d "tunnel.example.com"
```

**完整参数示例**:
```bash
./suoha-x.sh install \
    -a "API_TOKEN" \
    -z "ZONE_ID" \
    -d "tunnel.example.com" \
    -n "my-x-tunnel" \
    -o 1 \
    -g AM \
    -c 4 \
    -x mytoken
```

**参数说明**:
- `-a`: Cloudflare API Token (必需)
- `-z`: Cloudflare Zone ID (必需)
- `-d`: 隧道域名 (必需)
- `-n`: 隧道名称 (可选，默认: x-tunnel-auto)
- `-o`: 是否启用 Opera 前置代理 (可选，默认: 0)
- `-g`: Opera 国家代码 (可选，默认: AM)
- `-c`: Cloudflare 连接模式 (可选，默认: 4)
- `-x`: x-tunnel 身份令牌 (可选)
- `-p`: 固定端口 (可选，默认随机分配)

#### 交互式使用

运行 `./suoha-x.sh`，选择选项 `2. API 自动创建模式`:

```bash
$ ./suoha-x.sh

========================================
       suoha x-tunnel 管理脚本
========================================

梭哈模式不需要自己提供域名，使用 CF ARGO QUICK TUNNEL 创建快速链接
梭哈模式在重启或者脚本再次运行后失效，如果需要使用需要再次运行创建

========================================

梭哈是一种智慧!!! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈...

1. 梭哈模式 (Quick Tunnel)
2. API 自动创建模式 (需要 API Token 和域名)
3. 固定隧道模式 (需要 Tunnel Token)
4. 停止服务
5. 清空缓存 (卸载)
6. 查看状态
0. 退出脚本

请选择模式 (默认1): 2
```

然后按照提示输入:
- Cloudflare API Token
- Zone ID
- 隧道域名
- 隧道名称 (可选)
- 其他配置选项

#### 清理资源

使用 API 模式创建的隧道，需要提供 API Token 和 Zone ID 来清理远程资源:

```bash
./suoha-x.sh remove -a "API_TOKEN" -z "ZONE_ID"
```

脚本会自动:
1. 停止所有服务
2. 删除 DNS 记录
3. 删除 Cloudflare Tunnel
4. 删除 credentials 文件
5. 删除隧道信息文件 (.tunnel_info)
6. 删除二进制文件

#### 工作流程

```
[用户输入 API Token, Zone ID, 域名]
           ↓
[获取 Account ID]
           ↓
[创建 Cloudflare Tunnel]
           ↓
[生成 Tunnel ID 和 Credentials]
           ↓
[更新 Tunnel Config]
[配置 Ingress: 域名 → 本地端口]
           ↓
[创建 DNS CNAME 记录]
[域名 → tunnel-id.cfargotunnel.com]
           ↓
[保存隧道信息到 .tunnel_info]
           ↓
[启动 cloudflared]
[使用生成的 Token 连接]
           ↓
[启动 x-tunnel]
[监听随机端口]
           ↓
[显示结果给用户]
```

#### 注意事项

1. **API Token 权限**: 确保包含 Tunnel 和 DNS 的 Edit 权限
2. **域名要求**: 域名必须在 Cloudflare 上托管
3. **端口管理**: x-tunnel 使用随机端口，无需预先配置
4. **信息持久化**: 隧道信息保存在 `.tunnel_info` 文件中
5. **清理资源**: 卸载时需要提供 API Token 和 Zone ID
6. **重复创建**: 再次运行会创建新隧道，旧隧道需要手动清理

## 使用方法

### 模式一：交互式模式

直接运行脚本，通过菜单选择操作：

```bash
./suoha-x.sh
```

进入交互式菜单后，根据提示选择相应操作：

- **1. 梭哈模式**: 安装并启动服务
- **2. 停止服务**: 停止所有运行中的服务
- **3. 清空缓存**: 卸载并删除所有文件
- **4. 查看状态**: 查看服务运行状态
- **0. 退出脚本**: 退出程序

#### 交互式模式示例

```bash
$ ./suoha-x.sh

========================================
       suoha x-tunnel 管理脚本
========================================

梭哈模式不需要自己提供域名，使用 CF ARGO QUICK TUNNEL 创建快速链接
梭哈模式在重启或者脚本再次运行后失效，如果需要使用需要再次运行创建

========================================

梭哈是一种智慧!!! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈! 梭哈...

1. 梭哈模式 (安装服务)
2. 停止服务
3. 清空缓存 (卸载)
4. 查看状态
0. 退出脚本

请选择模式 (默认1): 1
```

### 模式二：命令行参数模式

通过命令行参数直接执行操作，适合自动化脚本和批量部署。

#### 命令格式

```bash
./suoha-x.sh <command> [options]
```

#### 可用命令

| 命令 | 说明 |
|------|------|
| `install` | 安装并启动服务 |
| `stop` | 停止所有服务 |
| `remove` | 卸载并清理所有文件 |
| `status` | 查看服务状态 |
| `--help`, `-h` | 显示帮助信息 |

#### install 命令选项

| 选项 | 参数 | 说明 | 默认值 |
|------|------|------|--------|
| `-o` | `0` 或 `1` | 是否启用 Opera 前置代理 | `0` |
| `-c` | `4` 或 `6` | Cloudflare 连接模式 (IPv4/IPv6) | `4` |
| `-x` | `<token>` | x-tunnel 身份令牌 | 无 |
| `-g` | `AM`/`AS`/`EU` | Opera 国家代码 | `AM` |

## 参数详细说明

### -o Opera 前置代理

控制是否启用 Opera 代理作为前置代理。

- `0`: 不启用（默认）
- `1`: 启用

启用后，流量路径为：`Opera 代理 → x-tunnel → Cloudflare Argo Tunnel`

### -c Cloudflare 连接模式

选择 Cloudflare 连接使用的 IP 版本。

- `4`: 使用 IPv4（默认）
- `6`: 使用 IPv6

### -x x-tunnel Token

设置 x-tunnel 的身份令牌，用于访问控制。

- 不提供：无需认证即可访问
- 提供值：访问时需要提供此令牌

### -g Opera 国家代码

当启用 Opera 前置代理时，选择代理服务器的地区。

- `AM`: 北美地区（默认）
- `AS`: 亚太地区
- `EU`: 欧洲地区

## 示例命令

### 基本使用

#### 1. 一键安装（使用默认配置）

```bash
./suoha-x.sh install
```

#### 2. 启用 Opera 代理（北美地区）

```bash
./suoha-x.sh install -o 1 -g AM
```

#### 3. 使用 IPv6 连接

```bash
./suoha-x.sh install -c 6
```

#### 4. 设置 Token 认证

```bash
./suoha-x.sh install -x my-secret-token
```

#### 5. 完整配置示例

```bash
./suoha-x.sh install -o 1 -c 4 -g AS -x mytoken
```

此命令将：
- 启用 Opera 前置代理
- 使用 IPv4 连接
- 使用亚太地区的 Opera 代理
- 设置身份令牌为 "mytoken"

### API 自动创建模式

#### 1. 基本使用

```bash
./suoha-x.sh install -a "YOUR_API_TOKEN" -z "YOUR_ZONE_ID" -d "tunnel.example.com"
```

#### 2. 自定义隧道名称

```bash
./suoha-x.sh install \
    -a "API_TOKEN" \
    -z "ZONE_ID" \
    -d "tunnel.example.com" \
    -n "my-x-tunnel"
```

#### 3. 完整配置示例

```bash
./suoha-x.sh install \
    -a "API_TOKEN" \
    -z "ZONE_ID" \
    -d "tunnel.example.com" \
    -n "my-tunnel" \
    -o 1 \
    -g AM \
    -c 4 \
    -x mytoken
```

此命令将：
- 使用 API 自动创建隧道
- 绑定域名 tunnel.example.com
- 隧道名称为 my-tunnel
- 启用 Opera 前置代理（北美地区）
- 使用 IPv4 连接
- 设置 x-tunnel 身份令牌为 "mytoken"
- x-tunnel 使用随机端口

#### 4. 清理 API 创建的资源

```bash
./suoha-x.sh remove -a "API_TOKEN" -z "ZONE_ID"
```

此命令将：
- 停止所有服务
- 删除 DNS CNAME 记录
- 删除 Cloudflare Tunnel
- 删除本地文件

### 服务管理

#### 停止所有服务

```bash
./suoha-x.sh stop
```

#### 卸载清理

```bash
./suoha-x.sh remove
```

#### 查看状态

```bash
./suoha-x.sh status
```

输出示例：

```
========== 服务状态 =========
✓ x-tunnel 服务正在运行
✓ opera 服务正在运行
✓ argo 服务正在运行

========== 文件检查 =========
✓ cloudflared-linux 存在
✓ x-tunnel-linux 存在
✓ opera-linux 存在

✓ 所有服务正常运行
```

### 获取帮助

```bash
./suoha-x.sh --help
# 或
./suoha-x.sh -h
```

## 注意事项

### 1. 系统要求

- **操作系统**: Linux（Debian、Ubuntu、CentOS、Fedora、Alpine）
- **必需工具**: `screen`、`curl`、`lsof`
- **权限**: 需要 root 权限或 sudo 权限（用于安装依赖）
- **网络**: 需要访问外网，能够访问 GitHub 和 Cloudflare

### 2. 隧道持久性

梭哈模式创建的隧道是临时的，具有以下特点：

- **服务器重启后失效**: 重启后需要重新运行脚本
- **脚本重复运行后失效**: 再次运行脚本会创建新的隧道
- **域名动态分配**: 每次创建都会获得新的域名

### 3. Opera 代理限制

Opera 代理仅支持以下三个地区：

- `AM` (Americas): 北美地区
- `AS` (Asia): 亚太地区
- `EU` (Europe): 欧洲地区

### 4. 端口管理

脚本自动分配可用端口，端口范围从 1024 开始。如果遇到端口占用问题，脚本会自动尝试其他端口。

### 5. Screen 会话

所有服务都在 screen 会话中运行：

- `x-tunnel`: 主隧道服务
- `opera`: Opera 代理服务
- `argo`: Cloudflare Argo Tunnel 服务

可以使用 `screen -r <会话名>` 连接到特定会话查看日志：

```bash
screen -r x-tunnel
screen -r opera
screen -r argo
```

使用 `Ctrl+A` 然后按 `D` 退出会话而不停止服务。

### 6. 防火墙设置

确保服务器防火墙允许必要的端口访问：

- 如果使用 Cloudflare 隧道，通常不需要额外配置防火墙
- Opera 代理仅在本地监听（127.0.0.1），不需要对外开放
- Metrics 端口也是本地监听

## 常见问题

### Q1: 脚本运行提示权限不足怎么办？

**A**: 使用 sudo 运行脚本：

```bash
sudo ./suoha-x.sh install
```

### Q2: 如何查看服务的详细日志？

**A**: 连接到对应的 screen 会话查看日志：

```bash
# 查看 x-tunnel 日志
screen -r x-tunnel

# 查看 argo 日志
screen -r argo
```

退出会话但不停止服务：按 `Ctrl+A` 然后按 `D`

### Q3: 隧道创建失败怎么办？

**A**: 检查以下几点：

1. 确保网络连接正常，能够访问 GitHub 和 Cloudflare
2. 检查服务器防火墙设置
3. 查看服务日志：`screen -r argo`
4. 重新运行脚本：`./suoha-x.sh install`

### Q4: 如何更改配置后重新部署？

**A**: 直接重新运行 install 命令，脚本会自动停止旧服务并启动新配置：

```bash
./suoha-x.sh install -o 1 -c 4 -g EU
```

### Q5: 服务器重启后服务不会自动启动？

**A**: 是的，梭哈模式的隧道是临时的。需要重新运行脚本创建隧道：

```bash
./suoha-x.sh install
```

如果需要持久化，可以考虑使用 Cloudflare 的命名隧道（需要自行配置）。

### Q6: Opera 代理连接失败怎么办？

**A**: 尝试以下方法：

1. 更换 Opera 代理的地区：`./suoha-x.sh install -o 1 -g EU`
2. 禁用 Opera 代理：`./suoha-x.sh install -o 0`
3. 检查网络是否能够访问 Opera 代理服务器

### Q7: 如何查看隧道是否正常工作？

**A**: 运行状态命令：

```bash
./suoha-x.sh status
```

所有服务都应该显示"正在运行"。然后使用生成的域名和端口进行测试。

### Q8: 下载二进制文件失败怎么办？

**A**: 可能是网络问题或下载源不可用。可以：

1. 检查网络连接
2. 手动下载二进制文件到当前目录
3. 重试运行脚本

### Q9: 如何完全卸载脚本？

**A**: 运行清理命令：

```bash
./suoha-x.sh remove
```

然后手动删除脚本文件：

```bash
rm suoha-x.sh
```

### Q10: 可以同时运行多个隧道吗？

**A**: 当前版本的脚本设计为单隧道模式。如果需要多个隧道，需要修改脚本或使用不同的目录运行多个实例。

### Q11: API 自动创建模式需要什么权限？

**A**: Cloudflare API Token 需要以下权限：

```
Account:
  - Cloudflare Tunnel: Edit

Zone:
  - DNS: Edit
  - Zone: Read

Zone Resources:
  - Include → Specific zone → [选择你的域名]
```

在 Cloudflare Dashboard 的 API Tokens 页面创建 Custom Token 时配置这些权限。

### Q12: API 自动创建模式和固定隧道模式有什么区别？

**A**: 主要区别：

| 特性 | API 自动创建模式 | 固定隧道模式 |
|------|-----------------|-------------|
| 隧道创建 | 通过 API 自动创建 | 需要在 Cloudflare 后台手动创建 |
| 域名配置 | 自动绑定 DNS 记录 | 需要手动配置 DNS |
| 配置方式 | 命令行参数 | Cloudflare 后台 |
| 清理方式 | 自动清理远程资源 | 需要手动清理 |
| 适用场景 | 自动化部署、CI/CD | 手动管理、长期使用 |

### Q13: API 自动创建模式创建的隧道会失效吗？

**A**: 不会。API 自动创建模式创建的是永久隧道，不会因为服务器重启或脚本再次运行而失效。只有手动执行 `remove` 命令时才会删除。

### Q14: 如何查看 API 自动创建模式的隧道信息？

**A**: 隧道信息保存在 `.tunnel_info` 文件中，包含：
- tunnel_id
- hostname (域名)
- dns_record_id
- local_port (本地端口)
- tunnel_name (隧道名称)

可以查看这个文件获取详细信息。

### Q15: API 自动创建模式失败怎么办？

**A**: 检查以下几点：

1. 确认 API Token 权限是否正确
2. 确认 Zone ID 是否正确
3. 确认域名是否在 Cloudflare 上托管
4. 检查网络连接，确保能访问 Cloudflare API
5. 查看错误日志，根据提示排查问题
6. 检查域名是否已经被其他隧道使用

### Q16: 可以重复运行 API 自动创建模式吗？

**A**: 可以，但建议先清理旧隧道。重复运行会创建新的隧道，旧隧道需要手动清理：

```bash
# 清理旧隧道
./suoha-x.sh remove -a "API_TOKEN" -z "ZONE_ID"

# 创建新隧道
./suoha-x.sh install -a "API_TOKEN" -z "ZONE_ID" -d "new.example.com"
```

## 技术架构

### 服务组件

1. **Opera Proxy** (可选): 提供额外的匿名代理层
2. **x-tunnel**: WebSocket 到 SOCKS5 的转换器
3. **Cloudflared**: Cloudflare 官方隧道客户端

### 流量路径

```
[客户端] → [Cloudflare Argo Tunnel] → [x-tunnel] → [Opera Proxy] → [目标服务器]
```

如果禁用 Opera 代理，路径简化为：

```
[客户端] → [Cloudflare Argo Tunnel] → [x-tunnel] → [目标服务器]
```

### 依赖关系

- 所有服务使用 screen 管理，确保在 SSH 断开后继续运行
- cloudflared 会自动更新到最新版本
- 二进制文件根据 CPU 架构自动下载对应版本

## 许可证

本项目仅供学习和研究使用。

## 贡献

欢迎提交 Issue 和 Pull Request！

## 更新日志

### v3.1.0

- 改进错误处理: 为所有 API 调用添加详细的错误信息显示
- 优化 JSON 解析: 增强数据提取逻辑,添加额外的错误检查
- 添加 DNS 冲突检测: 创建 DNS 记录前检查是否已存在,避免重复创建
- 添加 curl 超时保护: 所有 API 调用设置 30 秒超时,防止长时间挂起
- 修复变量作用域问题: remove_all 函数正确处理 load_tunnel_info 返回值
- 优化 API 响应解析: 从 result 字段提取数据,提高可靠性
- 增强安全性: 移除 JSON 字段值中的空格,避免解析错误

### v3.0.0

- 新增 API 自动创建隧道模式，完全自动化隧道管理
- 支持 Cloudflare API 创建隧道、配置 ingress、绑定域名
- 新增隧道信息持久化功能（.tunnel_info 文件）
- 支持自动清理 API 创建的远程资源（DNS 记录、隧道）
- 新增命令行参数: -d (域名), -n (隧道名称)
- 扩展 remove 命令支持清理 API 创建的资源
- 交互式菜单增加 API 自动创建模式选项
- 完善文档，增加 API 模式使用说明和 FAQ

### v2.0.0

- 新增命令行参数模式支持
- 新增状态查看功能
- 优化错误处理和日志输出
- 添加帮助文档
- 改进代码结构和可维护性

### v1.0.0

- 初始版本
- 支持交互式菜单
- 基础隧道功能实现

## 联系方式

如有问题或建议，请通过 GitHub Issues 联系。
