"""Draws the Lustra app icon: one lock of hair, drawn as a sheaf of fine rose-gold strands with a soft sheen band.

The mark: ~70 hairline strands leave a single point, swell into a flowing S-shaped lock and gather again at the
tip. A band of light crosses the lock, and because the band sits slightly higher on the left strands than on the
right ones, it bends the way a real highlight bends on hair. That one curved sheen is the whole idea: colour that
moves with light. Deep ink ground, no text, no tool or face clip-art.

Run: python tools/make_icon.py          (about 1 minute)
Writes AppIcon-1024.png, AppIcon-1024-dark.png and AppIcon-1024-tinted.png (RGB, no alpha) into the asset catalog
and design/icon/preview.png (a contact sheet at several sizes). strand_svg() feeds website/make_site_assets.py.
Needs Pillow and numpy.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset"
PREVIEW = ROOT / "design/icon"

S = 3584            # supersampled canvas
FINAL = 1024

INK = (12, 10, 15)          # #0C0A0F
INK_DEEP = (8, 7, 11)
LIFT = (34, 27, 40)         # plum-ink lift behind the mark
ROSE = (237, 183, 162)      # #EDB7A2 rose gold
ROSE_DEEP = (201, 134, 114) # #C98672
SHEEN = (255, 236, 224)     # the light itself

STRANDS = 73
SAMPLES = 700


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def centre(t):
    """Centre line of the lock in unit space, t from 0 (root) to 1 (tip). An S-curve leaning to the right."""
    y = 0.115 + 0.77 * t
    x = 0.50 + 0.165 * math.sin(2 * math.pi * (t - 0.08)) * (0.6 + 0.4 * math.sin(math.pi * t)) + 0.03 * (t - 0.5)
    return x, y


def envelope(t):
    """Half width of the lock: pinched at the root, full through the body, a long taper at the tip."""
    return 0.010 + 0.150 * (math.sin(math.pi * min(1.0, t ** 0.80)) ** 1.2)


def strand(o, n=SAMPLES):
    """Unit-space points of strand o in [-1, 1], plus the parameter t and the facing normal offset."""
    ts = np.linspace(0, 1, n)
    pts = np.zeros((n, 2))
    k = 1 + 0.9 * abs(math.sin(o * 7.3))                  # each strand drifts a little, so the sheaf is not a rigid band
    ph = o * 5.1
    for i, t in enumerate(ts):
        x, y = centre(t)
        x2, y2 = centre(min(1, t + 1e-3))
        x1, y1 = centre(max(0, t - 1e-3))
        L = math.hypot(x2 - x1, y2 - y1) or 1
        nx, ny = (y2 - y1) / L * 0.5 + 0.5, -(x2 - x1) / L * 0.5   # half the true normal, half sideways: spaced strands, no folds
        m = math.hypot(nx, ny) or 1
        nx, ny = nx / m, ny / m
        w = envelope(t)
        wob = 0.006 * math.sin(t * 9 * k + ph) * math.sin(math.pi * t)
        off = o * w + wob
        pts[i] = (x + nx * off, y + ny * off)
    return ts, pts


def shade(t, o, variant="light"):
    """Colour and alpha for a point of strand o at t: rose-gold body, champagne band that bends across the lock."""
    centre_t = 0.40 + 0.115 * o + 0.03 * math.sin(o * 3)  # where the band sits on this strand
    d = (t - centre_t) / 0.105
    band = math.exp(-d * d)
    d2 = (t - (centre_t + 0.30 + 0.05 * o)) / 0.05        # a faint second reflection near the tip
    band2 = 0.38 * math.exp(-d2 * d2)
    s = min(1.0, band + band2)
    body = lerp(ROSE_DEEP, ROSE, 0.30 + 0.85 * t)
    # the left edge (o = -1) catches rim light, the right edge falls away
    rim = max(0.0, -o) ** 3
    col = lerp(body, SHEEN, s * 0.97 + rim * 0.26)
    a = 0.60 + 0.40 * s + 0.20 * rim + 0.08 * (1 - abs(o))
    a *= min(1.0, t * 14 + 0.06) * min(1.0, (1 - t) * 10 + 0.05)   # soft fade at both ends
    return col, min(1.0, a)


def background(variant):
    if variant == "tinted":
        return Image.new("RGB", (S, S), (0, 0, 0))
    inner, outer = (LIFT, INK) if variant == "light" else ((24, 19, 29), INK_DEEP)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - S * 0.52) ** 2 + (yy - S * 0.42) ** 2) / (S * 0.80)
    k = np.clip(1 - d, 0, 1) ** 1.8
    arr = np.zeros((S, S, 3), np.float32)
    for c in range(3):
        arr[..., c] = outer[c] + (inner[c] - outer[c]) * k
    # a low warm bloom where the light leaves the lock
    d2 = np.sqrt((xx - S * 0.34) ** 2 + (yy - S * 0.82) ** 2) / (S * 0.55)
    k2 = np.clip(1 - d2, 0, 1) ** 2.4 * 0.13
    for c in range(3):
        arr[..., c] += (ROSE_DEEP[c] - arr[..., c]) * k2
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def sheaf_layers(variant):
    layer = Image.new("RGB", (S, S), (0, 0, 0))
    alpha = Image.new("L", (S, S), 0)
    dc, da = ImageDraw.Draw(layer), ImageDraw.Draw(alpha)
    mono = variant == "tinted"
    order = sorted(range(STRANDS), key=lambda j: abs(-1 + 2 * j / (STRANDS - 1)), reverse=True)  # edges first, centre on top
    for j in order:
        o = -1 + 2 * j / (STRANDS - 1)
        ts, pts = strand(o)
        for i in range(len(ts) - 1):
            col, a = shade(ts[i], o, variant)
            if mono:
                g = int((col[0] * 0.3 + col[1] * 0.59 + col[2] * 0.11))
                col = (g, g, g)
            w = max(2, int(S * (0.00105 + 0.0013 * (1 - abs(o)) ** 0.5)))
            p0 = (pts[i][0] * S, pts[i][1] * S)
            p1 = (pts[i + 1][0] * S, pts[i + 1][1] * S)
            dc.line([p0, p1], fill=tuple(int(c) for c in col), width=w)
            da.line([p0, p1], fill=int(255 * a), width=w)
    return layer, alpha


def compose(variant):
    base = background(variant)
    layer, alpha = sheaf_layers(variant)
    mono = variant == "tinted"
    if not mono:
        wide = layer.filter(ImageFilter.GaussianBlur(S * 0.030))
        wa = alpha.filter(ImageFilter.GaussianBlur(S * 0.030)).point(lambda v: int(min(255, v * 1.2) * 0.34))
        base.paste(wide, (0, 0), wa)
        soft = layer.filter(ImageFilter.GaussianBlur(S * 0.0085))
        sa = alpha.filter(ImageFilter.GaussianBlur(S * 0.0085)).point(lambda v: int(min(255, v * 1.15) * 0.55))
        base.paste(soft, (0, 0), sa)
    base.paste(layer, (0, 0), alpha)
    out = base.resize((FINAL, FINAL), Image.LANCZOS)
    return out


def strand_svg(size=100, strands=29, segs=22):
    """List of (d, colour, opacity, width) for the website mark. Shares the maths above."""
    out = []
    for j in range(strands):
        o = -1 + 2 * j / (strands - 1)
        ts, pts = strand(o, segs * 8 + 1)
        for s in range(segs):
            a, b = s * 8, (s + 1) * 8
            col, al = shade(ts[(a + b) // 2], o)
            d = "M" + " L".join(f"{pts[i][0] * size:.2f} {pts[i][1] * size:.2f}" for i in range(a, b + 1, 2))
            out.append((d, "#%02x%02x%02x" % tuple(int(c) for c in col), round(al, 2), round(0.22 + 0.28 * (1 - abs(o)) ** 0.5, 2)))
    return out


def preview(icons):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    sizes = [180, 120, 80, 60, 40, 29]
    sheet = Image.new("RGB", (1100, 620), (22, 22, 26))
    x = 30
    for name, im in icons.items():
        big = im.resize((320, 320), Image.LANCZOS)
        mask = Image.new("L", (320, 320), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, 319, 319], 72, fill=255)
        sheet.paste(big, (x, 30), mask)
        sx, yy = x, 380
        for s in sizes:
            if sx + s > x + 330:
                break
            sm = im.resize((s, s), Image.LANCZOS)
            m = Image.new("L", (s, s), 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, s - 1, s - 1], int(s * 0.2237), fill=255)
            sheet.paste(sm, (sx, yy), m)
            sx += s + 14
        x += 360
    sheet.save(PREVIEW / "preview.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icons = {}
    for variant, fname in (("light", "AppIcon-1024.png"), ("dark", "AppIcon-1024-dark.png"), ("tinted", "AppIcon-1024-tinted.png")):
        im = compose(variant)
        assert im.mode == "RGB"
        im.save(OUT / fname, optimize=True)
        icons[variant] = im
        print("wrote", OUT / fname)
    preview(icons)


if __name__ == "__main__":
    main()
