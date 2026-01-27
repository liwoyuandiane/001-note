# Swap.sh — Linux VPS Swap Manager

描述
- 基于 Bash 的脚本，用于在 Linux VPS 上管理交换文件（Swap）。
- 支持添加、删除、查看 Swap；提供高级模式自定义路径。
- 保留默认路径 /swapfile，保持向后兼容。
- 提供备份/回滚机制、日志记录，以及对常见文件系统的基本适配。

版本与变更
- 当前版本：1.7
- 变更要点（1.7）：保持默认路径、加强路径校验、回滚、日志观测、测试覆盖的改进（向后兼容）

快速开始
- 环境要求
  - 需要 root 权限运行脚本
  - Bash 环境，依赖常用系统命令（free、dd、mkswap、swapon、swapoff 等）
  - 某些环境可能需要 BusyBox 的兼容性考虑

- 安装与准备
  - 将脚本设为可执行并运行
  ```bash
  chmod +x swap.sh
  sudo ./swap.sh
  ```

- 使用说明（主菜单）
  - 1：添加 Swap（默认 /swapfile）
  - 2：删除 Swap（支持自定义路径）
  - 3：查看 Swap 状态
  - 4：高级模式 – 指定完整路径添加
  - 0：退出

- 常见用例
  - 使用默认路径添加 Swap：选择 1
  - 使用自定义路径添加 Swap：选择 4，输入绝对路径，如 /vol1/swapfile
  - 删除 Swap：选择 2，输入要删除的 Swap 路径（如 /swapfile）
  - 查看状态：选择 3

一键运行脚本
- 直接从远程执行（风险提示：请确保环境可信且在测试环境验证通过后再在生产环境执行）
- 直接一键执行（快速但风险较高）:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/swap/swap.sh | bash
  ```
- 更安全的分步执行：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/liwoyuandiane/001-note/refs/heads/main/swap/swap.sh -o /tmp/swap.sh
  bash /tmp/swap.sh
  ```

核心特性
- 默认路径保留：/swapfile，保持向后兼容
- 高级模式：支持自定义绝对路径
- 路径校验：绝对路径、父目录存在性与写权限检查
- 安全性：修改 /etc/fstab 之前备份，启用后可回滚
- 权限管理：Swap 文件权限固定为 600
- 文件系统支持：对 ext4 等文件系统有适配，包含对 btrfs 的 COW 处理等
- 磁盘空间检查：创建前会评估可用空间，留出缓冲
- 日志观测：日志文件位置为 /var/log/swap_manager.log，便于审计
- 回滚机制： /etc/fstab 备份与回滚、创建失败清理等

路径与校验策略（设计要点）
- 输入必须为绝对路径（以 / 开头），空输入将触发错误
- 提取父目录；若为空或不可解析，将兜底为根目录 /，并提示
- 父目录存在且可写；不可写时给出替代建议（如 HOME、/vol1、/vol2）
- 目标路径若存在且为普通文件，需确认覆盖或备份
- 根目录不可写时，提供替代路径并引导重新选择
- 修改 /etc/fstab 时，先备份，失败时提供回滚方案

配置与自定义
- 脚本顶部包含默认常量，便于快速覆盖与定制：
  - DEFAULT_SWAP_PATH="/swapfile"
  - VERSION="1.7"
- 如需自定义行为，可在后续版本引入简单的配置文件或环境变量覆盖

安全性与稳健性
- Swap 文件权限 600
- /etc/fstab 的变更前备份，必要时可回滚
- 若出现异常，尝试回滚并清理创建的交换文件

测试与验证建议
- 静态分析：使用 shellcheck（若环境可用）
- 单元测试：对路径校验、目录可写性、是否为交换文件等进行测试
- 集成测试：默认路径创建、备份、回滚、fstab 更新与回滚
- 场景测试：根目录不可写、输入为空、包含空格的路径、权限不足等
- Dry-run：实现一个无风险的 Dry-run 模式以便安全测试

变更日志（示例）
- 1.7：保持默认路径、加强路径校验、回滚、日志观测、测试覆盖的改进（向后兼容）
- 其他历史变更请参考 AGENTS.md

目录结构
- swap.sh：主脚本（当前版本 1.7）
- README.md：本文件
