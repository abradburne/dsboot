# Changes

## 0.1.0

First release. On one RG DS+ starting DSlot at power-on, the first picture comes 11.5 s after
power-on instead of 21.1 s.

- Stock start-up scripts run in a better order; the vendor launch script's fixed wait is
  shortened; no disk check at every start; system partitions named by device in `fstab`.
- Compressed copies of the files a start reads the most of, made on the device and mounted over
  the originals.
- Read-ahead of what a start needs, learned on the first start after installing, read at idle
  priority.
- An app on the OS card can start as soon as the screen is up (`update/early.sh`), with Wi-Fi
  and Bluetooth held back until it is on screen.
- dsboot_boot_fast: the device's own kernel, gzipped, and optional boot pictures, written to
  the boot partition, with the stock partition kept on the card to go back to.
- Falls back to the stock start-up by itself if a start does not reach the menu.
- dsboot_boot_fast writes "RG DS Plus" boot pictures unless told otherwise, and dsboot_install
  a "SEE YOU SOON" power-off picture.
- Installing and rewriting the boot partition show their progress on both screens.
- dsboot_timing: where a start's time went, written to the card.
