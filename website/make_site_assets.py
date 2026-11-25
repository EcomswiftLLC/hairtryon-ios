"""Builds the Lustra website image assets into website/lustra/assets/.

The mark geometry comes from tools/make_icon.py (a lock of hair drawn as fine strands with a bent sheen), so the site,
the app icon and the favicon are one drawing.

Writes: favicon.svg, lustra-mark.svg, favicon-32.png, apple-touch-icon.png, icon-512.png, og-image.png,
photos/<name>.jpg (small copies of the bundled sample photos) and recolour/*.jpg, an honest illustration: a plain
colour overlay applied to one real sample photo (hair found by a simple brightness threshold). It is NOT output of the
app and the page says so.
Usage: python website/make_site_assets.py     (needs Pillow, numpy, scipy; run tools/make_icon.py first)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import make_icon  # noqa: E402

OUT = ROOT / "website" / "lustra" / "assets"
ICON = ROOT / "Sources" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
SAMPLES = ROOT / "Sources" / "Resources" / "Samples"
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "photos").mkdir(exist_ok=True)
(OUT / "recolour").mkdir(exist_ok=True)

SITE_PHOTOS = ["ombre-golden-back", "blonde-wavy-back", "balayage-wavy-back", "silver-long-back",
               "auburn-straight-back", "copper-bob-back", "long-black-back", "dark-brown-straight-back"]

INK = "#0C0A0F"
ROSE = (237, 183, 162)
TEXT = (243, 238, 232)
MUTED = (175, 168, 179)


def mark_svg(bg, size=100, strands=13, label="Lustra"):
    paths = make_icon.strand_svg(size, strands, 18)
    body = "".join(f'<path d="{d}" stroke="{c}" stroke-opacity="{a}" stroke-width="{w * size / 100 * 1.6:.2f}"/>' for d, c, a, w in paths)
    bgrect = f'<rect width="{size}" height="{size}" rx="{size * 0.224:.1f}" fill="{INK}"/>' if bg else ""
    title = f'role="img" aria-label="{label}"><title>{label}</title>' if label else 'aria-hidden="true">'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" {title}{bgrect}'
            f'<g fill="none" stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>\n')


def fonts(size, serif=True):
    for n in (["georgia.ttf"] if serif else ["segoeui.ttf"]):
        p = Path("C:/Windows/Fonts") / n
        if p.exists():
            return ImageFont.truetype(str(p), size)
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf" if serif else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def rounded_icon(px):
    icon = Image.open(ICON).convert("RGB").resize((px, px), Image.LANCZOS)
    mask = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, px * 4 - 1, px * 4 - 1], radius=int(px * 4 * 0.2237), fill=255)
    mask = mask.resize((px, px), Image.LANCZOS)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    return out


def og_image():
    W, H = 1200, 630
    img = Image.new("RGB", (W, H), (12, 10, 15))
    glow = Image.new("RGB", (W, H), ROSE)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([W * 0.5, -H * 0.3, W * 1.2, H * 0.95], fill=46)
    mask = mask.filter(ImageFilter.GaussianBlur(120))
    img = Image.composite(glow, img, mask)
    d = ImageDraw.Draw(img)
    d.rectangle([80, 96, 80 + 64, 99], fill=ROSE)
    d.text((80, 128), "Hair Color Changer", font=fonts(64), fill=TEXT)
    d.text((80, 300), "Lustra", font=fonts(96), fill=ROSE)
    d.text((80, 430), "Try on dye, ombre and highlights.", font=fonts(34, False), fill=MUTED)
    d.text((80, 478), "Free for iPhone and iPad. Made on your device.", font=fonts(34, False), fill=MUTED)
    ic = rounded_icon(360)
    img.paste(ic, (W - 360 - 96, (H - 360) // 2), ic)
    d.rectangle([0, H - 10, W, H], fill=ROSE)
    img.save(OUT / "og-image.png", optimize=True)


# ---------------------------------------------------------------- honest recolour illustration
RAMPS = {
    "rose": ((58, 20, 28), (176, 104, 92), (250, 208, 188)),
    "plum": ((28, 10, 44), (98, 48, 134), (196, 146, 230)),
    "copper": ((62, 20, 8), (182, 88, 38), (244, 176, 104)),
}


def hair_mask(im):
    a = np.asarray(im).astype(np.float32) / 255
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    m = (lum < 0.32) & ((a[..., 0] - a[..., 2]) < 0.16)      # dark and not warm: hair, not shaded skin
    m = ndimage.binary_opening(m, iterations=4)
    lab, n = ndimage.label(m)
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    keep = lab == (1 + int(np.argmax(sizes)))
    keep = ndimage.binary_fill_holes(keep)
    soft = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2))
    return np.asarray(soft).astype(np.float32) / 255, lum


def recolour(im, ramp):
    m, lum = hair_mask(im)
    a = np.asarray(im).astype(np.float32)
    lo, hi = np.percentile(lum[m > 0.5], [3, 99])
    t = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1) ** 0.85
    s, mid, h = (np.array(c, np.float32) for c in ramp)
    t3 = t[..., None]
    col = np.where(t3 < 0.55, s + (mid - s) * (t3 / 0.55), mid + (h - mid) * ((t3 - 0.55) / 0.45))
    out = a * (1 - m[..., None] * 0.96) + col * (m[..., None] * 0.96)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def recolour_assets():
    im = Image.open(SAMPLES / "dark-brown-straight-back.jpg").convert("RGB")
    W, H = im.size
    crop = (int(W * 0.17), 0, int(W * 0.17) + int(H * 0.78), H)          # a portrait crop around the hair
    variants = {"original": im}
    for k, r in RAMPS.items():
        variants[k] = recolour(im, r)
    for k, v in variants.items():
        c = v.crop(crop)
        c = c.resize((720, round(c.height * 720 / c.width)), Image.LANCZOS)
        c.save(OUT / "recolour" / f"{k}.jpg", quality=84, optimize=True, progressive=True)
    # split: left half original, right half rose
    o = variants["original"].crop(crop)
    r = variants["rose"].crop(crop)
    o = o.resize((900, round(o.height * 900 / o.width)), Image.LANCZOS)
    r = r.resize(o.size, Image.LANCZOS)
    split = o.copy()
    split.paste(r.crop((o.width // 2, 0, o.width, o.height)), (o.width // 2, 0))
    d = ImageDraw.Draw(split)
    d.line([(o.width // 2, 0), (o.width // 2, o.height)], fill=(255, 245, 238), width=3)
    split.save(OUT / "recolour" / "split.jpg", quality=86, optimize=True, progressive=True)


def main():
    (OUT / "favicon.svg").write_text(mark_svg(True, strands=9, label="Lustra"), encoding="utf-8")
    (OUT / "lustra-mark.svg").write_text(mark_svg(False, strands=13, label=""), encoding="utf-8")
    icon = Image.open(ICON).convert("RGB")
    icon.resize((180, 180), Image.LANCZOS).save(OUT / "apple-touch-icon.png", optimize=True)
    rounded_icon(512).save(OUT / "icon-512.png", optimize=True)
    rounded_icon(32).save(OUT / "favicon-32.png", optimize=True)
    og_image()
    for n in SITE_PHOTOS:
        im = Image.open(SAMPLES / f"{n}.jpg").convert("RGB")
        im.thumbnail((1000, 1000), Image.LANCZOS)
        im.save(OUT / "photos" / f"{n}.jpg", quality=80, optimize=True, progressive=True)
    recolour_assets()
    # real app slides (from tools/make_store_shots.py) for the landing page; skipped until they exist
    slides = sorted((ROOT / "design" / "store" / "6.9").glob("*.png")) if (ROOT / "design" / "store" / "6.9").exists() else []
    shots_dir = OUT / "shots"
    if slides:
        shots_dir.mkdir(exist_ok=True)
        for old in shots_dir.glob("*.jpg"):
            old.unlink()
        for i, sp in enumerate(slides[:6], 1):
            im = Image.open(sp).convert("RGB")
            im = im.resize((660, round(im.height * 660 / im.width)), Image.LANCZOS)
            im.save(shots_dir / f"slide-{i:02d}.jpg", quality=82, optimize=True, progressive=True)
    print("assets written to", OUT, f"({len(slides[:6])} app slides)")


if __name__ == "__main__":
    main()
