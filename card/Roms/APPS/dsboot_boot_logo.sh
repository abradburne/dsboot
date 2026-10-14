#!/bin/bash
# dsboot_boot_logo: run from Apps. Writes the stock kernel with the new boot pictures
# to the SD card's boot partition and restarts. See dsboot/bootwrite.sh; what happened is in
# Roms/APPS/dsboot/boot.log.

exec bash "$(cd "$(dirname "$0")" && pwd)/dsboot/bootwrite.sh" boot-logo.img
