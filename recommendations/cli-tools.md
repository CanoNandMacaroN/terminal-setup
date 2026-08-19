# Optional specialist CLI tools

The Brewfile and Pixi manifest focus on general terminal work. Add specialist tools to a private platform manifest only when a machine needs them.

On macOS, install the relevant Homebrew formulae:

```sh
brew install herdr
brew install imagemagick
brew install poppler
brew install scrcpy
brew install wireguard-tools
```

On Linux/WSL or native Windows, first check whether conda-forge provides the package for the target platform, then add it to a private Pixi manifest or install it in a named global environment:

```sh
pixi search imagemagick
pixi search poppler
pixi global install --environment imagemagick imagemagick
pixi global install --environment poppler poppler
```

Pixi can only install packages published for the current platform. If `herdr`, `scrcpy`, `wireguard-tools`, or another specialist tool is unavailable, use its upstream installation method instead of adding it to the public baseline.

CodeBuddy is an AI-specific CLI and is intentionally separate from the public baseline:

```sh
brew tap tencent-codebuddy/tap
brew install tencent-codebuddy/tap/codebuddy-code
```

Provider credentials, endpoints, OAuth sessions, and the CodeBuddy-specific PATH belong to private or application-owned configuration.
