#!/bin/bash
# Builds the read-ahead program for the device and zips what goes on the card.
# Needs Rust with cargo-zigbuild and zig, as dslot does.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(cat VERSION)
(cd readahead && cargo zigbuild --release --target aarch64-unknown-linux-gnu.2.31)

stage=dist/stage
rm -rf dist
mkdir -p "$stage"
cp -R card/Roms "$stage/"
cp readahead/target/aarch64-unknown-linux-gnu/release/dsboot-readahead "$stage/Roms/APPS/dsboot/readahead"
# Nothing made on or for a particular device goes in.
find "$stage" \( -name .DS_Store -o -name '*.img' -o -name '*.png' -o -name '*.log' -o -name trace \) -delete
cp README.md LICENSE "$stage/Roms/APPS/dsboot/"
(cd "$stage" && zip -qr "../dsboot-$version-rgdsplus.zip" Roms)
echo "dist/dsboot-$version-rgdsplus.zip"
