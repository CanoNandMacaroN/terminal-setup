# terminal-setup

一套面向全新电脑的终端环境初始化工具。它会安装必要的命令行工具，用 chezmoi 把配置写入 Home，并通过软件清单持续维护环境。

默认配置公开、无凭据、可直接使用。GUI 应用、编辑器和 AI 工具不自动安装，你可以在基础终端环境完成后自行选择。

**[English](README_EN.md) · [安全策略中文版](SECURITY_ZH.md) · [维护边界](CONTRIBUTING_ZH.md)**

## 先选择你的使用方式

| 你的情况 | 从哪里开始 |
|---|---|
| 一台全新的 Mac，先使用本项目的通用配置 | [全新 Mac](#全新-mac从零安装) |
| 已经拥有自己的 chezmoi/dotfiles 仓库 | [恢复私人环境](#恢复你自己的-chezmoi-仓库) |
| Debian、Ubuntu、WSL 或 Linux 服务器 | [Linux/WSL](#debianubuntu-wsl-或-linux-服务器) |
| 只想看看脚本会做什么 | [安全预览](#先预览再安装) |

第一次使用 chezmoi，建议先按“全新 Mac”或“Linux/WSL”完成安装，再阅读后面的原理和日常维护章节。

## 全新 Mac：从零安装

这是推荐的新手路线。你不需要提前安装 Homebrew、chezmoi、Node.js 或逐个安装 CLI。

### 第 1 步：安装 Apple 命令行工具

打开系统自带的“终端”，运行：

```sh
xcode-select --install
```

macOS 会弹出安装窗口。等待它完全安装后，再执行下一步。这套工具提供 Git、Clang、make 和 macOS SDK；macOS 中的 `/usr/bin/gcc` 实际调用 Apple Clang，并不是 GNU GCC。

### 第 2 步：下载本项目

下面的地址已经是本仓库的真实地址，不需要替换：

```sh
git clone https://github.com/CanoNandMacaroN/terminal-setup.git
cd terminal-setup
```

### 第 3 步：先预览，再安装

先查看脚本准备执行的操作：

```sh
./setup.sh --dry-run
```

确认无误后正式安装：

```sh
./setup.sh
```

脚本会依次完成：

1. 检查 Xcode Command Line Tools。
2. 在缺少时调用 Homebrew 官方安装器。
3. 安装 Git、chezmoi 和通用命令行工具。
4. 把仓库中的 `starter/` 复制为本机 chezmoi 源状态。
5. 备份即将被 chezmoi 管理的已有配置。
6. 应用 Zsh、Git、Starship、Ghostty 等配置。
7. 根据 Brewfile 和 uv 清单补齐工具。
8. 通过 fnm 安装 Node LTS，再由 Corepack 启用 pnpm。
9. 使用 `chezmoi verify` 检查结果。

Homebrew 安装过程中可能要求确认或输入系统密码，这是官方安装器的正常行为。

### 第 4 步：进入新环境并检查

```sh
exec zsh -l
cd terminal-setup
./doctor.sh
```

看到 `Doctor passed` 就说明必需组件和 chezmoi 状态正常。个别可选工具未安装只会显示 warning，不一定代表安装失败。

安装完成后，你的 chezmoi 源目录位于：

```text
~/.local/share/chezmoi
```

它已经是一个本地 Git 仓库，但还没有绑定你的私人远程仓库。你可以先使用，等需要跨机器同步时再创建自己的私人 Git 仓库并添加 remote。

### 可选：一行启动

已经装好 Git 后，也可以让引导脚本在临时目录中下载并执行项目：

```sh
curl -fsSL https://raw.githubusercontent.com/CanoNandMacaroN/terminal-setup/main/bootstrap.sh \
  | sh -s -- https://github.com/CanoNandMacaroN/terminal-setup.git
```

这条命令适合熟悉管道脚本的用户。新手更推荐前面的“克隆、预览、安装”三步，因为可以先查看脚本内容和 dry run 结果。

## 恢复你自己的 chezmoi 仓库

如果你已经有私人 dotfiles 仓库，仍然先下载本项目：

```sh
git clone https://github.com/CanoNandMacaroN/terminal-setup.git
cd terminal-setup
```

然后把下面变量设置为你自己的仓库地址。这是本教程中必须由你提供的地址，因为公共项目无法知道你的私人仓库在哪里：

```sh
DOTFILES_REPO='git@github.com:你的账号/你的dotfiles仓库.git'
./setup.sh --repo "$DOTFILES_REPO"
```

如果私人仓库包含 age 密文，同时指定从密码管理器导出的 identity 文件：

```sh
DOTFILES_REPO='git@github.com:你的账号/你的dotfiles仓库.git'
AGE_KEY_FILE="$HOME/Downloads/key.txt"

./setup.sh \
  --repo "$DOTFILES_REPO" \
  --age-key-file "$AGE_KEY_FILE"
```

运行前应确认：

- `AGE_KEY_FILE` 指向的是 age identity，不是 SSH 私钥。
- identity 文件包含以 `AGE-SECRET-KEY-1` 开头的私钥行。
- 不要把 identity 放进 dotfiles 仓库。
- 不同机器的 SSH 私钥保持独立，不要通过 chezmoi 共用一把私钥。

脚本会把 identity 安装到 `~/.config/chezmoi/key.txt` 并设置为 `600` 权限，然后由 chezmoi 在 apply 时自动解密源状态。

如果只想使用 chezmoi 自己的最短恢复方式，也可以在手动准备好 chezmoi 和 age identity 后运行：

```sh
chezmoi init --apply git@github.com:你的账号/你的dotfiles仓库.git
```

这条短命令只负责 dotfiles；本项目的 `setup.sh --repo` 还会处理平台依赖、软件清单、备份、Node/pnpm 和最终验证。

## Debian、Ubuntu、WSL 或 Linux 服务器

服务器需要先具备下载本仓库所需的三个基础包：

```sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
```

然后使用真实仓库地址安装：

```sh
git clone https://github.com/CanoNandMacaroN/terminal-setup.git
cd terminal-setup
./server-setup.sh --dry-run
./server-setup.sh
```

最后进入 Zsh 并检查：

```sh
exec zsh -l
cd terminal-setup
./doctor.sh
```

服务器流程会通过 apt 安装基础终端工具，并安装 chezmoi、uv、Starship 和 fnm。它默认尝试把 Zsh 设置为登录 Shell。

容器、学校服务器或受限账号不允许修改登录 Shell 时，使用：

```sh
./server-setup.sh --skip-shell-change
```

这不会修改账号的登录 Shell，但当前 starter 只提供 Zsh 交互配置。需要时可以手动运行 `zsh`；本版本没有 Bash 配置层。

恢复自己的跨平台仓库时：

```sh
DOTFILES_REPO='git@github.com:你的账号/你的dotfiles仓库.git'
./server-setup.sh --repo "$DOTFILES_REPO"
```

私人仓库必须自行用 chezmoi 模板和 `.chezmoiignore` 区分 macOS/Linux；macOS Cask 不能直接用于 Linux。

## 先预览再安装

公共 starter 可以完整预览：

```sh
./setup.sh --dry-run
./server-setup.sh --dry-run
```

Dry run 不创建 chezmoi 源目录，也不修改 Home。

使用 `--repo` 恢复尚未下载的私人仓库时，dry run 无法预览仓库内部内容，因为脚本不会为了预览而克隆私人仓库。可以先手动审查仓库，或先在临时环境中测试。

## 安装完成后有什么

| 能力 | macOS | Linux/WSL |
|---|---|---|
| Zsh、Starship、fzf、zoxide | 是 | 是 |
| Git、chezmoi、jq、ripgrep、fd、bat | 是 | 是 |
| fnm 管理的 Node LTS、Corepack、pnpm | 是 | 是 |
| uv 与 uv 工具清单 | 是 | 是 |
| Homebrew Formula 清单 | 是 | 不应用 |
| SSH、rsync、tmux | 系统/可选 | 安装 |
| cmux/Ghostty 配置 | 保留 | cmux 忽略，Ghostty 配置保留 |
| GUI、Cask、AI 工具 | 不自动安装 | 不自动安装 |

### 终端与 CLI 选择

| 工具 | 作用 |
|---|---|
| Zsh + 少量插件 | 补全、历史前缀搜索、autosuggestions、syntax highlighting |
| Starship | Git、Node、Python 状态提示符 |
| fzf + fd + ripgrep | 历史、路径和内容搜索 |
| zoxide | 高频目录跳转 |
| lsd、bat | 更适合交互阅读的 `ls`/`cat` |
| Yazi、lazygit | 文件和 Git 的终端界面 |
| jq、jd、tlrc | JSON、结构化差异和示例式帮助 |
| fnm + Corepack | Node 版本和项目 pnpm 版本所有权 |
| uv | Python 工具和隔离运行环境 |

公共配置保留 cmux 和 Ghostty 的通用设置，但不安装应用。cmux 基于 Ghostty 的终端能力并增加工作区、分栏、端口和 agent 会话组织；它是可选工作流入口。

AI 工具同样只在文档中说明，不自动安装。Codex、OpenCode、CodeBuddy、CC Switch、ChatGPT、Cherry Studio 等可以自行添加。CC Switch 能管理和云同步的模型配置应继续由它负责；私人例外应进入启用了 age 的私人 chezmoi 仓库。

## 它是怎样工作的

```text
terminal-setup 安装器
  ├─ 准备当前平台的基础依赖
  ├─ 初始化公共 starter 或私人 chezmoi 仓库
  └─ 调用 chezmoi apply
          │
          ├─ 渲染 Shell/应用配置到 Home
          ├─ run_onchange 对齐 Brew/uv 清单
          └─ verify 检查目标状态
```

chezmoi 维护两个方向：

- **源状态**：通常位于 `~/.local/share/chezmoi`，由 Git 同步。
- **目标状态**：位于 Home，供 Shell 和应用直接读取。

常用操作方向如下：

| 目的 | 命令方向 |
|---|---|
| 把仓库配置写到 Home | `chezmoi apply` |
| 把 Home 中的新文件加入源状态 | `chezmoi add TARGET` |
| Home 已修改，更新已管理文件 | `chezmoi re-add TARGET` |
| 查看即将发生的变化 | `chezmoi diff` |
| 检查目标是否匹配源状态 | `chezmoi verify` |

### 使用的 chezmoi 特性

| 特性 | 在项目中的作用 |
|---|---|
| 属性命名 | `dot_`、`private_`、`encrypted_`、`executable_` 表达路径、权限、加密和执行位 |
| 模板 | 按 macOS/Linux、架构和 Home 路径渲染配置 |
| `.chezmoiignore` | 排除文档、缓存、运行状态和平台不适用目标 |
| `run_onchange` | 软件清单哈希变化时重新执行环境对齐 |
| age | 允许私人派生仓库只提交密文 |
| `status/diff/verify` | 应用前发现漂移，应用后验证结果 |

仓库根目录中的 README、License、测试和安装器不会被 apply 到 Home；只有 `starter/` 被用作公共 chezmoi 源状态。

## 为什么 `run_onchange` 能持续同步软件

脚本模板会把清单的 SHA-256 写入渲染结果：

```text
# Brewfile hash: {{ include "dot_Brewfile" | sha256sum }}
```

chezmoi 记录渲染后脚本的状态：

- 第一次 apply 没有运行记录，因此执行。
- 清单不变时渲染结果相同，因此跳过。
- 清单增加或删除条目后哈希变化，因此再次执行。

默认策略只补齐缺少的软件，不删除机器上的额外软件。确实要让机器严格匹配清单时，先检查清理范围，再显式运行：

```sh
./setup.sh --prune
```

服务器对应：

```sh
./server-setup.sh --prune
```

清理范围只包括 Brew Formula 和 uv 工具，不处理 Cask。

## Node 与 pnpm 的边界

```text
fnm → 安装和切换 Node
Corepack → 提供并选择 pnpm
node_modules/.pnpm → 当前项目的依赖布局
pnpm store → 可重建的内容寻址缓存
PNPM_HOME → pnpm 全局命令目录
```

chezmoi 只同步声明和 Shell 初始化，不同步 Node 安装目录、pnpm store、缓存或项目依赖。

## 可选的 age 加密

公共仓库不包含 recipient、identity 或示例密文。在你自己的私人 chezmoi 源目录中启用：

```sh
./scripts/enable-age.sh
./scripts/add-secret.sh ~/.ssh/config
```

`encryption = "age"` 只选择加密后端，不会自动判断哪个文件敏感。敏感目标必须明确使用 `--encrypt` 或 `add-secret.sh` 加入。

`private_` 只控制 Home 中的权限；只有 `encrypted_*.age` 才表示 Git 中保存的是密文。Home 中的目标仍是应用可读的明文。

## 日常维护

检查状态：

```sh
./doctor.sh
chezmoi status
chezmoi diff
```

预览并应用配置变化：

```sh
chezmoi apply --dry-run --verbose
chezmoi apply
chezmoi verify
```

把本机顶层 Formula 和 uv 工具写回清单：

```sh
env-sync "chore: sync package manifests"
```

macOS 不采集 Tap/Cask；Linux/WSL 只采集 uv。该函数只暂存对应清单，有未推送提交时会停止，无变化时不会创建空提交。

安装器的完整公开选项：

```text
--repo URL            使用已有 chezmoi 仓库
--age-key-file PATH   导入 age identity
--prune               清理清单外 Formula/uv 工具，不处理 Cask
--skip-shell-change   不修改登录 Shell
--dry-run             只预览
```

## 完整恢复备份

```sh
./scripts/full-backup.sh /path/to/private/backup-directory
```

归档包含完整源目录与 Git 状态、解密后的 managed targets、本机 chezmoi 配置、age identity、状态快照和 SHA-256 清单。

它故意不加密，只能保存到私人 NAS、离线磁盘或其他受控位置，绝不能上传到公共仓库。

## 公共仓库安全边界

不得发布 age/SSH 私钥、私人仓库地址、主机清单、实验室地址、Clash 节点或订阅、Token、Cookie、OAuth 状态、模型凭据、NAS 信息和个人绝对路径。

发布前运行：

```sh
./tests/test.sh
git diff --cached --check
```

测试覆盖 Shell 语法、平台检测、模板渲染、隔离 apply、清单安全、age、完整备份、安装预览和敏感信息扫描。

## 项目结构

```text
terminal-setup/
├── setup.sh                 # macOS/Linux 主安装器
├── server-setup.sh          # Linux/WSL 入口
├── bootstrap.sh             # 临时克隆并执行安装器
├── doctor.sh                # 安装后的健康检查
├── lib/                     # 平台检测和公共函数
├── scripts/                 # age 与完整备份工具
├── starter/                 # 公共 chezmoi 源状态
└── tests/                   # 隔离测试与安全检查
```

## 致谢与许可

新手文档结构参考了 [lewislulu/terminal-setup](https://github.com/lewislulu/terminal-setup)。安装、配置、清单、age、备份和服务器实现均为独立代码，不依赖参考仓库。

MIT License。
