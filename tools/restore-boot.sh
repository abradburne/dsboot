#!/bin/bash
# Writes the stock boot partition back to a DS+ SD card that no longer starts, on a Mac, from
# the copy dsboot kept on the card itself (Roms/APPS/dsboot/boot-stock.img). Put the card in
# the computer and run this; it asks for your password to write to the card.
set -euo pipefail

volume=${1:-/Volumes/ROMS}
kept="$volume/Roms/APPS/dsboot/boot-stock.img"
[ -f "$kept" ] || { echo "no $kept: is the card in, and is its ROMS volume mounted?"; exit 1; }
[ "$(shasum -a 256 "$kept" | cut -d' ' -f1)" = "$(cat "$kept.sha256")" ] || { echo "$kept does not match its checksum"; exit 1; }

node=$(diskutil info "$volume" | awk '/Device Node/ { print $3 }')
# ROMS is partition 11 of the card; the boot partition is number 3, 64 MiB.
[ "${node##*s}" = 11 ] || { echo "$node is not partition 11: not a DS+ OS card?"; exit 1; }
disk=${node%s11}
diskutil info "${disk}s3" | grep -q '(67108864 Bytes)' || { echo "${disk}s3 is not 64 MiB: not a DS+ OS card?"; exit 1; }

copy=$(mktemp -t boot-stock)
cp "$kept" "$copy"
echo "Writing the kept boot partition to ${disk}s3."
diskutil unmountDisk "$disk"
sudo dd if="$copy" of="/dev/r${disk#/dev/}s3" bs=1m
sync
diskutil eject "$disk"
echo "Done. The card can go back in the device."
