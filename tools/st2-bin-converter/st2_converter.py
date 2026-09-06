import sys
import os

# Valid RCA Studio II cartridge pages per 4K bank
VALID_PAGES_PER_4K = [
    0x04, 0x05, 0x06, 0x07,
    0x0A, 0x0B,
    0x0E, 0x0F
]

def get_st2_page_sequence(num_blocks):
    """Generates valid hardware target pages ($04-$07, $0A-$0B, $0E-$0F...)."""
    sequence = []
    bank = 0
    while len(sequence) < num_blocks:
        for p in VALID_PAGES_PER_4K:
            sequence.append((bank * 0x10) + p)
            if len(sequence) == num_blocks:
                break
        bank += 1
    return sequence

def convert_st2_to_bin(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    if len(data) < 256 or data[0:4] != b'RCA2':
        print(f"[-] {os.path.basename(filepath)} is not a valid ST2 file.")
        return

    num_blocks = data[4]
    out_bin = bytearray()

    # Extract code blocks in table order without sparse RAM gap padding
    for i in range(num_blocks - 1):
        page = data[64 + i]
        if page == 0:
            continue  # Unused page slot

        block_start = 256 + (i * 256)
        out_bin.extend(data[block_start : block_start + 256])

    out_path = os.path.splitext(filepath)[0] + '.bin'
    with open(out_path, 'wb') as f:
        f.write(out_bin)

    print(f"[+] Converted ST2 -> BIN: {os.path.basename(out_path)} ({len(out_bin)} bytes)")


def convert_bin_to_st2(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    if not data:
        print(f"[-] {os.path.basename(filepath)} is empty.")
        return

    # Pad data to 256-byte alignment if required
    remainder = len(data) % 256
    if remainder != 0:
        data += b'\x00' * (256 - remainder)

    num_data_blocks = len(data) // 256
    if num_data_blocks > 64:
        print(f"[-] {os.path.basename(filepath)} exceeds max 16KB capacity.")
        return

    header = bytearray(256)
    header[0:4] = b'RCA2'
    header[4] = num_data_blocks + 1
    header[5] = 1
    header[6] = 0

    # Assign target pages skipping reserved RAM/IO regions
    page_map = get_st2_page_sequence(num_data_blocks)
    for i, page in enumerate(page_map):
        header[64 + i] = page

    out_path = os.path.splitext(filepath)[0] + '.st2'
    with open(out_path, 'wb') as f:
        f.write(header)
        f.write(data)

    print(f"[+] Converted BIN -> ST2: {os.path.basename(out_path)} ({num_data_blocks} blocks mapped)")


def main():
    if len(sys.argv) < 2:
        print("Usage: Drag and drop .st2 or .bin files onto this script.")
        return

    for arg in sys.argv[1:]:
        if not os.path.isfile(arg):
            continue

        ext = os.path.splitext(arg)[1].lower()
        if ext == '.st2':
            convert_st2_to_bin(arg)
        elif ext == '.bin':
            convert_bin_to_st2(arg)

if __name__ == '__main__':
    main()
