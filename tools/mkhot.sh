#!/bin/bash
# Builds hot.sqsh: gzip-compressed copies of the files a start reads the most of,
# taken from the stock firmware image. On the device they are mounted over the originals, so
# that less has to come off the card; the processors, which mostly wait for the card while
# starting, do the unpacking. Needs mksquashfs and e2fsprogs' debugfs.
#
#   tools/mkhot.sh RG-DS-PLUS-EN16GB-V1.0-20260915.IMG
set -euo pipefail
image=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")/.."

debugfs=$(command -v debugfs || echo /opt/homebrew/opt/e2fsprogs/sbin/debugfs)
# Where the root filesystem starts in the image, in 512-byte sectors.
rootfs=491520

# The files, one per line, from tools/hot-files.txt.
files=()
while read -r f; do
	files+=("$f")
done < <(grep -v '^#' tools/hot-files.txt)

mkdir -p work
stage=$(mktemp -d work/hot.XXXXXX)
for f in "${files[@]}"; do
	mkdir -p "$stage$(dirname "$f")"
	"$debugfs" -R "dump -p $f $stage$f" "$image?offset=$((rootfs * 512))" 2> /dev/null
	[ -s "$stage$f" ] || { echo "not in the image: $f"; exit 1; }
done
out=card/Roms/APPS/dsboot/hot.sqsh
# The stock kernel reads gzip, lzo and xz squashfs, without extended attributes.
mksquashfs "$stage" "$out" -comp gzip -Xcompression-level 9 -b 131072 -no-xattrs -all-root -noappend -no-exports -quiet -no-progress
du -sh "$stage" "$out"
