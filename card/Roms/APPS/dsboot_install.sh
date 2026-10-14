#!/bin/bash
# dsboot_install: run from Apps on the stock RG DS+ menu. Switches the device to the fast
# start-up order and restarts it. Everything it replaces is kept in /etc/dsboot/stock;
# dsboot_remove puts it back. What happened is written to Roms/APPS/dsboot/install.log.

src="$(cd "$(dirname "$0")" && pwd)/dsboot"
state=/etc/dsboot
loadapp=/mnt/vendor/ctrl/loadapp.sh

install() {
	date
	echo "firmware: $(tr '\n' ' ' < /mnt/vendor/oem/version.ini 2>&1)"

	[ -f "$src/rcS" ] || { echo "missing $src/rcS"; return 1; }
	bash -n "$src/rcS" || { echo "$src/rcS does not parse"; return 1; }
	# The fast order names these scripts; on a firmware without them it is not safe to guess.
	for s in S00mountall.sh S10udev S30dbus S36wifibt-init.sh S40bluetoothd S45network-manager \
		S49weston S50pulseaudio S60launch; do
		[ -f "/etc/init.d/$s" ] || { echo "no /etc/init.d/$s: not the firmware this was made for"; return 1; }
	done

	mkdir -p "$state/stock" || return 1
	if [ ! -f "$state/stock/rcS" ]; then
		cp -p /etc/init.d/rcS "$state/stock/rcS" || return 1
	fi
	if [ ! -f "$state/stock/loadapp.sh" ]; then
		cp -p "$loadapp" "$state/stock/loadapp.sh" || return 1
	fi
	chmod 755 "$state/stock/rcS"

	cp "$src/rcS" /etc/init.d/rcS.dsboot && chmod 755 /etc/init.d/rcS.dsboot &&
		mv /etc/init.d/rcS.dsboot /etc/init.d/rcS || return 1

	# The vendor script waits 1.5 s for PulseAudio. In the fast order PulseAudio is already
	# up before that script starts.
	if [ "$(grep -c '^sleep 1\.5$' "$loadapp")" = 1 ]; then
		sed -i 's/^sleep 1\.5$/sleep 0.2/' "$loadapp" && echo "loadapp.sh: wait shortened"
	else
		echo "loadapp.sh: wait not found or already shortened; left alone"
	fi

	# The stock switch for skipping the disk check at every start.
	: > /.skip_fsck

	# An earlier version set a Weston option here that turned out to change nothing.
	rm -f /etc/profile.d/dsboot.sh

	rm -f "$state/booting"
	: > "$state/enabled"
	echo "installed"
}

if install > "$src/install.log" 2>&1; then
	sync
	reboot
else
	sync
fi
