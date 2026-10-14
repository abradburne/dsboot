# Benchmarks

How dsboot's numbers were measured, and what each change was worth.

## Setup

- One Anbernic RG DS+, stock firmware V1.0 (20260915), starting from its SD card: a 16 GB
  SDHC card, which the kernel runs at 50 MHz (SDR104 mode capped by the device tree, about
  20 MB/s). A second SD card, exFAT, holds 251 DS games.
- [DSlot](https://github.com/abradburne/dslot) starting at power-on, from the OS card.
- Lid open, no charger, Wi-Fi and Bluetooth off in the stock settings.

## Method

`dsboot_timing` (in Apps) is run once the menu is up. It changes nothing; it reads what the
system already records:

- **Time since power-on.** The kernel takes its log timestamps from the ARM timer, which starts
  at power-on; `/proc/uptime` starts when Linux starts its clock. Writing a line to the kernel log
  and reading both gives the difference, which is everything before the kernel: U-Boot, and
  loading and checking the kernel.
- **When each program started**, from `/proc/<pid>/stat`, to 10 ms.
- **When each start-up script finished**, with processor time and megabytes read from each card,
  logged by dsboot's `rcS`.
- **DSlot's own stages**, in its `log.txt`.
- **First picture.** The kernel logs `Freeing drm_logo memory` when the boot logo is replaced by
  the first frame an app has drawn. That moment, from power-on, is the headline figure.

Each figure is from at least two cold starts; repeated starts agreed within 0.2 s. A start that
followed an install (dsboot learns its read-ahead lists then) is not counted.

## Result

Seconds from power-on.

| Milestone | Stock | dsboot |
|---|---|---|
| Kernel starts | 5.8 | 3.9 |
| Kernel hands over to init | 7.0 | 5.0 |
| Screen ready (Weston) | 13.5 | 8.8 |
| Vendor launch script starts | 14.5 | 9.0 |
| DSlot starts | about 16.8 | 9.1 |
| **DSlot's first picture on screen** | **21.1** | **11.5** |

## What each change gave

In the order they were made, each measured against the one before.

| Change | First picture | Gain |
|---|---|---|
| Stock | 21.1 s | |
| Start-up scripts reordered (screen, sound, menu first), launch script's fixed wait shortened, no disk check at every start | 18.3 s | 2.8 s |
| DSlot: CJK font parsed in the background, game scan cached, moved to the OS card | 16.8 s | 1.5 s |
| Kernel stored gzip-compressed | 14.9 s | 1.9 s |
| System partitions named by device in fstab; launch script finds the screen at its first look | 14.3 s | 0.6 s |
| Read-ahead of what a start needs, at idle I/O priority | 13.7 s | 0.6 s |
| Compressed copies of the 19 largest libraries | 12.9 s | 0.8 s |
| DSlot started as soon as the screen is up; radios after its first picture; 112 files compressed | 11.5 s | 1.4 s |

Two things that were tried and gave nothing:

- **Running the OS card at 150 MHz** (`bootimg.py --sd-clock`). The kernel finds no working
  tuning at that speed and falls back to 50 MHz.
- **Holding Weston's first frame for less time** (`WESTON_DRM_INITIAL_FREEZE_MS`). No change.

## Where the 11.5 s goes now

| Stage | Takes |
|---|---|
| U-Boot, and loading the compressed kernel | 3.9 s |
| Kernel | 1.1 s |
| init and mounting | 0.6 s |
| udev, then the screen, sound and compressed copies coming up together | 3.2 s |
| DSlot starting and drawing its first frame | 1.4 s |
| Weston putting that frame on screen | about 1.1 s |

What is left is mostly fixed: U-Boot and the graphics driver are Anbernic's binaries, and the
card cannot be read faster.

## Not measured yet

- Starting into the stock menu, without an app at power-on. It gets the same changes up to the
  vendor launch script.

## Measuring your own

Run **dsboot_timing** from Apps as soon as the menu is up, a few times. Results are in
`Roms/APPS/dsboot/timing/boot1`, `boot2`, … on the card: `report.txt` has the time before the
kernel, the moment init starts, and every running program in the order it started; `dsboot.log`
has the start-up script timings. For more detail, put an empty file called `trace` in
`Roms/APPS/dsboot` and run dsboot_install once: the vendor launch script then logs each command
with its time. Delete the file and run dsboot_install again to stop.
