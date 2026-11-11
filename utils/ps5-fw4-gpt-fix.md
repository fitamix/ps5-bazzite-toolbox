# bootc images on PS5 firmware 4.x — GPT fix

For [VivaLaVent/ps5-bazzite-deck#47](https://github.com/VivaLaVent/ps5-bazzite-deck/issues/47): a drive flashed with
the bootc image isn't mounted by a PS5 on firmware 4.03/4.50 ("file system not supported", the loader finds no
files). With some fast USB 3 readers the console even powers off when the drive is plugged in.

## Cause

The image's GPT header says the **first usable sector is 2048**. On FW 4.x the PS5 kernel uses that to decide how
many partition entries to check: (2048 − 2) × 4 ≈ 8184, while only the 128 real ones were read. It reads past its
buffer, the table fails its consistency check, no partition nodes (`da1p1`…) are created, and AutoMounter only tries
the whole disk (`/dev/da1 has unknown format`). The kernel log shows it as thousands of lines like

```
GEOM_PART: partition 7938 has start offset inside partition 8111: ...
```

with partition numbers up to ~8178 and values that decode to PS5 library names (`ibSceRtc`, `pkg_3/pk`): memory, not
disk. FW 12.40 doesn't have the bug, which is why the same drive boots there. Legacy images (made with sgdisk, first
usable sector 34) mount on 4.x.

## How it was isolated

The first 1.8 GB of the bootc v2.9 image were written to a 512 GB microSD. For each test only the partition table
was changed. The card was then plugged into a running PS5 on FW 4.50 with klogsrv loaded.

| Test | Change from the image as flashed | Result on FW 4.50 |
|---|---|---|
| B | none (backup GPT mid-disk, as any imager leaves it) | refused; with a dual-slot USB 3 reader the console powered off |
| C | backup GPT moved to the end (`sgdisk -e`) and BIOS-boot entry removed | refused |
| L | only 2 entries, root as 1 and FAT as 2, like the Legacy image | refused |
| M | GRUB boot code in the MBR zeroed | refused |
| **F** | **first usable LBA 2048 → 34, nothing else** | **0 GEOM_PART lines, da1p1–p4 created, FAT mounted at /mnt/usb0** |

## Fix

**Fixed upstream in v2.11:** VivaLaVent's bootc images from v2.11 on are built with first usable LBA 34, so they mount
on FW 4.x as they are. Use this script only for an earlier image, or for a drive already flashed with one. The
project ships the same fix as `bootc/tools/gpt-first-lba.py`.

Download it from the latest release:
`curl -LO https://github.com/fitamix/ps5-bazzite-toolbox/releases/latest/download/ps5-fw4-gpt-fix.py`

`ps5-fw4-gpt-fix.py` changes only that field in both GPT headers, and their checksums. It doesn't touch the
partitions or the data. It needs Python 3 and nothing else.

```
python3 ps5-fw4-gpt-fix.py ps5-bazzite-deck-bootc-vX.img            # shows what it would change
python3 ps5-fw4-gpt-fix.py ps5-bazzite-deck-bootc-vX.img --apply    # fix the image, then flash it as usual
sudo python3 ps5-fw4-gpt-fix.py /dev/sdX --apply                   # or fix an already flashed drive (Linux)
sudo python3 ps5-fw4-gpt-fix.py /dev/rdiskN --apply                # macOS, after diskutil unmountDisk diskN
```

On Windows, run it in WSL on the `.img` before flashing it with balenaEtcher.

To undo the change, run `--first-lba 2048 --apply`.

For the image build, the fix is to create the table with first usable LBA 34 (sfdisk: `first-lba: 34`).

Fixing the image changes its checksum, so it no longer matches the release's `.sha256`. Check the download first,
then fix it.
