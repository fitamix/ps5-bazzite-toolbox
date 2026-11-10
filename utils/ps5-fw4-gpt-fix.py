#!/usr/bin/env python3
"""Make a PS5 Bazzite bootc image (or a drive flashed with it) mountable on PS5 firmware 4.x.

Why: the bootc image's GPT header says the first usable sector is 2048. On FW 4.x the PS5 kernel then walks
(2048 - 2) * 4 = ~8184 partition entries although only the 128 real ones were read: it reads past its buffer
(thousands of "GEOM_PART: partition NNNN ..." lines in the kernel log, some of them PS5 library names), the
partition table fails its check, no partitions show up, the loader finds no files ("this USB storage device's
file system is not supported"), and with some fast USB 3 readers the console powers off. Later firmware (12.40)
doesn't have the bug. With first usable sector = 34 (right after the 128 entries, what gdisk/sgdisk normally
write) FW 4.50 mounts the boot partition. See VivaLaVent/ps5-bazzite-deck issue #47.

What it changes: only the "first usable LBA" field of the two GPT headers (primary and backup), plus their
checksums. Partitions, data and the partition entries themselves are not touched; Linux, bootc and the loader
don't care about this field. Nothing is written without --apply, and it asks before writing.
Undo: run it again with --first-lba 2048 (the image's original value).

Usage:
  python3 ps5-fw4-gpt-fix.py IMAGE.img                 show what would change
  python3 ps5-fw4-gpt-fix.py IMAGE.img --apply         fix the image file, then flash it as usual
  sudo python3 ps5-fw4-gpt-fix.py /dev/sdX --apply     fix an already flashed drive (Linux)
  sudo python3 ps5-fw4-gpt-fix.py /dev/rdiskN --apply  same on macOS (diskutil unmountDisk diskN first)
Windows: run it inside WSL on the .img before flashing.
"""
import argparse, struct, sys, zlib

ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
ap.add_argument("target", help="the .img file or the whole drive (/dev/sdX, /dev/rdiskN)")
ap.add_argument("--apply", action="store_true", help="write the change (asks first)")
ap.add_argument("--yes", action="store_true", help="don't ask (with --apply)")
ap.add_argument("--first-lba", type=int, help="value to set (default: first sector after the partition entries)")
a = ap.parse_args()


def die(msg):
    sys.exit("ERROR: " + msg)


f = open(a.target, "r+b" if a.apply else "rb", buffering=0)


def read(lba, n=1):
    f.seek(lba * ss)
    return bytearray(f.read(n * ss))


# Logical sector size: the GPT header sits at LBA 1 (byte 512 or 4096).
for ss in (512, 4096):
    if read(1)[:8] == b"EFI PART":
        break
else:
    die(f"no GPT header found in {a.target}")


def parse(h, where):
    hsize, crc, _, cur, alt, first, last = struct.unpack_from("<IIIQQQQ", h, 12)
    if not 92 <= hsize <= ss:
        die(f"{where} GPT header has a strange size ({hsize})")
    chk = bytearray(h[:hsize]); struct.pack_into("<I", chk, 16, 0)
    if zlib.crc32(chk) & 0xFFFFFFFF != crc:
        die(f"{where} GPT header checksum doesn't match: not touching a damaged table")
    ent_lba, nent, esize = struct.unpack_from("<QII", h, 72)
    return dict(hsize=hsize, cur=cur, alt=alt, first=first, last=last, ent_lba=ent_lba, nent=nent, esize=esize)


prim = read(1); p = parse(prim, "primary")
back = read(p["alt"]);
if back[:8] != b"EFI PART":
    die(f"no backup GPT header at sector {p['alt']} (the primary header points there)")
b = parse(back, "backup")
ent_sectors = (p["nent"] * p["esize"] + ss - 1) // ss
target = a.first_lba if a.first_lba is not None else p["ent_lba"] + ent_sectors

# The new value must not overlap the entries and no partition may start before it.
ents = read(p["ent_lba"], ent_sectors)
starts = [struct.unpack_from("<Q", ents, i * p["esize"] + 32)[0]
          for i in range(p["nent"]) if any(ents[i * p["esize"]:i * p["esize"] + 16])]
if target < p["ent_lba"] + ent_sectors:
    die(f"first usable sector {target} would overlap the partition entries (they end at {p['ent_lba'] + ent_sectors - 1})")
if starts and min(starts) < target:
    die(f"a partition starts at {min(starts)}, before {target}")

print(f"{a.target}: {ss}-byte sectors, {len(starts)} partitions, entries at {p['ent_lba']}-{p['ent_lba'] + ent_sectors - 1}")
print(f"  primary header (sector 1):          first usable sector {p['first']}")
print(f"  backup header (sector {p['alt']}): first usable sector {b['first']}")
if p["first"] == target and b["first"] == target:
    print(f"Already {target}: nothing to do.")
    sys.exit(0)
print(f"  -> both set to {target}" + ("  (FW 4.x needs 34; 2048 is what trips it)" if target == 34 else ""))
if not a.apply:
    print("Nothing written. Add --apply to write it.")
    sys.exit(0)
if not a.yes:
    if input(f"Write the two GPT headers of {a.target}? [y/N] ").strip().lower() not in ("y", "yes"):
        sys.exit("Cancelled.")


def fix(h, info, lba):
    struct.pack_into("<Q", h, 40, target)
    struct.pack_into("<I", h, 16, 0)
    struct.pack_into("<I", h, 16, zlib.crc32(bytes(h[:info["hsize"]])) & 0xFFFFFFFF)
    f.seek(lba * ss); f.write(bytes(h))


fix(back, b, p["alt"])
fix(prim, p, 1)
f.close()
# Read back and check.
f = open(a.target, "rb", buffering=0)
for lba, where in ((1, "primary"), (p["alt"], "backup")):
    if parse(read(lba), where)["first"] != target:
        die(f"{where} header didn't take the change")
print(f"Done: first usable sector = {target} in both headers.")
