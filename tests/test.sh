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
for expected in macos debian wsl; do
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
    < "$ROOT/starter/dot_zprofile.tmpl" | zsh -n
chezmoi -S "$ROOT/starter" --override-data "$linux_data" execute-template \
    < "$ROOT/starter/dot_zshrc.tmpl" | zsh -n
darwin_intel_data='{"chezmoi":{"os":"darwin","arch":"amd64","homeDir":"/Users/tester"}}'
intel_profile="$(chezmoi -S "$ROOT/starter" --override-data "$darwin_intel_data" execute-template \
    < "$ROOT/starter/dot_zprofile.tmpl")"
rg -q '/usr/local/bin/brew' <<< "$intel_profile" || fail "Intel macOS did not select /usr/local Homebrew"
if rg -q '/opt/homebrew/bin/brew' <<< "$intel_profile"; then
    fail "Intel macOS rendered the Apple Silicon Homebrew path"
fi
jq empty "$ROOT/starter/dot_config/cmux/cmux.json"
rg -q '^cask "orca"$' "$ROOT/starter/dot_Brewfile" || fail "Orca is missing from the workstation manifest"
rg -q '^cask "codex"$' "$ROOT/starter/dot_Brewfile" || fail "Codex is missing from the workstation manifest"
rg -q '^cask "font-meslo-lg-nerd-font"$' "$ROOT/starter/dot_Brewfile" || fail "macOS prompt font is missing"
rg -q '^brew "wireguard-tools"$' "$ROOT/starter/dot_Brewfile" || fail "WireGuard tools are missing"
rg -q 'nerd-fonts/v3\.4\.0/patched-fonts/Meslo/S' "$ROOT/setup.sh" || \
    fail "Linux prompt font installer is missing or unpinned"
[[ "$(rg -c 'font_sha256=[0-9a-f]{64}' "$ROOT/setup.sh")" -eq 4 ]] || \
    fail "Linux prompt fonts do not have four pinned checksums"
rg -q '' "$ROOT/starter/dot_config/starship.toml" || fail "current Starship prompt theme was not synchronized"
if rg -qi 'warp' "$ROOT/starter/dot_Brewfile"; then
    fail "removed Warp app remains in the workstation manifest"
fi
if rg -q 'git|chezmoi-push' "$ROOT/starter/dot_myshell/functions/executable_env-sync"; then
    fail "env-sync must not stage, commit, or push"
fi

echo "[4/10] Starter target preview"
mkdir -p "$TEST_TMP/home"
preview="$(HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" apply --dry-run --verbose --no-tty)"
[[ -n "$preview" ]] || fail "starter dry-run produced no target changes"

echo "[5/10] Isolated starter apply"
HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" apply --exclude scripts --no-tty
HOME="$TEST_TMP/home" chezmoi -S "$ROOT/starter" -D "$TEST_TMP/home" verify --exclude scripts
[[ -f "$TEST_TMP/home/.zshrc" ]] || fail "isolated apply did not create .zshrc"
[[ -f "$TEST_TMP/home/.config/ghostty/config" ]] || fail "Ghostty configuration is missing"
[[ -x "$TEST_TMP/home/.myshell/functions/env-sync" ]] || fail "env-sync is not executable"

echo "[6/10] Manifest reconciliation safety"
fake_bin="$TEST_TMP/fake-bin"
fake_home="$TEST_TMP/fake-manifest-home"
fake_log="$TEST_TMP/manifest.log"
mkdir -p "$fake_bin" "$fake_home/.myshell"
cp "$ROOT/starter/dot_myshell/uv-tools.toml" "$fake_home/.myshell/uv-tools.toml"

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
chmod +x "$fake_bin/uname" "$fake_bin/brew" "$fake_bin/uv"

chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/run_onchange_install-packages.sh.tmpl" > "$TEST_TMP/install-packages.sh"
chezmoi -S "$ROOT/starter" execute-template < "$ROOT/starter/run_onchange_install-uv-tools.sh.tmpl" > "$TEST_TMP/install-uv.sh"
chmod +x "$TEST_TMP/install-packages.sh" "$TEST_TMP/install-uv.sh"

FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=0 "$TEST_TMP/install-packages.sh" >/dev/null
FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=0 "$TEST_TMP/install-uv.sh" >/dev/null
if rg -q 'cleanup|uninstall' "$fake_log"; then
    fail "default reconciliation pruned packages"
fi
rg -q '^uv python install 3\.10$' "$fake_log" || fail "determined Python policy was not applied"
rg -q '^uv tool install harlequin --force$' "$fake_log" || fail "harlequin should remain unpinned"
rg -q '^uv tool install ruff --force$' "$fake_log" || fail "ruff should remain unpinned"
rg -q '^uv tool install --python 3\.10 --with PyYAML==5\.3\.1 --with ruamel-yaml==0\.17\.40 determined==0\.19\.10 --force$' \
    "$fake_log" || fail "determined compatibility requirements were not applied"

FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=1 "$TEST_TMP/install-packages.sh" >/dev/null
FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=1 "$TEST_TMP/install-uv.sh" >/dev/null
rg -q 'brew bundle cleanup --global --force --formula --cask --tap' "$fake_log" || \
    fail "explicit Brew pruning did not cover formulae, casks, and taps"
rg -q 'uv tool uninstall black' "$fake_log" || fail "explicit uv pruning was not executed"
if rg -q 'uv tool uninstall ruff' "$fake_log"; then
    fail "explicit uv pruning removed a declared tool"
fi
rg -q 'contains no valid tool names; refusing to prune' "$ROOT/setup.sh" || \
    fail "installer lacks an empty uv manifest pruning guard"

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
[[ "$(rg -c '^  --' <<< "$help_output")" -eq 5 ]] || fail "installer option surface is no longer minimal"
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
    "$ROOT/setup.sh" --dry-run 2>&1)"
[[ ! -e "$TEST_TMP/linux-source" ]] || fail "Linux dry-run created a source directory"
[[ ! -e "$linux_home/.local/bin" ]] || fail "Linux dry-run created ~/.local/bin"
rg -q 'profile: server' <<< "$linux_output" || fail "Linux did not default to the server profile"
rg -q 'Would install MesloLGS Nerd Font' <<< "$linux_output" || fail "Linux font installation was not previewed"

server_output="$(HOME="$linux_home" CHEZMOI_SOURCE_DIR="$TEST_TMP/server-source" TERMINAL_SETUP_TEST_PLATFORM=debian \
    "$ROOT/server-setup.sh" --dry-run)"
rg -q 'profile: server' <<< "$server_output" || fail "server wrapper did not select the server profile"

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
rg -q 'cmux' "$ROOT/README.md" || fail "README does not document cmux"
rg -q 'server-setup.sh' "$ROOT/README.md" || fail "README does not document the server profile"
rg -q 'CC Switch' "$ROOT/README.md" || fail "README does not document AI configuration ownership"
rg -q 'ssh-keygen -y -f' "$ROOT/README.md" || fail "README does not document SSH public-key recovery"
rg -q '缺少时自动打开同一个 macOS 系统安装器' "$ROOT/README.md" || \
    fail "README does not document automatic macOS CLT bootstrap behavior"
rg -q 'opens the same macOS system installer when they are missing' "$ROOT/README_EN.md" || \
    fail "English README does not document automatic macOS CLT bootstrap behavior"
rg -q '不接收 Pull Request' "$ROOT/CONTRIBUTING_ZH.md" || fail "Chinese maintenance policy is missing"
rg -q 'does not accept pull requests' "$ROOT/CONTRIBUTING.md" || fail "English maintenance policy is missing"

echo "All tests passed."
