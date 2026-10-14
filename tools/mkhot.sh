#!/bin/bash
# Builds hot.sqsh: gzip-compressed copies of the large libraries a start reads the most of,
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

# What Weston, PulseAudio and NetworkManager keep most of in memory after a start. Nothing
# that init or the shell has already loaded by the time rcS runs: that would be read twice.
files=(
	/usr/lib/libmali.so.1.9.0
	/usr/sbin/NetworkManager
	/usr/lib/libcrypto.so.3
	/usr/lib/libgio-2.0.so.0.7600.1
	/usr/lib/libstdc++.so.6.0.32
	/usr/lib/libglib-2.0.so.0.7600.1
	/usr/lib/libasound.so.2.0.0
	/usr/lib/pulseaudio/libpulsecore-17.0.so
	/usr/lib/libweston-14.so.0.0.2
	/usr/lib/pulseaudio/libpulsecommon-17.0.so
	/usr/lib/libgobject-2.0.so.0.7600.1
	/usr/lib/libcurl.so.4.8.0
	/usr/lib/libssl.so.3
	/usr/lib/libpixman-1.so.0.44.2
	/usr/lib/pulseaudio/modules/libalsa-util.so
	/usr/lib/libinput.so.10.13.0
	/usr/lib/libx265.so.199
	/usr/lib/libxkbcommon.so.0.0.0
	/usr/lib/libgnutls.so.30.37.1
)

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
