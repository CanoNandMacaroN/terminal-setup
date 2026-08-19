#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo "[1/10] Shell syntax"
bash -n "$ROOT/setup.sh" "$ROOT/server-setup.sh" "$ROOT/doctor.sh" "$ROOT/lib/common.sh" "$ROOT/lib/platform.sh"
bash -n "$ROOT/starter/.chezmoitemplates/pixi-tools.sh"
bash -n "$ROOT/scripts/enable-age.sh" "$ROOT/scripts/add-secret.sh" "$ROOT/scripts/full-backup.sh"
for reset_script in "$ROOT"/starter/dot_myshell/bin/*.sh; do
    [[ -e "$reset_script" ]] || continue
    bash -n "$reset_script"
done
zsh -n "$ROOT/starter/dot_zshenv"
zsh -n "$ROOT/starter/dot_myshell/functions/executable_env-sync"

echo "[2/10] Platform detection"
# shellcheck source=../lib/platform.sh
source "$ROOT/lib/platform.sh"
for expected in macos debian wsl windows-native; do
    actual="$(TERMINAL_SETUP_TEST_PLATFORM="$expected" detect_platform)"
    [[ "$actual" == "$expected" ]] || fail "expected $expected, got $actual"
done

echo "[3/10] Chezmoi template rendering"
chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/run_onchange_install-packages.sh.tmpl" | bash -n
chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/run_onchange_install-uv-tools.sh.tmpl" | bash -n
chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/dot_zprofile.tmpl" | zsh -n
chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/dot_zshrc.tmpl" | zsh -n
linux_data='{"chezmoi":{"os":"linux","arch":"amd64","homeDir":"/home/tester"}}'
chezmoi -S "$ROOT/starter" --override-data "$linux_data" execute-template \
    < "$ROOT/starter/run_onchange_install-packages.sh.tmpl" | bash -n
chezmoi -S "$ROOT/starter" --override-data "$linux_data" execute-template \
    < "$ROOT/starter/run_onchange_install-pixi-tools.sh.tmpl" | bash -n
chezmoi -S "$ROOT/starter" --override-data "$linux_data" execute-template \
    < "$ROOT/starter/dot_zprofile.tmpl" | zsh -n
linux_zshrc="$(chezmoi -S "$ROOT/starter" --override-data "$linux_data" execute-template \
    < "$ROOT/starter/dot_zshrc.tmpl")"
printf '%s\n' "$linux_zshrc" | zsh -n
rg -q 'export FNM_HOME=.*\.local/share.*fnm' <<< "$linux_zshrc" || \
    fail "Linux zshrc does not define the user-level fnm directory"
rg -q 'PATH="\$FNM_HOME:\$PATH"' <<< "$linux_zshrc" || \
    fail "Linux zshrc does not persist the fnm PATH"
rg -q 'PIXI_HOME.*\.pixi' <<< "$linux_zshrc" || fail "Linux zshrc does not define the Pixi home"
rg -q 'PATH="\$PIXI_HOME/bin:\$PATH"' <<< "$linux_zshrc" || fail "Linux zshrc does not persist Pixi"
darwin_intel_data='{"chezmoi":{"os":"darwin","arch":"amd64","homeDir":"/Users/tester"}}'
intel_profile="$(chezmoi -S "$ROOT/starter" --override-data "$darwin_intel_data" execute-template \
    < "$ROOT/starter/dot_zprofile.tmpl")"
rg -q '/usr/local/bin/brew' <<< "$intel_profile" || fail "Intel macOS did not select /usr/local Homebrew"
if rg -q '/opt/homebrew/bin/brew' <<< "$intel_profile"; then
    fail "Intel macOS rendered the Apple Silicon Homebrew path"
fi
if rg -q '^(cask|tap) "' "$ROOT/starter/dot_Brewfile"; then
    fail "public Brewfile contains a cask or third-party tap"
fi
if rg -qi 'codebuddy|codex|cc-switch|cmux|ghostty|orca|spotify' "$ROOT/starter/dot_Brewfile"; then
    fail "public Brewfile contains an application or AI-specific tool"
fi
for formula in bat chezmoi fd fnm fzf jq ripgrep starship uv zoxide; do
    rg -q "^brew \"$formula\"$" "$ROOT/starter/dot_Brewfile" || fail "baseline formula is missing: $formula"
done
for pixi_environment in bat chezmoi eza fd fnm fzf jq ripgrep starship tmux uv yazi zoxide zsh; do
    rg -q "^environment = \"$pixi_environment\"$" "$ROOT/starter/dot_myshell/pixi-tools.toml" || \
        fail "Pixi baseline environment is missing: $pixi_environment"
done
rg -A3 '^environment = "tmux"$' "$ROOT/starter/dot_myshell/pixi-tools.toml" | \
    rg -q '^platforms = "linux"$' || fail "tmux is not limited to Linux"
rg -A3 '^environment = "zsh"$' "$ROOT/starter/dot_myshell/pixi-tools.toml" | \
    rg -q '^platforms = "linux"$' || fail "zsh is not limited to Linux"
rg -A3 '^environment = "git"$' "$ROOT/starter/dot_myshell/pixi-tools.toml" | \
    rg -q '^platforms = "windows"$' || fail "Pixi Git bootstrap is not limited to Windows"
if rg -qi 'codebuddy|codex|cc-switch|cmux|ghostty|orca|spotify' "$ROOT/starter/dot_myshell/pixi-tools.toml"; then
    fail "public Pixi manifest contains an application or AI-specific tool"
fi
[[ "$(rg -c '^\[\[tool\]\]$' "$ROOT/starter/dot_myshell/uv-tools.toml")" -eq 1 ]] || \
    fail "public uv manifest must contain exactly one tool"
rg -q '^name = "ruff"$' "$ROOT/starter/dot_myshell/uv-tools.toml" || fail "ruff is missing from the uv baseline"
if rg -qi 'determined|harlequin' "$ROOT/starter/dot_myshell/uv-tools.toml"; then
    fail "specialist uv tools remain in the public manifest"
fi
rg -q 'nerd-fonts/v3\.4\.0/patched-fonts/Meslo/S' "$ROOT/setup.sh" || \
    fail "prompt font installer is missing or unpinned"
[[ "$(rg -c 'font_sha256=[0-9a-f]{64}' "$ROOT/setup.sh")" -eq 4 ]] || \
    fail "prompt fonts do not have four pinned checksums"
rg -q '' "$ROOT/starter/dot_config/starship.toml" || fail "current Starship prompt theme was not synchronized"
if rg -q 'git|chezmoi-push' "$ROOT/starter/dot_myshell/functions/executable_env-sync"; then
    fail "env-sync must not stage, commit, or push"
fi
for env_sync_marker in 'brew tap' 'brew list --cask' 'pixi global list --json' 'pixi-tools.toml' 'uv-receipt.toml'; do
    rg -q "$env_sync_marker" "$ROOT/starter/dot_myshell/functions/executable_env-sync" || \
        fail "env-sync no longer captures $env_sync_marker"
done
windows_data='{"chezmoi":{"os":"windows","arch":"amd64","homeDir":"C:/Users/tester"}}'
windows_managed="$(chezmoi -S "$ROOT/starter" --override-data "$windows_data" managed --include files)"
rg -q 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1' <<< "$windows_managed" || \
    fail "Windows PowerShell 7 profile is not managed"
if rg -q 'Documents/PowerShell/profile.ps1' <<< "$windows_managed"; then
    fail "Windows uses a profile filename that PowerShell 7 does not load"
fi
rg -q '\.myshell/bin/sync-tools.ps1' <<< "$windows_managed" || fail "Windows tool sync script is not managed"
if rg -q '\.zshrc|install-pixi-tools\.sh' <<< "$windows_managed"; then
    fail "Windows still manages Unix-only targets"
fi
for powershell_template in \
    "$ROOT/starter/dot_myshell/bin/sync-tools.ps1.tmpl" \
    "$ROOT/starter/Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl"; do
    rendered_powershell="$(chezmoi -S "$ROOT/starter" --override-data "$windows_data" execute-template < "$powershell_template")"
    rg -q '\$ErrorActionPreference|\$PixiHome' <<< "$rendered_powershell" || \
        fail "Windows PowerShell template did not render: $(basename "$powershell_template")"
done
rg -q 'https://pixi\.sh/install\.ps1' "$ROOT/setup.ps1" || fail "Windows setup does not use the official Pixi installer"
rg -q 'PSVersionTable\.PSVersion\.Major -lt 7' "$ROOT/setup.ps1" || \
    fail "Windows setup does not enforce PowerShell 7"
rg -q 'pixi global uninstall' "$ROOT/setup.sh" || fail "Linux explicit Pixi pruning is missing"
rg -q '"global", "uninstall"' "$ROOT/setup.ps1" || fail "Windows explicit Pixi pruning is missing"
rg -q 'Get-DeclaredPixiEnvironments.*"windows"' "$ROOT/setup.ps1" || \
    fail "Windows Pixi pruning is not platform-aware"
rg -q 'terminal_setup_pixi_entries_for_platform.*linux' "$ROOT/setup.sh" || \
    fail "Linux Pixi pruning is not platform-aware"
if rg -q -- '--branch|zsh-autosuggestions.*v0\.7\.1|zsh-syntax-highlighting.*0\.8\.0' "$ROOT/setup.sh"; then
    fail "user-only Zsh plugins are still pinned to detached Git tags"
fi
rg -q 'git clone --quiet --depth 1 "\$plugin_repo"' "$ROOT/setup.sh" || \
    fail "user-only Zsh plugins are not cloned from their default branches"

echo "[4/10] Starter target preview"
mkdir -p "$TEST_TMP/home"
preview="$(HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" apply --dry-run --verbose --no-tty)"
[[ -n "$preview" ]] || fail "starter dry-run produced no target changes"

echo "[5/10] Isolated starter apply"
HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" apply --exclude scripts --no-tty
HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" verify --exclude scripts
HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" apply --exclude scripts --no-tty
HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" verify --exclude scripts
[[ -f "$TEST_TMP/home/.zshrc" ]] || fail "isolated apply did not create .zshrc"
[[ ! -e "$TEST_TMP/home/.config/ghostty/config" ]] || fail "application-specific Ghostty configuration was applied"
[[ ! -e "$TEST_TMP/home/.config/cmux/cmux.json" ]] || fail "application-specific cmux configuration was applied"
[[ -x "$TEST_TMP/home/.myshell/functions/env-sync" ]] || fail "env-sync is not executable"

echo "[6/10] Manifest reconciliation safety"
fake_bin="$TEST_TMP/fake-bin"
fake_home="$TEST_TMP/fake-manifest-home"
fake_log="$TEST_TMP/manifest.log"
mkdir -p "$fake_bin" "$fake_home/.myshell"
cp "$ROOT/starter/dot_myshell/uv-tools.toml" "$fake_home/.myshell/uv-tools.toml"
cp "$ROOT/starter/dot_myshell/pixi-tools.toml" "$fake_home/.myshell/pixi-tools.toml"

cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
echo Darwin
EOF
cat > "$fake_bin/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "$FAKE_LOG"
EOF
cat > "$fake_bin/uv" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "tool list")
        printf 'ruff v1\n- ruff\nblack v1\n- black\n'
        ;;
    *)
        echo "uv $*" >> "$FAKE_LOG"
        ;;
esac
EOF
cat > "$fake_bin/pixi" <<'EOF'
#!/usr/bin/env bash
echo "pixi $*" >> "$FAKE_LOG"
EOF
cat > "$fake_bin/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$fake_bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
command_path=${!#}
[[ "$command_path" == */jq ]]
EOF
chmod +x "$fake_bin/uname" "$fake_bin/brew" "$fake_bin/uv" "$fake_bin/pixi" \
    "$fake_bin/jq" "$fake_bin/dpkg-query"

chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/run_onchange_install-packages.sh.tmpl" > "$TEST_TMP/install-packages.sh"
chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/run_onchange_install-uv-tools.sh.tmpl" > "$TEST_TMP/install-uv.sh"
chezmoi -S "$ROOT/starter" --override-data "$linux_data" execute-template \
    < "$ROOT/starter/run_onchange_install-pixi-tools.sh.tmpl" > "$TEST_TMP/install-pixi.sh"
chmod +x "$TEST_TMP/install-packages.sh" "$TEST_TMP/install-pixi.sh" "$TEST_TMP/install-uv.sh"

FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=0 "$TEST_TMP/install-packages.sh" >/dev/null
FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=0 "$TEST_TMP/install-pixi.sh" >/dev/null
FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=0 "$TEST_TMP/install-uv.sh" >/dev/null
if rg -q 'cleanup|uninstall' "$fake_log"; then
    fail "default reconciliation pruned packages"
fi
rg -q '^uv tool install ruff --force$' "$fake_log" || fail "ruff should remain unpinned"
rg -q '^pixi global install --environment ripgrep --expose rg=rg ripgrep$' "$fake_log" || \
    fail "Pixi did not install the ripgrep environment"
rg -q '^pixi global install --environment tmux --expose tmux=tmux tmux$' "$fake_log" || \
    fail "Pixi did not install the Linux-only tmux environment"
if rg -q '^pixi global install --environment jq ' "$fake_log"; then
    fail "normal Linux reconciliation duplicated an apt-owned jq command"
fi
if rg -q '^pixi global install --environment git ' "$fake_log"; then
    fail "Linux installed the Windows-only Git Pixi environment"
fi
if rg -q 'determined|harlequin|uv python install' "$fake_log"; then
    fail "specialist uv tools were installed by the public manifest"
fi

reuse_apt_log="$TEST_TMP/reuse-apt.log"
FAKE_LOG="$reuse_apt_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" \
    TERMINAL_SETUP_PRUNE=0 "$TEST_TMP/install-pixi.sh" >/dev/null
if rg -q '^pixi global install --environment jq ' "$reuse_apt_log"; then
    fail "user-only reconciliation duplicated an apt-owned jq command"
fi
rg -q '^pixi global install --environment ripgrep ' "$reuse_apt_log" || \
    fail "user-only reconciliation did not fill a missing command through Pixi"

FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=1 "$TEST_TMP/install-packages.sh" >/dev/null
FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=1 "$TEST_TMP/install-uv.sh" >/dev/null
rg -q 'brew bundle cleanup --global --force --formula$' "$fake_log" || \
    fail "explicit Brew pruning did not cover formulae"
if rg -q -- '--cask|--tap' "$fake_log"; then
    fail "public pruning attempted to remove casks or taps"
fi
rg -q 'uv tool uninstall black' "$fake_log" || fail "explicit uv pruning was not executed"
if rg -q 'uv tool uninstall ruff' "$fake_log"; then
    fail "explicit uv pruning removed a declared tool"
fi
rg -q 'contains no valid tool names; refusing to prune' "$ROOT/setup.sh" || \
    fail "installer lacks an empty uv manifest pruning guard"
rg -q 'contains no valid environments; refusing to prune' "$ROOT/setup.sh" || \
    fail "installer lacks an empty Pixi manifest pruning guard"

echo "[7/10] Age enablement and encrypted add"
age_home="$TEST_TMP/age-home"
age_source="$TEST_TMP/age-source"
mkdir -p "$age_home" "$age_source"
tar -cf - -C "$ROOT/starter" . | tar -xf - -C "$age_source"
HOME="$age_home" CHEZMOI_SOURCE_DIR="$age_source" "$ROOT/scripts/enable-age.sh" >/dev/null
[[ -f "$age_home/.config/chezmoi/key.txt" ]] || fail "age identity was not created"
[[ -f "$age_source/.chezmoi.toml.tmpl" ]] || fail "age source config was not created"
age_recipient="$(HOME="$age_home" chezmoi age-keygen -y "$age_home/.config/chezmoi/key.txt")"
rg -q "recipient = \"$age_recipient\"" "$age_source/.chezmoi.toml.tmpl" || fail "age recipient mismatch"
mkdir -p "$age_home/.config/example"
printf 'example-secret-value\n' > "$age_home/.config/example/secret.txt"
HOME="$age_home" CHEZMOI_SOURCE_DIR="$age_source" "$ROOT/scripts/add-secret.sh" "$age_home/.config/example/secret.txt" >/dev/null
[[ -f "$age_source/dot_config/example/encrypted_secret.txt.age" ]] || fail "secret target was not encrypted"
if rg -q 'example-secret-value' "$age_source/dot_config/example/encrypted_secret.txt.age"; then
    fail "encrypted source contains plaintext"
fi

echo "[8/10] Full-backup workflow"
mkdir -p "$TEST_TMP/config" "$TEST_TMP/backups"
HOME="$TEST_TMP/home" CHEZMOI_SOURCE_DIR="$ROOT/starter" CHEZMOI_CONFIG_DIR="$TEST_TMP/config" \
    "$ROOT/scripts/full-backup.sh" "$TEST_TMP/backups" >/dev/null
backup_file="$(find "$TEST_TMP/backups" -type f -name 'dotfiles-full-backup-*.tar.gz' -print -quit)"
[[ -n "$backup_file" ]] || fail "full-backup did not create an archive"
tar -tzf "$backup_file" | rg -q '/chezmoi-source/dot_zshrc\.tmpl$' || fail "backup is missing source state"
tar -tzf "$backup_file" | rg -q '/home-plaintext/\.zshrc$' || fail "backup is missing plaintext targets"
tar -tzf "$backup_file" | rg -q '/MANIFEST\.sha256$' || fail "backup is missing its manifest"

echo "[9/10] Installer dry-run"
help_output="$("$ROOT/setup.sh" --help)"
[[ "$(rg -c '^  --' <<< "$help_output")" -eq 6 ]] || fail "installer option surface is no longer minimal"
rg -q -- '--user-only' <<< "$help_output" || fail "user-only mode is missing from the installer help"
if rg -q -- '--profile|--source-dir|--git-name|--git-email|--skip-packages|--skip-node|--non-interactive|--force|--doctor|--version' <<< "$help_output"; then
    fail "removed advanced options returned to the public interface"
fi
HOME="$TEST_TMP/home" CHEZMOI_SOURCE_DIR="$TEST_TMP/source" \
    "$ROOT/setup.sh" --dry-run >/dev/null
[[ ! -e "$TEST_TMP/source" ]] || fail "dry-run created a source directory"

clt_output="$(HOME="$TEST_TMP/home" CHEZMOI_SOURCE_DIR="$TEST_TMP/clt-source" \
    TERMINAL_SETUP_TEST_CLT_MISSING=1 "$ROOT/setup.sh" --dry-run 2>&1)"
rg -q 'Xcode Command Line Tools installer' <<< "$clt_output" || fail "macOS CLT bootstrap was not previewed"

linux_home="$TEST_TMP/linux-home"
mkdir -p "$linux_home"
linux_output="$(HOME="$linux_home" CHEZMOI_SOURCE_DIR="$TEST_TMP/linux-source" TERMINAL_SETUP_TEST_PLATFORM=debian \
    TERMINAL_SETUP_TEST_PIXI_MISSING=1 \
    "$ROOT/setup.sh" --dry-run 2>&1)"
[[ ! -e "$TEST_TMP/linux-source" ]] || fail "Linux dry-run created a source directory"
[[ ! -e "$linux_home/.local/bin" ]] || fail "Linux dry-run created ~/.local/bin"
rg -q 'profile: server' <<< "$linux_output" || fail "Linux did not default to the server profile"
rg -q 'Would install MesloLGS Nerd Font' <<< "$linux_output" || fail "Linux font installation was not previewed"
rg -q 'Would install Pixi into' <<< "$linux_output" || fail "Linux Pixi installation was not previewed"
rg -q 'Would install apt-available CLI packages, then bootstrap remaining tools through Pixi' <<< "$linux_output" || \
    fail "normal Linux dry-run did not select apt-first reconciliation"

server_output="$(HOME="$linux_home" CHEZMOI_SOURCE_DIR="$TEST_TMP/server-source" TERMINAL_SETUP_TEST_PLATFORM=debian \
    TERMINAL_SETUP_TEST_PIXI_MISSING=1 \
    "$ROOT/server-setup.sh" --dry-run)"
rg -q 'profile: server' <<< "$server_output" || fail "server wrapper did not select the server profile"

user_only_output="$(HOME="$linux_home" CHEZMOI_SOURCE_DIR="$TEST_TMP/user-only-source" \
    TERMINAL_SETUP_TEST_PLATFORM=debian TERMINAL_SETUP_TEST_CHEZMOI_MISSING=1 \
    TERMINAL_SETUP_TEST_PIXI_MISSING=1 \
    "$ROOT/server-setup.sh" --user-only --dry-run 2>&1)"
rg -q 'User-only mode: skipping apt packages and login-shell changes' <<< "$user_only_output" || \
    fail "user-only mode did not skip system packages"
if rg -q 'sudo apt-get' <<< "$user_only_output"; then
    fail "user-only mode still previewed sudo apt commands"
fi
rg -q 'chezmoi is not installed; would preview the rendered dotfiles here' <<< "$user_only_output" || \
    fail "dry-run did not tolerate missing chezmoi"
rg -q 'reuse installed apt commands' <<< "$user_only_output" || \
    fail "user-only mode did not report apt command reuse"
[[ ! -e "$TEST_TMP/user-only-source" ]] || fail "user-only dry-run created a source directory"

echo "[10/10] Public-repository secret scan"
# The public GitHub owner is intentionally documented in copy-ready clone URLs.
# Keep scanning for private identity details and infrastructure, not the public handle.
personal_pattern='jiapeng''fei|130811''4349|124\.16\.''139'
secret_pattern='AGE-SECRET-KEY-1[A-Z0-9]{20,}|apiKey["'"']?[[:space:]]*[:=][[:space:]]*["'"'][^"'"']+'
if rg -n --hidden --glob '!.git/**' --glob '!tests/test.sh' \
    "$personal_pattern|$secret_pattern" "$ROOT"; then
    fail "personal or secret-like data found"
fi
if rg -n --hidden --glob '!.git/**' --glob '!**/tests/test.sh' '/Users/[^ /]+' "$ROOT"; then
    fail "personal absolute path found"
fi
for readme in "$ROOT/README.md" "$ROOT/README_EN.md"; do
    rg -q 'https://github.com/CanoNandMacaroN/terminal-setup\.git' "$readme" || \
        fail "$(basename "$readme") is missing the copy-ready public clone URL"
    if rg -q 'YOUR_PUBLIC_REPOSITORY_URL|YOUR_GITHUB_USERNAME|YOUR_DOTFILES_REPOSITORY_URL' "$readme"; then
        fail "$(basename "$readme") contains a public quick-start placeholder"
    fi
done
rg -q 'recommendations/' "$ROOT/README.md" || fail "README does not link the optional recommendations"
rg -q 'server-setup.sh' "$ROOT/README.md" || fail "README does not document the server profile"
rg -q 'setup.ps1' "$ROOT/README.md" || fail "README does not document native Windows setup"
rg -q 'Pixi' "$ROOT/README.md" || fail "README does not document the Pixi package layer"
rg -q 'CodeBuddy' "$ROOT/recommendations/cli-tools.md" || fail "recommendations omit CodeBuddy"
rg -q 'determined' "$ROOT/recommendations/uv-tools.md" || fail "uv recommendations omit determined"
rg -q 'harlequin' "$ROOT/recommendations/uv-tools.md" || fail "uv recommendations omit harlequin"
rg -q 'ssh-keygen -y -f' "$ROOT/README.md" || fail "README does not document SSH public-key recovery"
rg -q '缺少时自动打开同一个 macOS 系统安装器' "$ROOT/README.md" || \
    fail "README does not document automatic macOS CLT bootstrap behavior"
rg -q 'opens the same macOS system installer when they are missing' "$ROOT/README_EN.md" || \
    fail "English README does not document automatic macOS CLT bootstrap behavior"
rg -q '不接收 Pull Request' "$ROOT/CONTRIBUTING_ZH.md" || fail "Chinese maintenance policy is missing"
rg -q 'does not accept pull requests' "$ROOT/CONTRIBUTING.md" || fail "English maintenance policy is missing"

echo "All tests passed."
