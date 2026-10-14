#!/bin/bash
# dsboot_boot_sdfast: run from Apps. Writes the gzipped kernel, the new boot pictures and a 150 MHz clock for the OS card
# to the SD card's boot partition and restarts. See dsboot/bootwrite.sh; what happened is in
# Roms/APPS/dsboot/boot.log.

exec bash "$(cd "$(dirname "$0")" && pwd)/dsboot/bootwrite.sh" boot-sdfast.img
