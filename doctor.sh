#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

failures=0
warnings=0
platform="$(detect_platform)"
profile="${TERMINAL_SETUP_PROFILE:-}"
if [[ -z "$profile" ]]; then
    if [[ "$platform" == macos ]]; then
        profile="workstation"
    else
        profile="server"
    fi
fi

file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

check_required() {
    local command_name=$1
    if has_cmd "$command_name"; then
        success "$command_name: $(command -v "$command_name")"
    else
        warn "$command_name is missing"
        failures=$((failures + 1))
    fi
}

check_optional() {
    local command_name=$1
    if has_cmd "$command_name"; then
        success "$command_name: available"
    else
        warn "$command_name: optional, not installed"
        warnings=$((warnings + 1))
    fi
}

section "Platform"
info "$(platform_label "$platform") / $(detect_arch) / $profile profile"

section "Required commands"
for command_name in git curl chezmoi zsh; do
    check_required "$command_name"
done

section "Workflow tools"
if has_cmd fnm; then
    eval "$(fnm env --shell bash)" 2>/dev/null || true
    fnm use --silent-if-unchanged default >/dev/null 2>&1 || true
fi
for command_name in starship fnm node corepack pnpm uv fzf zoxide jq rg fd bat lazygit yazi; do
    check_optional "$command_name"
done

if [[ "$profile" == server ]]; then
    section "Server tools"
    for command_name in ssh rsync tmux; do
        check_optional "$command_name"
    done
fi

section "Package manifests"
for manifest in "$HOME/.myshell/uv_tools.list"; do
    if [[ -f "$manifest" ]]; then
        success "$manifest: present"
    else
        warn "$manifest: missing"
        warnings=$((warnings + 1))
    fi
done
if [[ "$platform" == macos ]]; then
    manifest="$HOME/.Brewfile"
    if [[ -f "$manifest" ]]; then
        success "$manifest: present"
    else
        warn "$manifest: missing"
        warnings=$((warnings + 1))
    fi
fi

section "Chezmoi"
source_dir="$(chezmoi source-path 2>/dev/null || true)"
if [[ -n "$source_dir" && -d "$source_dir" ]]; then
    success "source: $source_dir"
    if chezmoi verify >/dev/null 2>&1; then
        success "target state verified"
    else
        warn "target state differs; inspect with chezmoi status and chezmoi diff"
        warnings=$((warnings + 1))
    fi

    if find "$source_dir" -type f -name 'encrypted_*.age' -print -quit 2>/dev/null | grep -q .; then
        key_file="$HOME/.config/chezmoi/key.txt"
        if [[ -f "$key_file" && "$(file_mode "$key_file")" == 600 ]]; then
            success "age identity exists with mode 600"
        else
            warn "encrypted files exist but age identity is missing or has wrong permissions"
            failures=$((failures + 1))
        fi
    fi
else
    warn "chezmoi source directory is not initialized"
    failures=$((failures + 1))
fi

printf '\n'
if [[ "$failures" -gt 0 ]]; then
    die "$failures required checks failed; $warnings optional warnings"
fi
success "Doctor passed with $warnings optional warnings"
