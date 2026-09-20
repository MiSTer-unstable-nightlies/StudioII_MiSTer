#!/usr/bin/env python3
"""Self-contained cartridge, Marcel, and OpenStudio2 loader regression."""

from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
SIM = ROOT / "obj_dir_headless" / "Vtop"
RACE_COLOUR_V2 = ROOT.parent / "homebrew" / (
    "Race Colour v2 (2026.08.30) (azya52, Alan Steremberg).st2"
)


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


def st2_image(pages: list[int]) -> bytes:
    header = bytearray(0x100)
    header[:4] = b"RCA2"
    header[4] = len(pages) + 1
    header[5] = 1
    header[0x40:0x40 + len(pages)] = bytes(pages)
    payload = b"".join(pattern(0x100, page) for page in pages)
    return bytes(header) + payload


def run_cart_case(name: str, machine: str, native_bios: Path,
                  cartridge: Path) -> None:
    print(f"[loader-regression] {name}")
    subprocess.run(
        [
            str(SIM),
            "--bios", str(native_bios),
            "--machine", machine,
            "--cart", str(cartridge),
            "--frames", "3",
            "--cart-loader-check",
            "--quiet",
        ],
        cwd=ROOT,
        check=True,
    )


def main() -> None:
    cart_only = sys.argv[1:] == ["--cart-only"]
    if sys.argv[1:] and not cart_only:
        raise SystemExit("usage: test_loader.py [--cart-only]")
    subprocess.run(["make", "headless"], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix="studio2-loader-") as tmp:
        work = Path(tmp)
        native_bios = work / "empty-native.rom"
        cart_bios = work / "cart-native.rom"
        marcel = work / "marcel.bin"
        os2 = work / "openstudio2.bin"
        program = work / "boundary-and-oversize.ch8"
        paged = work / "bare-metal.st2"
        raw = work / "conventional.bin"

        native_bios.write_bytes(b"")
        cart_bios.write_bytes(pattern(0x1000, 0x44))
        marcel.write_bytes(pattern(0x300, 0x11))
        os2.write_bytes(pattern(0x800, 0x22))
        # $E00 legal bytes fill logical CHIP-8 $200-$FFF. The final byte is
        # deliberately oversized and must not wrap around to logical $000.
        program.write_bytes(pattern(0xE01, 0x33))
        paged.write_bytes(st2_image([
            0x00, 0x01, 0x02, 0x03, 0x04, 0x07,
            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        ]))
        raw.write_bytes(pattern(0x400, 0x55))

        if not cart_only:
            run_case("Bundled OpenStudio2", "", os2, program, native_bios)
            run_case("Marcel legacy companion", "--chip8-fw", marcel, program,
                     native_bios)
            run_case("OpenStudio2 manual interpreter", "--manual-chip8-fw", os2,
                     program, native_bios)
        run_cart_case("Studio II bare-metal ST2", "studio2", cart_bios, paged)
        run_cart_case("Race Colour v2 combined ST2", "studio2", cart_bios,
                      RACE_COLOUR_V2)
        run_cart_case("Studio III PAL bare-metal ST2", "studio3", cart_bios, paged)
        run_cart_case("Studio III NTSC bare-metal ST2", "studio3ntsc", cart_bios, paged)
        run_cart_case("Studio II conventional BIN", "studio2", cart_bios, raw)

    print("[loader-regression] PASS")


if __name__ == "__main__":
    main()
