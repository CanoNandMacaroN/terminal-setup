# Optional uv tools

The public uv manifest installs only `ruff`. Other tools should be selected by project or machine role.

## Harlequin

```sh
uv tool install harlequin
```

## Determined CLI compatibility environment

```sh
uv tool install \
  --python 3.10 \
  --with PyYAML==5.3.1 \
  --with ruamel-yaml==0.17.40 \
  determined==0.19.10
```

Add a tool to a private `~/.myshell/uv-tools.toml` only when it should be restored automatically on every machine using that private source.
