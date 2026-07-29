#!/usr/bin/env bash
set -euo pipefail

command -v chezmoi >/dev/null 2>&1 || {
    echo "chezmoi is required" >&2
    exit 1
}

OUTPUT_DIR=${1:-"$PWD"}
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$(chezmoi source-path)}"
CONFIG_DIR="${CHEZMOI_CONFIG_DIR:-$HOME/.config/chezmoi}"
DATE_TAG="$(date +%Y-%m-%d-%H%M%S)"
ARCHIVE_NAME="dotfiles-full-backup-$DATE_TAG.tar.gz"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
[[ -d "$SOURCE_DIR" ]] || {
    echo "chezmoi source directory is missing" >&2
    exit 1
}
mkdir -p "$OUTPUT_DIR"
[[ ! -e "$ARCHIVE_PATH" ]] || {
    echo "backup already exists: $ARCHIVE_PATH" >&2
    exit 1
}

backup_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-full-backup.XXXXXX")"
trap 'rm -rf -- "$backup_tmp"' EXIT HUP INT TERM
backup_root="$backup_tmp/dotfiles-full-backup-$DATE_TAG"
umask 077
mkdir -p "$backup_root/chezmoi-source" "$backup_root/chezmoi-config" "$backup_root/home-plaintext"

COPYFILE_DISABLE=1 tar -cf - -C "$SOURCE_DIR" . | tar -xf - -C "$backup_root/chezmoi-source"
if [[ -d "$CONFIG_DIR" ]]; then
    COPYFILE_DISABLE=1 tar -cf - -C "$CONFIG_DIR" . | tar -xf - -C "$backup_root/chezmoi-config"
fi
chezmoi -S "$SOURCE_DIR" archive | tar -xf - -C "$backup_root/home-plaintext"
git -C "$SOURCE_DIR" status --short --branch > "$backup_root/GIT_STATUS.txt" 2>/dev/null || true

cat > "$backup_root/README.txt" <<'EOF'
This is an intentionally unencrypted full dotfiles recovery backup.
It can contain passwords, tokens, SSH configuration, and an age identity.
Store it only in a private backup location.
EOF

(
    cd "$backup_root"
    find . -type f ! -name MANIFEST.sha256 | LC_ALL=C sort | while IFS= read -r backup_file; do
        shasum -a 256 "$backup_file"
    done > MANIFEST.sha256
)

COPYFILE_DISABLE=1 tar -czf "$ARCHIVE_PATH" -C "$backup_tmp" "$(basename "$backup_root")"
chmod 600 "$ARCHIVE_PATH"

verify_tmp="$backup_tmp/verify"
mkdir -p "$verify_tmp"
tar -xzf "$ARCHIVE_PATH" -C "$verify_tmp"
(
    cd "$verify_tmp/$(basename "$backup_root")"
    shasum -a 256 -c MANIFEST.sha256 >/dev/null
)

echo "Backup created: $ARCHIVE_PATH"
shasum -a 256 "$ARCHIVE_PATH"
