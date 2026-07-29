# Security Policy

**[中文版](SECURITY_ZH.md)**

This repository is designed to remain public and credential-free.

Never commit:

- age identities or password-manager exports
- SSH private keys, passwords, host inventories, or known_hosts data
- proxy subscriptions, UUIDs, API keys, or model-provider credentials
- CC Switch exports, agent OAuth sessions, or private AI endpoint settings
- full plaintext backups produced by `scripts/full-backup.sh`
- personalized `.gitconfig.local` files

Use `scripts/enable-age.sh` inside your own private chezmoi source before adding sensitive targets. Full backups are intentionally unencrypted and must be stored outside this repository.

Report suspected credential exposure privately to the repository maintainer. Rotate exposed credentials before attempting Git history cleanup.
