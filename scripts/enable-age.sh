#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi}"
CONFIG_DIR="$HOME/.config/chezmoi"
KEY_FILE="$CONFIG_DIR/key.txt"
SOURCE_CONFIG="$SOURCE_DIR/.chezmoi.toml.tmpl"

command -v chezmoi >/dev/null 2>&1 || {
    echo "chezmoi is required" >&2
    exit 1
}
[[ -d "$SOURCE_DIR" ]] || {
    echo "chezmoi source directory is missing: $SOURCE_DIR" >&2
    exit 1
}

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

if [[ ! -f "$KEY_FILE" ]]; then
    chezmoi age-keygen -o "$KEY_FILE"
    chmod 600 "$KEY_FILE"
fi

recipient="$(chezmoi age-keygen -y "$KEY_FILE")"
[[ "$recipient" == age1* ]] || {
    echo "could not derive an age recipient" >&2
    exit 1
}

if [[ -e "$SOURCE_CONFIG" ]]; then
    echo "Refusing to overwrite existing $SOURCE_CONFIG" >&2
    echo "Merge the following age settings manually:" >&2
    printf 'encryption = "age"\n\n[age]\n    identity = "~/.config/chezmoi/key.txt"\n    recipient = "%s"\n    useBuiltin = true\n' "$recipient"
    exit 1
fi

umask 077
{
    printf 'encryption = "age"\n\n'
    printf '[age]\n'
    printf '    identity = "~/.config/chezmoi/key.txt"\n'
    printf '    recipient = "%s"\n' "$recipient"
    printf '    useBuiltin = true\n'
} > "$SOURCE_CONFIG"
chmod 644 "$SOURCE_CONFIG"

chezmoi -S "$SOURCE_DIR" init

cat <<EOF
Age encryption is enabled.

Private identity: $KEY_FILE
Public recipient: $recipient

Store the private identity in a password manager before encrypting files.
Encrypt a managed target with:

  chezmoi add --encrypt ~/.ssh/config
EOF
