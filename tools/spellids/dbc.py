import struct
def load(path):
    b = open(path, 'rb').read()
    magic, rows, cols, size, ssize = struct.unpack('<4s4I', b[:20])
    assert magic == b'WDBC'
    recs = b[20:20 + rows * size]
    strings = b[20 + rows * size:]
    def s(off):
        e = strings.index(b'\0', off)
        return strings[off:e].decode('utf-8', 'replace')
    out = []
    for r in range(rows):
        out.append(struct.unpack_from('<%dI' % cols, recs, r * size))
    return out, s, cols, size
