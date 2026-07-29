# 安全策略

本仓库必须保持公开且不包含凭据。

禁止提交：

- age identity 或密码管理器导出。
- SSH 私钥、密码、主机清单和 `known_hosts`。
- 代理订阅、UUID、API Key 和模型供应商凭据。
- CC Switch 导出、agent OAuth 会话和私人 AI 端点。
- `scripts/full-backup.sh` 生成的完整明文备份。
- 个人化的 `.gitconfig.local`。

需要同步敏感目标时，先在自己的私人 chezmoi 源中运行 `scripts/enable-age.sh`，再使用 `scripts/add-secret.sh` 明确加密添加。

完整备份故意不加密，必须保存在仓库之外的私人 NAS、离线磁盘或其他受控位置。

怀疑凭据泄露时，应先轮换凭据，再决定是否清理 Git 历史；不要只删除当前文件后继续使用旧凭据。
