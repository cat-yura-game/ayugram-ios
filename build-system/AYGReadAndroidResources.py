import struct, sys

RES_STRING_POOL_TYPE = 0x0001
RES_TABLE_TYPE       = 0x0002
RES_TABLE_PACKAGE    = 0x0200
RES_TABLE_TYPE_TYPE  = 0x0201
RES_TABLE_TYPE_SPEC  = 0x0202

def parse_string_pool(b, off):
    typ, hsize, size = struct.unpack_from('<HHI', b, off)
    assert typ == RES_STRING_POOL_TYPE, hex(typ)
    strCount, styleCount, flags, stringsStart, stylesStart = struct.unpack_from('<IIIII', b, off + 8)
    utf8 = bool(flags & (1 << 8))
    out = []
    base = off + stringsStart
    for i in range(strCount):
        o = base + struct.unpack_from('<I', b, off + hsize + i*4)[0]
        if utf8:
            # two uleb-ish lengths (utf16 len, utf8 len), each may be 1 or 2 bytes
            def l(o):
                n = b[o]; o += 1
                if n & 0x80: n = ((n & 0x7f) << 8) | b[o]; o += 1
                return n, o
            _, o = l(o)
            n, o = l(o)
            out.append(b[o:o+n].decode('utf-8', 'replace'))
        else:
            n = struct.unpack_from('<H', b, o)[0]; o += 2
            if n & 0x8000:
                n2 = struct.unpack_from('<H', b, o)[0]; o += 2
                n = ((n & 0x7fff) << 16) | n2
            out.append(b[o:o+n*2].decode('utf-16-le', 'replace'))
    return out, size

def main(path):
    b = open(path, 'rb').read()
    typ, hsize, size = struct.unpack_from('<HHI', b, 0)
    assert typ == RES_TABLE_TYPE
    pkgCount = struct.unpack_from('<I', b, 8)[0]
    off = hsize
    globalPool, poolSize = parse_string_pool(b, off)
    off += poolSize

    results = []
    for _ in range(pkgCount):
        ptyp, phsize, psize = struct.unpack_from('<HHI', b, off)
        if ptyp != RES_TABLE_PACKAGE:
            off += psize; continue
        pkgId = struct.unpack_from('<I', b, off + 8)[0]
        typeStringsOff, _lpt, keyStringsOff = struct.unpack_from('<III', b, off + 268)
        typeStrings, _ = parse_string_pool(b, off + typeStringsOff)
        keyStrings, _  = parse_string_pool(b, off + keyStringsOff)

        o = off + phsize
        end = off + psize
        while o < end:
            ctyp, chsize, csize = struct.unpack_from('<HHI', b, o)
            if csize == 0: break
            if ctyp == RES_TABLE_TYPE_TYPE:
                tid = b[o + 8]
                entryCount, entriesStart = struct.unpack_from('<II', b, o + 12)
                tname = typeStrings[tid - 1] if 0 < tid <= len(typeStrings) else f'type{tid}'
                for i in range(entryCount):
                    eo = struct.unpack_from('<I', b, o + chsize + i*4)[0]
                    if eo == 0xFFFFFFFF: continue
                    e = o + entriesStart + eo
                    esize, eflags, keyIdx = struct.unpack_from('<HHI', b, e)
                    if eflags & 0x0001:   # complex/bag entry
                        continue
                    vsize, res0, dtype, data = struct.unpack_from('<HBBI', b, e + esize)
                    name = keyStrings[keyIdx] if keyIdx < len(keyStrings) else '?'
                    val = globalPool[data] if dtype == 0x03 and data < len(globalPool) else None
                    rid = (pkgId << 24) | (tid << 16) | i
                    results.append((tname, name, val, rid))
            o += csize
        off += psize
    return results

if __name__ == '__main__':
    rows = main(sys.argv[1])
    want = sys.argv[2] if len(sys.argv) > 2 else None
    seen = set()
    for t, n, v, rid in rows:
        if want and t != want: continue
        k = (t, n, v, rid)
        if k in seen: continue
        seen.add(k)
        print(f"0x{rid:08x}\t{t}\t{n}\t{v or ''}")
