#!/usr/bin/env python3
"""Rebuilds the RG DS+ boot partition with other boot pictures and, optionally, a gzipped kernel.

The partition holds one U-Boot FIT: a device tree, the kernel and a "resource" block, each
with a SHA-256 in the FIT header that U-Boot checks. The resource block is Rockchip's RSCE
format and carries the two boot pictures (logo.bmp, shown by U-Boot, and logo_kernel.bmp, shown
by the kernel) with a SHA-1 each.

Pictures are replaced in place, in the stock size and layout, so nothing else moves. Gzipping
the kernel moves the resource block up and changes a few header fields, all without changing
the header's size. The header's RSA signature is left as it is and no longer matches.

  bootimg.py extract STOCK.IMG boot-stock.img
  bootimg.py build boot-stock.img out.img [--logo PIC] [--kernel-logo PIC] [--gzip-kernel]
  bootimg.py check some.img

Pictures can be anything ImageMagick reads; they are fitted inside the stock size on black.
"""

import argparse
import gzip
import hashlib
import struct
import subprocess
import sys

BOOT_SECTOR = 32768
BOOT_BYTES = 64 << 20
SECTOR = 512
PICTURES = {"logo": "logo.bmp", "kernel_logo": "logo_kernel.bmp"}


def die(why):
    sys.exit(f"bootimg: {why}")


class Fit:
    """The FIT header, with where each property's value sits so it can be changed in place."""

    def __init__(self, image):
        self.image = bytearray(image)
        if self.image[:4] != b"\xd0\x0d\xfe\xed":
            die("not a FIT image")
        off_struct, off_strings = struct.unpack_from(">II", self.image, 8)
        self.props = {}
        at, path = off_struct, []
        while True:
            (token,) = struct.unpack_from(">I", self.image, at)
            at += 4
            if token == 1:
                end = self.image.index(b"\0", at)
                path.append(self.image[at:end].decode())
                at = (end + 4) & ~3
            elif token == 2:
                path.pop()
            elif token == 3:
                size, name = struct.unpack_from(">II", self.image, at)
                at += 8
                end = self.image.index(b"\0", off_strings + name)
                key = "/".join(path) + ":" + self.image[off_strings + name:end].decode()
                self.props[key] = (at, size)
                at = (at + size + 3) & ~3
            elif token == 9:
                break
            elif token != 4:
                die("FIT header is damaged")

    def get(self, key):
        at, size = self.props[key]
        return bytes(self.image[at:at + size])

    def number(self, key):
        return int.from_bytes(self.get(key), "big")

    def put(self, key, value):
        at, size = self.props[key]
        if len(value) != size:
            die(f"{key}: {len(value)} bytes do not fit in {size}")
        self.image[at:at + size] = value

    def data(self, name):
        at, size = self.number(f"/images/{name}:data-position"), self.number(f"/images/{name}:data-size")
        return bytes(self.image[at:at + size])

    def size(self):
        return self.number(":totalsize")

    def check(self):
        for name in ("fdt", "kernel", "resource"):
            if hashlib.sha256(self.data(name)).digest() != self.get(f"/images/{name}/hash:value"):
                die(f"{name}: SHA-256 in the header does not match the data")


def entries(resource):
    """RSCE index: name -> (where its entry starts, data offset, data size)."""
    if resource[:4] != b"RSCE":
        die("resource block is not RSCE")
    found, at = {}, SECTOR
    while resource[at:at + 4] == b"ENTR":
        name = resource[at + 4:at + 224].split(b"\0")[0].decode()
        _, offset, size = struct.unpack_from("<III", resource, at + 256)
        found[name] = (at, offset * SECTOR, size)
        at += SECTOR
    return found


def check_resource(resource):
    for name, (at, offset, size) in entries(resource).items():
        if hashlib.sha1(resource[offset:offset + size]).digest() != resource[at + 224:at + 244]:
            die(f"{name}: SHA-1 in the resource index does not match the data")


def pixels(picture, width, height):
    """The picture fitted inside width x height on black, as rows of R, G, B."""
    size = f"{width}x{height}"
    made = subprocess.run(
        ["magick", picture, "-background", "black", "-alpha", "remove", "-resize", size,
         "-gravity", "center", "-extent", size, "-depth", "8", "rgb:-"],
        capture_output=True)
    if made.returncode or len(made.stdout) != width * height * 3:
        die(f"cannot read {picture}: {made.stderr.decode().strip()}")
    return made.stdout


def repaint(resource, name, picture):
    """Puts the picture into the stock bitmap, keeping its header: size, depth and row order."""
    at, offset, size = entries(resource)[name]
    bmp = resource[offset:offset + size]
    start, = struct.unpack_from("<I", bmp, 10)
    width, height, _, depth, packing = struct.unpack_from("<iiHHI", bmp, 18)
    if bmp[:2] != b"BM" or depth != 24 or packing != 0:
        die(f"{name}: not the plain 24-bit bitmap expected")
    rgb = pixels(picture, width, abs(height))
    row = (width * 3 + 3) & ~3
    for y in range(abs(height)):
        line = rgb[y * width * 3:(y + 1) * width * 3]
        bgr = bytearray(line)
        bgr[0::3], bgr[2::3] = line[2::3], line[0::3]
        # A negative height means the rows are stored top first.
        stored = y if height < 0 else abs(height) - 1 - y
        resource[offset + start + stored * row:offset + start + stored * row + len(bgr)] = bgr
    resource[at + 224:at + 244] = hashlib.sha1(resource[offset:offset + size]).digest()


def build(args):
    fit = Fit(open(args.stock, "rb").read())
    fit.check()
    resource = bytearray(fit.data("resource"))
    check_resource(resource)
    for option, name in PICTURES.items():
        if getattr(args, option):
            repaint(resource, name, getattr(args, option))
    check_resource(resource)

    kernel = fit.data("kernel")
    if args.gzip_kernel:
        if fit.get("/images/kernel:compression") != b"none\0":
            die("kernel is already compressed")
        kernel = gzip.compress(kernel, 9, mtime=0)
        fit.put("/images/kernel:compression", b"gzip\0")

    kernel_at = fit.number("/images/kernel:data-position")
    # The stock header counts a little more than the data; keep the same margin.
    margin = fit.size() - fit.number("/images/resource:data-position") - len(resource)
    resource_at = (kernel_at + len(kernel) + SECTOR - 1) // SECTOR * SECTOR
    total = resource_at + len(resource) + margin
    fit.put("/images/kernel:data-size", len(kernel).to_bytes(4, "big"))
    fit.put("/images/kernel/hash:value", hashlib.sha256(kernel).digest())
    fit.put("/images/resource:data-position", resource_at.to_bytes(4, "big"))
    fit.put("/images/resource/hash:value", hashlib.sha256(resource).digest())
    fit.put(":totalsize", total.to_bytes(4, "big"))

    out = bytearray(total)
    out[:kernel_at] = fit.image[:kernel_at]
    out[kernel_at:kernel_at + len(kernel)] = kernel
    out[resource_at:resource_at + len(resource)] = resource
    if total > BOOT_BYTES:
        die("result does not fit the boot partition")
    Fit(out).check()
    open(args.out, "wb").write(out)
    report(args.out)


def report(file):
    image = open(file, "rb").read()
    fit = Fit(image)
    fit.check()
    check_resource(fit.data("resource"))
    size = fit.size()
    kind = fit.get("/images/kernel:compression").rstrip(b"\0").decode()
    print(f"{file}: {size} bytes, kernel {fit.number('/images/kernel:data-size')} bytes ({kind}), hashes agree")
    print(f"{size} {hashlib.sha256(image[:size]).hexdigest()}")


def extract(args):
    with open(args.stock, "rb") as disk:
        disk.seek(BOOT_SECTOR * SECTOR)
        image = disk.read(BOOT_BYTES)
    size = Fit(image).size()
    if any(image[size:]):
        die("unexpected data after the FIT in the boot partition")
    open(args.out, "wb").write(image[:size])
    report(args.out)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    one = commands.add_parser("extract")
    one.add_argument("stock")
    one.add_argument("out")
    one = commands.add_parser("build")
    one.add_argument("stock")
    one.add_argument("out")
    one.add_argument("--logo")
    one.add_argument("--kernel-logo")
    one.add_argument("--gzip-kernel", action="store_true")
    one = commands.add_parser("check")
    one.add_argument("image")
    args = parser.parse_args()
    if args.command == "extract":
        extract(args)
    elif args.command == "build":
        build(args)
    else:
        report(args.image)


if __name__ == "__main__":
    main()
