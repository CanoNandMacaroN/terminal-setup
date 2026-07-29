if command -v lsd >/dev/null 2>&1; then
    alias ls='lsd --group-dirs first'
    alias ll='lsd -la --group-dirs first'
    alias lt='lsd --tree --depth 2'
fi
command -v bat >/dev/null 2>&1 && alias cat='bat'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
