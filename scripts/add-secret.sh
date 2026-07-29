#!/usr/bin/env bash
set -euo pipefail

[[ $# -gt 0 ]] || {
    echo "Usage: $0 TARGET..." >&2
    exit 1
}
command -v chezmoi >/dev/null 2>&1 || {
    echo "chezmoi is required" >&2
    exit 1
}
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$(chezmoi source-path)}"
[[ -f "$HOME/.config/chezmoi/key.txt" ]] || {
    echo "age identity is missing; run scripts/enable-age.sh first" >&2
    exit 1
}

chezmoi -S "$SOURCE_DIR" add --encrypt -- "$@"
echo "Encrypted source files were updated. Review them with git status in $SOURCE_DIR."
