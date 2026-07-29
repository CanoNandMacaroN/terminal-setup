#!/usr/bin/env bash

detect_platform() {
    if [[ -n "${TERMINAL_SETUP_TEST_PLATFORM:-}" ]]; then
        printf '%s\n' "$TERMINAL_SETUP_TEST_PLATFORM"
        return
    fi

    case "$(uname -s)" in
        Darwin)
            printf 'macos\n'
            ;;
        Linux)
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
                printf 'wsl\n'
            elif [[ -f /etc/debian_version ]] || grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null; then
                printf 'debian\n'
            else
                printf 'unsupported\n'
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            printf 'windows-native\n'
            ;;
        *)
            printf 'unsupported\n'
            ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64\n' ;;
        x86_64|amd64) printf 'x86_64\n' ;;
        *) uname -m ;;
    esac
}

platform_label() {
    case "$1" in
        macos) printf 'macOS\n' ;;
        debian) printf 'Debian/Ubuntu\n' ;;
        wsl) printf 'Windows WSL\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}
