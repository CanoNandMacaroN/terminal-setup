#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -s)" != Linux && "${TERMINAL_SETUP_TEST_PLATFORM:-}" != debian && \
    "${TERMINAL_SETUP_TEST_PLATFORM:-}" != wsl ]]; then
    printf 'server-setup.sh supports Linux/WSL only.\n' >&2
    exit 1
fi

exec "$SCRIPT_DIR/setup.sh" "$@"
