# dsboot

Making the Anbernic RG DS+ start faster, on the stock OS (firmware V1.0, 20260915).

You copy a few files to the card and run one of them from **Apps**. It changes the stock
system in place, keeps what it replaces, and can be undone. No image to flash.

Written for a device that starts its OS from the SD card, where a bad result can be fixed by
reflashing the card. Tried on one such device, which starts dslot at power-on: the vendor
launch script started at 12.4 s instead of 14.5 s, and the first picture came up at 18.3 s
instead of 21.1 s. Changes to dslot's own start-up brought that to 16.8 s, the gzipped
kernel below to 14.9 s, and the later changes listed here to 13.7 s.

## Where a stock start goes

Measured on one device, three power-ons, all within 0.05 s of each other. Seconds from power-on.

| | at | took |
|---|---|---|
| Boot loader, and loading the 39 MB kernel | 0 | 5.8 |
| Kernel | 5.8 | 1.1 |
| Mounting, with a disk check of five partitions | 7.0 | 1.9 |
| Logging, udev, IRQ balancing, D-Bus, Bluetooth, Wi-Fi, NetworkManager, time sync | 8.9 | 2.4 |
| Weston (the screen) starting, alongside mDNS, cron, PulseAudio and SSH | 11.3 | 3.2 |
| Vendor launch script, including a fixed 1.5 s wait | 14.5 | about 2.3 |
| Menu, or the card's `update/update.sh`, starts | about 16.8 | |

## Install

1. Copy everything in `card/Roms/APPS` into `Roms/APPS` on the card.
2. On the DS+, open **Apps** and choose **dsboot_install**. The device restarts by itself.

If it does not restart, nothing was changed; `Roms/APPS/dsboot/install.log` says why.

## What it changes

- `/etc/init.d/rcS` is replaced. The new one runs the same stock scripts in a different order:
  the screen, sound and the menu first, then SSH, time sync, mDNS, cron and the rest while the
  menu is already loading.
- The 1.5 s wait in `/mnt/vendor/ctrl/loadapp.sh` becomes 0.2 s.
- `/.skip_fsck` is created, the stock switch for skipping the disk check at every start.
- `/etc/fstab` names the four system partitions by device instead of by label, which init
  spends over half a second looking up.

- A small program, `/etc/dsboot/readahead`, starts reading the files the screen, sound and
  radios will ask for while the card is otherwise idle. The first start after installing
  reads nothing ahead and is a little slower: it notes what it has read from the card at
  three moments, and later starts read those lists back in that order, at idle priority so
  that nothing else waits for the card behind it. Worth about 0.6 s.

The stock `rcS`, `loadapp.sh` and `fstab` are kept in `/etc/dsboot/stock`.

None of this depends on dslot. The same changes bring the stock menu up sooner.

## If a fast start goes wrong

- A fast start that does not get as far as the menu is noticed at the next power-on, which goes
  back to the stock order and stays there until **dsboot_install** is run again.
- From a computer: put an empty file called `dsboot.off` at the top of the `ROMS` volume. The
  start after the next one is a stock start.
- **dsboot_remove** in Apps puts everything back and restarts.

## Measuring

**bootprof** in Apps records where the time went, into `Roms/APPS/bootprof/boot1`, `boot2`, …
Run it as soon as the menu is up. `report.txt` has the time before the kernel, the moment the
kernel hands over to init, whether it was a fast start, and every running process in the order
it started.

## Boot pictures and a compressed kernel

The boot partition holds the kernel (39 MB, uncompressed) and the two boot pictures: `logo.bmp`,
350×160, shown by U-Boot, and `logo_kernel.bmp`, 1024×110, shown by the kernel. `tools/bootimg.py`
rebuilds it with other pictures and, optionally, a gzipped kernel, and fixes the checksums
U-Boot verifies. The partition's RSA signature no longer matches afterwards; U-Boot on firmware
20260915 does not check it. Tried on one device: with the gzipped kernel the kernel starts
3.9 s after power-on instead of 5.8 s, and the new pictures show.

On the Mac, with ImageMagick installed:

```
tools/bootimg.py extract RG-DS-PLUS-EN16GB-V1.0-20260915.IMG work/boot-stock.img
tools/mkcard.sh
```

`mkcard.sh` takes the pictures from `art/` and writes `boot-logo.img` (new pictures) and
`boot-fast.img` (new pictures, gzipped kernel) into `card/Roms/APPS/dsboot`. Copy
`card/Roms/APPS` to the card as before. In Apps:

- **dsboot_boot_logo** writes the new pictures and restarts.
- **dsboot_boot_fast** writes the new pictures with the gzipped kernel and restarts.
- **dsboot_boot_stock** puts back the stock partition, which is kept from the device the first
  time one of the others runs.

Each refuses unless the OS is running from the SD card and the partition holds an image it
knows, and reads back what it wrote. `Roms/APPS/dsboot/boot.log` says what happened.

Starting up is held back by how fast the card can be read, and the OS card's slot is clocked
at 50 MHz, about 20 MB/s whatever the card. `bootimg.py --sd-clock` can raise that, but at
150 MHz the kernel finds no working tuning and falls back to 50, so it gains nothing here.

**If the device no longer starts** after one of these, put the card in the Mac and run
`tools/restore-boot.sh`. It writes the stock boot partition back and asks for your password.
