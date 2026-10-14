#!/bin/bash
# dsboot_boot_fast: run from Apps. Writes the device's own kernel, gzipped, and the boot pictures in dsboot/ if there are any
# to the SD card's boot partition and restarts. See dsboot/bootwrite.sh; what happened is in
# Roms/APPS/dsboot/boot.log.

exec bash "$(cd "$(dirname "$0")" && pwd)/dsboot/bootwrite.sh" fast
