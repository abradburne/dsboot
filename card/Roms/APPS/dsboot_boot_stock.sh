#!/bin/bash
# dsboot_boot_stock: run from Apps. Writes the boot partition as it was before
# to the SD card's boot partition and restarts. See dsboot/bootwrite.sh; what happened is in
# Roms/APPS/dsboot/boot.log.

exec bash "$(cd "$(dirname "$0")" && pwd)/dsboot/bootwrite.sh" stock
