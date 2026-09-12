#!/usr/bin/env python3
"""Self-contained Marcel/OpenStudio2 loader and decode regression."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
SIM = ROOT / "obj_dir_headless" / "Vtop"


def pattern(size: int, seed: int) -> bytes:
    return bytes(((i * 73) + seed) & 0xFF for i in range(size))


def run_case(name: str, firmware_option: str, firmware: Path, program: Path,
             native_bios: Path) -> None:
    print(f"[loader-regression] {name}")
    subprocess.run(
        [
            str(SIM),
            "--bios", str(native_bios),
            *([firmware_option, str(firmware)] if firmware_option else []),
            "--ch8", str(program),
            "--loader-check",
            "--quiet",
        ],
        cwd=ROOT,
        check=True,
    )


def main() -> None:
    subprocess.run(["make", "headless"], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix="studio2-loader-") as tmp:
        work = Path(tmp)
        native_bios = work / "empty-native.rom"
        marcel = work / "marcel.bin"
        os2 = work / "openstudio2.bin"
        program = work / "boundary-and-oversize.ch8"

        native_bios.write_bytes(b"")
        marcel.write_bytes(pattern(0x300, 0x11))
        os2.write_bytes(pattern(0x800, 0x22))
        # $E00 legal bytes fill logical CHIP-8 $200-$FFF. The final byte is
        # deliberately oversized and must not wrap around to logical $000.
        program.write_bytes(pattern(0xE01, 0x33))

        run_case("Bundled OpenStudio2", "", os2, program, native_bios)
        run_case("Marcel legacy companion", "--chip8-fw", marcel, program,
                 native_bios)
        run_case("OpenStudio2 manual interpreter", "--manual-chip8-fw", os2,
                 program, native_bios)

    print("[loader-regression] PASS")


if __name__ == "__main__":
    main()
