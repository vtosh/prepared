import struct, zlib, sys

def read_tga(path):
    d = open(path, "rb").read()
    idlen, cmtype, imgtype, _cmo, _cml, _cms, xo, yo, w, h, depth, desc = struct.unpack("<BBBHHBHHHHBB", d[:18])
    assert imgtype == 2 and depth == 32
    px = d[18+idlen:]
    top_down = bool(desc & 0x20)
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            i = (y*w + x) * 4
            b, g, r, a = px[i], px[i+1], px[i+2], px[i+3]
            row += bytes((r, g, b, a))
        rows.append(bytes(row))
    if not top_down:
        rows.reverse()
    return w, h, rows

def write_png(path, w, h, rows, bg=(30,30,30)):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        # composite over bg so preview shows how it reads on a dark UI
        out = bytearray()
        for x in range(w):
            r, g, b, a = row[x*4:x*4+4]
            af = a/255
            out += bytes((
                int(r*af + bg[0]*(1-af)),
                int(g*af + bg[1]*(1-af)),
                int(b*af + bg[2]*(1-af)),
            ))
        raw += out
    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ+data) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    open(path, "wb").write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

w, h, rows = read_tga("/home/dan/git/Bossprep/Textures/BossPrepIcon.tga")
write_png("/tmp/claude-1000/-home-dan-git-Bossprep/afe0d599-2e81-4569-babf-5a62686702f6/scratchpad/icon_dark.png", w, h, rows, (24,26,30))
write_png("/tmp/claude-1000/-home-dan-git-Bossprep/afe0d599-2e81-4569-babf-5a62686702f6/scratchpad/icon_light.png", w, h, rows, (120,120,120))
print("ok", w, h)
