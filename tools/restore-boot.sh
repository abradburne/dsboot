#!/bin/bash
# Puts the stock boot partition back on a card that no longer starts. Run it on the Mac with
# the card in the reader; it asks for your password to write to the card.
set -euo pipefail
cd "$(dirname "$0")/.."

stock=work/boot-stock.img
[ -f "$stock" ] || { echo "no $stock; make it with tools/bootimg.py extract"; exit 1; }
python3 tools/bootimg.py check "$stock" > /dev/null

node=$(diskutil info /Volumes/ROMS 2> /dev/null | awk '/Device Node/ { print $3 }')
[ -n "$node" ] || { echo "the card's ROMS volume is not mounted"; exit 1; }
# ROMS is partition 11 of the card; the boot partition is number 3, 64 MiB.
[ "${node##*s}" = 11 ] || { echo "$node is not partition 11: not the OS card?"; exit 1; }
disk=${node%s11}
diskutil info "${disk}s3" | grep -q '(67108864 Bytes)' || { echo "${disk}s3 is not 64 MiB: not the OS card?"; exit 1; }

echo "Writing $stock to ${disk}s3."
diskutil unmountDisk "$disk"
sudo dd if="$stock" of="/dev/r${disk#/dev/}s3" bs=1m
sync
diskutil eject "$disk"
echo "Done. The card can go back in the device."
