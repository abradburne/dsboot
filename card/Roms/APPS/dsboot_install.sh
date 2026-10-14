#!/bin/bash
# dsboot_install: run from Apps on the stock RG DS+ menu. Switches the device to the fast
# start-up order and restarts it. Everything it replaces is kept in /etc/dsboot/stock;
# dsboot_remove puts it back. What happened is written to Roms/APPS/dsboot/install.log.

src="$(cd "$(dirname "$0")" && pwd)/dsboot"
state=/etc/dsboot
loadapp=/mnt/vendor/ctrl/loadapp.sh

# The stock fstab names the four system partitions by label, and init spends about a second
# looking the labels up before anything else starts. This writes the same fstab with each
# label replaced by the device it is mounted from now. Nothing is changed unless every one
# of them checks out.
fast_fstab() {
	[ -f "$state/stock/fstab" ] || return 1
	: > /etc/fstab.dsboot
	while IFS= read -r line; do
		case "$line" in
			PARTLABEL=*)
				set -- $line
				label=${1#PARTLABEL=}
				dev=$(awk -v at="$2" '$2 == at { print $1 }' /proc/mounts | tail -n 1)
				case "$dev" in
					/dev/mmcblk[0-9]p[0-9]*) ;;
					*) echo "fstab: $2 is mounted from '$dev'"; return 1 ;;
				esac
				grep -q "^PARTNAME=$label\$" "/sys/class/block/${dev#/dev/}/uevent" || { echo "fstab: $dev is not $label"; return 1; }
				shift
				echo "$dev	$*" >> /etc/fstab.dsboot
				;;
			*)
				echo "$line" >> /etc/fstab.dsboot
				;;
		esac
	done < "$state/stock/fstab"
	[ "$(grep -c '^/dev/mmcblk' /etc/fstab.dsboot)" = 4 ] || { echo "fstab: expected four partitions"; return 1; }
	mv /etc/fstab.dsboot /etc/fstab
}

# Compressed copies of the files a start reads the most of (see rcS), made here from the
# device's own files, listed in hot-files.txt. Each is noted with the size and date of the
# original, and is only used while the original keeps them.
hot() {
	[ -f "$src/hot-files.txt" ] || return 0
	if [ -f "$state/hot.sqsh" ] && cmp -s "$src/hot-files.txt" "$state/hot-files.txt"; then
		echo "hot: already made"
		return 0
	fi
	# An older set is in use: let go of it so that the originals show again.
	if [ -f "$state/hot.list" ]; then
		while read -r _ _ path; do
			umount -l "$path" 2> /dev/null
		done < "$state/hot.list"
		umount -l /run/dsboot-hot 2> /dev/null
	fi
	rm -f "$state/hot.sqsh" "$state/hot.list" "$state/hot-files.txt"
	echo "hot: making the compressed copies; this takes a minute"
	python3 "$src/mksqsh.py" "$state/hot.new" "$src/hot-files.txt" --status "$status" || return 1
	rm -f "$status"
	# Check the kernel takes it, and note each original's size and date.
	mkdir -p /tmp/dsboot-hot
	mount -t squashfs -o loop,ro "$state/hot.new" /tmp/dsboot-hot || { echo "hot: the kernel will not mount it"; return 1; }
	: > "$state/hot.list.new"
	for f in $(cd /tmp/dsboot-hot && find . -type f); do
		f=${f#.}
		if cmp -s "/tmp/dsboot-hot$f" "$f"; then
			echo "$(stat -c '%s %Y' "$f") $f" >> "$state/hot.list.new"
		else
			echo "hot: $f changed while it was being copied; left out"
		fi
	done
	umount /tmp/dsboot-hot
	mv "$state/hot.new" "$state/hot.sqsh" && mv "$state/hot.list.new" "$state/hot.list" &&
		cp "$src/hot-files.txt" "$state/hot-files.txt" || return 1
	echo "hot: $(grep -c . "$state/hot.list") files will come from compressed copies"
	# What a start reads from the card is different now: learn it again.
	rm -f "$state/readahead.1" "$state/readahead.2" "$state/readahead.3"
}

# The picture the stock menu shows while it powers off, in both its styles: dsboot's, or
# goodbye.png beside rcS on the card if there is one, or the stock one with stock-pictures there.
shutdown_picture() {
	for style in res1 res2; do
		picture=/mnt/vendor/resource/$style/shutdown/goodbye.png
		kept="$state/stock/goodbye-$style.png"
		[ -f "$picture" ] || continue
		[ -f "$kept" ] || cp -p "$picture" "$kept" || return 1
		if [ -f "$src/stock-pictures" ]; then
			new=$kept
		elif [ -f "$src/goodbye.png" ]; then
			new="$src/goodbye.png"
		else
			new="$src/default/goodbye.png"
		fi
		[ -f "$new" ] || continue
		cmp -s "$new" "$picture" || cat "$new" > "$picture" || return 1
	done
	echo "shutdown picture: ${new##*/}"
}

install() {
	date '+%F %T'
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
	if [ ! -f "$state/stock/fstab" ] && grep -q '^PARTLABEL=' /etc/fstab; then
		cp -p /etc/fstab "$state/stock/fstab" || return 1
	fi

	cp "$src/rcS" /etc/init.d/rcS.dsboot && chmod 755 /etc/init.d/rcS.dsboot &&
		mv /etc/init.d/rcS.dsboot /etc/init.d/rcS || return 1

	# The vendor script waits 1.5 s for PulseAudio. In the fast order PulseAudio is already
	# up before that script starts.
	if [ "$(grep -c '^sleep 1\.5$' "$loadapp")" = 1 ]; then
		sed -i 's/^sleep 1\.5$/sleep 0.2/' "$loadapp" && echo "loadapp.sh: wait shortened"
	else
		echo "loadapp.sh: wait not found or already shortened; left alone"
	fi

	# See radios-wait and rcS: the launch script waits for the radios when they start late.
	cp "$src/radios-wait" "$state/radios-wait" && chmod 755 "$state/radios-wait" || return 1
	if grep -q radios-wait "$loadapp"; then
		echo "loadapp.sh: already waits for the radios"
	elif [ "$(grep -c '^nmcli networking off$' "$loadapp")" = 1 ]; then
		awk '$0 == "nmcli networking off" { print "[ -x /etc/dsboot/radios-wait ] && /etc/dsboot/radios-wait" } { print }' \
			"$state/stock/loadapp.sh" > "$state/loadapp.new" && sed -i 's/^sleep 1\.5$/sleep 0.2/' "$state/loadapp.new" &&
			cat "$state/loadapp.new" > "$loadapp"
		rm -f "$state/loadapp.new"
		if [ "$(grep -c '^nmcli networking off$' "$loadapp")" = 1 ] && grep -q '^\[ -x /etc/dsboot/radios-wait \] && /etc/dsboot/radios-wait$' "$loadapp" && bash -n "$loadapp"; then
			echo "loadapp.sh: waits for the radios"
		else
			echo "loadapp.sh: could not add the wait; putting the stock script back"
			cp -p "$state/stock/loadapp.sh" "$loadapp"
			rm -f "$state/radios-wait"
		fi
	else
		echo "loadapp.sh: no place for the radios wait; left alone"
		rm -f "$state/radios-wait"
	fi
	# An app that asks to start early is on the card now: let the next start know.
	if [ -f /mnt/mmc/update/early.sh ]; then
		: > "$state/early"
	fi

	shutdown_picture || echo "shutdown picture: left alone"

	# The stock switch for skipping the disk check at every start.
	: > /.skip_fsck

	# An earlier version set a Weston option here that turned out to change nothing.
	rm -f /etc/profile.d/dsboot.sh

	if fast_fstab; then
		echo "fstab: partitions named by device"
	else
		rm -f /etc/fstab.dsboot
		echo "fstab: left alone"
	fi

	hot || rm -f "$state/hot.sqsh" "$state/hot.list" "$state/hot.new" "$state/hot.list.new"

	# Reading ahead. The next start reads nothing ahead and instead notes what it reads from
	# the card; the starts after that use those notes. See rcS.
	rm -f "$state/readahead.list"
	if [ -f "$src/readahead" ]; then
		cp "$src/readahead" "$state/readahead.new" && chmod 755 "$state/readahead.new" &&
			mv "$state/readahead.new" "$state/readahead" || return 1
		# Lists from an earlier learning start are kept. Delete /etc/dsboot/readahead.1 to learn again.
		if [ -f "$state/readahead.1" ]; then
			echo "readahead: lists kept"
		else
			: > "$state/learn"
			echo "readahead: the next start learns what to read"
		fi
	fi

	# Tracing of the vendor launch script: on while a file called trace sits beside rcS on the card.
	cp "$src/trace.sh" "$state/trace.sh"
	if [ -f "$src/trace" ]; then
		: > "$state/trace"
	else
		rm -f "$state/trace"
	fi

	rm -f "$state/booting"
	: > "$state/enabled"
	echo "installed"
}

# What is going on, on screen, while this runs: the stock menu has made way for it.
status=/tmp/dsboot.status
: > "$src/install.log"
python3 "$src/progress.py" "Installing dsboot" "$src/install.log" "$status" 2> /dev/null &
shown=$!

if install >> "$src/install.log" 2>&1; then
	echo "restarting" >> "$src/install.log"
	sync
	sleep 2
	kill $shown 2> /dev/null
	reboot
else
	echo "nothing was changed; see install.log" >> "$src/install.log"
	sync
	sleep 5
	kill $shown 2> /dev/null
fi
