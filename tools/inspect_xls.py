#!/usr/bin/env python3
"""
Reports the STRUCTURE of a legacy .xls (OLE2 + BIFF) without revealing its contents.

Prints record types and counts, how the shared-string table is laid out, and at most the first
three characters of a handful of strings — enough to tell whether text decodes at all, not enough
to disclose a merchant, an amount or a balance. No value from any numeric cell is printed.

    python3 tools/inspect_xls.py /path/to/extrato.xls
"""

import struct
import sys
from collections import Counter

ENDOFCHAIN = 0xFFFFFFFE
FREESECT = 0xFFFFFFFF

BIFF_NAMES = {
    0x0809: "BOF", 0x000A: "EOF", 0x00FC: "SST", 0x003C: "CONTINUE",
    0x00FD: "LABELSST", 0x0204: "LABEL", 0x0203: "NUMBER", 0x027E: "RK",
    0x00BD: "MULRK", 0x0006: "FORMULA", 0x0207: "STRING", 0x0201: "BLANK",
    0x00BE: "MULBLANK", 0x0205: "BOOLERR", 0x00E0: "XF", 0x041E: "FORMAT",
    0x002F: "FILEPASS", 0x0085: "BOUNDSHEET", 0x013D: "TABID", 0x022: "DATEMODE",
    0x00FF: "EXTSST", 0x01AE: "SUPBOOK", 0x0017: "EXTERNSHEET",
}


def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


def read_ole2(data):
    if data[:8] != b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        return None, "not an OLE2 compound document"

    sector_size = 1 << u16(data, 30)
    mini_cutoff = u32(data, 56)
    fat_count = u32(data, 44)
    dir_start = u32(data, 48)

    print(f"  sector size      : {sector_size}")
    print(f"  FAT sectors      : {fat_count}")
    print(f"  mini cutoff      : {mini_cutoff}")

    def sector(n):
        off = 512 + n * sector_size
        return data[off:off + sector_size] if off + sector_size <= len(data) else None

    fat = []
    for i in range(min(fat_count, 109)):
        s = u32(data, 76 + i * 4)
        if s == FREESECT:
            continue
        blk = sector(s)
        if blk:
            fat += [u32(blk, o) for o in range(0, len(blk), 4)]

    def chain(start, limit=None):
        out, s, guard = b"", start, 0
        while s not in (ENDOFCHAIN, FREESECT) and guard < 100000:
            blk = sector(s)
            if not blk:
                break
            out += blk
            if limit and len(out) >= limit:
                break
            if s >= len(fat):
                break
            s = fat[s]
            guard += 1
        return out[:limit] if limit else out

    directory = chain(dir_start)
    entries = []
    for o in range(0, len(directory) - 127, 128):
        nlen = u16(directory, o + 64)
        etype = directory[o + 66]
        if 2 < nlen <= 64:
            name = directory[o:o + nlen - 2].decode("utf-16-le", "replace")
            entries.append((name, etype, u32(directory, o + 116), u32(directory, o + 120)))

    print(f"  streams          : {[(n, sz) for n, t, st, sz in entries]}")

    wb = next((e for e in entries if e[0] in ("Workbook", "Book")), None)
    if not wb:
        return None, "no Workbook stream"

    name, etype, start, size = wb
    if size < mini_cutoff:
        root = next((e for e in entries if e[1] == 5), None)
        mini_fat_start = u32(data, 60)
        mf = chain(mini_fat_start)
        mini_fat = [u32(mf, o) for o in range(0, len(mf), 4)]
        mini_stream = chain(root[2]) if root else b""
        out, s, guard = b"", start, 0
        while s not in (ENDOFCHAIN, FREESECT) and guard < 100000:
            off = s * 64
            out += mini_stream[off:off + 64]
            if s >= len(mini_fat):
                break
            s = mini_fat[s]
            guard += 1
        return out[:size], None

    return chain(start, size), None


def read_biff(stream):
    counts = Counter()
    sst_info = None
    bof_version = None
    offset = 0

    while offset + 4 <= len(stream):
        rec = u16(stream, offset)
        length = u16(stream, offset + 2)
        body = stream[offset + 4: offset + 4 + length]
        counts[BIFF_NAMES.get(rec, hex(rec))] += 1

        if rec == 0x0809 and bof_version is None and len(body) >= 2:
            bof_version = u16(body, 0)

        if rec == 0x00FC and sst_info is None and len(body) >= 8:
            total, unique = u32(body, 0), u32(body, 4)
            segments, scan = [len(body)], offset + 4 + length
            while scan + 4 <= len(stream) and u16(stream, scan) == 0x003C:
                clen = u16(stream, scan + 2)
                segments.append(clen)
                scan += 4 + clen
            sst_info = (total, unique, segments)

        offset += 4 + length

    return counts, sst_info, bof_version


def preview_sst(stream):
    """First few strings, truncated to 3 characters each."""
    offset = 0
    while offset + 4 <= len(stream):
        rec, length = u16(stream, offset), u16(stream, offset + 2)
        if rec == 0x00FC:
            segs = [stream[offset + 4: offset + 4 + length]]
            scan = offset + 4 + length
            while scan + 4 <= len(stream) and u16(stream, scan) == 0x003C:
                clen = u16(stream, scan + 2)
                segs.append(stream[scan + 4: scan + 4 + clen])
                scan += 4 + clen
            return decode_sst(segs)
        offset += 4 + length
    return []


def decode_sst(segments, limit=8):
    seg, off = 0, 8
    out = []

    def avail():
        return len(segments[seg]) - off if seg < len(segments) else 0

    while len(out) < limit and seg < len(segments):
        if avail() < 3:
            seg += 1
            off = 0
            continue
        count = u16(segments[seg], off); off += 2
        opts = segments[seg][off]; off += 1
        wide = opts & 0x01
        if opts & 0x08:
            off += 2
        if opts & 0x04:
            off += 4

        units, read = [], 0
        while read < count and seg < len(segments):
            if avail() == 0 or (wide and avail() < 2):
                seg += 1
                off = 0
                if seg >= len(segments) or not len(segments[seg]):
                    break
                wide = segments[seg][0] & 0x01
                off = 1
                continue
            if wide:
                units.append(u16(segments[seg], off)); off += 2
            else:
                units.append(segments[seg][off]); off += 1
            read += 1
        text = "".join(chr(u) for u in units)
        out.append(f"{text[:3]!r}… (len {len(text)})")
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    data = open(sys.argv[1], "rb").read()
    print(f"file bytes         : {len(data)}")
    print(f"first 8 bytes      : {data[:8].hex()}")

    stream, err = read_ole2(data)
    if err:
        print(f"ERROR: {err}")
        return 1

    print(f"workbook stream    : {len(stream)} bytes")
    counts, sst, bof = read_biff(stream)
    print(f"BOF version        : {hex(bof) if bof else 'none'}  (0x600 = BIFF8)")
    print(f"record histogram   : {dict(counts.most_common(14))}")

    if sst:
        total, unique, segments = sst
        print(f"SST total/unique   : {total} / {unique}")
        print(f"SST segments       : {len(segments)} -> sizes {segments[:6]}"
              f"{'…' if len(segments) > 6 else ''}")
        print("first strings      :")
        for s in preview_sst(stream):
            print(f"    {s}")
    else:
        print("SST                : none (strings may be in LABEL records, or BIFF5)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
