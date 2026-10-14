#!/bin/bash
# bootwrite.sh IMAGE: writes one of the boot images in this folder to the boot partition of
# the SD card the OS runs from, and restarts. Used by the dsboot_boot_* entries in Apps.
#
# The boot partition holds the kernel and the boot pictures. A card whose boot partition
# U-Boot will not accept does not start, and is put right from a computer with
# tools/restore-boot.sh. So: SD card only, never the internal storage.

here="$(cd "$(dirname "$0")" && pwd)"
name=$1
# One line per known image: file name, size in bytes, SHA-256 of that many bytes.
known="$here/boot-images.txt"
disk=mmcblk1

sum() {
	head -c "$2" "$1" | sha256sum | cut -d' ' -f1
}

# Which known image the partition holds now.
holds() {
	while read -r n size hash; do
		if [ "$(sum "$dev" "$size")" = "$hash" ]; then
			echo "$n"
			return
		fi
	done < "$known"
}

put() {
	dd if="$1" of="$dev" bs=1M conv=fsync 2>&1 && sync && echo 3 > /proc/sys/vm/drop_caches
}

write() {
	date
	[ "$(cat /sys/class/anbernic_misc/boot_device)" = 1 ] || { echo "the OS is not running from the SD card: refused"; return 1; }
	# Both the card and the internal storage have a partition called boot. Take the one on
	# the disk that / is on, and make sure of it.
	[ "$(mountpoint -d /)" = "$(cat /sys/class/block/${disk}p6/dev)" ] || { echo "/ is not on ${disk}p6: refused"; return 1; }
	grep -q '^PARTNAME=boot$' "/sys/class/block/${disk}p3/uevent" || { echo "${disk}p3 is not called boot: refused"; return 1; }
	dev=/dev/${disk}p3

	set -- $(grep "^$name " "$known")
	[ $# = 3 ] || { echo "$name is not listed in boot-images.txt"; return 1; }
	size=$2 hash=$3
	now=$(holds)
	echo "boot partition holds: ${now:-something unknown}"
	[ -n "$now" ] || { echo "not a boot partition this was made for: refused"; return 1; }
	[ "$now" != "$name" ] || { echo "nothing to do"; return 1; }

	# The stock image is not shipped; it is kept from the device the first time.
	if [ "$now" = boot-stock.img ] && [ ! -f "$here/boot-stock.img" ]; then
		set -- $(grep "^boot-stock.img " "$known")
		head -c "$2" "$dev" > "$here/boot-stock.img" && sync
		echo "stock boot partition kept as boot-stock.img"
	fi
	set -- $(grep "^boot-stock.img " "$known")
	[ "$(sum "$here/boot-stock.img" "$2")" = "$3" ] || { echo "no good copy of the stock boot partition to go back to: refused"; return 1; }
	[ "$(sum "$here/$name" "$size")" = "$hash" ] || { echo "$name on the card is damaged: refused"; return 1; }

	if put "$here/$name" && [ "$(sum "$dev" "$size")" = "$hash" ]; then
		echo "wrote $name and read it back"
		return 0
	fi
	echo "writing $name failed; putting the stock image back"
	if put "$here/boot-stock.img" && [ "$(holds)" = boot-stock.img ]; then
		echo "stock image is back"
	else
		echo "COULD NOT PUT THE STOCK IMAGE BACK. Do not turn the device off; if it is already off, use tools/restore-boot.sh on a computer."
	fi
	return 1
}

if write >> "$here/boot.log" 2>&1; then
	sync
	reboot
else
	sync
fi
