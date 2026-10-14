#!/bin/bash
# Builds the boot images that go on the card, from the stock boot partition and the pictures
# in art/. The stock partition comes from the stock firmware image:
#   tools/bootimg.py extract RG-DS-PLUS-EN16GB-V1.0-20260915.IMG work/boot-stock.img
set -euo pipefail
cd "$(dirname "$0")/.."

out=card/Roms/APPS/dsboot
pictures=(--logo art/logo.png --kernel-logo art/logo_kernel.png)
{
	python3 tools/bootimg.py check work/boot-stock.img | sed -n 's/^\([0-9]* [0-9a-f]*\)$/boot-stock.img \1/p'
	python3 tools/bootimg.py build work/boot-stock.img "$out/boot-logo.img" "${pictures[@]}" | sed -n 's/^\([0-9]* [0-9a-f]*\)$/boot-logo.img \1/p'
	python3 tools/bootimg.py build work/boot-stock.img "$out/boot-fast.img" "${pictures[@]}" --gzip-kernel | sed -n 's/^\([0-9]* [0-9a-f]*\)$/boot-fast.img \1/p'
} > "$out/boot-images.txt"
cat "$out/boot-images.txt"
