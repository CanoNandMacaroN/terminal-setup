# 服务器 Codex 问题与解决方案

[返回 README](README.md#server-codex) · [English](CODEX_SERVER_EN.md)

在**运行 Codex 的 Linux/WSL 服务器**上执行以下命令。需要已有 Python 3.11+、Node 和 Codex；脚本不需要 sudo，也不安装软件。

## 一次修好 SSH 环境与 bwrap 问题

在 `terminal-setup` 仓库目录运行：

```sh
./scripts/configure-codex.sh --no-sandbox
```

这条命令会修复 Bash/Zsh 下的工具路径，并把 Codex 设置为当前用户权限下的完全访问，保留按需审批。**它会关闭 Codex 本地沙箱，文件访问不再限于项目目录，但不会获得 root 权限。** 每条命令不一定都会询问。

想先查看将修改哪些文件：

```sh
./scripts/configure-codex.sh --no-sandbox --dry-run
```

执行后重新连接 SSH / 桌面端远程会话；CLI 输入 `/quit` 退出后重新运行 `codex`。

<a id="ssh-shell"></a>

## 问题：终端里能用 Codex，远程连接却找不到 node 或 codex

**解决：只修复 Shell 环境。**

```sh
./scripts/configure-codex.sh
```

常见原因是账号登录 Shell 为 Bash，交互终端才切换到 Zsh。远程非交互命令不会执行 `.bashrc` 末尾的 Zsh 切换，因而读不到只写在 `.zshrc` / `.zprofile` 中的 Node、pnpm 路径。

脚本把 Pixi、fnm、pnpm 和 `~/.local/bin` 的环境初始化写到 `~/.config/terminal-setup/codex-env.sh`，再从以下位置加载：

- `.bashrc` 开头，在非交互 `return` 之前。
- 如果 `.bashrc` 已有本仓库 chezmoi 管理的 Bash SSH 环境块，脚本会保留它，不重复插入初始化块。
- Bash 实际使用的登录配置：`.bash_profile`、`.bash_login`、`.profile` 中首个存在的文件；都不存在时创建 `.profile`。
- `.zshenv`，让 Zsh 非交互命令也能使用；设置了 `ZDOTDIR` 时使用该目录。

它分别调用 `fnm env --shell bash` / `--shell zsh`，不会让 Bash 加载 Zsh 配置。如果 `.bashrc` 已有本项目标记的交互 Zsh 切换块，还会修正为保留显式命令、避免读取 stdin 的版本；不会新增切换，也不修改账号的登录 Shell。

从客户端检查，替换自己的 SSH Host 别名：

```sh
ssh your-server 'command -v node; command -v codex; node --version; codex --version'
```

仍缺少 Node 时，先用 `fnm list` 检查是否安装并设置了默认版本。脚本能修复路径，不能补上未安装的 Node 或 Codex。

<a id="bwrap"></a>

## 问题：Codex 执行命令时报 bwrap 权限错误

典型报错：

```text
bwrap: setting up uid map: Permission denied
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

**解决：在无法调整系统策略、且接受完全访问时运行：**

```sh
./scripts/configure-codex.sh --no-sandbox
```

这类错误表示创建沙箱所需的权限被系统拒绝。此次 Ubuntu 24.04 的诊断指向 AppArmor 非特权用户命名空间限制；用户目录中安装的 `bwrap --version` 能运行，但创建沙箱仍失败，因此重新安装 bwrap 无法解决。

脚本在服务器端 `~/.codex/config.toml` 顶层写入以下配置；设置了 `CODEX_HOME` 时使用该目录：

```toml
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
```

原有模型、供应商等配置保留。为避免两套权限配置混用，脚本会移除顶层 `default_permissions`、`[permissions]` 及其子表、`[sandbox_workspace_write]` 及其子表；原文件会备份。命名 profile 中的设置不改，选中的 profile 或桌面端权限选择仍可能覆盖这些默认值。

如果桌面端仍报相同错误，给该远程会话选择“完全访问”，再断开重连。组织策略禁止完全访问时，本脚本不能覆盖它。

<a id="verify"></a>

## 问题：配置后仍使用旧环境或权限

1. 断开并重新连接桌面端远程会话；仅重开本机终端不一定重启远程 Codex。
2. CLI 输入 `/quit` 后重新运行 `codex`。如需显式指定本次权限：

   ```sh
   codex --sandbox danger-full-access --ask-for-approval on-request
   ```

3. 在 Codex 中用 `/status` 查看权限，再让它执行 `pwd`、`id`。能找到 Codex 命令和 Codex 能执行工具是两项不同的检查。

## 备份与重复运行

脚本修改前会备份原文件，输出备份目录，默认位于 `~/.local/state/terminal-setup/codex-backups/`；设置了 `XDG_STATE_HOME` 时使用该状态目录。备份里的 `manifest.json` 记录每个备份文件对应的原路径，`backup: null` 表示原先不存在。备份可能包含私人配置，不要提交到仓库。

重复运行相同命令不会重复添加配置块。它支持现有配置文件的符号链接，保留链接并更新目标；遇到无法解析的 TOML 或损坏的标记块，会在修改前停止。由 chezmoi 管理的配置修改后，检查 `chezmoi diff`，再将需要保留的更改收回私人源状态。

参考：[OpenAI 配置文档](https://developers.openai.com/codex/config-reference) · [权限文档](https://learn.chatgpt.com/docs/permissions)
