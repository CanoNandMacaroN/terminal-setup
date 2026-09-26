#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -s)" != Linux && "${TERMINAL_SETUP_TEST_PLATFORM:-}" != debian && \
    "${TERMINAL_SETUP_TEST_PLATFORM:-}" != wsl ]]; then
    printf 'server-setup.sh supports Linux/WSL only.\n' >&2
    exit 1
fi

if [[ "${1:-}" == --services ]]; then
    shift
    exec "$SCRIPT_DIR/server-services/setup.sh" "$@"
fi
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    "$SCRIPT_DIR/setup.sh" --help
    printf '\nOptional server services:\n  ./server-setup.sh --services --config /path/to/server-services.toml [--dry-run]\n'
    exit 0
fi

exec "$SCRIPT_DIR/setup.sh" "$@"
