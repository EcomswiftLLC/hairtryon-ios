#!/usr/bin/env python3
"""Runs the converted .mlpackage with the real Core ML runtime (macOS only) and compares with the original TFLite model.

Usage: python tools/verify_coreml_macos.py --work build/model --model build/out/HairSegmenter.mlpackage --photos build/photos
"""
import argparse
import json
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_hair_model as C  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="build/model")
    ap.add_argument("--model", required=True)
    ap.add_argument("--photos", required=True)
    ap.add_argument("--report", default=None)
    args = ap.parse_args()
    import coremltools as ct

    tfl = os.path.join(args.work, "hair_segmenter.tflite")
    files = sorted(f for f in os.listdir(args.photos) if f.lower().endswith((".jpg", ".png")))
    report = {}
    for units_name, units in [("CPU_ONLY", ct.ComputeUnit.CPU_ONLY), ("ALL", ct.ComputeUnit.ALL)]:
        model = ct.models.MLModel(args.model, compute_units=units)
        print(units_name, "input", model.get_spec().description.input[0].type.WhichOneof("Type"),
              "output", model.get_spec().description.output[0].name)
        rows = []
        for f in files:
            im = Image.open(os.path.join(args.photos, f)).convert("RGB").resize((C.SIZE, C.SIZE), Image.BILINEAR)
            ref = C.tflite_run(tfl, np.asarray(im, dtype=np.float32) / 255.0)
            t0 = time.time()
            out = model.predict({"image": im})["hair_probability"]
            dt = time.time() - t0
            arr = np.asarray(out, dtype=np.float32)
            assert arr.shape == (1, 1, C.SIZE, C.SIZE), arr.shape
            arr = arr[0, 0]
            row = dict(image=f, mae=float(np.abs(arr - ref).mean()), max_abs=float(np.abs(arr - ref).max()),
                       iou_05=C.iou(arr, ref), min=float(arr.min()), max=float(arr.max()), seconds=round(dt, 3),
                       ref_cov=float((ref >= 0.5).mean()), cov=float((arr >= 0.5).mean()))
            rows.append(row)
            print(json.dumps(row))
        mean = {k: float(np.mean([r[k] for r in rows])) for k in ("mae", "iou_05", "seconds")}
        mean["min_iou"] = float(min(r["iou_05"] for r in rows))
        print(units_name, "MEAN", json.dumps(mean))
        report[units_name] = dict(per_image=rows, mean=mean)
        if mean["min_iou"] < 0.95 or mean["mae"] > 0.02:
            report["failed"] = True
    if args.report:
        json.dump(report, open(args.report, "w"), indent=2)
    if report.get("failed"):
        sys.exit("Core ML runtime output deviates from TFLite")


if __name__ == "__main__":
    main()
