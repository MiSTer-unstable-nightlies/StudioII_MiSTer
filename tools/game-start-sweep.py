#!/usr/bin/env python3
"""Inventory software, capture start sequences, and compare approved pixel baselines."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
from urllib.parse import quote
import zlib

ROOT = Path(__file__).resolve().parents[1]
CORPUS = Path("software/RCA-Studio-II-Fullset")
RETAIL = CORPUS / "1 Studio II - MPT-02"
VISICOM = CORPUS / "1 Visicom COM-100"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def pixel_hash(path):
    """Hash dimensions and RGB pixels, independent of the harness PNG compression."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Invalid PNG")
    pos, payload, dimensions = 8, bytearray(), None
    while pos < len(data):
        size = struct.unpack_from(">I", data, pos)[0]
        tag, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + size]
        if pos + size + 12 > len(data):
            raise ValueError("Truncated PNG")
        if zlib.crc32(tag + body) & 0xffffffff != struct.unpack_from(">I", data, pos + size + 8)[0]:
            raise ValueError("PNG checksum mismatch")
        if tag == b"IHDR":
            w, h, depth, colour, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, colour, compression, filtering, interlace) != (8, 2, 0, 0, 0):
                raise ValueError("Expected harness RGB8 non-interlaced PNG")
            dimensions = (w, h)
        elif tag == b"IDAT":
            payload.extend(body)
        pos += size + 12
        if tag == b"IEND":
            break
    if dimensions is None:
        raise ValueError("Missing PNG dimensions")
    w, h = dimensions
    raw = zlib.decompress(payload)
    stride = 1 + 3 * w
    if len(raw) != h * stride or any(raw[y * stride] != 0 for y in range(h)):
        raise ValueError("Expected harness unfiltered RGB rows")
    pixels = b"".join(raw[y * stride + 1:(y + 1) * stride] for y in range(h))
    return digest(struct.pack(">II", w, h) + pixels)


def make_case(machine, bios, cart, title, keys):
    events = [f"{key}@{40 + i * 50}:15" for i, key in enumerate(keys)]
    # Capture after the entire sequence, with a fixed interval for motion review.
    shot = max(240, 100 + 50 * len(keys))
    identity = {"machine": machine, "bios_sha256": digest(bios.read_bytes()),
                "cart_sha256": digest(cart.read_bytes()) if cart else None,
                "presses": events, "shots": [shot, shot + 40, shot + 80],
                "ce4": True, "joy_map": 0, "scale": 1}
    return {"id": digest(json.dumps(identity, sort_keys=True).encode())[:20],
            "title": title, "machine": machine, "bios": str(bios),
            "cart": str(cart) if cart else None, "identity": identity}


def inventory(manifest, explore, folders=None, machine_override=None):
    known, cases, coverage = {}, {}, []
    configured = manifest.get("folders", [
        {"path": str(RETAIL), "machines": ["studio2", "mpt02", "studio3ntsc"]},
        {"path": str(VISICOM), "machines": ["visicom"]}])
    defaults = { (ROOT / item["path"]).resolve(): item["machines"] for item in configured }
    folders = [Path(p).resolve() for p in folders] if folders else list(defaults)
    missing = [str(path) for path in folders if not path.is_dir()]
    if missing:
        raise ValueError("Missing approved software folders: " + ", ".join(missing))
    def allowed(path):
        return path.suffix.lower() == ".st2" and any(
            path.resolve().is_relative_to(folder.absolute()) for folder in folders)

    exploratory_modes = {"No input": []}
    exploratory_modes.update({f"Explore {pad.upper()}{key}": [f"{pad}{key}"]
                              for pad in (explore or "") for key in range(10)})
    for entry in manifest["cartridges"]:
        sha = entry["sha256"]
        if not re.fullmatch("[0-9a-f]{64}", sha) or sha in known:
            raise ValueError(f"Invalid or duplicate cartridge SHA-256: {sha}")
        known[sha] = entry
    machines = manifest["machines"]
    for path in sorted({path for folder in folders for path in folder.rglob("*")}):
        if not path.is_file() or not allowed(path):
            continue
        relative = path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path)
        record = {"path": relative, "cases": []}
        coverage.append(record)
        sha = digest(path.read_bytes())
        record["sha256"] = sha
        entry = known.get(sha)
        if entry:
            targets, modes = entry["machines"], entry.get("modes", {})
            record["title"] = entry["title"]
            record["status"] = "recorded sequences" if modes else "known image; starts unverified"
        else:
            record["status"] = "unknown image/sequence"
            if not explore:
                continue
            targets = machine_override or sorted({m for folder, names in defaults.items()
                                                  if path.is_relative_to(folder) for m in names})
            if not targets:
                raise ValueError(f"Unknown image in selected folder: {path}; specify --machine")
            modes = {}
        if explore:
            modes = exploratory_modes
            record["status"] = "exploration (not verified starts)"
        for machine in targets:
            bios = ROOT / machines[machine]
            if not bios.is_file():
                record.setdefault("missing_firmware", []).append(machine)
                continue
            for mode, keys in modes.items():
                if any(not re.fullmatch("[ab][0-9]", key) for key in keys):
                    raise ValueError(f"Invalid keys for {mode}: {keys}")
                title = entry["title"] if entry else path.stem
                case = make_case(machine, bios, path, title + " / " + mode, keys)
                cases.setdefault(case["id"], case)
                record["cases"].append(case["id"])
    return list(cases.values()), coverage


def gallery(out, results, coverage):
    esc = html.escape
    body = ["<!doctype html><meta charset='utf-8'><title>Game start review</title>",
            "<style>body{font:16px system-ui;margin:24px;background:#eee}article{background:white;padding:16px;margin:16px 0}img{width:256px;max-height:320px;object-fit:contain;image-rendering:pixelated;margin:8px}code{word-break:break-all}</style>",
            "<h1>Game start review</h1><p>Review the selected mode and setup screen. Matching pixels are regression evidence, not proof of complete gameplay.</p>",
            "<p>Visicom A1/A2/A3/A4/A7 select resident games even with a cartridge loaded. These are resident controls, not cartridge starts. Identify each candidate mode visually.</p>",
            "<p><a href='results.json'>Results and commands</a> · <a href='coverage.json'>Full inventory and gaps</a></p>"]
    for row in results:
        body.append(f"<article><h2>{esc(row['machine'])}: {esc(row['title'])}</h2>"
                    f"<p>{esc(row['status'])} · <code>{row['id']}</code></p>"
                    f"<p>{esc(', '.join(row['identity']['presses']) or 'No input')}</p>")
        for shot in row.get("images", []):
            body.append(f"<a href='{quote(shot)}'><img src='{quote(shot)}' alt='{esc(shot)}'></a>")
        if row.get("error"):
            body.append(f"<p>{esc(row['error'])}</p>")
        body.append("</article>")
    gaps = [r for r in coverage if not r.get("cases")]
    body.append(f"<h2>Inventory gaps ({len(gaps)})</h2><ul>")
    body.extend(f"<li>{esc(r['path'])}: {esc(r['status'])}</li>" for r in gaps)
    body.append("</ul>")
    (out / "index.html").write_text("\n".join(body), encoding="utf-8")


def approve(args):
    data = read_json(args.approve / "results.json")
    selected = set(args.case or [])
    if not selected:
        raise ValueError("Approval requires explicit --case IDs after visual review")
    rows = {row["id"]: row for row in data["results"]}
    if selected - rows.keys():
        raise ValueError("Approval contains unknown case IDs")
    baseline = read_json(args.baseline) if args.baseline.exists() else {}
    for key in selected:
        row = rows[key]
        hashes = row.get("repeat_hashes", [])
        if row.get("error") or len(hashes) < 2 or not all(h == hashes[0] for h in hashes):
            raise ValueError(f"{key}: needs at least two successful identical runs")
        baseline[key] = {"identity": row["identity"], "pixels": hashes[0],
                         "title": row["title"], "reviewed_run": str(args.approve.resolve())}
    args.baseline.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.baseline, baseline)
    print(f"Approved {len(selected)} cases in {args.baseline}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / "tools/game-starts.json")
    parser.add_argument("--run", action="store_true", help="execute simulations; default only inventories")
    parser.add_argument("--folder", action="append", type=Path,
                        help="scan only ST2 files under this folder; repeatable; replaces manifest folders")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--explore", choices=["a", "ab"], default="a", help="fresh boot for every A key (default), or all 20 keys, plus no input")
    mode.add_argument("--sequences", dest="explore", action="store_const", const=None,
                      help="replay manifest sequences instead of discovering start keys")
    parser.add_argument("--machine", action="append", choices=["studio2", "mpt02", "studio3ntsc", "visicom"])
    parser.add_argument("--match", default="", help="case-insensitive title/path substring")
    parser.add_argument("--case", action="append", help="exact case ID; repeatable")
    parser.add_argument("--limit", type=int, help="limit cases for a small first run")
    parser.add_argument("--repeat", type=int, default=1, choices=[1, 2], help="two runs required before baseline approval")
    parser.add_argument("--timeout", type=int, default=300, help="wall seconds per simulation")
    parser.add_argument("--rtl", type=Path, default=ROOT / "verilator/obj_dir_headless/Vtop")
    parser.add_argument("--out", type=Path, help="new output directory; must not already exist")
    parser.add_argument("--baseline", type=Path, default=ROOT / "out/game-start-baselines.json")
    parser.add_argument("--approve", type=Path, help="reviewed run directory; requires --case IDs")
    args = parser.parse_args()
    if args.approve:
        approve(args)
        return 0
    if args.timeout <= 0 or (args.limit is not None and args.limit <= 0):
        raise ValueError("Timeout and limit must be positive")
    cases, coverage = inventory(read_json(args.manifest), args.explore, args.folder, args.machine)
    cases = [c for c in cases if (not args.machine or c["machine"] in args.machine)
             and args.match.lower() in (c["title"] + str(c["cart"])).lower()
             and (not args.case or c["id"] in args.case)]
    if args.limit:
        cases = cases[:args.limit]
    if not cases:
        raise ValueError("No matching cases")
    if args.run and not args.rtl.is_file():
        raise ValueError("Build the harness first: make -C verilator -B headless")
    if args.out:
        out = args.out.resolve()
        out.mkdir(parents=True, exist_ok=False)
    else:
        (ROOT / "out").mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix="game-start-sweep-", dir=ROOT / "out"))
    write_json(out / "coverage.json", coverage)
    baseline = read_json(args.baseline) if args.baseline.exists() else {}
    report = {"simulator_sha256": digest(args.rtl.read_bytes()) if args.run else None,
              "results": []}
    print(f"{len(cases)} cases, {args.repeat} run(s) each. Output: {out}", flush=True)
    failed = False
    for case in cases:
        row = dict(case, status="PLANNED", repeat_hashes=[], images=[])
        report["results"].append(row)
        if args.run:
            print(f"{case['machine']}: {case['title']}", flush=True)
            try:
                for repeat in range(args.repeat):
                    folder = out / case["id"] / str(repeat + 1)
                    folder.mkdir(parents=True)
                    shots = case["identity"]["shots"]
                    cmd = [str(args.rtl.resolve()), "--machine", case["machine"], "--bios", case["bios"],
                           "--joy-map", "0", "--ce4", "--scale", "1", "--quiet", "--frame-log",
                           "--frames", str(shots[-1] + 1), "--shot", ",".join(map(str, shots)),
                           "--outdir", str(folder), "--prefix", "frame"]
                    if case["cart"]:
                        cmd += ["--cart", case["cart"]]
                    for event in case["identity"]["presses"]:
                        cmd += ["--press", event]
                    write_json(folder / "command.json", cmd)
                    with (folder / "run.log").open("w") as log:
                        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout, check=True)
                    images = [folder / f"frame_f{frame:05d}.png" for frame in shots]
                    row["repeat_hashes"].append([pixel_hash(p) for p in images])
                    row["images"].extend(p.relative_to(out).as_posix() for p in images)
                row["status"] = "REVIEW"
                if any(h != row["repeat_hashes"][0] for h in row["repeat_hashes"]):
                    row["status"] = "NONDETERMINISTIC"
                elif case["id"] in baseline:
                    expected = baseline[case["id"]]
                    if expected["identity"] != case["identity"]:
                        raise ValueError("Baseline protocol mismatch")
                    row["status"] = "PASS" if row["repeat_hashes"][0] == expected["pixels"] else "DIFF"
                failed |= row["status"] in {"DIFF", "NONDETERMINISTIC"}
            except (OSError, ValueError, subprocess.SubprocessError, zlib.error, struct.error) as error:
                row["status"], row["error"], failed = "ERROR", str(error), True
        write_json(out / "results.json", report)
        gallery(out, report["results"], coverage)
    print(f"Review: {out / 'index.html'}")
    print("Unapproved cases remain REVIEW; coverage.json lists approved-folder ST2 images only.")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
