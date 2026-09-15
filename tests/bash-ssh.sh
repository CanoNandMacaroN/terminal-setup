#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
bridge_home="$scratch/home"
mkdir -p "$bridge_home/.pixi/bin"
ln -s "$(command -v zsh)" "$bridge_home/.pixi/bin/zsh"
data='{"chezmoi":{"os":"linux","arch":"amd64"}}'
chezmoi -S "$ROOT/starter" --override-data "$data" execute-template \
    < "$ROOT/starter/run_onchange_before_configure-bash-ssh.sh.tmpl" > "$scratch/install.sh"
bash -n "$scratch/install.sh"
printf '# existing user configuration\ncase $- in *i*) ;; *) return;; esac\n' > "$bridge_home/.bashrc"
cp "$bridge_home/.bashrc" "$scratch/original"
HOME="$bridge_home" bash "$scratch/install.sh" >/dev/null
HOME="$bridge_home" bash "$scratch/install.sh" >/dev/null
[[ "$(find "$bridge_home" -name '.bashrc.backup-terminal-setup.*' | wc -l | tr -d ' ')" == 1 ]]
tail -n 2 "$bridge_home/.bashrc" | cmp - "$scratch/original"

run_bridge() {
    env -i HOME="$bridge_home" PATH=/usr/bin:/bin \
        bash --noprofile --rcfile "$bridge_home/.bashrc" -ic "$1" 2> "$scratch/stderr"
}
[[ "$(run_bridge 'printf "%s" "$ZSH_VERSION"')" != '' ]]
[[ "$(run_bridge 'printf "%s" "$SHELL"')" == "$bridge_home/.pixi/bin/zsh" ]]
# Command quoting, multiline input, and arbitrary protocol bytes survive exec.
payload=$'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n'
printf '%s' "$payload" > "$scratch/expected"
printf '%s' "$payload" | run_bridge 'cat' > "$scratch/actual"
cmp "$scratch/expected" "$scratch/actual"
[[ "$(run_bridge $'printf "%s\\n" "a b"\nprintf "%s" "literal \$value"')" == $'a b\nliteral $value' ]]
status=0
run_bridge 'exit 37' || status=$?
[[ "$status" == 37 ]]
run_bridge '' < /dev/null
# Ordinary non-interactive Bash retains Bash semantics and gets CLI paths.
result="$(env -i HOME="$bridge_home" PATH=/usr/bin:/bin bash -c \
    '. "$HOME/.bashrc"; [[ -n "$BASH_VERSION" ]]; command -v zsh')"
[[ "$result" == "$bridge_home/.pixi/bin/zsh" ]]
# Render the real Zsh template and catch fzf initialization without a terminal.
chezmoi -S "$ROOT/starter" --override-data "$data" execute-template \
    < "$ROOT/starter/dot_zshrc.tmpl" > "$bridge_home/.zshrc"
cat > "$bridge_home/.pixi/bin/fzf" <<'EOF'
#!/bin/sh
echo FZF_INIT_WITHOUT_TTY >&2
EOF
chmod +x "$bridge_home/.pixi/bin/fzf"
env -i HOME="$bridge_home" PIXI_HOME="$bridge_home/.pixi" PATH=/usr/bin:/bin \
    "$bridge_home/.pixi/bin/zsh" -dfi -c '. "$HOME/.zshrc"; printf ZSH_OK' \
    < /dev/null > "$scratch/zsh-out" 2> "$scratch/zsh-err"
[[ "$(cat "$scratch/zsh-out")" == ZSH_OK ]]
if grep -q 'FZF_INIT_WITHOUT_TTY\|can.t change option: zle' "$scratch/zsh-err"; then
    cat "$scratch/zsh-err" >&2
    exit 1
fi
# Preserve symlinked user configuration and make non-Linux hooks empty.
mv "$bridge_home/.bashrc" "$bridge_home/bashrc-target"
ln -s "$bridge_home/bashrc-target" "$bridge_home/.bashrc"
HOME="$bridge_home" bash "$scratch/install.sh" >/dev/null
[[ -L "$bridge_home/.bashrc" ]]
for platform in darwin windows; do
    rendered="$(chezmoi -S "$ROOT/starter" --override-data "{\"chezmoi\":{\"os\":\"$platform\"}}" \
        execute-template < "$ROOT/starter/run_onchange_before_configure-bash-ssh.sh.tmpl")"
    [[ -z "$rendered" ]]
done
# A missing zsh must not break Bash startup.
mv "$bridge_home/.pixi/bin/zsh" "$scratch/zsh"
if [[ ! -x /usr/bin/zsh && ! -x /bin/zsh ]]; then
    [[ "$(run_bridge 'printf "%s" "$BASH_VERSION"')" != '' ]]
fi
# A malformed block must fail without modifying the file.
printf '\n# >>> terminal-setup: Bash SSH environment >>>\n' >> "$bridge_home/.bashrc"
cp "$bridge_home/.bashrc" "$scratch/broken"
if HOME="$bridge_home" bash "$scratch/install.sh"; then
    echo 'Malformed block was accepted' >&2
    exit 1
fi
cmp "$bridge_home/.bashrc" "$scratch/broken"
echo 'Bash SSH handoff tests passed.'
