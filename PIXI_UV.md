# 用 Pixi + uv 构建可复现的 Python 项目环境

[返回主文档](README.md) · [English](PIXI_UV_EN.md)

本文说明如何用 Pixi（接替 conda 的角色）与 uv（接替 pyenv + pip + virtualenv 的角色）组合出项目级 Python 环境：环境自包含、依赖可复现、缓存可回收。适用于服务器、WSL 与 macOS 上的普通用户，不需要 root，也不需要预先安装 conda 或 base 环境。

行为基线：Pixi 0.81、uv 0.12。更低版本可能缺少本文提到的部分开关。

## 1. 分工模型

| 层 | 工具 | 负责内容 | 声明与锁 |
|---|---|---|---|
| 原生侧 | Pixi | Python 之外的原生库、二进制 CLI、编译工具链、任务入口 | `pixi.toml` + `pixi.lock` |
| Python 侧 | uv | Python 解释器版本、Python 包、`.venv` | `pyproject.toml` + `uv.lock` + `.python-version` |

一个项目的典型布局：

```text
项目/
├── pixi.toml          原生依赖、任务、requires-pixi
├── pixi.lock          原生世界精确解
├── pyproject.toml     Python 依赖声明 + [tool.uv] 闸门
├── uv.lock            Python 世界精确解
├── .python-version    解释器版本
├── .venv/             uv 建的 Python 环境（不提交）
└── .pixi/             Pixi 环境与内部文件（不提交）
```

三条不可越界的规则：

1. 不要 `pixi add python`，也不要用 `pixi add --pypi`——Python 与 Python 包统一归 uv，否则会出现两个解释器与两套依赖来源。
2. 同一个库只交给一边：编译型/原生依赖走 Pixi，纯 Python 包走 uv。
3. 项目需要 Pixi 提供的原生库或 CLI 时，先在 `pixi shell`（或 `pixi run`）里执行 uv 命令，否则 uv 的世界里看不到它们。

Pixi 的 `pypi-dependencies` 内部使用 uv 解析，因此第 1 条是纪律而非能力限制：真遇到必须由 conda 侧统一求解的包（见第 10 节），才局部启用。

## 2. 安装与版本闸门

```sh
# Pixi
curl -fsSL https://pixi.sh/install.sh | PIXI_HOME="$HOME/.pixi" sh

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
```

若机器已按本仓库安装过终端环境，`uv` 通常已随 Pixi global 清单存在，升级命令是 `pixi global update`。

三道闸门让"目标机只要有 pixi 和 uv 就能复现"这句话成立：

| 闸门 | 位置 | 作用 |
|---|---|---|
| `requires-pixi = ">=0.81,<2"` | `pixi.toml` 的 `[workspace]` | Pixi 版本不符直接报错 |
| `[tool.uv] required-version = ">=0.12.19"` | `pyproject.toml` | uv 版本不符直接报错（报错信息形如 `Required uv version ... does not match the running version ...`） |
| `.python-version` 写全补丁号（如 `3.12.14`） | 项目根目录 | 只写 `3.12` 会随日期取到最新的 3.12.x，解释器 patch 会漂移 |

`required-version` 写在 `[tool.uv]` 而不是激活变量里，是因为它在任何 Shell 中生效；写在 Pixi 激活环境里只对 `pixi run` 的子进程有效。

## 3. 新项目初始化

顺序固定为 uv 先、Pixi 后。命令中的 `<...>` 是占位符，按项目实际值替换：

```sh
cd <项目目录>
uv init --app --python <版本> --no-readme     # 生成 pyproject.toml / .python-version / .gitignore，并 git init
pixi init --format pixi -c conda-forge        # 生成 pixi.toml / .gitattributes
uv python pin <主版本>.<次版本>.<补丁号>        # 写全补丁号，避免解释器 patch 漂移
pixi workspace requires-pixi set ">=0.81,<2"  # 下限按当前 Pixi 版本调整
pixi add <原生工具或库>                        # 按项目替换
uv add <Python 包>                            # 按项目替换
```

两个与顺序有关的行为，避免反复踩：

- `pixi init` 不带 `--format pixi` 时，若目录里已有 `pyproject.toml`，它不会生成 `pixi.toml`。
- 先 `pixi init` 再 `uv init` 的话，`.gitignore` 只保留一套规则。按上面顺序时，Pixi 会把 `.pixi/*` 追加进已有规则，两边内容都在。

初始化后自查：

```sh
find . -mindepth 1 -maxdepth 1 -not -name '.git' | sort
grep -E 'venv|pixi' .gitignore          # 期望两条规则都存在
pixi info | grep -i manifest            # 期望 Manifest file: …/pixi.toml
```

## 4. 配置模板

模板中的 `<...>` 是占位符，按项目替换；被注释的条目只是示例，不要原样保留。版本号、平台名等取值同样按项目实际情况调整，示例值不代表推荐值。

`pixi.toml`：

```toml
[workspace]
channels = ["conda-forge"]
name = "<项目名>"
platforms = ["linux-64"]            # 需要别的平台就列进来，并重新求解提交锁
version = "0.1.0"
requires-pixi = ">=0.81,<2"

[dependencies]
# <原生工具或库> = "*"              # 按项目需要添加
# python = "*"                      # 不要添加

[tasks]
# 任务可选；把命令换成项目真实入口后再启用
# test = "uv run <测试命令>"
# run  = "uv run python <入口脚本>"
```

仅当项目确实需要声明系统能力（GPU、glibc 下限）时才追加；这些值会进入平台标识并影响锁的求解结果，没有对应需求就不要写：

```toml
[system-requirements]
# libc = "<最低 glibc 版本>"
# cuda = "<CUDA 主版本>"
# archspec = "<CPU 架构标识>"
```

`pyproject.toml`（在 `uv init` 生成的基础上补充 `[tool.uv]`）：

```toml
[tool.uv]
required-version = ">=0.12.19"
python-preference = "only-managed"  # 只用 uv 托管的解释器，绝不落到系统 Python
python-downloads = "automatic"      # 需要时自动下载托管解释器
```

`.python-version`（填项目需要的版本，写全补丁号，并与 `pyproject.toml` 的 `requires-python` 对齐）：

```text
<主版本>.<次版本>.<补丁号>
```

## 5. 日常使用

```sh
pixi shell                          # 等价于 conda activate：拿到原生环境
uv run python <入口脚本>             # Python 侧照常使用 uv
exit
```

依赖变更与同步：

```sh
uv add <包>                          # Python 依赖 → pyproject.toml + uv.lock
uv add --dev <开发依赖>              # 开发依赖组
uv remove <包>
pixi add <包>                        # 原生依赖 → pixi.toml + pixi.lock

uv sync --locked                     # 严格按 uv.lock 还原
pixi install --locked                # 严格按 pixi.lock 还原
uv lock --check                      # 检查锁是否过期（CI 用）
```

升级：

```sh
uv lock --upgrade && uv sync         # Python 包
uv python upgrade                    # 解释器 patch
pixi update                          # 原生依赖
pixi self-update                     # Pixi 本体
```

uv 常用命令：

```sh
uv python list|install|pin|find|upgrade|uninstall|dir       # 解释器
uv init|add|remove|lock|sync|tree|export                    # 项目与依赖
uv run python <脚本> | uv run --with <临时依赖> <命令> | uv run --no-project ...   # 执行
uvx <CLI> <参数>                                            # 临时环境跑 CLI
uv tool install <CLI> | uv tool list | uv tool upgrade --all # 常驻 CLI
uv build | uv publish                                       # 打包发布
uv pip install --python .venv/bin/python <包>                # 救急，不写锁
```

conda / pip 习惯对照（`<环境名>`、`<包>`、`<CLI>` 均为占位符）：

| conda / pip | Pixi + uv |
|---|---|
| `conda create -n <环境名> python=<版本>` | `uv python install <版本> && uv python pin <版本>` |
| `conda activate <环境名>` | `pixi shell`（原生侧）；Python 侧 `source .venv/bin/activate` |
| `pip install <包>` | `uv add <包>` |
| `pip install -r requirements.txt` | `uv sync` |
| `pip freeze > requirements.txt` | `uv export --format requirements-txt` |
| `conda list` | `uv tree` / `pixi list` |
| `conda update --all` | `uv lock --upgrade && uv sync`（原生侧 `pixi update`） |
| `pipx install <CLI>` / `pipx run <CLI>` | `uv tool install <CLI>` / `uvx <CLI>` |
| `conda env remove -n <环境名>` | `rm -rf .pixi .venv` |

## 6. 可选：一个入口同时激活两层

不加也能工作——`uv run` 自己会找到 `.venv`。加上之后，`pixi shell` 里可以直接敲 `python` 以及项目自己的 CLI，更接近 conda 手感。

`scripts/activate-venv.sh`：

```sh
if [ -f "$PIXI_PROJECT_ROOT/.venv/bin/activate" ]; then
    . "$PIXI_PROJECT_ROOT/.venv/bin/activate"
fi
```

`pixi.toml`：

```toml
[activation]
scripts = ["scripts/activate-venv.sh"]

[activation.env]
# 让 .venv 里的扩展库链接到 Pixi 提供的 .so
LD_LIBRARY_PATH = "$CONDA_PREFIX/lib"
```

实测行为：

- `[activation.env]` 的值会展开 `$CONDA_PREFIX`、`$PIXI_PROJECT_ROOT`、`$PATH`、`$USER`。
- `[activation] scripts` 传递的是环境变量；`deactivate` 这类 Shell 函数不会带进来，会话内退出用 `exit`。
- 顺序必须是 Pixi 在前、venv 在后。先激活 venv 再 `pixi shell` 会被 Pixi 重建 PATH，叠加失效。

## 7. 纯净性

uv 建立的 venv 天然屏蔽用户级 site-packages（`site.ENABLE_USER_SITE` 为 `False`），配合 `python-preference = "only-managed"` 可保证解释器不落到系统 Python。自检：

```sh
pixi shell
command -v python                                       # 期望 <项目>/.venv/bin/python
python -c "import sys; print(sys.executable, sys.prefix)"
python -c "import site; print(site.ENABLE_USER_SITE)"    # 期望 False
pixi list | awk '$1 == "python"' | grep . || echo "OK: Pixi 环境不含 python 包"
```

两个容易忽略的点：

- 裸 `python` 在 `pixi shell` 里指向 `.venv` 的 python；如果 Pixi 环境被装进了 python（例如某个原生包的传递依赖），裸命令可能指向 Pixi 环境，统一用 `uv run python` 可避免歧义。
- `PYTHONPATH` 若被外部工具注入（部分 IDE、远程开发插件），会出现在 `sys.path` 中。用 `uv run python -c "import sys; print(sys.path)"` 确认。

## 8. 产物位置、缓存与清理

Pixi 与 uv 的项目产物都在项目内，用户级只有共享缓存与工具本体：

| 产物 | 位置 | 性质 |
|---|---|---|
| Pixi 项目环境 | `<项目>/.pixi/envs/default` | 随项目删除 |
| uv 的 venv | `<项目>/.venv` | 随项目删除 |
| Pixi 安装缓存 | `~/.cache/rattler/cache` | 可随时清理 |
| uv 缓存、托管解释器、uv tool 环境 | `~/.cache/uv`、`~/.local/share/uv/*` | 可随时清理或被重建 |
| 工具本体 | `~/.pixi/bin`、`~/.local/bin` | 机器级安装，不属于项目 |

缓存删除是安全的：环境文件是独立副本（uv 从缓存硬链接，Pixi 实测为复制），缓存被清空后已建环境照常运行，只是后续安装需要重新下载。

```sh
pixi clean cache -y     # 也可分类：--conda / --repodata / --pypi-wheels / --exec
uv cache clean
rm -rf .pixi .venv      # 删除项目环境，保留锁文件即可重建
```

注意 `pixi clean cache` 清的是共享缓存；`pixi clean`（不带 `cache`）删的是当前项目的 `.pixi` 环境。

需要把大文件移出 Home 时用环境变量，且必须在启动 uv 之前导出：

```sh
export UV_CACHE_DIR=/data/$USER/data/scratch/uv-cache
export UV_PYTHON_INSTALL_DIR=/data/$USER/env/uv-python
```

代价：缓存与 `.venv` 不在同一文件系统时，uv 的硬链接会退化为复制，安装变慢、占用上升。可用 `UV_LINK_MODE`（`clone` / `copy` / `hardlink` / `symlink`）显式指定，或用 `uv venv <路径>` 配合 `uv sync --active` 把 venv 放到同一文件系统。

Pixi 侧同理，`PIXI_CACHE_DIR` 可整体重定向其缓存，但要在 Shell 层导出（Pixi 在进程启动时读取），写在 `[activation.env]` 里只对 `pixi run` 的子进程有效。

## 9. 迁移复现

提交进版本库：`pixi.toml`、`pixi.lock`、`pyproject.toml`、`uv.lock`、`.python-version`、`.gitignore`、`.gitattributes`。

目标机上的步骤：

```sh
git clone <仓库> && cd <项目>

# 安装两个工具（若已存在则确认版本满足闸门）
curl -fsSL https://pixi.sh/install.sh | PIXI_HOME="$HOME/.pixi" sh
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$PATH"

uv python install            # 读取 .python-version
uv sync --locked             # 读取 uv.lock
pixi install --locked        # 读取 pixi.lock
```

`--locked` 报错说明清单与锁不一致。正确做法是回到源机器执行 `uv lock` 或 `pixi update` 并提交新锁，而不是在目标机放开严格模式重新求解——后者会引入无法察觉的漂移。

需要新增平台（ARM、macOS、Windows）时，先把平台加入 `pixi.toml` 的 `platforms` 并重新求解提交锁；`uv.lock` 本身覆盖所有平台，通常无需改动。

锁之外仍需单独交付的内容：数据集与产物、模型权重、`.env` 与凭据、CUDA 驱动等系统能力、网络可达性（conda-forge、PyPI、python-build-standalone）。

## 10. 边界与限制

- 两套依赖图不联动求解。同一个库只能交给一边；需求强耦合时（例如 GDAL 的 C 库与 Python 绑定）建议整体收进 Pixi，或局部使用 `pixi add --pypi`。
- Pixi 的求解不认识 uv 托管的解释器。若某个原生包自身依赖 Python，环境里会同时存在 Pixi 的 python 与 `.venv` 的 python，日常统一用 `uv run python`。
- `.venv` 默认没有 pip（`uv venv --seed` 才装）。装包用 `uv add`；`uv pip install` 只用于临时手段，不写入锁。
- `uv sync` 默认移除不在锁中的包，临时安装的包会被清掉，需要保留时加 `--inexact`。
- Pixi 覆盖不到 uv 的部分主要是 Python 生命周期后段：standalone CPython 构建、`uv build` / `uv publish`、多包 workspace（`[tool.uv.workspace]`）、`uv.lock` 的跨平台统一求解、`uv pip` 对任意解释器的兼容层。需要这些时保留 uv 的独立使用。
- 纯 Python 且不需要 Pixi 提供的原生依赖时，可以只用 uv，不必引入 `pixi.toml`。

## 11. 常见问题

| 症状 | 原因 | 处理 |
|---|---|---|
| `Required uv version ... does not match` | uv 版本不满足 `required-version` | 升级 uv |
| Pixi 提示 `requires-pixi` 不满足 | Pixi 版本过低 | `pixi self-update` |
| `--locked` 报锁与清单不一致 | 改了清单未更新锁 | 源机器 `uv lock` / `pixi update` 后提交锁 |
| `No module named pip` | venv 默认不带 pip | 用 `uv add` / `uv run --with`；需要 pip 则 `uv venv --seed` 重建 |
| uv 用了系统 Python | `python-preference` 未生效 | 在 `[tool.uv]` 设 `only-managed` |
| 在普通 Shell 里找不到 Pixi 提供的 CLI 或原生库 | 不在 Pixi 环境内 | 先 `pixi shell`（或 `pixi run ...`） |
| `uv run` 提示找不到项目 | 不在项目目录内 | 进入项目目录，或用 `--no-project` / `uvx` |
| 安装变慢或磁盘翻倍 | 缓存与 venv 跨文件系统，硬链接退化 | 放同一文件系统，或用 `UV_LINK_MODE` |
| 目标机 glibc 版本低 | 不满足系统要求 | 在 `pixi.toml` 声明 `[system-requirements] libc` 或更换平台 |

## 12. 与本仓库工具链的分工

本仓库的 Pixi / uv 清单（`~/.myshell/pixi-tools.toml`、`~/.myshell/uv-tools.toml`）管理的是**个人级命令**：`bat`、`rg`、`gh` 等来自 Pixi global，`uv tool` 安装的 Python CLI 来自 uv。本文描述的是**项目级环境**，两者互不干扰，但同一个命令不要两处都装，避免 PATH 优先级带来的歧义。

项目内需要的 CLI 走 `pixi add`，跨项目使用的个人 CLI 走 `pixi global install` 或 `uv tool install`。
