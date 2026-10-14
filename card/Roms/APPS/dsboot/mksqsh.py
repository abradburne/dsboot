#!/usr/bin/env python3
"""Writes a squashfs 4.0 image of some files, gzip-compressed, for the stock RG DS+ kernel.

dsboot keeps compressed copies of the files a start reads the most of and mounts them over
the originals. The device has no mksquashfs, so this writes the image itself, with only what
that needs: regular files and the directories above them, owned by root, no fragments, no
extended attributes, no export table. Metadata is stored uncompressed; it is a few kilobytes.

  mksqsh.py OUT LIST [--root DIR] [--level N]

LIST names the files, one absolute path per line; lines starting with # and files that do not
exist are passed over. Each file is read from DIR + path (default DIR: /) and stored at path,
with its permissions and modification time.
"""

import argparse
import os
import stat
import struct
import sys
import time
import zlib

BLOCK = 128 * 1024
META = 8192
UNCOMPRESSED_BLOCK = 1 << 24
UNCOMPRESSED_META = 0x8000
NONE = 0xFFFFFFFFFFFFFFFF
NO_FRAGMENT = 0xFFFFFFFF
DIR_TYPE, FILE_TYPE = 1, 2
ZLIB = 1
# Inodes and ids are stored uncompressed; no fragments, no extended attributes.
FLAGS = 0x1 | 0x10 | 0x200 | 0x800


class Table:
    """A metadata table: a byte stream cut into blocks of 8 KiB, each stored uncompressed
    behind a two-byte header. Places in it are given as (block start, offset)."""

    def __init__(self):
        self.data = bytearray()

    def place(self):
        block, offset = divmod(len(self.data), META)
        return block * (META + 2), offset

    def add(self, chunk):
        at = self.place()
        self.data += chunk
        return at

    def stored(self):
        out = bytearray()
        for at in range(0, len(self.data), META):
            chunk = self.data[at:at + META]
            out += struct.pack("<H", len(chunk) | UNCOMPRESSED_META) + chunk
        return bytes(out)


class Dir:
    def __init__(self, mtime):
        self.dirs = {}
        self.files = {}
        self.mtime = mtime


def build(out, paths, root, level):
    now = int(time.time())
    top = Dir(now)
    for path in paths:
        parts = path.strip("/").split("/")
        node = top
        for part in parts[:-1]:
            node = node.dirs.setdefault(part, Dir(now))
        node.files[parts[-1]] = path

    with open(out, "wb") as image:
        image.write(bytes(96))
        inodes, dirs = Table(), Table()
        count = [0]

        def put_file(path):
            source = root.rstrip("/") + path
            info = os.stat(source)
            start = image.tell()
            sizes = []
            with open(source, "rb") as f:
                while True:
                    chunk = f.read(BLOCK)
                    if not chunk:
                        break
                    if not any(chunk):
                        sizes.append(0)
                        continue
                    packed = zlib.compress(chunk, level)
                    if len(packed) < len(chunk):
                        image.write(packed)
                        sizes.append(len(packed))
                    else:
                        image.write(chunk)
                        sizes.append(len(chunk) | UNCOMPRESSED_BLOCK)
            if info.st_size >= 1 << 32 or start >= 1 << 32:
                sys.exit(f"mksqsh: {path} is too large")
            count[0] += 1
            number = count[0]
            inode = struct.pack("<HHHHII", FILE_TYPE, stat.S_IMODE(info.st_mode), 0, 0, int(info.st_mtime), number)
            inode += struct.pack("<IIII", start, NO_FRAGMENT, 0, info.st_size)
            inode += struct.pack(f"<{len(sizes)}I", *sizes)
            return number, inodes.add(inode)

        # Inodes are numbered in the order they are written: a directory's subdirectories, then
        # its files, then itself. A directory records its parent's number, so the numbers are
        # worked out first, in the same order.
        numbers = {}

        def plan(node, last):
            for name in sorted(node.dirs):
                last = plan(node.dirs[name], last)
            last += len(node.files) + 1
            numbers[id(node)] = last
            return last

        total = plan(top, 0)

        def put_dir(node, parent_number):
            # Children first: their inodes are written before the listing that points at them.
            entries = []
            for name in sorted(node.dirs):
                entries.append((name, DIR_TYPE) + put_dir(node.dirs[name], numbers[id(node)]))
            for name in sorted(node.files):
                entries.append((name, FILE_TYPE) + put_file(node.files[name]))
            entries.sort(key=lambda e: e[0].encode())

            listing = bytearray()
            run = []

            def flush():
                if not run:
                    return
                block, base = run[0][3][0], run[0][2]
                listing.extend(struct.pack("<III", len(run) - 1, block, base))
                for name, kind, number, (_, offset) in run:
                    raw = name.encode()
                    listing.extend(struct.pack("<HhHH", offset, number - base, kind, len(raw) - 1) + raw)
                run.clear()

            for entry in entries:
                _, _, number, (block, _) = entry
                if run and (run[0][3][0] != block or len(run) == 256 or not -32768 <= number - run[0][2] <= 32767):
                    flush()
                run.append(entry)
            flush()
            if len(listing) + 3 > 0xFFFF:
                sys.exit("mksqsh: a directory is too large")

            at = dirs.add(bytes(listing))
            count[0] += 1
            number = count[0]
            assert number == numbers[id(node)]
            nlink = 2 + len(node.dirs)
            inode = struct.pack("<HHHHII", DIR_TYPE, 0o755, 0, 0, node.mtime, number)
            inode += struct.pack("<IIHHI", at[0], nlink, len(listing) + 3, at[1], parent_number)
            return number, inodes.add(inode)

        # The root's parent is one past the last inode, as mksquashfs has it.
        _, root_ref = put_dir(top, total + 1)

        inode_table = image.tell()
        image.write(inodes.stored())
        directory_table = image.tell()
        image.write(dirs.stored())
        ids = image.tell()
        image.write(struct.pack("<H", 4 | UNCOMPRESSED_META) + struct.pack("<I", 0))
        id_table = image.tell()
        image.write(struct.pack("<Q", ids))
        used = image.tell()
        image.write(bytes(-used % 4096))

        image.seek(0)
        image.write(struct.pack(
            "<IIIIIHHHHHHQQQQQQQQ",
            0x73717368, total, now, BLOCK, 0, ZLIB, BLOCK.bit_length() - 1,
            FLAGS, 1, 4, 0,
            (root_ref[0] << 16) | root_ref[1], used, id_table, NONE,
            inode_table, directory_table, NONE, NONE))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out")
    parser.add_argument("list")
    parser.add_argument("--root", default="/")
    parser.add_argument("--level", type=int, default=6)
    args = parser.parse_args()
    paths = []
    with open(args.list) as f:
        for line in f:
            path = line.strip()
            if not path or path.startswith("#"):
                continue
            if not path.startswith("/"):
                sys.exit(f"mksqsh: not an absolute path: {path}")
            source = args.root.rstrip("/") + path
            if os.path.isfile(source) and not os.path.islink(source):
                paths.append(path)
            else:
                print(f"mksqsh: no file {path}; left out")
    if not paths:
        sys.exit("mksqsh: no files")
    build(args.out, paths, args.root, args.level)
    print(f"mksqsh: {len(paths)} files, {os.path.getsize(args.out) // 1024} KB")


if __name__ == "__main__":
    main()
