#!/usr/bin/env python3
"""Exercise the server helper against disposable homes, never the real account."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/configure-codex.sh"
ZSH = shutil.which("zsh")


class ConfigureCodexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-config-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = {"HOME": str(self.home), "PATH": os.environ["PATH"], "LC_ALL": "C"}
        self.write(".bashrc", '# keep my alias\ncase $- in *i*) ;; *) return ;; esac\nalias ll="ls -l"\n')
        self.write(".profile", '# existing login content\n. "$HOME/.bashrc"\n')
        self.write(".zshenv", '# keep my zsh settings\nexport MY_ZSH_SETTING=kept\n')

    def write(self, relative, content):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def run_helper(self, *args, success=True):
        result = subprocess.run([str(SCRIPT), *args], env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def snapshot(self):
        return {str(p.relative_to(self.home)): p.read_bytes()
                for p in self.home.rglob("*") if p.is_file()}

    def test_preview_preserves_all_files_and_creates_nothing(self):
        self.write(".codex/config.toml", 'model = "example"\n')
        before = self.snapshot()
        self.run_helper("--no-sandbox", "--dry-run")
        self.assertEqual(before, self.snapshot())

    def test_config_preservation_backup_and_repeat_run(self):
        original = '''# user comment
model = "example"
default_permissions = "workspace"
approval_policy = { granular = { rules = true } }
instructions = """Keep this verbatim.
[permissions.fake]
sandbox_mode = 'inside a string'
"""
[model_providers."custom.name"]
name = "my provider"
[permissions.workspace.filesystem]
":root" = "read"
[sandbox_workspace_write]
network_access = true
[profiles.special]
model = "other-model"
sandbox_mode = "workspace-write"
'''
        config = self.write(".codex/config.toml", original)
        original = original.replace("\n", "\r\n")
        config.write_bytes(original.encode())
        config.chmod(0o600)
        before = tomllib.loads(original)
        self.run_helper("--no-sandbox")
        updated = tomllib.loads(config.read_text())
        self.assertEqual(updated["model_providers"], before["model_providers"])
        self.assertEqual(updated["profiles"], before["profiles"])
        self.assertEqual(updated["instructions"], before["instructions"])
        self.assertIn("# user comment", config.read_text())
        self.assertEqual(updated["sandbox_mode"], "danger-full-access")
        self.assertEqual(updated["approval_policy"], "on-request")
        for key in ("permissions", "default_permissions", "sandbox_workspace_write"):
            self.assertNotIn(key, updated)
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        backup = next((self.home / ".local/state/terminal-setup/codex-backups").iterdir())
        records = json.loads((backup / "manifest.json").read_text())
        record = next(row for row in records if row["target"] == str(config))
        self.assertEqual((backup / record["backup"]).read_bytes(), original.encode())
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        snapshot = self.snapshot()
        self.run_helper("--no-sandbox")
        self.assertEqual(self.snapshot(), snapshot)

    def test_default_does_not_touch_codex_permissions(self):
        config = self.write(".codex/config.toml", 'sandbox_mode = "workspace-write"\n')
        self.run_helper()
        self.assertEqual(config.read_text(), 'sandbox_mode = "workspace-write"\n')
        self.assertIn('alias ll="ls -l"', (self.home / ".bashrc").read_text())

    def test_existing_bash_bridge_is_not_duplicated(self):
        original = '''# >>> terminal-setup: Bash SSH environment >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< terminal-setup: Bash SSH environment <<<
case $- in *i*) ;; *) return ;; esac
'''
        bashrc = self.write(".bashrc", original)
        self.run_helper()
        self.assertEqual(bashrc.read_text(), original)
        self.assertTrue((self.home / ".config/terminal-setup/codex-env.sh").exists())

    def test_invalid_input_stops_before_any_write(self):
        self.write(".codex/config.toml", "not valid TOML!")
        before = self.snapshot()
        self.run_helper("--no-sandbox", success=False)
        self.assertEqual(self.snapshot(), before)
        self.write(".bashrc", "# >>> terminal-setup: Codex SSH environment >>>\n")
        before = self.snapshot()
        self.run_helper(success=False)
        self.assertEqual(self.snapshot(), before)

    def test_login_precedence_custom_paths_and_symlinks(self):
        profile = self.write("private/bash_profile", "# linked login settings\n")
        (self.home / ".bash_profile").symlink_to(profile)
        previous_profile = (self.home / ".profile").read_text()
        self.env["CODEX_HOME"] = str(self.home / "custom-codex")
        self.env["ZDOTDIR"] = str(self.home / "custom-zsh")
        self.env["XDG_STATE_HOME"] = str(self.home / "custom-state")
        self.run_helper("--no-sandbox")
        self.assertTrue((self.home / ".bash_profile").is_symlink())
        self.assertIn("Codex SSH environment", profile.read_text())
        self.assertEqual((self.home / ".profile").read_text(), previous_profile)
        self.assertTrue((self.home / "custom-codex/config.toml").exists())
        self.assertTrue((self.home / "custom-zsh/.zshenv").exists())
        self.assertTrue((self.home / "custom-state/terminal-setup/codex-backups").exists())
        self.assertFalse((self.home / ".codex").exists())

    def test_legacy_block_and_interactive_command_forwarding(self):
        self.write(".bashrc", '''# >>> terminal-setup: Bash environment for non-interactive SSH clients >>>
export OLD_CODEX_PATH=obsolete
# <<< terminal-setup <<<
case $- in *i*) ;; *) return ;; esac
# >>> switch to zsh as default interactive shell >>>
exec zsh
# <<< switch to zsh as default interactive shell <<<
''')
        self.run_helper()
        text = (self.home / ".bashrc").read_text()
        self.assertNotIn("OLD_CODEX_PATH", text)
        fake_zsh = self.write(".pixi/bin/zsh", '#!/bin/sh\nprintf "%s\\n" "$@"\n')
        fake_zsh.chmod(0o755)
        result = subprocess.run(["/bin/bash", "--noprofile", "-ic", "printf preserved"],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "-lc\nprintf preserved\n")

    def test_noninteractive_bash_and_zsh_find_tools_and_preserve_stdin(self):
        fake_fnm = self.write(".local/share/fnm/fnm", '''#!/bin/sh
printf 'export PATH="%s/fake-node:$PATH"\n' "$HOME"
''')
        node = self.write("fake-node/node", '#!/bin/sh\nprintf "test-node\\n"\n')
        codex = self.write(".local/share/pnpm/bin/codex", '#!/bin/sh\nnode\n')
        for path in (fake_fnm, node, codex):
            path.chmod(0o755)
        self.run_helper()
        clean_env = {**self.env, "PATH": "/usr/bin:/bin"}
        probe = 'command -v node; command -v codex; codex; cat'
        commands = [
            ["/bin/bash", "--noprofile", "--norc", "-c", '. "$HOME/.bashrc"; ' + probe],
            ["/bin/bash", "--noprofile", "--norc", "-c", '. "$HOME/.profile"; ' + probe],
        ]
        if ZSH:
            commands.extend([[ZSH, "-c", probe], [ZSH, "-lc", probe]])
        for command in commands:
            with self.subTest(command=command):
                result = subprocess.run(command, env=clean_env, input="stdin preserved\n",
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, f"{node}\n{codex}\ntest-node\nstdin preserved\n")


if __name__ == "__main__":
    unittest.main()
