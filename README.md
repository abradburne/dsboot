# dsboot

A faster start-up for the Anbernic RG DS+ on its stock OS.

dsboot changes how the stock system starts, not what it is. You keep Anbernic's firmware, menu
and emulators; dsboot brings them up in a better order and reads less from the SD card on the
way. It installs from the stock **Apps** menu, keeps a copy of everything it replaces, and can
be rolled back the same way.

| Seconds from power-on | Stock | dsboot |
|---|---|---|
| Kernel starts | 5.8 | 3.9 |
| Screen ready | 13.5 | 8.8 |
| First picture of the app started at power-on ([DSlot](https://github.com/abradburne/dslot)) | **21.1** | **11.5** |

Measured on one RG DS+ starting from its SD card, firmware V1.0 (20260915). How, and what each
change gave: [docs/benchmarks.md](docs/benchmarks.md).

## What it does

The DS+ spends most of its start waiting for the SD card, which it reads at about 20 MB/s
whatever the card. dsboot:

- **Starts what you see first.** The stock scripts start every service one after another and
  only then the screen, sound and menu. dsboot runs the same scripts with the screen, sound and
  menu first, and SSH, time sync, network discovery and the rest behind them.
- **Reads less.** It keeps gzip-compressed copies of the 112 files a start reads the most of
  (166 MB, the 54 MB graphics driver above all, becomes about 70 MB) and uses them in place of the
  originals. The processors, which otherwise mostly wait, do the unpacking.
- **Reads ahead.** It learns once what a start reads, then reads it in the background at every
  start, only when nothing else is waiting for the card.
- **Drops waits it does not need:** a fixed 1.5 s pause in the vendor launch script, a disk check
  of five partitions at every start, and half a second spent looking up partitions by name.
- **Lets an app start as soon as the screen is up**, if the app asks to (DSlot does), with Wi-Fi
  and Bluetooth starting once its first picture is shown.
- **Swaps the stock menu's power-off picture** (the Anbernic "R") for a sleepy pixel handheld
  saying "SEE YOU SOON".
- **Optionally, stores the kernel compressed** (2 seconds) and swaps the two boot pictures for
  "RG DS Plus" ones. This is a separate step because it rewrites the card's boot partition.

## What you need

- An RG DS+ on the stock firmware V1.0 (20260915), starting from an SD card.
- A computer with an SD card reader.

dsboot has only been tried on a device that starts from its SD card. The main install should
also work on one that starts from internal storage; the compressed-kernel step refuses to run
there, and on any other firmware.

## Install

1. Download `dsboot-0.1.0-rgdsplus.zip` from the
   [latest release](https://github.com/abradburne/dsboot/releases/latest) and unzip it. Inside is a folder,
   `Roms`, holding one folder, `APPS`.
2. Turn the DS+ off, take out the SD card in the slot marked **TF1/INT**, the one it starts from,
   and put it in your computer. It shows as a drive called `ROMS`.
3. Copy **everything inside the zip's `Roms/APPS` folder** into the card's `Roms/APPS` folder:
   the `dsboot` folder and five `dsboot_*.sh` files. Copy the contents, not the `Roms` folder.
4. Put the card back and turn the DS+ on. In the stock menu open **Apps** and choose
   **dsboot_install**. Both screens show what it is doing; preparing the compressed copies takes
   a minute or so. Then the DS+ restarts by itself.
5. That first start is a little slower than usual: it learns what to read ahead. Let it reach the
   menu, wait a few seconds, then turn the DS+ off and on. Every start from then on is the fast
   one.

If the DS+ does not restart at step 4, nothing was changed; the screen and
`Roms/APPS/dsboot/install.log` say why.

### Optional: compressed kernel and boot pictures

6. In Apps, choose **dsboot_boot_fast**. It shows its progress, takes about half a minute, then
   the DS+ restarts with the kernel stored compressed and the "RG DS Plus" boot pictures.

The first time, the boot partition as it was is copied to the card as
`Roms/APPS/dsboot/boot-stock.img`, with its checksum beside it. **Keep that file**: rolling back,
from the DS+ or from a computer, puts it back.

### Pictures

All three pictures can be changed, in `Roms/APPS/dsboot` on the card, before running
dsboot_install (the power-off one) or dsboot_boot_fast (the two boot ones):

- An empty file called `stock-pictures` keeps Anbernic's.
- PNG files named `logo.png` (350×160, shown first at power-on), `logo_kernel.png` (1024×110,
  shown next) and `goodbye.png` (1024×768, shown by the stock menu as it powers off) are used
  instead of dsboot's. The boot ones may be other sizes, fitted inside on black.

`pictures/` in this repository has dsboot's, a DSlot pair, and their SVG sources.

## Roll back

In Apps, in this order:

1. **dsboot_boot_stock**, if you ran dsboot_boot_fast. It writes `boot-stock.img` back and
   restarts.
2. **dsboot_remove**. It puts back everything dsboot_install changed and restarts.

The DS+ then starts exactly as it did before. To finish, delete the `dsboot` folder and the
`dsboot_*.sh` files from the card's `Roms/APPS`.

## If something goes wrong

- **A start does not reach the menu.** Turn the DS+ off and on. The next start notices, uses the
  stock start-up instead, and keeps using it until dsboot_install is run again.
- **The menu comes up but something is wrong.** Put an empty file called `dsboot.off` at the top
  of the card's `ROMS` drive; the start after next is a stock one. Then roll back as above.
- **The DS+ does not start at all after dsboot_boot_fast.** Put the boot partition back from a
  computer, using the copy on the card:
  - Mac: with the card in, run `tools/restore-boot.sh` from this repository. It finds the card,
    checks the copy against its checksum, and asks for your password to write it.
  - Linux: copy `Roms/APPS/dsboot/boot-stock.img` off the card, check it against
    `boot-stock.img.sha256` beside it, and write it to the card's third partition:
    `sudo dd if=boot-stock.img of=/dev/sdX3 bs=1M conv=fsync`, where `sdX` is the card. Be sure of
    the device name: this overwrites what is there.

Every step writes what it did to `install.log` or `boot.log` in `Roms/APPS/dsboot`.

Wi-Fi and Bluetooth start at a different moment but work as before: switched on from the stock
settings after a dsboot start, both connect. Starting into the stock menu (no app at power-on)
has not been timed yet.

## What it changes on the device

| File | Change | Kept as it was in |
|---|---|---|
| `/etc/init.d/rcS` | Replaced: runs the stock start-up scripts in dsboot's order | `/etc/dsboot/stock/rcS` |
| `/etc/fstab` | System partitions named by device instead of label | `/etc/dsboot/stock/fstab` |
| `/mnt/vendor/ctrl/loadapp.sh` | Fixed wait 1.5 s → 0.2 s; waits for Wi-Fi and Bluetooth when they start late | `/etc/dsboot/stock/loadapp.sh` |
| `/.skip_fsck` | Created: the stock switch for no disk check at every start | (removed on roll back) |
| `/mnt/vendor/resource/res*/shutdown/goodbye.png` | The power-off picture | `/etc/dsboot/stock/` |
| `/etc/dsboot/` | dsboot's own files: compressed copies, read-ahead lists, helper | (removed on roll back) |
| Boot partition | Only with dsboot_boot_fast: kernel gzipped, boot pictures | `Roms/APPS/dsboot/boot-stock.img` on the card |

The compressed copies are made on the device from its own files, and each is only used while the
original still has the size and date it had then, so a library replaced by a firmware update is
not hidden by an old copy. The menu, emulators and sleep are untouched.

## For app makers: starting early

An app on the card the DS+ starts from can ask to start as soon as the screen is up, a second or
more before the vendor launch script would start it. Put an executable `update/early.sh` on that
card, beside the `update/update.sh` the stock system already runs at start. Without dsboot nothing
runs `early.sh`, so `update.sh` should start the app as before, and when `early.sh` has already
done so, wait for it instead. DSlot does both: see its `boot.sh` and `early.sh`.

When dsboot runs `early.sh`, `DSBOOT_SHOWN` names a file to create once the app's first picture is
on screen. dsboot holds Wi-Fi and Bluetooth back until then, five seconds at most.

## Measuring

**dsboot_timing** in Apps records where a start's time went, into
`Roms/APPS/dsboot/timing/boot1`, `boot2`, … on the card. See
[docs/benchmarks.md](docs/benchmarks.md) for what it records and how the figures above were made.

## Building

The release zip holds only dsboot's own scripts and programs; everything taken from the firmware
is made on the device. You need Rust with
[cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild) and zig. `tools/package.sh`
writes `dist/dsboot-<version>-rgdsplus.zip`.

| Path | What it is |
|---|---|
| `card/Roms/APPS/` | What goes on the card: the five Apps entries and the `dsboot` folder |
| `card/Roms/APPS/dsboot/rcS` | The start-up script that replaces the stock one |
| `card/Roms/APPS/dsboot/mksqsh.py` | Writes the compressed copies (squashfs), on the device's own Python |
| `card/Roms/APPS/dsboot/bootimg.py` | Rebuilds the boot partition: gzipped kernel, boot pictures |
| `card/Roms/APPS/dsboot/hot-files.txt` | The files that get compressed copies |
| `readahead/` | The helper program that records and reads ahead, and mounts the compressed copies |
| `pictures/` | Boot picture pairs, with SVG sources |
| `tools/` | Packaging, and restoring the boot partition from a Mac |

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE). dsboot is not affiliated with Anbernic.
