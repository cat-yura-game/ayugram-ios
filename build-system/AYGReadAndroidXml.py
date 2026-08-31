import struct, sys

def parse_string_pool(b, off):
    typ, hsize, size = struct.unpack_from('<HHI', b, off)
    strCount, styleCount, flags, stringsStart, _ = struct.unpack_from('<IIIII', b, off + 8)
    utf8 = bool(flags & (1 << 8))
    out = []
    base = off + stringsStart
    for i in range(strCount):
        o = base + struct.unpack_from('<I', b, off + hsize + i*4)[0]
        if utf8:
            def l(o):
                n = b[o]; o += 1
                if n & 0x80: n = ((n & 0x7f) << 8) | b[o]; o += 1
                return n, o
            _, o = l(o); n, o = l(o)
            out.append(b[o:o+n].decode('utf-8', 'replace'))
        else:
            n = struct.unpack_from('<H', b, o)[0]; o += 2
            if n & 0x8000:
                n = ((n & 0x7fff) << 16) | struct.unpack_from('<H', b, o)[0]; o += 2
            out.append(b[o:o+n*2].decode('utf-16-le', 'replace'))
    return out, size

def main(path):
    b = open(path, 'rb').read()
    _typ, hsize, _size = struct.unpack_from('<HHI', b, 0)
    o = hsize
    pool = []
    while o < len(b):
        ctyp, chsize, csize = struct.unpack_from('<HHI', b, o)
        if csize == 0: break
        if ctyp == 0x0001:
            pool, _ = parse_string_pool(b, o)
        elif ctyp == 0x0102:   # START_ELEMENT
            base = o + chsize
            _ns, nameIdx = struct.unpack_from('<II', b, base)
            attrStart, attrSize, attrCount = struct.unpack_from('<HHH', b, base + 8)
            name = pool[nameIdx] if nameIdx < len(pool) else '?'
            attrs = {}
            ao = base + attrStart
            for _ in range(attrCount):
                _ans, anameIdx, rawIdx = struct.unpack_from('<III', b, ao)
                _vs, _r0, dtype, data = struct.unpack_from('<HBBI', b, ao + 12)
                aname = pool[anameIdx] if anameIdx < len(pool) else '?'
                if rawIdx != 0xFFFFFFFF and rawIdx < len(pool):
                    val = pool[rawIdx]
                elif dtype == 0x1c or dtype == 0x1d:      # #aarrggbb
                    val = f"#{data:08x}"
                elif dtype == 0x04:                        # float
                    val = struct.unpack('<f', struct.pack('<I', data))[0]
                elif dtype == 0x05:                        # dimension
                    val = (data >> 8) / 1.0
                else:
                    val = data
                attrs[aname] = val
            print(f"<{name} " + " ".join(f'{k}="{v}"' for k, v in attrs.items()) + ">")
        o += csize

main(sys.argv[1])
