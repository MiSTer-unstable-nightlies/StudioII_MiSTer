import sys
import os

# Raw .bin files are address-faithful images beginning at CPU address $0400.
# An output byte at offset N is therefore loaded at $0400 + N.
RAW_BASE_PAGE = 0x04
RAW_FILL = 0xFF

# On an RCA Studio II these pages are RAM, not cartridge ROM.
RESERVED_RAM_PAGES = {0x08, 0x09}

# If these first-bank cartridge pages contain only $FF, omitting them from an
# ST2 is equivalent to mapping an all-$FF ROM there: the unmapped bus reads $FF.
# This lets a padded raw BIN reconstruct sparse ST2 layouts such as Grand Pack.
OPEN_BUS_PAGES = {0x0A, 0x0B, 0x0E, 0x0F}

ST2_MAX_BLOCKS = 64


def _is_all_ff(block):
    return all(b == RAW_FILL for b in block)


def convert_st2_to_bin(filepath):
    with open(filepath, "rb") as f:
        data = f.read()

    if len(data) < 256 or data[0:4] != b"RCA2":
        print(f"[-] {os.path.basename(filepath)} is not a valid ST2 file.")
        return False

    count_field = data[4]
    if count_field < 1:
        print(f"[-] {os.path.basename(filepath)} has an invalid ST2 block count.")
        return False

    num_data_blocks = count_field - 1
    if num_data_blocks > ST2_MAX_BLOCKS:
        print(f"[-] {os.path.basename(filepath)} declares too many ST2 blocks.")
        return False

    expected_size = 256 + (num_data_blocks * 256)
    if len(data) < expected_size:
        print(
            f"[-] {os.path.basename(filepath)} is truncated: "
            f"expected at least {expected_size} bytes, got {len(data)}."
        )
        return False

    mapped = []
    seen_pages = set()

    for i in range(num_data_blocks):
        page = data[64 + i]
        if page == 0:
            continue

        if page < RAW_BASE_PAGE:
            print(
                f"[-] {os.path.basename(filepath)} maps block {i} to page "
                f"${page:02X}, below the raw BIN base address $0400."
            )
            return False

        if page in seen_pages:
            print(
                f"[-] {os.path.basename(filepath)} maps more than one block "
                f"to page ${page:02X}; refusing an ambiguous conversion."
            )
            return False

        seen_pages.add(page)
        block_start = 256 + (i * 256)
        block = data[block_start:block_start + 256]
        mapped.append((page, block))

    if not mapped:
        print(f"[-] {os.path.basename(filepath)} contains no mapped cartridge blocks.")
        return False

    highest_page = max(page for page, _ in mapped)
    out_len = (highest_page - RAW_BASE_PAGE + 1) * 256
    out_bin = bytearray([RAW_FILL]) * out_len

    for page, block in mapped:
        out_offset = (page - RAW_BASE_PAGE) * 256
        out_bin[out_offset:out_offset + 256] = block

    out_path = os.path.splitext(filepath)[0] + ".bin"
    with open(out_path, "wb") as f:
        f.write(out_bin)

    pages = " ".join(f"{page:02X}" for page, _ in mapped)
    print(
        f"[+] Converted ST2 -> BIN: {os.path.basename(out_path)} "
        f"({len(out_bin)} bytes; pages {pages})"
    )
    return True


def convert_bin_to_st2(filepath):
    with open(filepath, "rb") as f:
        data = f.read()

    if not data:
        print(f"[-] {os.path.basename(filepath)} is empty.")
        return False

    # Raw BIN holes represent unmapped/open-bus space, so pad partial pages with $FF.
    remainder = len(data) % 256
    if remainder:
        data += bytes([RAW_FILL]) * (256 - remainder)

    raw_blocks = len(data) // 256
    highest_page = RAW_BASE_PAGE + raw_blocks - 1
    if highest_page > 0xFF:
        print(
            f"[-] {os.path.basename(filepath)} extends beyond ST2 page $FF "
            f"when based at $0400."
        )
        return False

    mapped = []

    for i in range(raw_blocks):
        page = RAW_BASE_PAGE + i
        block = data[i * 256:(i + 1) * 256]

        if page in RESERVED_RAM_PAGES:
            if not _is_all_ff(block):
                print(
                    f"[-] {os.path.basename(filepath)} contains non-$FF data for "
                    f"reserved Studio II RAM page ${page:02X}. "
                    f"This cannot be represented as cartridge ROM."
                )
                return False
            continue

        # In the first 4K bank these pages normally read as open bus ($FF).
        # Dropping an all-$FF page preserves runtime behaviour and reconstructs
        # sparse ST2 page maps produced by ST2 -> BIN.
        if page in OPEN_BUS_PAGES and _is_all_ff(block):
            continue

        mapped.append((page, block))

    if len(mapped) > ST2_MAX_BLOCKS:
        print(
            f"[-] {os.path.basename(filepath)} requires {len(mapped)} ST2 blocks; "
            f"the format table holds at most {ST2_MAX_BLOCKS}."
        )
        return False

    header = bytearray(256)
    header[0:4] = b"RCA2"
    header[4] = len(mapped) + 1
    header[5] = 1
    header[6] = 0

    for i, (page, _) in enumerate(mapped):
        header[64 + i] = page

    out_path = os.path.splitext(filepath)[0] + ".st2"
    with open(out_path, "wb") as f:
        f.write(header)
        for _, block in mapped:
            f.write(block)

    pages = " ".join(f"{page:02X}" for page, _ in mapped)
    print(
        f"[+] Converted BIN -> ST2: {os.path.basename(out_path)} "
        f"({len(mapped)} blocks; pages {pages})"
    )
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: Drag and drop .st2 or .bin files onto the converter batch file.")
        return

    for arg in sys.argv[1:]:
        if not os.path.isfile(arg):
            print(f"[-] Not a file: {arg}")
            continue

        ext = os.path.splitext(arg)[1].lower()
        if ext == ".st2":
            convert_st2_to_bin(arg)
        elif ext == ".bin":
            convert_bin_to_st2(arg)
        else:
            print(f"[-] Unsupported file type: {os.path.basename(arg)}")


if __name__ == "__main__":
    main()
