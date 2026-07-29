#!/usr/bin/env bash

if [[ -t 1 ]]; then
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_YELLOW=$'\033[33m'
    COLOR_BLUE=$'\033[34m'
    COLOR_BOLD=$'\033[1m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_BOLD=""
    COLOR_RESET=""
fi

DRY_RUN=${DRY_RUN:-0}

info() { printf '%s[INFO]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"; }
success() { printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
die() { printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; exit 1; }

section() {
    printf '\n%s== %s ==%s\n' "$COLOR_BOLD" "$*" "$COLOR_RESET"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '%s[DRY-RUN]%s' "$COLOR_YELLOW" "$COLOR_RESET"
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

ensure_private_dir() {
    local directory=$1
    run mkdir -p "$directory"
    run chmod 700 "$directory"
}
