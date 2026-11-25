#!/usr/bin/env python3
"""Which model input works best on real portraits: whole photo (stretched / letterboxed) or a face-centred crop?

There is no ground truth for these stock photos, so the script reports proxy metrics (hair area, share of hair mask that
is connected to the main hair blob, hair mask far away from the face = background false positives, IoU between the
strategies) and saves overlay sheets for visual judgement. Face boxes come from MediaPipe's BlazeFace detector (only used
in this experiment, not shipped).

Usage: python tools/experiment_hair_input.py --work build/model --photos build/photos --out build/out/experiments
"""
import argparse
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_hair_model as C  # noqa: E402

FACE_URL = ("https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/latest/"
            "blaze_face_short_range.tflite")


def detect_face(work, path):
    import mediapipe as mp
    from mediapipe.tasks import python as mpp
    from mediapipe.tasks.python import vision
    fp = os.path.join(work, "blaze_face_short_range.tflite")
    if not os.path.exists(fp):
        urllib.request.urlretrieve(FACE_URL, fp)
    det = vision.FaceDetector.create_from_options(vision.FaceDetectorOptions(base_options=mpp.BaseOptions(model_asset_path=fp)))
    arr = np.array(Image.open(path).convert("RGB"))
    r = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=arr))
    if not r.detections:
        return None
    best = max(r.detections, key=lambda d: d.bounding_box.width * d.bounding_box.height)
    b = best.bounding_box
    return b.origin_x, b.origin_y, b.width, b.height


def run_window(tfl, img, cx, cy, side, stretch=False):
    """Draw the square window (cx, cy, side) of img onto a 512 canvas (grey padding), run the model, map back to photo size."""
    W, H = img.size
    if stretch:
        p = C.tflite_run(tfl, np.asarray(img.resize((C.SIZE, C.SIZE), Image.BILINEAR), dtype=np.float32) / 255.0)
        return np.asarray(Image.fromarray(p).resize((W, H), Image.BILINEAR))
    rx, ry = cx - side / 2, cy - side / 2
    s = C.SIZE / side
    canvas = Image.new("RGB", (C.SIZE, C.SIZE), (128, 128, 128))
    canvas.paste(img.resize((max(1, round(W * s)), max(1, round(H * s))), Image.BILINEAR), (round(-rx * s), round(ry * -s)))
    p = C.tflite_run(tfl, np.asarray(canvas, dtype=np.float32) / 255.0)
    big = np.asarray(Image.fromarray(p).resize((max(1, round(side)), max(1, round(side))), Image.BILINEAR))
    out = np.zeros((H, W), np.float32)
    x0, y0 = round(rx), round(ry)
    sx0, sy0 = max(0, -x0), max(0, -y0)
    dx0, dy0 = max(0, x0), max(0, y0)
    w = min(big.shape[1] - sx0, W - dx0)
    h = min(big.shape[0] - sy0, H - dy0)
    if w > 0 and h > 0:
        out[dy0:dy0 + h, dx0:dx0 + w] = big[sy0:sy0 + h, sx0:sx0 + w]
    return out


def blobs(mask):
    from scipy import ndimage
    lab, n = ndimage.label(mask)
    if n == 0:
        return 0, 0.0
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    return int(n), float(sizes.max() / mask.sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="build/model")
    ap.add_argument("--photos", required=True)
    ap.add_argument("--out", default="build/out/experiments")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    tfl = os.path.join(args.work, "hair_segmenter.tflite")
    files = sorted(f for f in os.listdir(args.photos) if f.lower().endswith((".jpg", ".png")))
    rows = []
    for f in files:
        img = Image.open(os.path.join(args.photos, f)).convert("RGB")
        W, H = img.size
        face = detect_face(args.work, os.path.join(args.photos, f))
        long_side = max(W, H)
        strategies = {
            "stretch_whole": lambda: run_window(tfl, img, 0, 0, 0, stretch=True),
            "letterbox_whole": lambda: run_window(tfl, img, W / 2, H / 2, long_side),
        }
        if face:
            fx, fy, fw, fh = face
            fcx, fcy = fx + fw / 2, fy + fh / 2
            for name, kw, kh in [("face_tight_2.6x3.2", 2.6, 3.2), ("face_app_3.4x4.2", 3.4, 4.2), ("face_wide_4.4x5.4", 4.4, 5.4)]:
                side = max(fw * kw, fh * kh)
                strategies[name] = (lambda side=side: run_window(tfl, img, fcx, fcy + 0.55 * fh, side))
        masks = {k: v() for k, v in strategies.items()}
        row = dict(image=f, size=[W, H], face=None if not face else [round(v) for v in face])
        for k, m in masks.items():
            b = m >= 0.5
            n, main_share = blobs(b)
            far = 0.0
            if face:
                fx, fy, fw, fh = face
                yy, xx = np.mgrid[0:H, 0:W]
                d = np.maximum(np.abs(xx - (fx + fw / 2)) / (fw * 2.2), np.abs(yy - (fy + fh / 2)) / (fh * 2.6))
                far = float((b & (d > 1.0)).sum() / max(1, b.sum()))
            row[k] = dict(coverage=float(b.mean()), blobs=n, main_blob_share=main_share, share_far_from_face=far)
        ref = masks.get("face_app_3.4x4.2", masks["letterbox_whole"]) >= 0.5
        for k, m in masks.items():
            row[k]["iou_vs_face_app"] = C.iou(m, ref.astype(np.float32))
        rows.append(row)
        print(json.dumps(row))
        # overlay sheet: original + one panel per strategy
        tw = 260
        panels = [img]
        for k, m in masks.items():
            ov = np.asarray(img, dtype=np.float32).copy()
            a = (m[..., None] >= 0.5) * 0.55
            ov = ov * (1 - a) + np.array([255, 40, 160], np.float32) * a
            im = Image.fromarray(ov.astype(np.uint8))
            ImageDraw.Draw(im).text((8, 8), k, fill=(255, 255, 0))
            panels.append(im)
        th = int(tw * H / W)
        sheet = Image.new("RGB", (tw * len(panels), th), "white")
        for i, p in enumerate(panels):
            sheet.paste(p.resize((tw, th)), (i * tw, 0))
        sheet.save(os.path.join(args.out, os.path.splitext(f)[0] + "_overlay.png"))
    keys = [k for k in rows[0] if k not in ("image", "size", "face")]
    for r in rows:
        keys = [k for k in keys if k in r] or keys
    summary = {}
    for k in ["stretch_whole", "letterbox_whole", "face_tight_2.6x3.2", "face_app_3.4x4.2", "face_wide_4.4x5.4"]:
        rs = [r[k] for r in rows if k in r]
        if rs:
            summary[k] = {m: float(np.mean([x[m] for x in rs])) for m in rs[0]}
            summary[k]["n"] = len(rs)
    print("SUMMARY", json.dumps(summary, indent=1))
    json.dump(dict(per_image=rows, summary=summary), open(os.path.join(args.out, "experiments.json"), "w"), indent=2)


if __name__ == "__main__":
    main()
