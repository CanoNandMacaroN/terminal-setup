# 可选应用与工具推荐

[返回 README](README.md#optional-tools) · [English](RECOMMENDATIONS_EN.md)

公共 starter 只安装通用终端与 CLI 基线。本文集中列出可选应用、专业 CLI 和 Python 工具，不会自动安装；根据机器用途选择，需要自动恢复时再加入私人 Brewfile、Pixi 或 uv 清单。

- [macOS 应用](#macos-apps)
- [专业 CLI](#specialist-cli)
- [可选 uv 工具](#uv-tools)

账号、Token、供应商配置、OAuth 会话和应用状态应由私人配置或应用自身管理，不进入公共 starter。服务器上的 Codex 环境与权限问题见 [服务器配置指南](CODEX_SERVER.md)。

<a id="macos-apps"></a>

## macOS 应用

这些应用不在 `starter/dot_Brewfile` 中。以下按用途分组，按需执行对应命令。

### 终端与工作区

```sh
brew install --cask ghostty
brew tap manaflow-ai/cmux
brew install --cask cmux
```

### AI 客户端与配置管理

```sh
brew install --cask codex
brew tap farion1231/ccswitch
brew install --cask cc-switch
brew tap stablyai/orca
brew install --cask orca
brew tap anomalyco/tap
if [ "$(uname -m)" = arm64 ]; then
  brew install --cask sbx
else
  echo "跳过 sbx：此 Cask 仅支持 Apple Silicon。"
fi
```

### 桌面与设备工具

```sh
brew install --cask android-platform-tools
brew install --cask keka
brew install --cask monitorcontrol
brew install --cask spotify
brew install --cask switchhosts
```

<a id="specialist-cli"></a>

## 专业 CLI

macOS 可按需安装以下 Homebrew Formula：

```sh
brew install herdr
brew install imagemagick
brew install poppler
brew install scrcpy
brew install wireguard-tools
```

Linux/WSL 或原生 Windows 上，先检查 conda-forge 是否提供当前平台的包，再加入私人 Pixi 清单，或安装到具名的 global 环境：

```sh
pixi search imagemagick
pixi search poppler
pixi global install --environment imagemagick imagemagick
pixi global install --environment poppler poppler
```

Pixi 只能安装 conda-forge 已收录且支持当前平台的包。`herdr`、`scrcpy`、`wireguard-tools` 等工具如果查不到，使用上游官方安装方式，不要加入公共基线。

CodeBuddy 是可选 AI CLI，macOS 安装方式：

```sh
brew tap tencent-codebuddy/tap
brew install tencent-codebuddy/tap/codebuddy-code
```

CodeBuddy 的供应商凭据、服务地址、OAuth 会话和专用 PATH 属于私人或应用自身配置。

<a id="uv-tools"></a>

## 可选 uv 工具

公共 uv 清单只安装 `ruff`。其他工具按项目或机器角色选择；确实需要在每台使用同一私人源的机器上恢复时，再加入私人 `~/.myshell/uv-tools.toml`。

### Harlequin

```sh
uv tool install harlequin
```

### Determined CLI 兼容环境

以下保留指定旧版 CLI 的解释器和依赖组合，并非要求所有项目使用这些版本：

```sh
uv tool install \
  --python 3.10 \
  --with PyYAML==5.3.1 \
  --with ruamel-yaml==0.17.40 \
  determined==0.19.10
```
