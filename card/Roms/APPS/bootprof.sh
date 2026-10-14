#!/bin/bash
# bootprof: run from Apps on the stock RG DS+ menu, soon after power-on. Writes where the boot
# time went to Roms/APPS/bootprof/ on this card. Nothing on the system partitions is changed.

out="$(cd "$(dirname "$0")" && pwd)/bootprof"
n=1
while [ -e "$out/boot$n" ]; do n=$((n + 1)); done
out="$out/boot$n"
mkdir -p "$out" || exit 1

# Kernel log stamps count from power-on (the kernel is built to take them from the ARM timer);
# /proc/uptime counts from when Linux started its clock. A mark written to the log now and read
# back beside the uptime gives the difference: the time spent before the kernel ran.
echo "bootprof mark $$" > /dev/kmsg
up=$(cut -d' ' -f1 /proc/uptime)
now=$(date '+%s')
dmesg > "$out/dmesg.txt" 2>&1

stamp() { grep -m 1 -E "$1" "$out/dmesg.txt" | sed 's/^[^[]*\[ *\([0-9.]*\)\].*/\1/'; }
mark=$(stamp "bootprof mark $$")
first=$(stamp '^[^[]*\[ *[0-9.]+\]')
init=$(stamp 'Run /.*init as init process|Freeing unused kernel')

# Every process still running, in the order it started, in seconds since Linux started its
# clock. The scripts that ran and finished are not here; they show as the gaps.
processes() {
	for d in /proc/[0-9]*; do
		s=$(cat "$d/stat" 2> /dev/null) || continue
		set -- ${s##*) }
		cmd=$(tr '\0' ' ' < "$d/cmdline" 2> /dev/null)
		[ -n "$cmd" ] || continue
		printf '%5d.%02d %6s %6s  %s\n' $((${20} / 100)) $((${20} % 100)) "${d#/proc/}" "$2" "$cmd"
	done | sort -n
}

{
	echo "bootprof $(date '+%F %T')"
	echo "firmware:    $(tr '\n' ' ' < /mnt/vendor/oem/version.ini 2>&1)"
	echo "boot_device: $(cat /sys/class/anbernic_misc/boot_device 2>&1)"
	echo "cmdline:     $(cat /proc/cmdline)"
	echo "dsboot:      $(cat /etc/dsboot/last 2> /dev/null || echo "not installed, or no fast boot yet")"
	echo
	echo "uptime now:                $up s (epoch $now)"
	echo "kernel log stamp now:      ${mark:-?} s"
	echo "first kernel log stamp:    ${first:-?} s"
	echo "kernel hands over to init: ${init:-?} s (kernel log stamp)"
	if [ -n "$mark" ]; then
		echo "before the kernel's clock: $(awk "BEGIN { printf \"%.2f\", $mark - $up }") s"
	fi
	echo
	printf '%8s %6s %6s  %s\n' start pid ppid command
	processes
} > "$out/report.txt" 2>&1

for f in /var/log/messages /var/log/mount-all.log /var/log/weston.log /tmp/dsboot.log /tmp/loadapp.trace; do
	[ -f "$f" ] && cp "$f" "$out/"
done
# How much of each file a running program has actually pulled in from the card.
touched() {
	awk '/^[0-9a-f]+-[0-9a-f]+ / { f = $6 } /^Rss:/ && f ~ /^\// { kb[f] += $2 }
		END { for (f in kb) printf "%7d kB %s\n", kb[f], f }' "/proc/$1/smaps" 2> /dev/null | sort -rn | head -n 25
}

{
	for name in weston pulseaudio NetworkManager; do
		for pid in $(pgrep -x "$name"); do
			echo "== files in memory for $name ($pid)"; touched "$pid"
		done
	done
	echo "== mounts"; cat /proc/mounts
	echo "== modules"; lsmod
	echo "== memory"; free
	echo "== /tmp"; ls -la --full-time /tmp 2>&1 || ls -la /tmp
	echo "== /var/run"; ls -la --full-time /var/run/ 2>&1 || ls -la /var/run/
	echo "== init.d"; ls -la /etc/init.d
	echo "== dsboot"; ls -la /etc/dsboot; wc -l /etc/dsboot/readahead.[123]
} > "$out/state.txt" 2>&1
sync
