#!/usr/bin/env python3
"""Verify reversible client maintenance without touching live client state."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("maintenance", Path(__file__).with_name("maintenance.py"))
maintenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(maintenance)


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="client-maintenance-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        environment = patch.dict(os.environ, {"HOME": str(self.home)}, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        processes = patch.object(maintenance, "active_clients", return_value=[])
        self.processes = processes.start()
        self.addCleanup(processes.stop)
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        self.codex = self.home / ".codex"
        for name, content in {"config.toml": 'model = "example"', "auth.json": "private-auth",
                              "state_1.sqlite": "database", "worktrees/work/file": "project",
                              "log/app.log": "log-data", "sessions/session.jsonl": "history"}.items():
            path = self.codex / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def inventory(self):
        return {str(p.relative_to(self.home)): ("link", os.readlink(p)) if p.is_symlink()
                else ("file", p.read_bytes()) if p.is_file() else ("directory",)
                for p in self.home.rglob("*")}

    def test_preview_makes_no_changes_and_does_not_check_or_stop_processes(self):
        before = self.inventory()
        maintenance.archive_runtime("codex", True, False)
        self.assertEqual(self.inventory(), before)
        self.processes.assert_not_called()

    def test_default_archives_logs_but_preserves_credentials_databases_worktrees_and_history(self):
        maintenance.archive_runtime("codex", False, True)
        self.assertFalse((self.codex / "log").exists())
        for name in ("auth.json", "config.toml", "state_1.sqlite", "worktrees/work/file", "sessions/session.jsonl"):
            self.assertTrue((self.codex / name).exists())
        archive = next((self.codex / maintenance.ARCHIVES).iterdir())
        self.assertEqual((archive / "files/log/app.log").read_text(), "log-data")
        self.assertEqual(archive.stat().st_mode & 0o777, 0o700)
        before = self.inventory()
        maintenance.restore(archive, False)
        self.assertEqual(self.inventory(), before)
        maintenance.restore(archive, True)
        self.assertEqual((self.codex / "log/app.log").read_text(), "log-data")

    def test_explicit_history_archive_and_restore_collision(self):
        maintenance.archive_runtime("codex", True, True)
        self.assertFalse((self.codex / "sessions").exists())
        archive = next((self.codex / maintenance.ARCHIVES).iterdir())
        (self.codex / "log").mkdir()
        before = self.inventory()
        with self.assertRaisesRegex(ValueError, "New runtime data"):
            maintenance.restore(archive, True)
        self.assertEqual(self.inventory(), before)

    def test_running_client_and_symlink_targets_refuse_before_changes(self):
        self.processes.return_value = ["123"]
        before = self.inventory()
        with self.assertRaisesRegex(ValueError, "Close codex"):
            maintenance.archive_runtime("codex", True, True)
        self.assertEqual(self.inventory(), before)
        self.processes.return_value = []
        (self.codex / "cache").symlink_to(self.home)
        before = self.inventory()
        with self.assertRaisesRegex(ValueError, "symlink"):
            maintenance.archive_runtime("codex", False, True)
        self.assertEqual(self.inventory(), before)

    def test_codebuddy_multiple_roots_and_preserved_settings(self):
        server = self.home / ".codebuddy-server-cn"
        agent = self.home / ".codebuddy"
        for path in (server / "data/logs/log.txt", server / "data/User/History/history",
                     server / "data/User/settings.json", agent / "expert-history.json", agent / "config.json"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(path.name)
        maintenance.archive_runtime("codebuddy", True, True)
        self.assertTrue((server / "data/User/settings.json").exists())
        self.assertTrue((agent / "config.json").exists())
        self.assertFalse((server / "data/User/History").exists())
        self.assertFalse((agent / "expert-history.json").exists())
        for root in (server, agent):
            maintenance.restore(next((root / maintenance.ARCHIVES).iterdir()), True)
        self.assertTrue((server / "data/User/History/history").exists())
        self.assertTrue((agent / "expert-history.json").exists())

    def test_restore_rejects_path_traversal_in_manifest(self):
        maintenance.archive_runtime("codex", False, True)
        archive = next((self.codex / maintenance.ARCHIVES).iterdir())
        (archive / "manifest.json").write_text(json.dumps({"schema": 1, "client": "codex", "entries": ["../outside"]}))
        before = self.inventory()
        with self.assertRaisesRegex(ValueError, "Unsafe recovery"):
            maintenance.restore(archive, True)
        self.assertEqual(self.inventory(), before)

    def test_process_detection_covers_node_and_native_clients(self):
        # Inspect a fake /proc with the real implementation rather than the guard mock.
        proc = self.home / "proc"
        for pid, arguments in {"900001": ["/tools/codex", "app-server"],
                               "900002": ["/tools/node", "/tools/codex.js"],
                               "900003": ["/tools/.codebuddy-server-cn/bin/node", "server.js"],
                               "900004": ["/usr/bin/bash", "normal-script.sh"]}.items():
            directory = proc / pid
            directory.mkdir(parents=True)
            (directory / "cmdline").write_bytes(b"\0".join(x.encode() for x in arguments))
        # The mock patch stores the replaced original on the patcher only; load a fresh module.
        fresh = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fresh)
        self.assertEqual(set(fresh.active_clients("codex", proc)), {"900001", "900002"})
        self.assertEqual(fresh.active_clients("codebuddy", proc), ["900003"])


if __name__ == "__main__":
    unittest.main(buffer=True)
