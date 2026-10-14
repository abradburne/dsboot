#!/bin/bash
# dsboot_remove: run from Apps on the stock RG DS+ menu. Puts back everything dsboot_install
# replaced and restarts the device. What happened is written to Roms/APPS/dsboot/remove.log.

src="$(cd "$(dirname "$0")" && pwd)/dsboot"
state=/etc/dsboot
loadapp=/mnt/vendor/ctrl/loadapp.sh

remove() {
	date '+%F %T'
	[ -f "$state/stock/rcS" ] || { echo "nothing to remove: no $state/stock/rcS"; return 1; }
	cp -p "$state/stock/rcS" /etc/init.d/rcS.stock && mv /etc/init.d/rcS.stock /etc/init.d/rcS || return 1
	if [ -f "$state/stock/loadapp.sh" ]; then
		cp -p "$state/stock/loadapp.sh" "$loadapp.stock" && mv "$loadapp.stock" "$loadapp" || return 1
	fi
	if [ -f "$state/stock/fstab" ]; then
		cp -p "$state/stock/fstab" /etc/fstab.stock && mv /etc/fstab.stock /etc/fstab || return 1
	fi
	for style in res1 res2; do
		if [ -f "$state/stock/goodbye-$style.png" ]; then
			cat "$state/stock/goodbye-$style.png" > "/mnt/vendor/resource/$style/shutdown/goodbye.png" &&
				rm -f "$state/stock/goodbye-$style.png"
		fi
	done
	rm -f /.skip_fsck /etc/profile.d/dsboot.sh
	rm -f "$state/enabled" "$state/booting" "$state/last" "$state/trace" "$state/trace.sh" "$state/early" "$state/radios-wait" "$state/readahead" "$state/learn" "$state"/readahead.* "$state"/hot.* "$state/hot-files.txt"
	rm -f "$state/stock/rcS" "$state/stock/loadapp.sh" "$state/stock/fstab"
	rmdir "$state/stock" "$state"
	echo "removed"
}

mkdir -p "$src"
if remove > "$src/remove.log" 2>&1; then
	sync
	reboot
else
	sync
fi
