# dsboot: read by every bash script started under S60launch while /etc/dsboot/trace exists
# (it is their BASH_ENV). Makes the vendor launch script and autostart write each command
# they run, with the kernel's clock, to /tmp/loadapp.trace. Everything else is left alone.
case "$0" in
	*/loadapp.sh | */autostart)
		exec 9>> /tmp/loadapp.trace
		BASH_XTRACEFD=9
		PS4='+ $(< /proc/uptime) ${0##*/}: '
		set -x
		;;
	*)
		unset BASH_ENV
		;;
esac
