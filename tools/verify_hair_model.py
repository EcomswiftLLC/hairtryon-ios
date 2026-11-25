#!/usr/bin/env python3
"""Linux-side verification of the converted hair model (Core ML cannot be *run* on Linux).

1. Loads the SAVED .mlpackage back into a PyMIL program (weights included, fp16 as shipped) and evaluates that
   program with a small reference interpreter (torch ops, fp16 rounding after every fp16 op) on real portraits.
2. Compares the result with (a) the original TFLite model and (b) MediaPipe Tasks ImageSegmenter output
   (full production pipeline incl. its own resize), reporting MAE / IoU@0.5.

Usage: python tools/verify_hair_model.py --work build/model --model build/out/HairSegmenter.mlpackage \
         --photos build/photos --report build/out/verify-report.json
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_hair_model as C  # noqa: E402

SIZE = C.SIZE


# ------------------------------------------------------------------------------------------------
# tiny MIL interpreter (just the ops this graph uses; unknown ops raise so nothing is silently skipped)
# ------------------------------------------------------------------------------------------------
def _val(v):
    return v.val if getattr(v, "val", None) is not None else None


def evaluate_program(prog, image255, emulate_fp16=True):
    """image255: float32 [1,3,H,W] with 0..255 values. Returns dict output_name -> np.ndarray."""
    import torch
    import torch.nn.functional as F

    main = prog.functions["main"]
    env = {}
    in_name = list(main.inputs.keys())[0]
    env[main.inputs[in_name].name] = torch.from_numpy(image255.astype(np.float32))

    from coremltools.converters.mil.mil import types as mil_types

    def dt(var):
        return mil_types.builtin_to_string(var.dtype)

    def get(var):
        if var.name in env:
            return env[var.name]
        if var.val is not None:
            v = var.val
            return v if not isinstance(v, np.ndarray) else torch.from_numpy(np.array(v)).float() \
                if v.dtype.kind == "f" else torch.from_numpy(np.array(v))
        raise KeyError(var.name)

    def ints(var):
        v = var.val
        return [int(i) for i in np.array(v).reshape(-1)]

    for op in main.operations:
        t = op.op_type
        out = op.outputs[0]
        inp = op.inputs
        if t == "const":
            continue
        elif t == "cast":
            d = op.dtype.val
            x = get(inp["x"])
            if d == "fp16":
                y = x.float().half().float()
            elif d == "fp32":
                y = x.float()
            elif d == "int32":
                y = x.to(torch.int32)
            elif d == "bool":
                y = x != 0
            else:
                raise NotImplementedError(d)
        elif t == "conv":
            x = get(inp["x"])
            w = torch.from_numpy(np.array(inp["weight"].val, dtype=np.float32))
            b = inp["bias"].val if "bias" in inp and inp["bias"] is not None and inp["bias"].val is not None else None
            b = None if b is None else torch.from_numpy(np.array(b, dtype=np.float32))
            pt = inp["pad_type"].val
            pad = ints(inp["pad"]) if "pad" in inp and inp["pad"] is not None and pt == "custom" else [0, 0, 0, 0]
            if any(pad):
                x = F.pad(x, (pad[2], pad[3], pad[0], pad[1]))
            y = F.conv2d(x, w, b, stride=tuple(ints(inp["strides"])), dilation=tuple(ints(inp["dilations"])),
                         groups=int(inp["groups"].val))
        elif t == "conv_transpose":
            x = get(inp["x"])
            w = torch.from_numpy(np.array(inp["weight"].val, dtype=np.float32))
            b = inp["bias"].val if "bias" in inp and inp["bias"] is not None and inp["bias"].val is not None else None
            b = None if b is None else torch.from_numpy(np.array(b, dtype=np.float32))
            assert inp["pad_type"].val in ("valid",) or not any(ints(inp["pad"])), "padded conv_transpose not expected"
            y = F.conv_transpose2d(x, w, b, stride=tuple(ints(inp["strides"])),
                                   dilation=tuple(ints(inp["dilations"])), groups=int(inp["groups"].val))
        elif t == "prelu":
            x = get(inp["x"])
            a = torch.from_numpy(np.array(inp["alpha"].val, dtype=np.float32)).reshape(-1)
            y = F.prelu(x, a)
        elif t == "pad":
            x = get(inp["x"])
            p = ints(inp["pad"])
            assert inp["mode"].val == "constant"
            cv = float(inp["constant_val"].val)
            pairs = [(p[i], p[i + 1]) for i in range(0, len(p), 2)]
            pairs = [(0, 0)] * (x.dim() - len(pairs)) + pairs
            flat = []
            for lo, hi in reversed(pairs):
                flat += [lo, hi]
            y = F.pad(x, flat, value=cv)
        elif t == "slice_by_index":
            x = get(inp["x"])
            begin = ints(inp["begin"])
            end = ints(inp["end"])
            strides = ints(inp["stride"]) if "stride" in inp and inp["stride"] is not None else [1] * len(begin)
            bm = np.array(inp["begin_mask"].val).reshape(-1) if "begin_mask" in inp and inp["begin_mask"] is not None else [False] * len(begin)
            em = np.array(inp["end_mask"].val).reshape(-1) if "end_mask" in inp and inp["end_mask"] is not None else [False] * len(begin)
            sm = np.array(inp["squeeze_mask"].val).reshape(-1) if "squeeze_mask" in inp and inp["squeeze_mask"] is not None else [False] * len(begin)
            sl, sq = [], []
            for i in range(len(begin)):
                b0 = None if bm[i] else begin[i]
                e0 = None if em[i] else end[i]
                sl.append(slice(b0, e0, strides[i]))
                if sm[i]:
                    sq.append(i)
            y = x[tuple(sl)]
            for i in reversed(sq):
                y = y.squeeze(i)
        elif t == "add":
            y = get(inp["x"]) + get(inp["y"])
        elif t == "mul":
            y = get(inp["x"]) * get(inp["y"])
        elif t == "sub":
            y = get(inp["x"]) - get(inp["y"])
        elif t == "concat":
            y = torch.cat([get(v) for v in inp["values"]], dim=int(inp["axis"].val))
        elif t == "reshape":
            y = get(inp["x"]).reshape(ints(inp["shape"]))
        elif t == "expand_dims":
            y = get(inp["x"])
            for ax in sorted(ints(inp["axes"])):
                y = y.unsqueeze(ax)
        elif t == "squeeze":
            y = get(inp["x"]).squeeze(ints(inp["axes"])[0]) if "axes" in inp and inp["axes"] is not None else get(inp["x"]).squeeze()
        elif t == "transpose":
            y = get(inp["x"]).permute(ints(inp["perm"]))
        elif t == "reduce_max":
            y = get(inp["x"])
            for ax in sorted(ints(inp["axes"]), reverse=True):
                y = y.amax(dim=ax, keepdim=bool(inp["keep_dims"].val))
        elif t == "reduce_argmax":
            y = torch.argmax(get(inp["x"]), dim=int(inp["axis"].val), keepdim=bool(inp["keep_dims"].val)).to(torch.int32)
        elif t == "equal":
            y = get(inp["x"]) == get(inp["y"])
        elif t == "sigmoid":
            y = torch.sigmoid(get(inp["x"]))
        elif t == "pixel_unshuffle":
            y = F.pixel_unshuffle(get(inp["x"]), int(inp["downscale_factor"].val))
        elif t == "pixel_shuffle":
            y = F.pixel_shuffle(get(inp["x"]), int(inp["upscale_factor"].val))
        else:
            raise NotImplementedError(f"MIL op not handled by the reference interpreter: {t}")
        if emulate_fp16 and y.dtype == torch.float32 and dt(out) == "fp16":
            y = y.half().float()
        env[out.name] = y
    return {v.name: env[v.name].numpy() for v in main.outputs}


def load_saved_program(path):
    import coremltools as ct
    from coremltools.converters.mil.frontend.milproto.load import load as milproto_to_pymil
    m = ct.models.MLModel(path, skip_model_load=True)
    spec = m.get_spec()
    prog = milproto_to_pymil(spec, spec.specificationVersion, m.weights_dir)
    return prog, spec


# ------------------------------------------------------------------------------------------------
# comparisons
# ------------------------------------------------------------------------------------------------
def mediapipe_hair(path_img):
    import mediapipe as mp
    from mediapipe.tasks import python as mpp
    from mediapipe.tasks.python import vision
    opts = vision.ImageSegmenterOptions(
        base_options=mpp.BaseOptions(model_asset_path=os.path.join(ARGS.work, "hair_segmenter.tflite")),
        running_mode=vision.RunningMode.IMAGE, output_confidence_masks=True, output_category_mask=False)
    seg = vision.ImageSegmenter.create_from_options(opts)
    from PIL import Image
    arr = np.array(Image.open(path_img).convert("RGB"))
    r = seg.segment(mp.Image(image_format=mp.ImageFormat.SRGB, data=arr))
    return r.confidence_masks[1].numpy_view()[..., 0].copy()


def upscale(mask512, w, h):
    from PIL import Image
    return np.asarray(Image.fromarray(mask512.astype(np.float32)).resize((w, h), Image.BILINEAR))


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="build/model")
    ap.add_argument("--model", default="Sources/Resources/Models/HairSegmenter.mlpackage")
    ap.add_argument("--photos", required=True)
    ap.add_argument("--report", default=None)
    ARGS = ap.parse_args()

    tfl = os.path.join(ARGS.work, "hair_segmenter.tflite")
    prog, spec = load_saved_program(ARGS.model)
    print("saved model: spec version", spec.specificationVersion, "| input", [i.name for i in spec.description.input],
          "| output", [o.name for o in spec.description.output])
    print("MIL ops:", {t: sum(1 for o in prog.functions['main'].operations if o.op_type == t)
                       for t in sorted({o.op_type for o in prog.functions['main'].operations})})
    photos = sorted(os.path.join(ARGS.photos, f) for f in os.listdir(ARGS.photos) if f.lower().endswith((".jpg", ".png")))
    rows = []
    for p in photos:
        x = C.load_rgb512(p)
        ref = C.tflite_run(tfl, x)
        res = evaluate_program(prog, (x * 255.0).transpose(2, 0, 1)[None])
        out = list(res.values())[0][0, 0]
        res32 = evaluate_program(prog, (x * 255.0).transpose(2, 0, 1)[None], emulate_fp16=False)
        out32 = list(res32.values())[0][0, 0]
        mp_full = mediapipe_hair(p)
        h, w = mp_full.shape
        mine_full = upscale(out, w, h)
        row = dict(image=os.path.basename(p),
                   coreml_graph_vs_tflite_mae=float(np.abs(out - ref).mean()),
                   coreml_graph_vs_tflite_max=float(np.abs(out - ref).max()),
                   coreml_graph_vs_tflite_iou=C.iou(out, ref),
                   coreml_graph_fp16_noemu_mae=float(np.abs(out32 - ref).mean()),
                   vs_mediapipe_tasks_mae=float(np.abs(mine_full - mp_full).mean()),
                   vs_mediapipe_tasks_iou=C.iou(mine_full, mp_full),
                   hair_coverage=float((out >= 0.5).mean()))
        rows.append(row)
        print(json.dumps(row))
    agg = {k: float(np.mean([r[k] for r in rows])) for k in rows[0] if k != "image"}
    agg["min_iou_vs_tflite"] = float(min(r["coreml_graph_vs_tflite_iou"] for r in rows))
    print("MEAN", json.dumps(agg))
    report = dict(per_image=rows, mean=agg)
    if ARGS.report:
        os.makedirs(os.path.dirname(ARGS.report) or ".", exist_ok=True)
        json.dump(report, open(ARGS.report, "w"), indent=2)
    if agg["min_iou_vs_tflite"] < 0.97 or agg["coreml_graph_vs_tflite_mae"] > 0.02:
        sys.exit("converted graph deviates from TFLite more than expected")


if __name__ == "__main__":
    main()
