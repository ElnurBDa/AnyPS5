#!/usr/bin/env python3
# unself.py — extract the clean inner ELF from a FAKE-SIGNED PS4/PS5 SELF.
#
#   python3 unself.py <eboot.bin|something.self> <out.elf>
#
# Works only on *fake-signed* homebrew SELFs (magic 0x1D3D154F), where the
# segments are stored plaintext/uncompressed (or zlib) and there is nothing
# encrypted to break. It reads the SELF segment table and places each segment
# at its real ELF file offset, reconstructing a loadable ELF that AnyPS5's
# relinker accepts. It CANNOT and does not decrypt retail/encrypted content.
import struct, sys, zlib

def main(src, out):
    d = open(src, "rb").read()
    if struct.unpack_from("<I", d, 0)[0] != 0x1d3d154f:
        sys.exit("not a (fake-signed) SELF: magic != 0x1D3D154F")
    file_size = struct.unpack_from("<Q", d, 0x10)[0]
    nseg = struct.unpack_from("<H", d, 0x18)[0]
    segs = [struct.unpack_from("<QQQQ", d, 0x20 + i * 0x20) for i in range(nseg)]  # flags, off, csize, usize
    elf_off = 0x20 + nseg * 0x20
    if d[elf_off:elf_off + 4] != b"\x7fELF":
        sys.exit("no ELF header at 0x%x" % elf_off)
    e = d[elf_off:]
    phoff = struct.unpack_from("<Q", e, 0x20)[0]
    phes  = struct.unpack_from("<H", e, 0x36)[0]
    phn   = struct.unpack_from("<H", e, 0x38)[0]
    ph = []
    for i in range(phn):
        b = phoff + i * phes
        p_off  = struct.unpack_from("<Q", e, b + 8)[0]
        p_fsz  = struct.unpack_from("<Q", e, b + 0x20)[0]
        ph.append((p_off, p_fsz))
    need = max([o + s for o, s in ph] + [file_size])
    buf = bytearray(need)
    meta = max(0x40, phoff + phn * phes)
    buf[0:meta] = e[0:meta]                       # ELF header + program headers
    placed = 0
    for flags, off, csz, usz in segs:
        pid = (flags >> 20) & 0xFFF               # target program-header index
        if pid >= phn:
            continue
        blob = d[off:off + csz]
        if (flags >> 3) & 1:                      # compressed
            try: blob = zlib.decompress(blob)
            except Exception as ex: sys.exit("zlib fail on seg id=%d: %s" % (pid, ex))
        p_off = ph[pid][0]
        buf[p_off:p_off + len(blob)] = blob
        placed += 1
    open(out, "wb").write(buf)
    print("reconstructed %s (%d bytes, %d/%d segments placed)" % (out, len(buf), placed, nseg))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python3 unself.py <in.self/eboot.bin> <out.elf>")
    main(sys.argv[1], sys.argv[2])
