# Reproducible Python Project Environments with Pixi and uv

[Back to main document](README_EN.md) · [中文](PIXI_UV.md)

This document describes how to combine Pixi (taking the role of conda) with uv (taking the role of pyenv, pip, and virtualenv) to build project-level Python environments: self-contained, reproducible from lock files, and safe to delete. It targets regular users on servers, WSL, and macOS. No root access, no conda, and no pre-existing base environment are required.

Behavior baseline: Pixi 0.81 and uv 0.12. Older versions may lack some of the switches mentioned here.

## 1. Division of Responsibility

| Layer | Tool | Owns | Declarations and locks |
|---|---|---|---|
| Native side | Pixi | Non-Python native libraries, binary CLIs, compilers, task entry points | `pixi.toml` + `pixi.lock` |
| Python side | uv | Python interpreter version, Python packages, `.venv` | `pyproject.toml` + `uv.lock` + `.python-version` |

A typical project layout:

```text
project/
├── pixi.toml          native dependencies, tasks, requires-pixi
├── pixi.lock          exact native solution
├── pyproject.toml     Python dependencies plus [tool.uv] gates
├── uv.lock            exact Python solution
├── .python-version    interpreter version
├── .venv/             uv-managed Python environment (not committed)
└── .pixi/             Pixi environment and internal files (not committed)
```

Three rules that must not be crossed:

1. Do not run `pixi add python`, and do not use `pixi add --pypi`. Python and Python packages belong to uv; otherwise you end up with two interpreters and two sources of truth.
2. Assign each library to exactly one side: compiled or native dependencies to Pixi, pure Python packages to uv.
3. When the project needs native libraries or CLIs provided by Pixi, run uv commands inside `pixi shell` (or through `pixi run`). Otherwise uv cannot see them.

Pixi resolves `pypi-dependencies` with uv internally, so rule 1 is a discipline rather than a limitation. Enable that path only for the cases described in section 10.

## 2. Installation and Version Gates

```sh
# Pixi
curl -fsSL https://pixi.sh/install.sh | PIXI_HOME="$HOME/.pixi" sh

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
```

If the machine was set up by this repository, `uv` usually already exists through the Pixi global manifest; upgrade it with `pixi global update`.

Three gates make the promise "the target machine only needs pixi and uv to reproduce the environment" hold:

| Gate | Location | Effect |
|---|---|---|
| `requires-pixi = ">=0.81,<2"` | `[workspace]` in `pixi.toml` | Fails fast when the Pixi version does not match |
| `[tool.uv] required-version = ">=0.12.19"` | `pyproject.toml` | Fails fast when the uv version does not match (`Required uv version ... does not match the running version ...`) |
| Full patch version in `.python-version` (for example `3.12.14`) | project root | Writing `3.12` resolves to the newest 3.12.x at install time, so the interpreter patch drifts |

`required-version` belongs in `[tool.uv]` rather than in an activation variable because it applies in every shell. Inside a Pixi activation environment it only affects child processes started by `pixi run`.

## 3. Initializing a New Project

Always initialize uv first and Pixi second. Values in `<...>` are placeholders and must be replaced:

```sh
cd <project directory>
uv init --app --python <version> --no-readme  # creates pyproject.toml / .python-version / .gitignore and runs git init
pixi init --format pixi -c conda-forge        # creates pixi.toml / .gitattributes
uv python pin <major>.<minor>.<patch>         # pin the full patch version to avoid interpreter drift
pixi workspace requires-pixi set ">=0.81,<2"  # adjust the lower bound to the installed Pixi
pixi add <native tool or library>             # replace with what the project needs
uv add <python package>                       # replace with what the project needs
```

Two order-dependent behaviors worth remembering:

- `pixi init` without `--format pixi` does not create `pixi.toml` when the directory already contains `pyproject.toml`.
- Running `pixi init` before `uv init` keeps only one set of `.gitignore` rules. In the order above, Pixi appends `.pixi/*` to the existing rules, so both sets survive.

Verify the result:

```sh
find . -mindepth 1 -maxdepth 1 -not -name '.git' | sort
grep -E 'venv|pixi' .gitignore          # both rule sets should match
pixi info | grep -i manifest            # expect Manifest file: .../pixi.toml
```

## 4. Configuration Templates

Every `<...>` below is a placeholder; replace it for the actual project. Commented entries are examples and should not be kept as-is. Version numbers, platform names, and similar values are examples, not recommendations.

`pixi.toml`:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project name>"
platforms = ["linux-64"]            # add other platforms here and re-solve before committing the lock
version = "0.1.0"
requires-pixi = ">=0.81,<2"

[dependencies]
# <native tool or library> = "*"    # add what the project needs
# python = "*"                      # do not add

[tasks]
# Tasks are optional; uncomment and adapt after wiring the real entry points
# test = "uv run <test command>"
# run  = "uv run python <entry script>"
```

Declare system capabilities only when the project actually needs them. These values become part of the platform identifier and change how the lock is solved:

```toml
[system-requirements]
# libc = "<minimum glibc version>"
# cuda = "<CUDA major version>"
# archspec = "<CPU architecture>"
```

`pyproject.toml` (additions on top of what `uv init` generates):

```toml
[tool.uv]
required-version = ">=0.12.19"
python-preference = "only-managed"  # use uv-managed interpreters only, never a system Python
python-downloads = "automatic"      # download a managed interpreter when needed
```

`.python-version` (fill in the version the project needs, with the full patch number, consistent with `requires-python`):

```text
<major>.<minor>.<patch>
```

## 5. Daily Usage

```sh
pixi shell                          # equivalent to conda activate: the native environment
uv run python <entry script>        # the Python side keeps using uv
exit
```

Dependency changes and synchronization:

```sh
uv add <package>                     # Python dependency -> pyproject.toml + uv.lock
uv add --dev <dev dependency>        # development dependency group
uv remove <package>
pixi add <package>                   # native dependency -> pixi.toml + pixi.lock

uv sync --locked                     # restore exactly from uv.lock
pixi install --locked                # restore exactly from pixi.lock
uv lock --check                      # verify the lock is current (use in CI)
```

Upgrades:

```sh
uv lock --upgrade && uv sync         # Python packages
uv python upgrade                    # interpreter patch releases
pixi update                          # native dependencies
pixi self-update                     # the Pixi binary
```

Common uv commands:

```sh
uv python list|install|pin|find|upgrade|uninstall|dir        # interpreters
uv init|add|remove|lock|sync|tree|export                     # projects and dependencies
uv run python <script> | uv run --with <temp dependency> <cmd> | uv run --no-project ...   # execution
uvx <CLI> <arguments>                                        # run a CLI in a temporary environment
uv tool install <CLI> | uv tool list | uv tool upgrade --all  # persistent CLIs
uv build | uv publish                                        # packaging and publishing
uv pip install --python .venv/bin/python <package>            # escape hatch, never writes the lock
```

conda and pip habits, translated (`<name>`, `<package>`, `<CLI>` are placeholders):

| conda / pip | Pixi + uv |
|---|---|
| `conda create -n <name> python=<version>` | `uv python install <version> && uv python pin <version>` |
| `conda activate <name>` | `pixi shell` (native side); `source .venv/bin/activate` (Python side) |
| `pip install <package>` | `uv add <package>` |
| `pip install -r requirements.txt` | `uv sync` |
| `pip freeze > requirements.txt` | `uv export --format requirements-txt` |
| `conda list` | `uv tree` / `pixi list` |
| `conda update --all` | `uv lock --upgrade && uv sync` (native side: `pixi update`) |
| `pipx install <CLI>` / `pipx run <CLI>` | `uv tool install <CLI>` / `uvx <CLI>` |
| `conda env remove -n <name>` | `rm -rf .pixi .venv` |

## 6. Optional: Activating Both Layers Through One Entry Point

This is not required — `uv run` finds `.venv` on its own. With it enabled, `python` and the project's own CLIs work directly inside `pixi shell`, which feels closer to conda.

`scripts/activate-venv.sh`:

```sh
if [ -f "$PIXI_PROJECT_ROOT/.venv/bin/activate" ]; then
    . "$PIXI_PROJECT_ROOT/.venv/bin/activate"
fi
```

`pixi.toml`:

```toml
[activation]
scripts = ["scripts/activate-venv.sh"]

[activation.env]
# let extensions inside .venv link against .so files provided by Pixi
LD_LIBRARY_PATH = "$CONDA_PREFIX/lib"
```

Observed behavior:

- Values in `[activation.env]` expand `$CONDA_PREFIX`, `$PIXI_PROJECT_ROOT`, `$PATH`, and `$USER`.
- `[activation] scripts` propagates environment variables. Shell functions such as `deactivate` are not carried over; leave the session with `exit`.
- The order must be Pixi first, venv second. Activating the venv before `pixi shell` fails because Pixi rebuilds `PATH`.

## 7. Purity

A uv-managed venv excludes user-level site-packages by default (`site.ENABLE_USER_SITE` is `False`), and `python-preference = "only-managed"` keeps the interpreter away from system Python. Self-check:

```sh
pixi shell
command -v python                                       # expect <project>/.venv/bin/python
python -c "import sys; print(sys.executable, sys.prefix)"
python -c "import site; print(site.ENABLE_USER_SITE)"    # expect False
pixi list | awk '$1 == "python"' | grep . || echo "OK: no python package in the Pixi environment"
```

Two details that are easy to miss:

- A bare `python` inside `pixi shell` resolves to `.venv`. If the Pixi environment itself contains python (for example as a transitive dependency of a native package), the bare command may resolve there instead; `uv run python` removes the ambiguity.
- If an external tool injects `PYTHONPATH` (some IDEs and remote development extensions do), it shows up in `sys.path`. Check with `uv run python -c "import sys; print(sys.path)"`.

## 8. Artifact Locations, Caches, and Cleanup

Project artifacts live inside the project; only shared caches and the tools themselves live at the user level:

| Artifact | Location | Nature |
|---|---|---|
| Pixi project environment | `<project>/.pixi/envs/default` | removed with the project |
| uv venv | `<project>/.venv` | removed with the project |
| Pixi package cache | `~/.cache/rattler/cache` | safe to clean at any time |
| uv cache, managed interpreters, uv tool environments | `~/.cache/uv`, `~/.local/share/uv/*` | safe to clean or rebuild |
| Tool binaries | `~/.pixi/bin`, `~/.local/bin` | machine-level installs, not project state |

Deleting the cache is safe: environment files are independent copies (uv hardlinks from the cache, Pixi copies in practice). Existing environments keep working after the cache is cleared; only later installs have to download again.

```sh
pixi clean cache -y     # category flags: --conda / --repodata / --pypi-wheels / --exec
uv cache clean
rm -rf .pixi .venv      # remove the project environments; keep the lock files to rebuild
```

Note that `pixi clean cache` removes the shared cache, while `pixi clean` (without `cache`) removes the current project's `.pixi` environment.

To move large files out of Home, use environment variables and export them before uv starts:

```sh
export UV_CACHE_DIR=/data/$USER/data/scratch/uv-cache
export UV_PYTHON_INSTALL_DIR=/data/$USER/env/uv-python
```

Trade-off: when the cache and `.venv` live on different filesystems, uv falls back from hardlinks to copies, which slows installation and increases disk usage. Set `UV_LINK_MODE` (`clone` / `copy` / `hardlink` / `symlink`) explicitly, or place the venv on the same filesystem with `uv venv <path>` plus `uv sync --active`.

The same applies to Pixi: `PIXI_CACHE_DIR` redirects its cache as a whole, but it must be exported in the shell because Pixi reads it at process start. Setting it in `[activation.env]` only affects child processes of `pixi run`.

## 9. Migration and Reproduction

Commit to version control: `pixi.toml`, `pixi.lock`, `pyproject.toml`, `uv.lock`, `.python-version`, `.gitignore`, and `.gitattributes`.

Steps on the target machine:

```sh
git clone <repository> && cd <project>

# install both tools (skip if present, but check the version gates)
curl -fsSL https://pixi.sh/install.sh | PIXI_HOME="$HOME/.pixi" sh
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$PATH"

uv python install            # reads .python-version
uv sync --locked             # reads uv.lock
pixi install --locked        # reads pixi.lock
```

A `--locked` failure means the manifest and the lock disagree. The correct fix is to run `uv lock` or `pixi update` on the source machine and commit the new lock, not to relax strict mode on the target machine and re-solve; the latter introduces silent drift.

To add a platform (ARM, macOS, Windows), add it to `platforms` in `pixi.toml`, re-solve, and commit the lock. `uv.lock` covers all platforms and usually needs no change.

Content that stays outside the locks and must be delivered separately: datasets and outputs, model weights, `.env` files and credentials, system capabilities such as CUDA drivers, and network reachability (conda-forge, PyPI, python-build-standalone).

## 10. Boundaries and Limitations

- The two dependency graphs are solved independently. Assign each library to one side; when the coupling is tight (for example the GDAL C library with its Python bindings), keep the whole group in Pixi, or use `pixi add --pypi` locally.
- Pixi's solver does not know about uv-managed interpreters. If a native package itself depends on Python, the environment contains both the Pixi python and the `.venv` python; use `uv run python` consistently.
- `.venv` has no pip by default (`uv venv --seed` adds it). Install packages with `uv add`; treat `uv pip install` as a temporary escape hatch that does not write the lock.
- `uv sync` removes packages that are not in the lock. Temporarily installed packages disappear; add `--inexact` to keep them.
- What Pixi cannot replace on the uv side is mostly the later part of the Python lifecycle: standalone CPython builds, `uv build` / `uv publish`, multi-package workspaces (`[tool.uv.workspace]`), the universal cross-platform resolution of `uv.lock`, and the `uv pip` compatibility layer for arbitrary interpreters. Keep standalone uv usage for those.
- For a pure Python project that needs nothing from Pixi, use uv alone and skip `pixi.toml`.

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Required uv version ... does not match` | uv does not satisfy `required-version` | Upgrade uv |
| Pixi reports a `requires-pixi` mismatch | Pixi is too old | `pixi self-update` |
| `--locked` reports a manifest/lock mismatch | The manifest changed without re-locking | Run `uv lock` / `pixi update` on the source machine and commit the lock |
| `No module named pip` | venvs have no pip by default | Use `uv add` / `uv run --with`; recreate with `uv venv --seed` if pip is required |
| uv used a system Python | `python-preference` did not apply | Set `only-managed` in `[tool.uv]` |
| Pixi-provided CLIs or native libraries are missing in a plain shell | Not inside the Pixi environment | Run `pixi shell` (or `pixi run ...`) first |
| `uv run` cannot find a project | Not inside a project directory | Change into the project, or use `--no-project` / `uvx` |
| Installs are slow or disk usage doubles | Cache and venv are on different filesystems, so hardlinks degrade to copies | Keep them on one filesystem or set `UV_LINK_MODE` |
| The target machine has an older glibc | System requirements are not met | Declare `[system-requirements] libc` in `pixi.toml`, or use a matching platform |

## 12. Relationship to This Repository's Toolchain

The Pixi and uv manifests in this repository (`~/.myshell/pixi-tools.toml` and `~/.myshell/uv-tools.toml`) manage **machine-level commands**: `bat`, `rg`, `gh`, and similar CLIs come from Pixi global, while `uv tool` provides Python CLIs. This document covers **project-level environments**. The two do not interfere, but a given command should not be installed in both places, otherwise `PATH` precedence decides which one runs.

Install CLIs needed by a project with `pixi add`, and machine-wide personal CLIs with `pixi global install` or `uv tool install`.
