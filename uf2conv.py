#!/usr/bin/env python3
"""
Simple bin to UF2 converter for RP2040
Family ID for RP2040: 0xe48bff56
"""
import sys
import struct

UF2_MAGIC_START0 = 0x0A324655
UF2_MAGIC_START1 = 0x9E5D5157
UF2_MAGIC_END    = 0x0AB16F30
RP2040_FAMILY_ID = 0xe48bff56
FLASH_START      = 0x10000000

def bin_to_uf2(bin_path, uf2_path, base_addr=FLASH_START):
    with open(bin_path, "rb") as f:
        data = f.read()

    payload_size = 256
    num_blocks = (len(data) + payload_size - 1) // payload_size
    if num_blocks == 0:
        num_blocks = 1

    out_bytes = bytearray()
    for block_no in range(num_blocks):
        offset = block_no * payload_size
        chunk = data[offset : offset + payload_size]
        if len(chunk) < payload_size:
            chunk = chunk + b"\x00" * (payload_size - len(chunk))

        target_addr = base_addr + offset
        flags = 0x00002000 # familyID present

        header = struct.pack(
            "<IIIIIIII",
            UF2_MAGIC_START0,
            UF2_MAGIC_START1,
            flags,
            target_addr,
            payload_size,
            block_no,
            num_blocks,
            RP2040_FAMILY_ID
        )

        padding = b"\x00" * (512 - len(header) - len(chunk) - 4)
        footer = struct.pack("<I", UF2_MAGIC_END)

        block = header + chunk + padding + footer
        assert len(block) == 512
        out_bytes.extend(block)

    with open(uf2_path, "wb") as f:
        f.write(out_bytes)
    print(f"Created {uf2_path}: {len(data)} bytes -> {num_blocks} UF2 blocks ({len(out_bytes)} bytes)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: uf2conv.py <input.bin> <output.uf2>")
        sys.exit(1)
    bin_to_uf2(sys.argv[1], sys.argv[2])

