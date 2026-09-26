# Optional applications and tools

[Back to README](README_EN.md#optional-tools) · [中文](RECOMMENDATIONS.md)

The public starter installs only a reusable terminal and CLI baseline. This document consolidates optional applications, specialist CLIs, and Python tools; none are installed automatically. Select tools by machine role and add reviewed entries to private Brewfile, Pixi, or uv manifests when automatic restoration is needed.

- [macOS applications](#macos-apps)
- [Specialist CLI tools](#specialist-cli)
- [Optional uv tools](#uv-tools)

Accounts, tokens, provider settings, OAuth sessions, and application state belong in private configuration or application-owned storage. For server Codex environment and permission issues, see the [server configuration guide](CODEX_SERVER_EN.md).

<a id="macos-apps"></a>

## macOS applications

These applications are excluded from `starter/dot_Brewfile`. Run only the commands relevant to your machine.

### Terminals and workspaces

```sh
brew install --cask ghostty
brew tap manaflow-ai/cmux
brew install --cask cmux
```

### AI clients and configuration managers

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
  echo "Skipping sbx: this Cask supports Apple Silicon only."
fi
```

### Desktop and device utilities

```sh
brew install --cask android-platform-tools
brew install --cask keka
brew install --cask monitorcontrol
brew install --cask spotify
brew install --cask switchhosts
```

<a id="specialist-cli"></a>

## Specialist CLI tools

On macOS, install the relevant Homebrew formulae:

```sh
brew install herdr
brew install imagemagick
brew install poppler
brew install scrcpy
brew install wireguard-tools
```

On Linux/WSL or native Windows, first check whether conda-forge provides the package for the target platform, then add it to a private Pixi manifest or install it in a named global environment:

```sh
pixi search imagemagick
pixi search poppler
pixi global install --environment imagemagick imagemagick
pixi global install --environment poppler poppler
```

Pixi can only install packages published on conda-forge for the current platform. If `herdr`, `scrcpy`, `wireguard-tools`, or another specialist tool is unavailable, use its upstream installation method instead of adding it to the public baseline.

CodeBuddy is an optional AI-specific CLI. On macOS:

```sh
brew tap tencent-codebuddy/tap
brew install tencent-codebuddy/tap/codebuddy-code
```

Provider credentials, endpoints, OAuth sessions, and the CodeBuddy-specific PATH belong to private or application-owned configuration.

<a id="uv-tools"></a>

## Optional uv tools

The public uv manifest installs only `ruff`. Select other tools by project or machine role. Add a tool to a private `~/.myshell/uv-tools.toml` only when it should be restored on every machine using that private source.

### Harlequin

```sh
uv tool install harlequin
```

### Determined CLI compatibility environment

This preserves the interpreter and dependency combination for the specified older CLI, rather than prescribing these versions for every project:

```sh
uv tool install \
  --python 3.10 \
  --with PyYAML==5.3.1 \
  --with ruamel-yaml==0.17.40 \
  determined==0.19.10
```
