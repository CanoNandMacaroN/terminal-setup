# Optional specialist CLI tools

The Brewfile and Pixi manifest focus on general terminal work. Add specialist tools to a private platform manifest only when a machine needs them.

```sh
brew install herdr
brew install imagemagick
brew install poppler
brew install scrcpy
brew install wireguard-tools
```

CodeBuddy is an AI-specific CLI and is intentionally separate from the public baseline:

```sh
brew tap tencent-codebuddy/tap
brew install tencent-codebuddy/tap/codebuddy-code
```

Provider credentials, endpoints, OAuth sessions, and the CodeBuddy-specific PATH belong to private or application-owned configuration.
