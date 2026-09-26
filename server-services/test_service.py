#!/usr/bin/env python3
"""Integration checks using temporary disks and real rsync; no real services."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).with_name("service.py")


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="server-services-tests-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.shared_mount = self.root / "shared mount"
        self.data_mount = self.root / "data mount"
        self.shared_mount.mkdir()
        self.data_mount.mkdir()
        self.shared = self.shared_mount / "account"
        self.data = self.data_mount / "account"
        self.local = self.home / "local"
        self.config = self.root / "config.toml"
        self.settings = {
            "paths": {"shared_mount": str(self.shared_mount), "shared_root": str(self.shared),
                      "data_mount": str(self.data_mount), "data_root": str(self.data),
                      "local_root": str(self.local), "links_root": str(self.home / "storage")},
            "storage": {"require_mounts": False, "instance": "test-server"},
            "sync": {"working_dirs": ["code", "tasks"], "snapshot_dirs": ["scripts", "docs"]},
            "backup": {"keep_snapshots": 2, "include_data": False, "calendar": "daily"},
        }
        self.save_config()
        self.env = {"HOME": str(self.home), "PATH": os.environ["PATH"], "LC_ALL": "C"}

    def save_config(self):
        # JSON strings, arrays and booleans are valid TOML value syntax here.
        self.config.write_text("\n".join(f"[{section}]\n" + "\n".join(
            f"{key} = {json.dumps(value)}" for key, value in values.items())
            for section, values in self.settings.items()) + "\n")

    def run_service(self, command, *args, ok=True):
        result = subprocess.run([sys.executable, str(MODULE), command, "--config", str(self.config), *args],
                                env=self.env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def inventory(self):
        return {str(p.relative_to(self.root)): ("link", os.readlink(p)) if p.is_symlink()
                else ("file", p.read_bytes()) if p.is_file() else ("directory",)
                for p in self.root.rglob("*")}

    def test_install_preview_and_idempotence(self):
        before = self.inventory()
        self.run_service("install", "--dry-run")
        self.assertEqual(self.inventory(), before)
        self.run_service("install")
        self.assertEqual((self.home / "storage/code").resolve(), self.shared / "code")
        self.assertEqual((self.home / "storage/data/input").resolve(), self.data / "input")
        self.assertFalse((self.home / ".config/systemd").exists())
        installed = self.home / ".local/bin/server-services"
        self.assertTrue(os.access(installed.with_name("server-maintenance"), os.X_OK))
        result = subprocess.run([str(installed), "status"], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(installed), "install"], env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Reinstall from the repository", result.stderr)
        before = self.inventory()
        self.run_service("install")
        self.assertEqual(self.inventory(), before)

    def test_mount_overlap_and_existing_link_conflicts_stop_before_writes(self):
        self.settings["storage"]["require_mounts"] = True
        self.save_config()
        before = self.inventory()
        self.assertIn("not mounted", self.run_service("install", ok=False).stderr)
        self.assertEqual(self.inventory(), before)
        self.settings["storage"]["require_mounts"] = False
        self.settings["paths"]["data_root"] = str(self.shared / "nested")
        self.save_config()
        self.assertIn("overlap", self.run_service("install", ok=False).stderr)
        self.settings["paths"]["data_root"] = str(self.data)
        self.save_config()
        (self.home / "storage/code").mkdir(parents=True)
        before = self.inventory()
        self.run_service("install", ok=False)
        self.assertEqual(self.inventory(), before)

    def test_configured_symlink_and_writable_root_refuse_before_writes(self):
        attacker = self.root / "attacker"
        attacker.mkdir()
        self.shared.symlink_to(attacker, target_is_directory=True)
        before = self.inventory()
        self.assertIn("symlink", self.run_service("install", ok=False).stderr)
        self.assertEqual(self.inventory(), before)
        self.shared.unlink()
        self.shared.mkdir(mode=0o777)
        self.shared.chmod(0o777)
        before = self.inventory()
        self.assertIn("not writable by others", self.run_service("install", ok=False).stderr)
        self.assertEqual(self.inventory(), before)
        self.shared.chmod(0o700)
        team = self.shared_mount / "team"
        team.mkdir()
        team.chmod(0o777)
        self.settings["paths"]["shared_root"] = str(team / "account")
        self.save_config()
        before = self.inventory()
        self.assertIn("Storage parent", self.run_service("install", ok=False).stderr)
        self.assertEqual(self.inventory(), before)

    def test_working_sync_overwrite_history_and_mirror_deletions(self):
        self.run_service("install")
        (self.local / "code/example").write_text("local changed version")
        (self.shared / "code/example").write_text("old shared version")
        (self.shared / "code/remote-only").write_text("keep unless mirror")
        self.run_service("push")
        self.assertEqual((self.shared / "code/example").read_text(), "local changed version")
        self.assertTrue((self.shared / "code/remote-only").exists())
        histories = list((self.shared / "backups").rglob("example"))
        self.assertTrue(any(p.read_text() == "old shared version" for p in histories))
        self.run_service("push", "--mirror", "--allow-empty")
        self.assertFalse((self.shared / "code/remote-only").exists())
        self.assertTrue(list((self.shared / "backups").rglob("remote-only")))
        (self.shared / "code/example").write_text("new shared version for pull")
        self.run_service("pull")
        self.assertEqual((self.local / "code/example").read_text(), "new shared version for pull")
        self.assertTrue(list((self.local / ".sync-trash").rglob("example")))

    def test_all_previews_are_read_only_even_with_missing_destinations(self):
        self.run_service("install")
        (self.local / "docs/note").write_text("private note")
        (self.data / "input/source").write_text("dataset")
        self.settings["backup"]["include_data"] = True
        self.save_config()
        before = self.inventory()
        for command in ("status", "pull", "push", "snapshot", "backup-data", "backup"):
            with self.subTest(command=command):
                self.run_service(command, "--dry-run")
                self.assertEqual(self.inventory(), before)

    def test_snapshots_layout_hardlinks_retention_and_restore(self):
        self.run_service("install")
        (self.local / "docs/note").write_text("unchanged")
        self.run_service("snapshot")
        snapshots = self.shared / "backups/server-services/test-server/snapshots"
        first = (snapshots / "latest").resolve()
        self.assertEqual((first / "docs/note").read_text(), "unchanged")
        self.assertFalse((first / "home").exists())
        unrelated = snapshots / "keep-manually-created-directory"
        unrelated.mkdir()
        self.run_service("snapshot")
        second = (snapshots / "latest").resolve()
        self.assertEqual((first / "docs/note").stat().st_ino, (second / "docs/note").stat().st_ino)
        # A newly configured snapshot directory has no link-dest in older snapshots.
        self.settings["sync"]["snapshot_dirs"].append("notes")
        self.save_config()
        (self.local / "notes").mkdir()
        (self.local / "notes/new").write_text("new directory")
        self.run_service("snapshot")
        self.assertFalse(first.exists())
        self.assertTrue(unrelated.exists())
        self.assertTrue((snapshots / "latest/notes/new").is_file())
        restored = self.root / "restored"
        subprocess.run(["rsync", "-a", str(snapshots / "latest/docs") + "/", str(restored) + "/"], check=True)
        self.assertEqual((restored / "note").read_text(), "unchanged")

    def test_data_backups_are_per_instance_and_keep_old_content(self):
        self.run_service("install")
        (self.data / "output/result").write_text("old result")
        self.run_service("backup-data")
        destination = self.shared / "dataset/test-server/output/result"
        self.assertEqual(destination.read_text(), "old result")
        (self.data / "output/result").write_text("new result, longer")
        self.run_service("backup-data")
        self.assertTrue(any(p.read_text() == "old result" for p in (self.shared / "backups").rglob("result")))
        (self.data / "output/result").unlink()
        self.run_service("backup-data")
        self.assertTrue(destination.exists())
        before = self.inventory()
        self.run_service("backup-data", "--mirror", ok=False)
        self.assertEqual(self.inventory(), before)

    def test_symlinks_missing_sources_and_lock_prevent_writes(self):
        self.run_service("install")
        (self.shared / "code").rmdir()
        (self.shared / "code").symlink_to(self.root)
        before = self.inventory()
        self.run_service("push", ok=False)
        self.assertEqual(self.inventory(), before)
        (self.shared / "code").unlink()
        (self.shared / "code").mkdir()
        instance_lock = self.shared / "backups/server-services/test-server/.terminal-setup-sync.lock"
        instance_lock.mkdir()
        self.assertIn("locked", self.run_service("snapshot", ok=False).stderr)
        instance_lock.rmdir()
        (self.local / "tasks").rmdir()
        before = self.inventory()
        self.run_service("push", ok=False)
        self.assertEqual(self.inventory(), before)

    def test_rsync_failure_propagates_and_does_not_publish_snapshot(self):
        self.run_service("install")
        fakebin = self.root / "fake-bin"
        fakebin.mkdir()
        fake = fakebin / "rsync"
        fake.write_text("#!/bin/sh\nexit 23\n")
        fake.chmod(0o755)
        self.env["PATH"] = str(fakebin) + ":" + self.env["PATH"]
        self.run_service("snapshot", ok=False)
        snapshots = self.shared / "backups/server-services/test-server/snapshots"
        self.assertFalse((snapshots / "latest").exists())
        self.assertFalse((self.shared / ".terminal-setup-sync.lock").exists())

    def test_timer_uses_backup_only_and_can_be_disabled(self):
        self.run_service("install")
        fakebin = self.root / "fake-bin"
        fakebin.mkdir()
        fake = fakebin / "systemctl"
        fake.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/systemctl-calls"\n')
        fake.chmod(0o755)
        self.env["PATH"] = str(fakebin) + ":" + self.env["PATH"]
        before = self.inventory()
        self.run_service("enable-timer", "--dry-run")
        self.assertEqual(self.inventory(), before)
        self.run_service("enable-timer")
        unit = self.home / ".config/systemd/user/terminal-setup-backup.service"
        content = unit.read_text()
        self.assertIn('"backup" "--config"', content)
        self.assertNotIn('"pull"', content)
        self.assertIn("ExecStart=:", content)
        self.run_service("disable-timer")
        self.assertIn("--user disable --now terminal-setup-backup.timer", (self.home / "systemctl-calls").read_text())
        self.config.unlink()
        self.run_service("disable-timer")


if __name__ == "__main__":
    unittest.main()
