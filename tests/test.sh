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
bash -n "$ROOT/starter/run_onchange_install-packages.sh.tmpl"
bash -n "$ROOT/starter/run_onchange_install-uv-tools.sh.tmpl"
for reset_script in "$ROOT"/starter/dot_myshell/bin/*.sh; do
    [[ -e "$reset_script" ]] || continue
    bash -n "$reset_script"
done
zsh -n "$ROOT/starter/dot_zshrc" "$ROOT/starter/dot_zprofile" "$ROOT/starter/dot_zshenv"
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
jq empty "$ROOT/starter/dot_config/cmux/cmux.json"
if rg -q '^[[:space:]]*(cask|tap)[[:space:]]' "$ROOT/starter/dot_Brewfile"; then
    fail "public Brewfile must contain formulae only"
fi
if rg -q -- '--(cask|tap)|brew (tap|list --cask)' \
    "$ROOT/setup.sh" "$ROOT/starter/run_onchange_install-packages.sh.tmpl" \
    "$ROOT/starter/dot_myshell/functions/executable_env-sync"; then
    fail "casks or taps entered automated capture/pruning"
fi
if rg -ni 'codex|opencode|codebuddy|cc[ -]switch|chatgpt|cherry[ -]studio' \
    "$ROOT/setup.sh" "$ROOT/server-setup.sh" "$ROOT/doctor.sh" "$ROOT/lib" \
    "$ROOT/scripts" "$ROOT/starter"; then
    fail "optional AI tools entered the automated terminal workflow"
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
rg -q '^uv python install 3\.10\.20$' "$fake_log" || fail "uv Python version was not installed"
rg -q '^uv tool install --python 3\.10\.20 harlequin==2\.2\.1 --force$' "$fake_log" || fail "harlequin was not version-pinned"
rg -q '^uv tool install --python 3\.10\.20 ruff==0\.16\.0 --force$' "$fake_log" || fail "ruff was not version-pinned"

FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=1 "$TEST_TMP/install-packages.sh" >/dev/null
FAKE_LOG="$fake_log" HOME="$fake_home" PATH="$fake_bin:/usr/bin:/bin" TERMINAL_SETUP_PRUNE=1 "$TEST_TMP/install-uv.sh" >/dev/null
rg -q 'brew bundle cleanup' "$fake_log" || fail "explicit Brew pruning was not executed"
rg -q 'uv tool uninstall black' "$fake_log" || fail "explicit uv pruning was not executed"

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
tar -tzf "$backup_file" | rg -q '/chezmoi-source/dot_zshrc$' || fail "backup is missing source state"
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
    "$ROOT/setup.sh" --dry-run)"
[[ ! -e "$TEST_TMP/linux-source" ]] || fail "Linux dry-run created a source directory"
[[ ! -e "$linux_home/.local/bin" ]] || fail "Linux dry-run created ~/.local/bin"
rg -q 'profile: server' <<< "$linux_output" || fail "Linux did not default to the server profile"

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
rg -q '不接收 Pull Request' "$ROOT/CONTRIBUTING_ZH.md" || fail "Chinese maintenance policy is missing"
rg -q 'does not accept pull requests' "$ROOT/CONTRIBUTING.md" || fail "English maintenance policy is missing"

echo "All tests passed."
