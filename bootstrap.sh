#!/bin/sh
set -eu

repo_url=${TERMINAL_SETUP_REPO_URL:-${1:-}}
if [ -z "$repo_url" ]; then
    echo "Usage: bootstrap.sh REPOSITORY_URL [setup options...]" >&2
    exit 1
fi
shift || true

command -v git >/dev/null 2>&1 || {
    echo "git is required to bootstrap terminal-setup" >&2
    exit 1
}

bootstrap_tmp=$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup.XXXXXX")
trap 'rm -rf -- "$bootstrap_tmp"' EXIT HUP INT TERM
git clone --depth 1 "$repo_url" "$bootstrap_tmp/repo"
"$bootstrap_tmp/repo/setup.sh" "$@"
