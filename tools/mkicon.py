import math, struct, os

HI = 1024
OUT = 128
SS = HI // OUT

def clamp(v, a=0.0, b=1.0): return a if v < a else (b if v > b else v)
def lerp(a, b, t): return a + (b - a) * t

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx-ax, by-ay
    dd = dx*dx + dy*dy
    t = 0.0 if dd == 0 else ((px-ax)*dx + (py-ay)*dy) / dd
    t = clamp(t)
    return math.hypot(px-(ax+t*dx), py-(ay+t*dy))

# iq hexagon SDF, flat-top (swap axes), centred at 0.5,0.5
K = (-0.8660254038, 0.5, 0.5773502692)
def hex_sd(x, y, r):
    px, py = abs(y-0.5), abs(x-0.5)          # swapped -> flat top
    d = K[0]*px + K[1]*py
    m = d if d < 0 else 0.0
    px -= 2.0*m*K[0]
    py -= 2.0*m*K[1]
    px -= clamp(px, -K[2]*r, K[2]*r)
    py -= r
    l = math.hypot(px, py)
    return l if py >= 0 else -l

R_HEX   = 0.452
R_ROUND = 0.045       # corner rounding
BORDER_W = 0.055

CK = [(0.300, 0.530), (0.440, 0.662), (0.742, 0.336)]
CK_W = 0.061

BORDER   = (0.20, 1.00, 0.62)
CHECK    = (0.55, 1.00, 0.78)
CHECK_SH = (0.02, 0.11, 0.07)
FILL_TOP = (0.115, 0.165, 0.150)
FILL_BOT = (0.040, 0.060, 0.056)
GLOW     = (0.20, 1.00, 0.62)
OUTRIM   = (0.02, 0.05, 0.04)

def check_cover(x, y, w):
    d = min(seg_dist(x, y, *CK[0], *CK[1]), seg_dist(x, y, *CK[1], *CK[2]))
    return d <= w

def sample(x, y):
    r = g = b = a = 0.0
    def over(cr, cg, cb, ca):
        nonlocal r, g, b, a
        r = cr*ca + r*(1-ca); g = cg*ca + g*(1-ca)
        b = cb*ca + b*(1-ca); a = ca + a*(1-ca)

    sd = hex_sd(x, y, R_HEX) - R_ROUND      # <0 inside rounded hex

    # faint dark outer rim (definition on light backgrounds)
    if sd < 0.012:
        over(*OUTRIM, 0.30)

    # plate fill + gradient + centre glow
    if sd < 0.0:
        t = clamp((y-0.06)/0.88)
        fr = lerp(FILL_TOP[0], FILL_BOT[0], t)
        fg = lerp(FILL_TOP[1], FILL_BOT[1], t)
        fb = lerp(FILL_TOP[2], FILL_BOT[2], t)
        gk = clamp(1.0 - math.hypot(x-0.5, y-0.5)/0.55) ** 2 * 0.12
        fr += (GLOW[0]-fr)*gk; fg += (GLOW[1]-fg)*gk; fb += (GLOW[2]-fb)*gk
        over(fr, fg, fb, 0.965)

    # inner border ring
    if -BORDER_W < sd < 0.0:
        k = clamp(1.0 - (y-0.05)/0.9)          # top bevel
        over(clamp(BORDER[0]+0.12*k), BORDER[1], clamp(BORDER[2]+0.14*k), 0.95)

    # check drop shadow, then check
    if check_cover(x, y-0.018, CK_W*1.03):
        over(*CHECK_SH, 0.55)
    if check_cover(x, y, CK_W):
        sh = clamp(0.5 + (x - y)*0.65)
        over(clamp(lerp(CHECK[0]*0.8, 1.0, sh)),
             clamp(lerp(CHECK[1]*0.9, 1.0, sh)),
             clamp(lerp(CHECK[2]*0.8, 1.0, sh)), 1.0)
    return (r, g, b, a)

px = bytearray(OUT*OUT*4)
inv = 1.0/HI
for oy in range(OUT):
    for ox in range(OUT):
        r=g=b=a=0.0
        for sy in range(SS):
            for sx in range(SS):
                sr,sg,sb,sa = sample((ox*SS+sx+0.5)*inv, (oy*SS+sy+0.5)*inv)
                r+=sr*sa; g+=sg*sa; b+=sb*sa; a+=sa
        n=SS*SS; a/=n
        if a > 1e-6: r/= (n*a); g/=(n*a); b/=(n*a)
        else: r=g=b=0.0
        i=(oy*OUT+ox)*4
        px[i]=int(clamp(b)*255+0.5); px[i+1]=int(clamp(g)*255+0.5)
        px[i+2]=int(clamp(r)*255+0.5); px[i+3]=int(clamp(a)*255+0.5)

hdr = struct.pack("<BBBHHBHHHHBB", 0,0,2,0,0,0,0,0,OUT,OUT,32,0x28)
os.makedirs("/home/dan/git/Bossprep/Textures", exist_ok=True)
open("/home/dan/git/Bossprep/Textures/BossPrepIcon.tga","wb").write(hdr+bytes(px))
print("wrote tga")
