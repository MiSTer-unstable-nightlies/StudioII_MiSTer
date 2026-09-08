#!/usr/bin/env python3
"""Quick checks of screenshot regression bookkeeping; no RTL simulation."""
import argparse
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

spec = importlib.util.spec_from_file_location("sweep", Path(__file__).with_name("game-start-sweep.py"))
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)


def png(colour, level=6):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0" + bytes(colour), level)) + chunk(b"IEND", b""))


class SweepChecks(unittest.TestCase):
    def test_discovery_ignores_manifest_prefixes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / sweep.VISICOM).mkdir(parents=True)
            (root / sweep.RETAIL).mkdir(parents=True)
            (root / "bios").write_bytes(b"firmware")
            (root / sweep.VISICOM / "example.st2").write_bytes(b"cartridge")
            manifest = {"machines": {"visicom": "bios"}, "resident": {},
                        "cartridges": [{"sha256": sweep.digest(b"cartridge"), "title": "Example",
                                        "machines": ["visicom"],
                                        "modes": {"Bad prefix": ["a0", "a5"]}}]}
            with patch.object(sweep, "ROOT", root):
                cases, _ = sweep.inventory(manifest, "a")
            self.assertEqual(len(cases), 11)
            self.assertEqual({tuple(c["identity"]["presses"]) for c in cases},
                             {()} | {(f"a{key}@40:15",) for key in range(10)})

    def test_only_approved_st2_files_and_no_resident_cases(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for folder in (sweep.RETAIL, sweep.VISICOM):
                (root / folder).mkdir(parents=True)
                for suffix in ("st2", "bin", "rom", "ch8", "zip"):
                    (root / folder / f"game.{suffix}").write_bytes(str(folder).encode())
            (root / "verilator").mkdir()
            (root / "verilator/stale.st2").write_bytes(b"stale")
            (root / "software/stale.st2").write_bytes(b"stale")
            (root / "bios").write_bytes(b"bios")
            manifest = {"machines": {m: "bios" for m in
                        ("studio2", "mpt02", "studio3ntsc", "visicom")},
                        "resident": {"visicom": {"resident": ["a1"]}},
                        "cartridges": [{"sha256": sweep.digest(b"stale"), "title": "Stale",
                                        "machines": ["visicom"], "modes": {"stale": ["a0"]}}]}
            with patch.object(sweep, "ROOT", root):
                cases, coverage = sweep.inventory(manifest, "a")
                replay, _ = sweep.inventory(manifest, None)
            self.assertEqual(len(cases), 44)
            self.assertEqual(len(coverage), 2)
            self.assertEqual(replay, [])
            self.assertTrue(all(c["cart"] and Path(c["cart"]).suffix == ".st2" for c in cases))

    def test_missing_corpus_does_not_fall_back(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(sweep, "ROOT", Path(temp)):
            with self.assertRaisesRegex(ValueError, "Missing approved software folders"):
                sweep.inventory({}, "a")

    def test_hash_mapping_survives_rename_and_folder_move(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / "selected"
            folder.mkdir()
            cart = folder / "old.st2"
            cart.write_bytes(b"cartridge")
            (root / "bios").write_bytes(b"bios")
            manifest = {"machines": {"visicom": "bios"}, "cartridges": [
                {"sha256": sweep.digest(b"cartridge"), "title": "Reikan",
                 "machines": ["visicom"], "modes": {"Candidate": ["a5"]}}]}
            with patch.object(sweep, "ROOT", root):
                before, _ = sweep.inventory(manifest, None, [folder])
                moved = root / "moved"
                moved.mkdir()
                cart.rename(moved / "Reikan (Japan) (metadata).st2")
                after, _ = sweep.inventory(manifest, None, [moved])
                self.assertEqual(before[0]["id"], after[0]["id"])
                self.assertEqual(after[0]["title"], "Reikan / Candidate")
                (moved / "Reikan (Japan) (metadata).st2").write_bytes(b"different")
                with self.assertRaisesRegex(ValueError, "specify --machine"):
                    sweep.inventory(manifest, "a", [moved])
                unknown, _ = sweep.inventory(manifest, "a", [moved], ["visicom"])
                self.assertEqual(len(unknown), 11)
                self.assertNotEqual(before[0]["identity"]["cart_sha256"],
                                    unknown[0]["identity"]["cart_sha256"])

    def test_pixel_hash_ignores_compression_but_detects_pixels_and_corruption(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "frame.png"
            path.write_bytes(png((10, 20, 30), 0))
            expected = sweep.pixel_hash(path)
            path.write_bytes(png((10, 20, 30), 9))
            self.assertEqual(expected, sweep.pixel_hash(path))
            path.write_bytes(png((10, 20, 31)))
            self.assertNotEqual(expected, sweep.pixel_hash(path))
            path.write_bytes(path.read_bytes()[:-3])
            with self.assertRaises(ValueError):
                sweep.pixel_hash(path)

    def test_review_approval_comparison_and_missing_capture(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bios, rtl = root / "bios", root / "rtl"
            bios.write_bytes(b"firmware")
            rtl.write_bytes(b"mock simulator")
            case = sweep.make_case("visicom", bios, None, "Example", ["a5"])
            baseline = root / "baseline.json"
            colour = [10, 20, 30]
            missing = False

            def simulate(cmd, **kwargs):
                self.assertEqual([cmd[i + 1] for i, arg in enumerate(cmd) if arg == "--press"],
                                 ["a5@40:15"])
                folder = Path(cmd[cmd.index("--outdir") + 1])
                for frame in case["identity"]["shots"]:
                    if not missing:
                        (folder / f"frame_f{frame:05d}.png").write_bytes(png(colour))

            def run(name, repeats):
                out = root / name
                argv = ["sweep", "--run", "--rtl", str(rtl), "--out", str(out),
                        "--repeat", str(repeats), "--baseline", str(baseline)]
                with patch.object(sweep, "inventory", return_value=([case], [])) as inventory, \
                     patch.object(sweep.subprocess, "run", side_effect=simulate), \
                     patch.object(sweep.sys, "argv", argv):
                    code = sweep.main()
                    self.assertEqual(inventory.call_args.args[1], "a")
                row = sweep.read_json(out / "results.json")["results"][0]
                return code, row, out

            code, row, out = run("once", 1)
            self.assertEqual((code, row["status"]), (0, "REVIEW"))
            args = argparse.Namespace(approve=out, case=[case["id"]], baseline=baseline)
            with self.assertRaises(ValueError):
                sweep.approve(args)
            code, row, out = run("twice", 2)
            args.approve = out
            sweep.approve(args)
            self.assertEqual(run("match", 1)[1]["status"], "PASS")
            colour[0] += 1
            code, row, _ = run("changed", 1)
            self.assertEqual((code, row["status"]), (1, "DIFF"))
            missing = True
            code, row, _ = run("missing", 1)
            self.assertEqual((code, row["status"]), (1, "ERROR"))

    def test_unstable_runs_cannot_be_approved(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sweep.write_json(root / "results.json", {"results": [
                {"id": "unstable", "repeat_hashes": [["a"], ["b"]]}]})
            args = argparse.Namespace(approve=root, case=["unstable"], baseline=root / "baseline.json")
            with self.assertRaises(ValueError):
                sweep.approve(args)
            self.assertFalse(args.baseline.exists())


if __name__ == "__main__":
    unittest.main()
