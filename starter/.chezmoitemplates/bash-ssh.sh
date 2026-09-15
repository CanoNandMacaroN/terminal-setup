# Expose user-installed CLIs even when sshd starts non-interactive Bash.
export PIXI_HOME="${PIXI_HOME:-$HOME/.pixi}"
export FNM_HOME="${FNM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
export PNPM_HOME="${PNPM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pnpm}"
for _terminal_setup_dir in "$PIXI_HOME/bin" "$FNM_HOME" "$PNPM_HOME/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_terminal_setup_dir:"*) ;;
        *) PATH="$_terminal_setup_dir:$PATH" ;;
    esac
done
export PATH
unset _terminal_setup_dir
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
fi

# Preserve -c commands and stdin; do not redirect ordinary non-interactive Bash.
if [[ $- == *i* && -z "${ZSH_VERSION:-}" ]]; then
    _terminal_setup_zsh="$(command -v zsh 2>/dev/null)"
    if [[ -n "$_terminal_setup_zsh" && -x "$_terminal_setup_zsh" ]]; then
        export SHELL="$_terminal_setup_zsh"
        unset _terminal_setup_zsh
        if [[ -n "${BASH_EXECUTION_STRING+x}" ]]; then
            exec "$SHELL" -lc "$BASH_EXECUTION_STRING"
        fi
        exec "$SHELL" -l
    fi
    unset _terminal_setup_zsh
fi
