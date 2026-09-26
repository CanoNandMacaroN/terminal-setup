# 可选服务器存储与备份服务

[返回主文档](../README.md#server-services) · [English](README_EN.md)

把服务器的共享存储、本地工作区和数据盘统一起来，提供工作副本同步、快照、数据备份和可选定时任务。普通用户即可安装；不会挂载磁盘、安装系统软件，也不会随终端基础环境自动启用。

## 1. 配置并安装

需要 Linux/WSL、Python 3.11+、rsync，以及已经可以访问的共享盘和本地数据盘。终端工具未准备好时，先运行仓库根目录的 `./server-setup.sh --user-only`。

在仓库根目录复制配置：

```sh
cp -n server-services/config.example.toml "$HOME/server-services.toml"
```

编辑 `~/server-services.toml`，填写**这台服务器实际可写的路径**：

| 字段 | 填写内容 |
|---|---|
| `shared_mount` / `shared_root` | 已挂载的共享盘挂载点，以及盘上的个人目录 |
| `data_mount` / `data_root` | 已挂载的本地数据盘挂载点，以及盘上的个人目录 |
| `local_root` | 本地工作区，默认 `~/local` |
| `links_root` | 存储快捷入口，默认 `~/storage` |
| `instance` | 本机备份名称，例如 `server-01`；不同机器使用不同名称 |

路径支持 `~`、`$HOME`、`$USER`，不执行 Shell 代码。四个功能根目录必须互不包含，不能经过符号链接，且必须由当前用户拥有、不可由其他用户写入。挂载点到个人目录之间的每一级也不能由其他用户写入；多人可写的挂载点须由 root 或当前用户拥有并设置 sticky bit。默认检查挂载点，避免磁盘未挂载时把数据误写到系统盘；使用普通目录测试时才将 `require_mounts` 改为 `false`。

预览、确认路径后安装：

```sh
./server-setup.sh --services --config "$HOME/server-services.toml" --dry-run
./server-setup.sh --services --config "$HOME/server-services.toml"
```

也可以直接运行 `./server-services/setup.sh --config "$HOME/server-services.toml"`。该入口只安装存储模块，不重新安装终端基础环境。

安装后：

- 命令：`~/.local/bin/server-services` 和 `~/.local/bin/server-maintenance`，不依赖原仓库位置。
- 配置：`~/.config/terminal-setup/server-services.toml`。
- 创建必要目录和链接；已存在的真实目录或不同目标的链接会报错，不会被覆盖。
- 不自动拉取数据，不自动启用定时任务。从仓库重复运行安装入口可更新两个命令；覆盖模块配置或程序前保留旧文件到 `~/.local/state/terminal-setup/server-services/install-backups/`。

如果命令暂时不在 PATH，先使用完整路径 `~/.local/bin/server-services`。

## 2. 文件放在哪里

```text
~/local/                    本地工作区
├── code/ tasks/    与共享盘同名目录手动 pull/push
└── scripts/ docs/          本地为主，快照到共享盘

~/storage/                  仅提供快捷链接
├── code/ tasks/    → 共享盘主库
├── backups/ env/ logs/     → 共享盘对应目录
├── dataset/               → 共享盘数据集；备份按 instance/input、output 分开
└── data/
    ├── input/             → 本地数据盘：原始输入
    ├── output/            → 本地数据盘：处理产物
    └── scratch/           → 本地数据盘：临时处理，不备份
```

大规模下载和处理在本地数据盘完成，再备份产物到共享盘。Shell、工具清单和账号配置继续由现有终端/私人 dotfiles 流程管理。

## 3. 日常使用

```sh
# 查看两个方向将发生的变化，不写文件
server-services status

# 开始工作前：共享主库 → 本地工作副本
server-services pull --dry-run
server-services pull

# 完成工作后：本地工作副本 → 共享主库
server-services push --dry-run
server-services push

# scripts/docs 快照；默认保留最近 10 代
server-services snapshot

# 数据盘 input/output → 共享盘 dataset/<instance>/
server-services backup-data --dry-run
server-services backup-data
```

默认同步新增和修改文件，**不删除接收端独有文件**。被覆盖的旧版本会进入回收目录：pull 使用 `~/local/.sync-trash/`，push 和数据备份使用共享盘 `backups/server-services/<instance>/trash/`。

确实需要镜像删除时，先预览再加 `--mirror`：

```sh
server-services push --mirror --dry-run
server-services push --mirror
```

镜像删除的文件也会进入回收目录。空源默认拒绝镜像；只有确认各源目录为空是预期行为时才加 `--allow-empty`。回收目录不自动清理，应定期检查占用。

pull/push 是有方向的 rsync，不是冲突合并。跨服务器编辑同一文件时，先 pull，再编辑，结束后 push；代码仍建议使用 Git。共享锁阻止本模块的同步任务同时写入，不能锁住编辑器或外部 rsync。

## 4. 可选定时备份

```sh
# 查看将安装的用户级 unit
server-services enable-timer --dry-run
server-services enable-timer

systemctl --user list-timers terminal-setup-backup.timer
journalctl --user -u terminal-setup-backup.service

# 停止后续定时触发，保留数据与 unit 文件
server-services disable-timer
```

默认每天执行 `server-services backup`，只快照 scripts/docs。需要同时备份 input/output 时，编辑已安装配置，把 `include_data = true`；修改 `calendar` 后重新执行 `enable-timer`。定时任务不会自动 pull/push，也不执行镜像删除。

没有可用的 `systemd --user` 时，直接运行 `server-services backup`，或交给已有调度器。登出后是否继续运行取决于服务器已有的用户服务/linger 策略，本模块不修改系统策略；`Persistent=true` 会在用户服务再次运行后补触发错过的任务。

## 5. 换服务器与恢复

1. 在新服务器取得本仓库、准备终端工具和已有挂载。
2. 复制自己的配置，修改本机路径和 `instance`，重新执行第 1 节安装命令。
3. `server-services pull --dry-run` 检查后拉取共享主库。旧服务器应先 push 完成的工作。
4. 旧机 scripts/docs 在共享盘 `backups/server-services/<旧 instance>/snapshots/latest/`。先恢复到单独目录检查，例如：

   ```sh
   rsync -a "$HOME/storage/backups/server-services/server-01/snapshots/latest/docs/" "$HOME/recovered-docs/"
   ```

快照里的内容直接是 `scripts/`、`docs/`，不包含旧机器的完整绝对路径。未变化的文件通过硬链接复用；只清理本模块标记的、已完成且超过保留代数的快照。失败的 `.partial` 目录不会替换 `latest`，可查明错误后手动清理。

已有旧布局的共享 `code/tasks` 可以直接复用；旧 dataset/input/output 和旧快照不移动、不删除，新数据备份写入按 `instance` 分开的目录。自己的运维文档可放入本机 `local/docs`；私人资料不提交到公共仓库。

## 6. 常见问题

| 报错 | 处理 |
|---|---|
| `Storage is not mounted` | 检查实际挂载点与配置；不要为绕过未挂载问题而关闭检查 |
| 链接位置已有真实目录/其他链接 | 先检查其中数据并自行移到合适位置，再重新安装 |
| `Storage is locked` | pull/push 查看共享根目录的锁；快照/备份查看 `backups/server-services/<instance>/` 下的锁。确认记录的主机进程已停止后再手动移除遗留锁 |
| rsync 返回非零状态 | 修复权限、配额或网络后重试；错误会传播到 CLI / systemd，不会被忽略 |
| `systemctl --user` 不可用 | 用手动命令或已有调度器，不需要改系统服务 |

## 7. Codex / CodeBuddy 运行数据维护

可以独立运行仓库里的脚本，无需先配置存储盘：

```sh
# 默认仅预览，不修改文件
./server-services/maintenance.sh codex
./server-services/maintenance.sh codebuddy

# 完全退出对应客户端、断开远程会话后，归档日志和临时数据
./server-services/maintenance.sh codex --apply
./server-services/maintenance.sh codebuddy --apply

# 确实需要时，再包含所列会话历史文件/目录
./server-services/maintenance.sh codex --include-history --apply
```

安装存储模块后也可以使用 `~/.local/bin/server-maintenance`。脚本不会停止进程；执行归档或恢复前会检查当前用户的相关客户端进程，发现仍在运行就退出。

| 客户端 | 默认归档 | `--include-history` 额外归档 |
|---|---|---|
| Codex | `log`、`cache`、`tmp`、`shell_snapshots` | `sessions`、`archived_sessions`、`history.jsonl`、`session_index.jsonl` |
| CodeBuddy | 服务端 `data/logs` 和顶层 `.log` 文件 | 编辑历史、工作区状态、扩展对话/消息队列和 `expert-history.json` |

配置、登录凭据、插件、数据库、工作树均不修改。**这不是完整的应用重置**：数据库里的历史索引或桌面列表可能仍存在；需要清空这些内容时使用应用自身功能。

归档保存在各应用目录的 `.terminal-setup-archives/<时间戳>/`，脚本会输出具体位置。恢复前同样退出客户端，并用该位置替换下面路径：

```sh
./server-services/maintenance.sh restore --archive /path/to/printed/archive
./server-services/maintenance.sh restore --archive /path/to/printed/archive --apply
```

若应用已经产生同名新数据，恢复会停止；先自行保留并移开新数据再重试。支持服务器上的 `CODEX_HOME`、`CODEBUDDY_HOME` 和 `CODEBUDDY_SERVER_HOME` 环境变量；拒绝符号链接路径。不处理桌面端 macOS 数据，不卸载工具链。

运行测试：

```sh
python3 server-services/test_service.py
python3 server-services/test_maintenance.py
```

测试使用临时 HOME/存储、真实 rsync 和替代的进程/服务检查，不会归档当前账号的客户端数据，也不会启用真实服务。
