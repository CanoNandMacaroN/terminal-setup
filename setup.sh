#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -r "$SCRIPT_DIR/lib/common.sh" ]]; then
    printf 'setup.sh must be run from a cloned terminal-setup repository.\n' >&2
    printf 'For one-line usage, clone the repository first or set up your published URL.\n' >&2
    exit 1
fi

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

DOTFILES_REPO=""
AGE_KEY_FILE=""
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi}"
BACKUP_BASE="${TERMINAL_SETUP_BACKUP_DIR:-$HOME/.terminal-setup/backups}"
SKIP_SHELL_CHANGE=0
PRUNE=0

usage() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Options:
  --repo URL            Bootstrap an existing chezmoi repository.
  --age-key-file PATH   Import an age identity before applying dotfiles.
  --prune               Remove undeclared Brew formulae, casks, taps, and uv tools.
  --skip-shell-change   Do not make Zsh the login shell.
  --dry-run             Print actions without changing the machine.
  -h, --help            Show this help.

macOS installs the workstation workflow. Linux/WSL installs the headless
server workflow. Run ./doctor.sh separately for diagnostics.

Without --repo, the bundled public starter is copied into the chezmoi source
directory. It contains no personal repository URL, identity, age recipient,
host, token, or credential.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) [[ $# -ge 2 ]] || die "--repo requires a URL"; DOTFILES_REPO=$2; shift 2 ;;
        --age-key-file) [[ $# -ge 2 ]] || die "--age-key-file requires a path"; AGE_KEY_FILE=$2; shift 2 ;;
        --prune) PRUNE=1; shift ;;
        --skip-shell-change) SKIP_SHELL_CHANGE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

PLATFORM="$(detect_platform)"
case "$PLATFORM" in
    macos|debian|wsl) ;;
    windows-native) die "Native Windows is unsupported. Run inside WSL." ;;
    *) die "Unsupported platform: $(uname -s)" ;;
esac

if [[ "$PLATFORM" == macos ]]; then
    PROFILE="workstation"
else
    PROFILE="server"
fi
export TERMINAL_SETUP_PROFILE="$PROFILE"

ensure_macos_command_line_tools() {
    [[ "$PLATFORM" == macos ]] || return 0
    if [[ "${TERMINAL_SETUP_TEST_CLT_MISSING:-0}" != 1 ]] && \
        xcode-select -p >/dev/null 2>&1 && xcrun --find clang >/dev/null 2>&1; then
        success "Xcode Command Line Tools already installed"
        return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would open the Xcode Command Line Tools installer"
        return
    fi
    xcode-select --install >/dev/null 2>&1 || true
    die "Complete the Xcode Command Line Tools installation, then rerun setup.sh"
}

install_homebrew() {
    if has_cmd brew; then
        success "Homebrew already installed"
        return
    fi
    info "Installing Homebrew from the official installer"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would run the Homebrew official installer"
        return
    fi
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    case "$(detect_arch)" in
        arm64)
            [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
            ;;
        x86_64)
            [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
            ;;
        *)
            die "Unsupported macOS architecture: $(uname -m)"
            ;;
    esac
}

install_linux_starship_font() {
    local font_dir font_temp_dir font_base font_variant font_style font_file font_sha256
    font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MesloLGS-NF"
    if find "$font_dir" -maxdepth 1 -type f -name 'MesloLGSNerdFont-*.ttf' -print -quit 2>/dev/null | grep -q .; then
        success "MesloLGS Nerd Font already installed"
        return
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would install MesloLGS Nerd Font for the Starship prompt"
        return
    fi

    font_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup-font.XXXXXX")"
    font_base="https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/patched-fonts/Meslo/S"
    for font_variant in Regular:Regular Bold:Bold Italic:Italic Bold-Italic:BoldItalic; do
        font_style=${font_variant%%:*}
        font_file="MesloLGSNerdFont-${font_variant#*:}.ttf"
        case "$font_file" in
            MesloLGSNerdFont-Regular.ttf) font_sha256=44ae9b687639c1529ecd01e5d0ae8d98f3b30cb20b02bbe4e6d9fb474c8dee36 ;;
            MesloLGSNerdFont-Bold.ttf) font_sha256=9799788a96066045c3f53f2e5bcbe376c6b9adb9514e3276cc84ac42d8b176d0 ;;
            MesloLGSNerdFont-Italic.ttf) font_sha256=3dede17df16e62abdae99ea7f13a14cbc391e2cc9429c8dfa1b5349e78758e9c ;;
            MesloLGSNerdFont-BoldItalic.ttf) font_sha256=734956444bc02c8ea0e7f7effe46c616f2e492734c6afe91049e4735d522542c ;;
            *) die "Unexpected font file: $font_file" ;;
        esac
        curl -fsSL "$font_base/$font_style/$font_file" -o "$font_temp_dir/$font_file"
        printf '%s  %s\n' "$font_sha256" "$font_temp_dir/$font_file" | sha256sum -c - >/dev/null ||
            die "Checksum verification failed for $font_file"
    done
    mkdir -p "$font_dir"
    install -m 644 "$font_temp_dir"/MesloLGSNerdFont-*.ttf "$font_dir/"
    rm -f -- "$font_temp_dir"/MesloLGSNerdFont-*.ttf
    rmdir "$font_temp_dir"

    find "$font_dir" -maxdepth 1 -type f -name 'MesloLGSNerdFont-*.ttf' -print -quit | grep -q . ||
        die "MesloLGS Nerd Font archive did not contain the expected files"
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$font_dir" >/dev/null 2>&1 || true
    success "MesloLGS Nerd Font installed for the Starship prompt"
}

install_linux_prerequisites() {
    local package
    run sudo apt-get update
    run sudo apt-get install -y \
        ca-certificates curl git openssh-client rsync zsh build-essential \
        jq fzf ripgrep fd-find bat tmux

    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would install htop, tree, and Zsh plugins when available"
    else
        for package in htop tree; do
            sudo apt-get install -y "$package" || warn "Optional package unavailable: $package"
        done
        sudo apt-get install -y zsh-autosuggestions zsh-syntax-highlighting zoxide || \
            warn "Some optional zsh/zoxide packages were unavailable from apt"
    fi

    run mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
    if has_cmd batcat && ! has_cmd bat; then
        run ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    fi
    if has_cmd fdfind && ! has_cmd fd; then
        run ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    fi

    if ! has_cmd chezmoi; then
        info "Installing chezmoi from its official installer"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "Would install chezmoi into $HOME/.local/bin"
        else
            mkdir -p "$HOME/.local/bin"
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi

    if ! has_cmd uv; then
        info "Installing uv from its official installer"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "Would install uv"
        else
            curl -LsSf https://astral.sh/uv/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi

    if ! has_cmd starship; then
        info "Installing Starship from its official installer"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "Would install Starship into $HOME/.local/bin"
        else
            curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
        fi
    fi

    if ! has_cmd fnm; then
        info "Installing fnm from its official installer"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "Would install fnm without modifying shell files"
        else
            curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
            export PATH="$HOME/.local/share/fnm:$PATH"
        fi
    fi

    install_linux_starship_font
}

install_prerequisites() {
    section "Platform prerequisites"
    info "Detected $(platform_label "$PLATFORM") ($(detect_arch)); profile: $PROFILE"
    case "$PLATFORM" in
        macos)
            ensure_macos_command_line_tools
            install_homebrew
            has_cmd brew || [[ "$DRY_RUN" -eq 1 ]] || die "Homebrew installation failed"
            if [[ "$DRY_RUN" -eq 1 ]]; then
                warn "Would install git, curl, and chezmoi with Homebrew"
            else
                brew install git curl chezmoi
            fi
            ;;
        debian|wsl)
            install_linux_prerequisites
            ;;
    esac
}

configure_default_shell() {
    local zsh_path current_shell account_name
    section "Default shell"
    if [[ "$SKIP_SHELL_CHANGE" -eq 1 ]]; then
        warn "Skipping login-shell change"
        return
    fi
    zsh_path="$(command -v zsh 2>/dev/null || true)"
    [[ -n "$zsh_path" ]] || { warn "Zsh is unavailable; login shell was not changed"; return; }
    account_name="${USER:-$(id -un)}"
    if command -v getent >/dev/null 2>&1; then
        current_shell="$(getent passwd "$account_name" | awk -F: '{print $7}')"
    else
        current_shell="${SHELL:-}"
    fi
    if [[ "$current_shell" == "$zsh_path" || "$current_shell" == */zsh ]]; then
        success "Zsh is already the login shell"
        return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would set the login shell to $zsh_path"
        return
    fi
    if [[ "$PLATFORM" == macos ]]; then
        chsh -s "$zsh_path"
    else
        sudo chsh -s "$zsh_path" "$account_name"
    fi
    success "Login shell changed to $zsh_path; it takes effect on the next login"
}

copy_starter_source() {
    local starter_dir="$SCRIPT_DIR/starter"
    [[ -d "$starter_dir" ]] || die "starter source is missing: $starter_dir"

    if [[ -d "$SOURCE_DIR" ]] && [[ -n "$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        success "Reusing existing chezmoi source without overwriting it: $SOURCE_DIR"
        return
    fi

    info "Creating a local chezmoi source from the public starter"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would copy starter to $SOURCE_DIR and initialize Git"
        return
    fi
    mkdir -p "$SOURCE_DIR"
    COPYFILE_DISABLE=1 tar -cf - -C "$starter_dir" . | tar -xf - -C "$SOURCE_DIR"
    if [[ ! -d "$SOURCE_DIR/.git" ]]; then
        git -C "$SOURCE_DIR" init -b main >/dev/null
    fi
}

initialize_source() {
    section "Chezmoi source"
    if [[ -n "$DOTFILES_REPO" ]]; then
        info "Initializing the provided chezmoi repository"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "Would initialize $DOTFILES_REPO into $SOURCE_DIR"
        else
            chezmoi -S "$SOURCE_DIR" init "$DOTFILES_REPO"
        fi
    else
        copy_starter_source
    fi
}

install_age_key() {
    local key_target="$HOME/.config/chezmoi/key.txt" key_value
    [[ -d "$SOURCE_DIR" ]] || return 0
    if ! find "$SOURCE_DIR" -type f -name 'encrypted_*.age' -print -quit 2>/dev/null | grep -q .; then
        success "No encrypted source files require an age identity"
        return 0
    fi

    section "Age identity"
    if [[ -f "$key_target" ]]; then
        run chmod 600 "$key_target"
        success "Existing age identity found"
        return 0
    fi

    ensure_private_dir "$HOME/.config/chezmoi"
    if [[ -n "$AGE_KEY_FILE" ]]; then
        [[ -r "$AGE_KEY_FILE" ]] || die "age key file is unreadable: $AGE_KEY_FILE"
        grep -q '^AGE-SECRET-KEY-1' "$AGE_KEY_FILE" || die "invalid age identity file"
        run install -m 600 "$AGE_KEY_FILE" "$key_target"
        success "Age identity imported"
        return 0
    fi

    printf 'Paste AGE-SECRET-KEY-... from your password manager: ' >&2
    read -r -s key_value
    printf '\n' >&2
    [[ "$key_value" == AGE-SECRET-KEY-1* ]] || die "invalid age identity"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would store the age identity at $key_target with mode 600"
    else
        umask 077
        printf '%s\n' "$key_value" > "$key_target"
        chmod 600 "$key_target"
    fi
    key_value=""
    success "Age identity stored"
}

backup_managed_targets() {
    local timestamp backup_dir target relative destination
    section "Existing configuration backup"
    [[ "$DRY_RUN" -eq 0 ]] || { warn "Would back up existing managed targets"; return; }

    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$BACKUP_BASE/$timestamp/home"
    mkdir -p "$backup_dir"

    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        relative=${target#./}
        [[ -e "$HOME/$relative" || -L "$HOME/$relative" ]] || continue
        destination="$backup_dir/$relative"
        mkdir -p "$(dirname "$destination")"
        cp -pPR "$HOME/$relative" "$destination"
    done < <(chezmoi -S "$SOURCE_DIR" managed --include files,symlinks 2>/dev/null || true)

    if find "$backup_dir" -mindepth 1 -print -quit | grep -q .; then
        success "Existing targets backed up to $backup_dir"
    else
        rmdir "$backup_dir" 2>/dev/null || true
        success "No existing managed targets needed backup"
    fi
}

apply_dotfiles() {
    local apply_source="$SOURCE_DIR"
    section "Apply dotfiles and manifests"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ -n "$DOTFILES_REPO" && ! -d "$SOURCE_DIR" ]]; then
            warn "Repository mode cannot render a dry-run before the repository is cloned"
            return
        fi
        if [[ -z "$DOTFILES_REPO" && ! -d "$SOURCE_DIR" ]]; then
            apply_source="$SCRIPT_DIR/starter"
        fi
        chezmoi -S "$apply_source" apply --dry-run --verbose --no-tty
        return
    fi

    [[ "$PRUNE" -eq 0 ]] || warn "Manifest pruning enabled: undeclared Brew entries and uv tools may be removed"
    TERMINAL_SETUP_PRUNE=0 chezmoi -S "$SOURCE_DIR" apply
    chezmoi -S "$SOURCE_DIR" verify
    success "Chezmoi target state verified"
}

prune_manifests() {
    local desired_file current_file tool
    [[ "$PRUNE" -eq 1 ]] || return 0
    section "Manifest pruning"

    if [[ "$(uname -s)" == Darwin && -f "$HOME/.Brewfile" ]] && command -v brew >/dev/null 2>&1; then
        warn "Removing Homebrew formulae, casks, and taps not declared by ~/.Brewfile"
        HOMEBREW_NO_AUTO_UPDATE=1 brew bundle cleanup --global --force --formula --cask --tap
    fi

    if command -v uv >/dev/null 2>&1 && [[ -f "$HOME/.myshell/uv-tools.toml" ]]; then
        desired_file="$(mktemp "${TMPDIR:-/tmp}/terminal-setup-uv-desired.XXXXXX")"
        current_file="$(mktemp "${TMPDIR:-/tmp}/terminal-setup-uv-current.XXXXXX")"
        awk '
            $0 == "[[tool]]" { in_tool=1; next }
            in_tool && /^name = "/ {
                value=$0
                sub(/^name = "/, "", value)
                sub(/"$/, "", value)
                print value
                in_tool=0
            }
        ' "$HOME/.myshell/uv-tools.toml" | LC_ALL=C sort -u > "$desired_file"
        if [[ ! -s "$desired_file" ]]; then
            rm -f -- "$desired_file" "$current_file"
            die "uv-tools.toml contains no valid tool names; refusing to prune"
        fi
        uv tool list | awk 'NF && $1 != "-" { print $1 }' | LC_ALL=C sort -u > "$current_file"
        while IFS= read -r tool; do
            [[ -n "$tool" ]] || continue
            grep -Fqx -- "$tool" "$desired_file" || uv tool uninstall "$tool"
        done < "$current_file"
        rm -f -- "$desired_file" "$current_file"
    fi

    success "Package manifests pruned"
}

initialize_node() {
    section "fnm, Node.js, Corepack, and pnpm"
    if ! has_cmd fnm; then
        warn "fnm is not installed yet; open a new shell after package installation and rerun setup"
        return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Would use fnm to ensure Node LTS, then enable Corepack and pnpm"
        return
    fi

    eval "$(fnm env --shell bash)"
    fnm install --lts
    fnm default lts-latest
    fnm use lts-latest
    corepack enable
    corepack prepare pnpm@latest --activate
    success "Node $(node --version) and pnpm $(pnpm --version) are ready"
}

install_prerequisites
configure_default_shell
initialize_source

if [[ "$DRY_RUN" -eq 0 ]]; then
    has_cmd chezmoi || die "chezmoi is required"
fi

install_age_key
if [[ "$DRY_RUN" -eq 0 ]]; then
    backup_managed_targets
fi
apply_dotfiles
if [[ "$DRY_RUN" -eq 0 ]]; then
    prune_manifests
fi
initialize_node

printf '\n'
success "Terminal setup completed"
info "Run ./doctor.sh for a detailed health check"
if [[ -z "$DOTFILES_REPO" ]]; then
    info "Your local starter source is at $SOURCE_DIR"
    info "Add your own private Git remote before publishing this source"
fi
