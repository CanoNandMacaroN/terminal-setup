# terminal-setup

一套面向全新电脑的终端环境初始化工具。它会安装必要的命令行工具，用 chezmoi 把配置写入 Home，并通过软件清单持续维护环境。

默认配置公开、无凭据、可直接使用。macOS 使用 Homebrew；Linux/WSL 和原生 Windows 使用 Pixi global。Linux 的 apt 只负责系统引导依赖，纯用户模式例外地复用 apt 已有命令。uv 专门管理 Python 工具，fnm 专门管理 Node.js。GUI、Cask、AI 客户端和专业工具只列为推荐，不自动安装。

**[English](README_EN.md) · [安全策略中文版](SECURITY_ZH.md) · [维护边界](CONTRIBUTING_ZH.md)**

## 先选择你的使用方式

| 你的情况 | 从哪里开始 |
|---|---|
| 一台全新的 Mac，先使用本项目的通用配置 | [全新 Mac](#全新-mac从零安装) |
| 已经拥有自己的 chezmoi/dotfiles 仓库 | [恢复私人环境](#恢复你自己的-chezmoi-仓库) |
| Debian、Ubuntu、WSL 或 Linux 服务器 | [Linux/WSL](#debianubuntu-wsl-或-linux-服务器) |
| 原生 Windows 与 PowerShell 7 | [原生 Windows](#原生-windows) |
| 只想看看脚本会做什么 | [安全预览](#先预览再安装) |

第一次使用 chezmoi，建议先按当前平台的 Mac、Linux/WSL 或原生 Windows 路线完成安装，再阅读后面的原理和日常维护章节。

## 全新 Mac：从零安装

这是推荐的新手路线。你不需要提前安装 Homebrew、chezmoi、Node.js 或逐个安装 CLI。

### 第 1 步：确认 Apple 命令行工具

打开系统自带的“终端”，运行：

```sh
xcode-select --install
```

macOS 会弹出安装窗口。等待它完全安装后，再执行下一步。这套工具提供 Git、Clang、make 和 macOS SDK；macOS 中的 `/usr/bin/gcc` 实际调用 Apple Clang，并不是 GNU GCC。

全新 Mac 需要先用这里提供的 Git 下载本项目，因此推荐在克隆前手动安装。如果你已经通过其他方式取得了本仓库，也可以直接运行 `./setup.sh`：脚本会检查 Xcode Command Line Tools，缺少时自动打开同一个 macOS 系统安装器，并提示你在安装完成后重新运行。

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

1. 检查 Xcode Command Line Tools；缺少时打开 macOS 系统安装器，并在安装完成前停止后续步骤。
2. 在缺少时调用 Homebrew 官方安装器。
3. 安装 Git、chezmoi 和通用命令行工具。
4. 把仓库中的 `starter/` 复制为本机 chezmoi 源状态。
5. 备份即将被 chezmoi 管理的已有配置。
6. 应用 Zsh、Git、Starship 等基础配置。
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

### 恢复 SSH 私钥并重建公钥

SSH 私钥不进入 chezmoi 或 Git。应从密码管理器、硬件密钥或受控离线备份单独恢复；如果你明确需要在新机器复用同一把私钥，可以在恢复私钥后重新导出对应公钥：

```sh
install -d -m 700 ~/.ssh
install -m 600 /path/from/password-manager/id_ed25519 ~/.ssh/id_ed25519
ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
chmod 644 ~/.ssh/id_ed25519.pub
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

`ssh-keygen -y` 只从私钥推导公钥，不会生成新身份。确认指纹后可载入该身份：

```sh
set-ssh-key id_ed25519
ssh-add -l
```

目标机器应保留自己的私钥时，则在该机器新建密钥并只登记新公钥；不要为了方便而把私钥加入公共 starter。

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

服务器流程只通过 apt 安装证书、Git、SSH、rsync、Zsh 和编译工具等系统引导依赖。随后把 Pixi 安装到 `~/.pixi`，由 Pixi global 安装 chezmoi、uv、Starship、fnm 和通用 CLI。它默认尝试把 Zsh 设置为登录 Shell。

如果账号不在 sudoers 中，或者管理员已经代装好系统依赖，可以使用纯用户模式：

```sh
./server-setup.sh --user-only
```

纯用户模式不会调用 `sudo`，不会执行 `apt`，也不会修改登录 Shell。运行前只需确认 `curl` 和 `git` 已存在。安装器会写入本机标记 `~/.terminal-setup/reuse-apt`；后续 apply 会检查排除 `~/.pixi/bin` 后的实际命令，并用 `dpkg-query` 确认其是否由 apt 提供。已有且可执行的 apt 命令直接复用，Pixi 只在 Home 内补齐缺失的 CLI。之后以普通模式运行安装器会删除该标记，恢复 Pixi 统一管理。Zsh autosuggestions 和 syntax-highlighting 会从各自 Git 仓库的默认分支浅克隆到用户数据目录，不锁定 tag。

Pixi 和 conda-forge 下载会继承当前 Shell 的 `http_proxy`、`https_proxy` 和 `no_proxy`。受限网络应先导入可信代理再运行安装，不要关闭 TLS 校验。

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

私人仓库必须自行用 chezmoi 模板和 `.chezmoiignore` 区分 macOS、Linux 与 Windows；macOS Cask 不能直接用于其他平台。

## 原生 Windows

原生 Windows 使用 PowerShell 入口，不需要 WSL，也不使用 Homebrew。先通过已有 Git 或 GitHub ZIP 取得仓库，然后在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./setup.ps1 -DryRun
./setup.ps1
./doctor.ps1
```

`setup.ps1` 会调用 Pixi 官方 PowerShell 安装器，把 Pixi、Git、chezmoi 和通用 CLI 写入 `%USERPROFILE%\.pixi`，再应用 Git、Starship、Pixi、uv 和 PowerShell 配置。`tmux` 只在 Linux 安装；Windows 使用 PowerShell 7，本项目不尝试在原生 Windows 模拟 Zsh。

恢复私人仓库时使用：

```powershell
./setup.ps1 -Repo 'git@github.com:你的账号/你的dotfiles仓库.git'
```

存在 age 密文时还要传入 `-AgeKeyFile`。Windows 会使用 `chezmoi apply --exclude scripts` 避免执行 Unix Shell 钩子，然后显式调用受管的 `~/.myshell/bin/sync-tools.ps1`。日常手动应用也应保持这个顺序：

```powershell
chezmoi apply --exclude scripts
& "$HOME/.myshell/bin/sync-tools.ps1"
chezmoi verify --exclude scripts
```

当前 Windows 流程不自动安装字体。Starship 图标需要用户在 Windows Terminal 中选择已安装的 Nerd Font。

## 先预览再安装

公共 starter 可以完整预览：

```sh
./setup.sh --dry-run
./server-setup.sh --dry-run
```

Dry run 不创建 chezmoi 源目录，也不修改 Home。

使用 `--repo` 恢复尚未下载的私人仓库时，dry run 无法预览仓库内部内容，因为脚本不会为了预览而克隆私人仓库。可以先手动审查仓库，或先在临时环境中测试。

## 安装完成后有什么

| 能力 | macOS | Linux/WSL | 原生 Windows |
|---|---|---|---|
| 平台包管理器 | Homebrew | Pixi global；`--user-only` 可复用 apt 命令 | Pixi global |
| 系统引导依赖 | Xcode Command Line Tools | apt 或管理员预装 | PowerShell；仓库可由 Git/ZIP 获得 |
| 交互 Shell | Zsh | Zsh | PowerShell 7 |
| Starship、fzf、zoxide | 是 | 是 | 是 |
| Git、chezmoi、jq、ripgrep、fd、bat | 是 | 是 | 是 |
| fnm 管理的 Node LTS、Corepack、pnpm | 是 | 是 | 是 |
| uv 与 uv 工具清单 | 是 | 是 | 是 |
| 平台 CLI 清单 | Brewfile | Pixi 清单 | Pixi 清单 |
| MesloLGS Nerd Font | 自动安装 | 自动安装 | 手动选择已安装字体 |
| GUI、Cask、AI 工具 | 仅提供推荐 | 仅提供推荐 | 仅提供推荐 |

### 终端与 CLI 选择

| 工具 | 作用 |
|---|---|
| Zsh + 少量插件 | 补全、历史前缀搜索、autosuggestions、syntax highlighting |
| Starship | Git、Node、Python 状态提示符 |
| fzf + fd + ripgrep | 历史、路径和内容搜索 |
| zoxide | 高频目录跳转 |
| lsd/eza、bat | 更适合交互阅读的 `ls`/`cat`；macOS 用 lsd，Pixi 平台用 eza |
| Yazi、lazygit | 文件和 Git 的终端界面 |
| jq、jd、tlrc | JSON、结构化差异和示例式帮助 |
| fnm + Corepack | Node 版本和项目 pnpm 版本所有权 |
| uv | Python 工具和隔离运行环境 |

### Starship 与字体

当前 Starship 主题使用 Nerd Font 图标。macOS 和 Linux/WSL 都从固定版本下载并校验四个 `MesloLGS Nerd Font` 字体文件到当前用户的字体目录，不通过 Brew Cask 安装字体或应用。原生 Windows 暂不自动安装字体。终端应选择 `MesloLGS NF`/`MesloLGS Nerd Font`，否则提示符图标可能显示为方框。

`doctor.sh` 会检查字体文件是否存在。字体只影响显示，不改变 Shell、Git 或软件清单行为。

公共 starter 不下发 cmux、Ghostty、Codex、CodeBuddy、CC Switch 等具体应用的安装或配置。可选应用、专业 CLI 和 uv 工具保留在 [`recommendations/`](recommendations/README.md) 中，由用户按机器角色选择；账号、Token、模型供应商配置和应用状态应进入私人配置或由应用自身管理。

### 可选推荐清单

下面的项目只作为建议，不会被公共 starter 自动安装。需要跨机器自动恢复时，应把经过审核的项目加入自己的私人 Brewfile、Pixi 清单或 uv 清单。

**macOS 应用**

```sh
# 终端和工作区
brew install --cask ghostty
brew tap manaflow-ai/cmux && brew install --cask cmux

# AI 客户端和配置管理
brew install --cask codex
brew tap farion1231/ccswitch && brew install --cask cc-switch
brew tap stablyai/orca && brew install --cask orca

# 桌面和设备工具
brew install --cask keka monitorcontrol spotify switchhosts android-platform-tools
```

**专业 CLI**

```sh
# macOS
brew install herdr imagemagick poppler scrcpy wireguard-tools
brew tap tencent-codebuddy/tap
brew install tencent-codebuddy/tap/codebuddy-code

# Linux/WSL/Windows：先查询 conda-forge，再加入私人 Pixi 清单
pixi search imagemagick
pixi search poppler
pixi global install --environment imagemagick imagemagick
pixi global install --environment poppler poppler
```

Pixi 只能安装 conda-forge 已收录且支持当前平台的包。`herdr`、`scrcpy`、`wireguard-tools` 和 CodeBuddy 这类工具若查询不到，应使用上游官方安装方式，不要加入公共基线。

**可选 uv 工具**

```sh
uv tool install harlequin
uv tool install --python 3.10 \
  --with PyYAML==5.3.1 \
  --with ruamel-yaml==0.17.40 \
  determined==0.19.10
```

CodeBuddy、Codex、CC Switch 等 AI 工具的账号、Token、OAuth 会话和供应商配置不应进入公共仓库。

## 它是怎样工作的

```text
terminal-setup 安装器
  ├─ 准备当前平台的基础依赖
  ├─ 初始化公共 starter 或私人 chezmoi 仓库
  └─ 调用 chezmoi apply
          │
          ├─ 渲染 Shell/CLI 配置到 Home
          ├─ macOS: run_onchange 对齐 Brew/uv 清单
          ├─ Linux/WSL: run_onchange 对齐 Pixi/uv 清单
          └─ Windows: sync-tools.ps1 对齐 Pixi/uv 清单
              然后 verify 检查目标状态
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

## 软件清单的双向同步

Homebrew、Pixi 和 uv 清单同时有 Home 目标状态与 chezmoi 源状态：

| 清单 | Home 目标文件 | 公共 starter 源文件 |
|---|---|---|
| Homebrew | `~/.Brewfile` | `starter/dot_Brewfile` |
| Pixi CLI | `~/.myshell/pixi-tools.toml` | `starter/dot_myshell/pixi-tools.toml` |
| uv tools | `~/.myshell/uv-tools.toml` | `starter/dot_myshell/uv-tools.toml` |

在 macOS/Linux/WSL 的 Zsh 中运行 `env-sync` 时，它会盘点 Brew Tap、顶层 Formula、Cask 和 uv receipt，并收回受管的 Pixi 期望清单。Pixi 的缓存、环境目录和求解后的内部 manifest 不进入 chezmoi。`env-sync` 不会暂存、提交或推送；发布私人派生仓库前仍需检查个人应用和临时工具：

```text
当前安装状态 → env-sync → Home 目标清单 → chezmoi add → chezmoi 源清单
```

在新机器恢复或日常应用时，方向相反。macOS/Linux/WSL 由 `run_onchange` 调用 Brew 或 Pixi 以及 uv；原生 Windows 由 `setup.ps1` 在排除 Unix scripts 后调用 `sync-tools.ps1`：

```text
Git/chezmoi 源清单 → chezmoi apply → Home 目标清单 → 平台同步器 → 当前安装状态
```

`run_onchange_*.sh.tmpl` 是 Unix 平台的 chezmoi 特殊执行源，不会作为普通脚本长期复制到 Home。Windows 的 `sync-tools.ps1` 是显式调用的受管脚本。Git 只同步声明和脚本源，不同步 Pixi/uv 缓存、工具环境、Python 二进制或 Homebrew 下载缓存。

## 为什么 `run_onchange` 能持续同步软件

脚本模板会把清单的 SHA-256 写入渲染结果：

```text
# Pixi tools hash: {{ include "dot_myshell/pixi-tools.toml" | sha256sum }}
```

chezmoi 记录渲染后脚本的状态：

- 第一次 apply 没有运行记录，因此执行。
- 清单不变时渲染结果相同，因此跳过。
- 清单增加或删除条目后哈希变化，因此再次执行。

默认策略只补齐缺少的软件，不删除机器上的额外软件。Pixi 为每个 CLI 创建隔离的 global 环境，并把命令暴露到 `~/.pixi/bin`。确实要让机器严格匹配清单时，先检查清理范围，再显式运行：

```sh
./setup.sh --prune
```

服务器对应：

```sh
./server-setup.sh --prune
```

Windows 对应为 `./setup.ps1 -Prune`。清理范围包括 Brew Formula、Pixi global 环境和 uv 工具；不会清理 Cask、Tap、Pixi 缓存或项目环境。该操作会卸载清单外项目，因此只在明确检查过差异后使用。

公共 starter 的 `~/.myshell/uv-tools.toml` 只声明不锁版本和解释器的 `ruff`。`determined`、`harlequin` 等工具移到 [`recommendations/uv-tools.md`](recommendations/uv-tools.md)，不会自动安装。清单只在 `chezmoi apply` 的 `run_onchange` 钩子中解析和安装，不会在 Zsh 启动时加载，也不复制 uv 缓存、工具虚拟环境或下载的 Python。

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

把当前机器的受管软件清单写回本地 chezmoi 源：

```sh
env-sync
```

Linux/WSL 收回 Pixi 期望清单并采集 uv；macOS 同时采集完整 Brewfile。它会保留已有 uv 工具的版本约束和 Python 策略；发布仍是单独的 Git 操作。原生 Windows 使用 `setup.ps1`/`sync-tools.ps1`，不安装 Zsh 的 `env-sync` 函数。公共仓库不要未经审查直接发布同步结果。

安装器的完整公开选项：

```text
--repo URL            使用已有 chezmoi 仓库
--age-key-file PATH   导入 age identity
--prune               清理清单外 Formula、Pixi 环境和 uv 工具
--user-only           Linux/WSL 纯用户安装，不调用 apt 或修改登录 Shell
--skip-shell-change   不修改登录 Shell
--dry-run             只预览
```

原生 Windows 使用 PowerShell 参数：`-Repo`、`-AgeKeyFile`、`-Prune` 和 `-DryRun`。

## 完整恢复备份

```sh
./scripts/full-backup.sh /path/to/private/backup-directory
```

归档包含完整源目录与 Git 状态、解密后的 managed targets、本机 chezmoi 配置、age identity、状态快照和 SHA-256 清单。未受 chezmoi 管理的 SSH 私钥不在其中，必须另行安全备份。

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
├── setup.ps1                # 原生 Windows PowerShell 安装器
├── server-setup.sh          # Linux/WSL 入口
├── bootstrap.sh             # 临时克隆并执行安装器
├── doctor.sh                # 安装后的健康检查
├── doctor.ps1               # 原生 Windows 健康检查
├── lib/                     # 平台检测和公共函数
├── scripts/                 # age 与完整备份工具
├── starter/                 # 公共 chezmoi 源状态
└── tests/                   # 隔离测试与安全检查
```

## 致谢与许可

新手文档结构参考了 [lewislulu/terminal-setup](https://github.com/lewislulu/terminal-setup)。安装、配置、清单、age、备份和服务器实现均为独立代码，不依赖参考仓库。

MIT License。
