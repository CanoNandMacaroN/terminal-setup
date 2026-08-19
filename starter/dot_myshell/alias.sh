if command -v lsd >/dev/null 2>&1; then
    alias ls='lsd --group-dirs first'
    alias ll='lsd -la --group-dirs first'
    alias lt='lsd --tree --depth 2'
elif command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first'
    alias ll='eza -la --group-directories-first'
    alias lt='eza --tree --level 2'
fi
command -v bat >/dev/null 2>&1 && alias cat='bat'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
