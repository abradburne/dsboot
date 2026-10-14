#!/bin/bash
# bootwrite.sh fast|stock: rewrites the boot partition of the SD card the OS runs from, and
# restarts. Used by dsboot_boot_fast and dsboot_boot_stock in Apps.
#
#   fast   the device's own kernel, gzipped, so that it loads in half the time; and, if
#          logo.png or logo_kernel.png are in this folder, those as the two boot pictures
#   stock  the boot partition as it was
#
# The first time, the partition as it is is kept in this folder as boot-stock.img, with its
# SHA-256 beside it. A card whose boot partition U-Boot will not accept does not start; it is
# put right from a computer by writing boot-stock.img back (see the README). So: SD card
# only, never the internal storage.

here="$(cd "$(dirname "$0")" && pwd)"
what=$1
disk=mmcblk1
stock="$here/boot-stock.img"
fast="$here/boot-fast.img"
now="$here/boot-now.img"

image() {
	python3 "$here/bootimg.py" "$@"
}

hash() {
	sha256sum "$1" | cut -d' ' -f1
}

# Whether the partition starts with exactly this file.
holds() {
	[ "$(head -c $(($(wc -c < "$1"))) "$dev" | sha256sum | cut -d' ' -f1)" = "$(hash "$1")" ]
}

put() {
	dd if="$1" of="$dev" bs=1M conv=fsync 2>&1 && sync && echo 3 > /proc/sys/vm/drop_caches
}

write() {
	date '+%F %T'
	case "$what" in fast | stock) ;; *) echo "usage: bootwrite.sh fast|stock"; return 1 ;; esac
	[ "$(cat /sys/class/anbernic_misc/boot_device)" = 1 ] || { echo "the OS is not running from the SD card: refused"; return 1; }
	# Both the card and the internal storage have a partition called boot. Take the one on
	# the disk that / is on, and make sure of it.
	[ "$(mountpoint -d /)" = "$(cat /sys/class/block/${disk}p6/dev)" ] || { echo "/ is not on ${disk}p6: refused"; return 1; }
	grep -q '^PARTNAME=boot$' "/sys/class/block/${disk}p3/uevent" || { echo "${disk}p3 is not called boot: refused"; return 1; }
	dev=/dev/${disk}p3
	firmware=$(head -n 1 /mnt/vendor/oem/version.ini 2> /dev/null)
	if [ "$firmware" != 20260915 ] && [ ! -f "$here/any-firmware" ]; then
		echo "made for firmware 20260915, this is '$firmware': refused (an empty file called any-firmware here allows it)"
		return 1
	fi

	image extract "$dev" "$now" > /dev/null || { echo "the boot partition does not hold a boot image this understands: refused"; rm -f "$now"; return 1; }
	if image check "$now" | grep -q '(none)'; then
		# An uncompressed kernel: the partition is as the firmware made it. Keep it, unless a
		# copy of it is already kept.
		if ! cmp -s "$now" "$stock"; then
			[ ! -f "$stock" ] || mv "$stock" "$here/boot-stock.old.img"
			mv "$now" "$stock" && hash "$stock" > "$stock.sha256" && sync
			echo "the boot partition as it is now is kept as boot-stock.img"
		fi
	fi
	rm -f "$now"
	[ -f "$stock" ] && [ "$(hash "$stock")" = "$(cat "$stock.sha256" 2> /dev/null)" ] && image check "$stock" > /dev/null ||
		{ echo "no good copy of the stock boot partition to go back to: refused"; return 1; }

	if [ "$what" = fast ]; then
		pictures=()
		[ ! -f "$here/logo.png" ] || pictures+=(--logo "$here/logo.png")
		[ ! -f "$here/logo_kernel.png" ] || pictures+=(--kernel-logo "$here/logo_kernel.png")
		image build "$stock" "$fast" --gzip-kernel --status "$status" "${pictures[@]}" || { echo "could not make the image"; return 1; }
		rm -f "$status"
		new=$fast
	else
		new=$stock
	fi

	if holds "$new"; then
		echo "the boot partition already holds this image; nothing to do"
		return 1
	fi
	if put "$new" && holds "$new"; then
		echo "wrote ${new##*/} and read it back"
		return 0
	fi
	echo "writing ${new##*/} failed; putting the stock image back"
	if put "$stock" && holds "$stock"; then
		echo "stock image is back"
	else
		echo "COULD NOT PUT THE STOCK IMAGE BACK. Do not turn the device off; if it is already off, see the README."
	fi
	return 1
}

# What is going on, on screen, while this runs: the stock menu has made way for it.
status=/tmp/dsboot.status
log=/tmp/dsboot-boot.log
: > "$log"
python3 "$here/progress.py" "Boot partition" "$log" "$status" 2> /dev/null &
shown=$!

if write > "$log" 2>&1; then
	echo "restarting" >> "$log"
	cat "$log" >> "$here/boot.log"
	sync
	sleep 2
	kill $shown 2> /dev/null
	reboot
else
	cat "$log" >> "$here/boot.log"
	sync
	sleep 5
	kill $shown 2> /dev/null
fi
