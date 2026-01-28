# Ubuntu Web Terminal

基于 Ubuntu 22.04 的 Web 终端，使用 ttyd 提供 Web 访问。

## 功能特性

- 🐧 基于 Ubuntu 22.04（工具更丰富）
- 💻 通过浏览器访问完整 Linux 终端
- 🔐 强制密码认证（安全要求）
- 📦 轻量化镜像，快速部署
- 🏗️ 自动检测架构（支持 x86_64 和 ARM64）
- 🔧 支持自定义脚本执行（带参数）
- 📝 简洁的日志输出

## 部署到 Hugging Face Spaces

### ⚠️ 重要提示

**必须设置密码环境变量**，否则容器无法启动！这是安全要求，防止公开访问。

### 设置密码环境变量

在 Hugging Face Spaces 的 **Settings** → **Variables and secrets** 中添加环境变量：

**变量名**: `TTYD_CREDENTIAL`  
**格式**: `用户名:密码`

**示例**:
- `admin:MySecurePassword123!`
- `user:StrongP@ssw0rd`

设置后，访问终端时需要输入用户名和密码进行认证。

## 使用方法

### 1. 访问 Hugging Face Spaces 链接

直接访问你的 Space 链接，如果设置了密码会弹出认证对话框。

### 2. 输入用户名和密码

输入格式：`用户名:密码`（例如：`admin:MySecurePassword123!`）

### 3. 开始使用 Debian 终端

认证成功后，即可开始使用完整的 Linux 终端。

## 技术栈

- **基础镜像**: ubuntu:22.04
- **Web 终端**: ttyd v1.7.7
- **认证方式**: HTTP Basic Authentication
- **终端类型**: xterm-256color

## 环境变量配置

### 必需变量

| 变量名 | 用途 | 是否必需 | 示例值 |
|---------|------|----------|--------|
| `TTYD_CREDENTIAL` | ttyd 密码认证 | ✅ 是 | `admin:MySecurePassword123!` |

### 可选变量

| 变量名 | 用途 | 是否必需 | 示例值 |
|---------|------|----------|--------|
| `url_sh` | 脚本下载地址 | ❌ 否 | `https://www.baipiao.eu.org/xtunnel/suoha-x.sh` |
| `home` | 工作目录 | ❌ 否 | `/root/x-tunnel/` |
| `script_args` | 脚本执行参数 | ❌ 否 | `install -e` 或 `--token=xxx` |

### 环境变量说明

#### TTYD_CREDENTIAL（必需）

**用途**: 设置 ttyd 的密码认证，保护终端访问安全。

**设置方法**:
1. 进入 Hugging Face Space
2. 点击 **Settings** 标签
3. 选择 **Variables and secrets**
4. 点击 **New variable** 按钮
5. 填写：
   - **Name**: `TTYD_CREDENTIAL`
   - **Value**: `用户名:密码`（例如：`admin:MySecurePassword123!`）
6. 点击 **Save** 保存

**格式要求**:
- 必须使用冒号分隔用户名和密码
- 示例：`admin:MySecurePassword123!`

#### url_sh（可选）

**用途**: 指定要下载并执行的脚本地址。

**使用场景**:
- 下载单个脚本（如隧道脚本、代理脚本等）
- 脚本会自动下载到 `$home` 目录

**设置方法**:
1. 在 **Variables and secrets** 中添加新变量
2. **Name**: `url_sh`
3. **Value**: 脚本的完整 URL（例如：`https://example.com/script.sh`）

**注意事项**:
- URL 必须是有效的 HTTP/HTTPS 地址
- 脚本会自动从 URL 中提取文件名
- 下载的脚本会保存到 `$home` 目录

#### home（可选）

**用途**: 指定脚本的工作目录。

**使用场景**:
- 当需要执行多个脚本时，可以提前准备脚本文件
- 与 `url_sh` 配合使用

**设置方法**:
1. 在 **Variables and secrets** 中添加新变量
2. **Name**: `home`
3. **Value**: 工作目录路径（例如：`/root/x-tunnel/`）

**注意事项**:
- 目录路径必须以 `/` 开头
- 如果目录不存在会自动创建
- 建议使用绝对路径

#### script_args（可选）

**用途**: 传递参数给下载的脚本。

**使用场景**:
- 脚本需要参数才能正常运行（如安装模式、令牌等）
- 支持各种参数格式

**设置方法**:
1. 在 **Variables and secrets** 中添加新变量
2. **Name**: `script_args`
3. **Value**: 脚本参数（例如：`install -e` 或 `--token=xxx`）

**注意事项**:
- 参数会传递给所有下载的脚本
- 如果不设置此变量，脚本将无参数执行
- 支持多个参数（空格分隔）

## 使用场景

### 场景 1：默认使用（不设置可选变量）

**环境变量设置**:
- `TTYD_CREDENTIAL`: `admin:MySecurePassword123!`
- 其他变量：未设置

**执行流程**:
1. 容器启动
2. 直接启动 ttyd 服务
3. 不下载任何脚本
4. 提供纯净的 Debian 终端访问

### 场景 2：下载并执行单个脚本

**环境变量设置**:
```
TTYD_CREDENTIAL=admin:MySecurePassword123!
url_sh=https://www.baipiao.eu.org/xtunnel/suoha-x.sh
home=/root/x-tunnel/
```

**执行流程**:
1. 创建工作目录：`/root/x-tunnel/`
2. 下载脚本：从 `url_sh` 下载 `suoha-x.sh`
3. 启动 ttyd 服务（后台运行）
4. 等待 ttyd 启动完成
5. 执行脚本：运行 `suoha-x.sh`
6. 等待脚本执行完成

### 场景 3：下载并执行带参数的脚本

**环境变量设置**:
```
TTYD_CREDENTIAL=admin:MySecurePassword123!
url_sh=https://www.baipiao.eu.org/xtunnel/suoha-x.sh
home=/root/x-tunnel/
script_args=install -e
```

**执行流程**:
1. 创建工作目录：`/root/x-tunnel/`
2. 下载脚本：从 `url_sh` 下载 `suoha-x.sh`
3. 启动 ttyd 服务（后台运行）
4. 等待 ttyd 启动完成
5. 执行脚本：运行 `suoha-x.sh install -e`（带参数）
6. 等待脚本执行完成

### 场景 4：执行多个脚本

**环境变量设置**:
```
TTYD_CREDENTIAL=admin:MySecurePassword123!
url_sh=未设置
home=/root/scripts/
```

**执行流程**:
1. 创建工作目录：`/root/scripts/`
2. 不下载任何脚本（`url_sh` 未设置）
3. 启动 ttyd 服务（后台运行）
4. 遍历执行 `home` 目录下的所有 `.sh` 文件
5. 等待脚本执行完成

## 安全建议

- 🔒 必须设置密码环境变量，容器才能启动
- 🛡️ 使用强密码（至少 12 位，包含字母、数字和特殊字符）
- 🔄 定期更换密码
- 📝 不要在代码中硬编码密码

## 故障排查

### exec format error 错误

**错误信息**: `exec /usr/local/bin/ttyd: exec format error`

**原因**: ttyd 二进制文件与容器运行时架构不匹配

**解决方案**: 本项目已修复此问题，Dockerfile 会自动检测架构并下载对应版本：
- x86_64 架构：下载 `ttyd_linux.x86_64`
- ARM64 架构：下载 `ttyd_linux.aarch64`

如果仍然遇到此错误，请检查：
1. 容器运行时架构是否为 x86_64 或 ARM64
2. 网络连接是否正常，能否访问 GitHub
3. ttyd 版本 1.7.7 是否仍然可用

### 容器无法启动

**错误信息**: `错误: 必须设置 TTYD_CREDENTIAL 环境变量才能启动服务`

**原因**: 未设置密码环境变量

**解决方案**: 在 Hugging Face Spaces Settings 中添加 `TTYD_CREDENTIAL` 环境变量

### 认证失败

**问题**: 输入用户名和密码后仍然无法访问

**排查步骤**:
1. 确认环境变量格式正确：`用户名:密码`
2. 检查是否有空格或特殊字符
3. 尝试重新设置环境变量并重启 Space
4. 查看容器日志获取详细错误信息

## 可用工具

容器中预装了以下常用工具：

| 工具 | 用途 |
|------|------|
| `vim` | 文本编辑器 |
| `nano` | 轻量级文本编辑器 |
| `git` | 版本控制 |
| `htop` | 系统监控 |
| `iputils-ping` | 网络测试 |
| `net-tools` | 网络工具（ifconfig, netstat） |
| `sudo` | 权限管理 |
| `less` | 文件查看器 |
| `tree` | 目录树显示 |

## 许可证

MIT License
