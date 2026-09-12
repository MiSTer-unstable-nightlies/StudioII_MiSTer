#!/usr/bin/env python3
"""Negative controls for the shell suite; no Verilator build or simulation."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
BASH = os.environ.get("BASH", "bash")


class SmokeChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("tools", "bin", "rom", "verilator/obj_dir_headless"):
            (self.root / directory).mkdir(parents=True)
        for name in ("headless-smoke.sh", "memdecode-test.sh", "tone-test.sh",
                     "chip8-loader-test.sh", "visicom-loader-test.sh"):
            shutil.copyfile(TOOLS / name, self.root / "tools" / name)
        (self.root / "rom/studio2.rom").write_bytes(bytes(2048))
        self.script("bin/make", 'exit "${FAKE_MAKE_STATUS:-0}"')
        python = sys.executable.replace("\\", "/").replace("'", "'\"'\"'")
        self.script("bin/python3", f"exec '{python}' \"$@\"")
        self.script("verilator/obj_dir_headless/Vtop", "echo injected-failure >&2\nexit 37")
        self.env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"])

    def script(self, name, body):
        path = self.root / name
        path.write_text("#!/usr/bin/env bash\n" + body + "\n", encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, name):
        return subprocess.run([BASH, str(self.root / "tools" / name)],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def test_simulator_failure_reaches_every_check(self):
        result = self.run_script("headless-smoke.sh")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("FAIL "), 5, result.stdout)
        self.assertNotIn("PASS ", result.stdout)
        logs = list((self.root / "out").glob("*/*.log"))
        self.assertEqual(len(logs), 5)
        for log in logs:
            self.assertIn("injected-failure", log.read_text(), log.name)

    def test_stale_build_and_make_error_stop_before_tests(self):
        for status in ("1", "2"):
            with self.subTest(status=status):
                self.env["FAKE_MAKE_STATUS"] = status
                result = self.run_script("headless-smoke.sh")
                self.assertEqual(result.returncode, 2)
                self.assertIn("stale or cannot be checked", result.stderr)
                self.assertFalse((self.root / "out").exists())

    def test_missing_measurement_cannot_pass(self):
        self.script("verilator/obj_dir_headless/Vtop", "exit 0")
        for name in ("tone-test.sh", "memdecode-test.sh"):
            with self.subTest(name=name):
                result = self.run_script(name)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_timeout_is_failure_and_keeps_log(self):
        self.script("verilator/obj_dir_headless/Vtop", "echo waiting\nwhile :; do :; done")
        self.env["HEADLESS_TIMEOUT"] = "0.1"
        result = self.run_script("headless-smoke.sh")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("FAIL "), 5, result.stdout)
        self.assertIn("exit 124", result.stdout)

    def test_success_and_separate_run_logs(self):
        self.script("verilator/obj_dir_headless/Vtop", "exit 0")
        for name in ("memdecode-test.sh", "tone-test.sh", "chip8-loader-test.sh",
                     "visicom-loader-test.sh"):
            self.script("tools/" + name, "exit 0")
        for _ in range(2):
            result = self.run_script("headless-smoke.sh")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count("PASS "), 5)
        self.assertEqual(len(list((self.root / "out").glob("*/*.log"))), 10)


if __name__ == "__main__":
    unittest.main()
