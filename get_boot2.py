import urllib.request

url = "https://raw.githubusercontent.com/rp-rs/rp2040-boot2/main/bin/boot2_w25q080.padded.bin"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
data = urllib.request.urlopen(req).read()
assert len(data) == 256, f"Expected 256 bytes, got {len(data)}"

out_path = r"C:\Users\cachi\.gemini\antigravity\scratch\Pong_ARM_RP2040\boot2.s"
with open(out_path, "w") as f:
    f.write("/* Second stage bootloader for RP2040 (W25Q080 / W25Q16JV Flash) */\n")
    f.write(".syntax unified\n")
    f.write(".cpu cortex-m0plus\n")
    f.write(".thumb\n")
    f.write('.section .boot2, "ax"\n')
    f.write(".align 2\n")
    f.write(".global __boot2_start\n")
    f.write("__boot2_start:\n")
    for i in range(0, 256, 16):
        chunk = data[i:i+16]
        f.write("    .byte " + ", ".join(f"0x{b:02x}" for b in chunk) + "\n")

print("boot2.s generated successfully! Length:", len(data))

