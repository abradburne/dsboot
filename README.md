# dsboot

A faster start-up for the Anbernic RG DS+ on its stock OS.

dsboot changes how the stock system starts, not what it is: the same Anbernic firmware, menu
and emulators, brought up in a better order, with less read from the SD card. You copy a
folder to the card and run it from **Apps**. Everything it changes is kept and can be put back.

| | Stock | dsboot |
|---|---|---|
| Power-on to the first picture of an app started at power-on ([DSlot](https://github.com/abradburne/dslot)) | 21.1 s | 11.5 s |

Measured on one RG DS+ starting from its SD card, firmware V1.0 (20260915). Starting into the
stock menu instead gets the same changes but has not been timed yet.

## What you need

- An RG DS+ on the stock firmware V1.0 (20260915), starting from an SD card. (dsboot's main
  part should also work on a device starting from its internal storage, but it has only been
  tried on one starting from an SD card. The faster kernel refuses to run on anything else.)
- A computer with an SD card reader.

## Install

1. Download `dsboot-0.1.0-rgdsplus.zip` from the latest release and unzip it. Inside is a folder,
   `Roms`, holding one folder, `APPS`.
2. Turn the DS+ off, take out the SD card it starts from and put it in your computer. It shows
   as a drive called `ROMS`.
3. Copy **everything inside the zip's `Roms/APPS` folder** into the card's `Roms/APPS` folder:
   the `dsboot` folder and five `.sh` files. Copy the contents, not the `Roms` folder itself.
4. Put the card back and turn the DS+ on. In the stock menu open **Apps** and choose
   **dsboot_install**. The screen does not change for a minute or so while it prepares; then
   the DS+ restarts by itself.
5. The first start after installing is a little slower than usual: it notes what it reads, so
   that later starts can read it ahead of time. Let it reach the menu and wait a few seconds.
   Every start after that is the fast one.

If the DS+ does not restart at step 4, nothing was changed: `Roms/APPS/dsboot/install.log` on
the card says why.

### Faster kernel and your own boot pictures

A further 2 seconds come from storing the kernel compressed. This rewrites the card's boot
partition, which a mistake can leave unable to start until it is put right from a computer, so
it is a separate step:

- In Apps, choose **dsboot_boot_fast**. It takes half a minute, then the DS+ restarts.
- **dsboot_boot_stock** puts the boot partition back as it was.

The first time, the boot partition as it was is copied to the card as
`Roms/APPS/dsboot/boot-stock.img`. Keep that file: it is what everything goes back to.

The same step can change the two boot pictures, the Anbernic logo and the line of text under
it. Put PNG files in `Roms/APPS/dsboot` on the card, named `logo.png` (350×160) and
`logo_kernel.png` (1024×110), and run **dsboot_boot_fast** again. Pictures of another size are
fitted inside on black. Without them the stock pictures stay. `pictures/` in this repository
has a pair to start from, with their SVG sources.

## Undo

**dsboot_remove** in Apps puts back everything dsboot_install changed and restarts.
**dsboot_boot_stock** does the same for the boot partition. Then delete `dsboot` and the
`dsboot_*.sh` and `bootprof.sh` files from the card's `Roms/APPS`.

## If something goes wrong

- **A start does not reach the menu.** The next start notices and goes back to the stock way of
  starting, and stays with it until dsboot_install is run again. Turn the DS+ off and on.
- **The menu comes up but something is wrong.** Put an empty file called `dsboot.off` at the top
  of the card's `ROMS` drive. The start after next is a stock one. Then run dsboot_remove.
- **The DS+ does not start at all after dsboot_boot_fast.** Write `boot-stock.img` back to the
  card's boot partition from a computer:
  - Mac: with the card in, run `tools/restore-boot.sh` from this repository. It finds the card,
    checks the file and asks for your password.
  - Linux: copy `Roms/APPS/dsboot/boot-stock.img` off the card, check it against
    `boot-stock.img.sha256` beside it, then write it to the card's third partition, for example
    `sudo dd if=boot-stock.img of=/dev/sdX3 bs=1M conv=fsync` where `sdX` is the card. Be sure
    of the device name: this overwrites what is there.

What happened at each step is written to `install.log` and `boot.log` in `Roms/APPS/dsboot`.

## What it changes

Starting is held back by the SD card, which the DS+ reads at about 20 MB/s however fast the
card is, while the processors mostly wait. Most of what dsboot does is about reading less, or
reading it at a better moment.

| Change | Saves |
|---|---|
| The stock start-up scripts in a different order: screen, sound and menu first; SSH, time sync, network discovery and the rest after the menu is on its way | 2.8 s together with the next two |
| The vendor launch script's fixed 1.5 s wait shortened to 0.2 s | |
| No disk check of all five system partitions at every start (the stock `/.skip_fsck` switch) | |
| `/etc/fstab` names the system partitions by device, not by label, which took over half a second to look up | 0.6 s |
| Compressed copies of the 112 files a start reads the most of, the 54 MB graphics driver above all, mounted over the originals: 166 MB becomes about 70 MB to read | 0.8 s, and makes the next two pay |
| Read-ahead: what a start reads is learned once, then read in the background at each start, behind everything else | 0.6 s |
| An app on the card can start as soon as the screen is up, a second or more before the vendor launch script gets to it; Wi-Fi and Bluetooth then wait until it is on screen | 1.5 s with the two above |
| The kernel stored gzip-compressed (dsboot_boot_fast) | 1.9 s |

The files changed are `/etc/init.d/rcS`, `/etc/fstab` and `/mnt/vendor/ctrl/loadapp.sh`, kept
as they were in `/etc/dsboot/stock`, plus `/.skip_fsck`. Everything else dsboot adds is in
`/etc/dsboot`. The compressed copies are made on the device from its own files, and only used
while each original keeps the size and date it had then.

Only the start is changed; the menu, emulators and sleep work as before. Wi-Fi and Bluetooth
start at a different moment and have not yet been checked after a dsboot start.

## For app makers: starting early

An app on the card the DS+ starts from can ask to be started as soon as the screen is up, rather
than by the vendor launch script about a second later. Put an executable `update/early.sh` on
that card, beside the `update/update.sh` the stock system already runs at start. Without dsboot
nothing runs `early.sh`, so `update.sh` should start the app as before and, when `early.sh` has
already done so, wait for it instead. DSlot does both; see its `boot.sh` and `early.sh`.

When dsboot runs `early.sh`, `DSBOOT_SHOWN` names a file to create once the app's first picture
is on screen. dsboot holds Wi-Fi and Bluetooth back until then (five seconds at most), so that
starting them does not slow the app down.

## Measuring

**bootprof** in Apps records where a start's time went, into `Roms/APPS/bootprof/boot1`,
`boot2`, … on the card. Run it as soon as the menu is up. `report.txt` has the time before the
kernel, every running program in the order it started, and the timings dsboot noted.

## Building

The zip holds only dsboot's own scripts and programs; everything that comes from the firmware
is made on the device. To build it: Rust with
[cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild) and zig, then `tools/package.sh`,
which writes `dist/dsboot-<version>-rgdsplus.zip`.

- `card/Roms/APPS` is what goes on the card; `dsboot/rcS` is the new start-up script.
- `readahead/` is the program that records and reads ahead, and mounts the compressed copies.
- `dsboot/mksqsh.py` writes the compressed copies; `dsboot/bootimg.py` rebuilds the boot
  partition. Both run on the device's own Python.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
