#!/usr/bin/env python3
"""Convert the MediaPipe hair segmenter (hair_segmenter.tflite, Apache-2.0) to Core ML.

Why a custom converter: the TFLite graph contains three MediaPipe *custom* ops
(MaxPoolingWithArgmax2D, MaxUnpooling2D, Convolution2DTransposeBias) that tf2onnx / onnx2torch /
coremltools' TFLite path cannot read. The flatbuffer is therefore parsed directly and re-expressed as a
small PyTorch module (every op is plain conv / depthwise conv / PReLU / add / concat / pool / unpool /
transposed conv), which is then traced and converted with coremltools (ML Program, iOS 17 target).

Changes versus the original network (all mathematically exact, see docs/licences/hair-segmenter.md):
  * the 4th input channel (MediaPipe's temporal prior channel, always 0 for single images) is dropped:
    the first conv keeps only its 3 RGB input-channel weights;
  * the 2-class output (background, hair) + softmax is folded into ONE channel: p(hair) = sigmoid(l1 - l0),
    done by subtracting the last transposed-conv's two output-channel kernels/biases;
  * max-unpooling is expressed with pixel_unshuffle / argmax / pixel_shuffle (tensor rank <= 5, supported by Core ML).

Usage:
  python tools/convert_hair_model.py --work build/model --out Sources/Resources/Models/HairSegmenter.mlpackage \
         [--verify-dir photos] [--report build/model/report.json]
Subcommands are selected with flags: --no-coreml skips the coremltools step (torch-only verification).
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.request

import numpy as np

MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/image_segmenter/hair_segmenter/"
             "float32/latest/hair_segmenter.tflite")
MODEL_SHA256 = "2628cf3ce5f695f604cbea2841e00befcaa3624bf80caf3664bef2656d59bf84"
SIZE = 512


# --------------------------------------------------------------------------------------------------
# fetch
# --------------------------------------------------------------------------------------------------
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(work):
    os.makedirs(work, exist_ok=True)
    path = os.path.join(work, "hair_segmenter.tflite")
    if not os.path.exists(path):
        print("downloading", MODEL_URL)
        urllib.request.urlretrieve(MODEL_URL, path)
    digest = sha256_file(path)
    if digest != MODEL_SHA256:
        sys.exit(f"sha256 mismatch: {digest} != {MODEL_SHA256}")
    print("sha256 ok", digest, os.path.getsize(path), "bytes")
    return path


# --------------------------------------------------------------------------------------------------
# flatbuffer parsing (python package `tflite`, generated flatbuffer bindings of the TFLite schema)
# --------------------------------------------------------------------------------------------------
class Graph:
    """Constants + ordered op list of the single TFLite subgraph."""

    def __init__(self, path):
        import tflite
        self.t = tflite
        buf = open(path, "rb").read()
        model = tflite.Model.GetRootAsModel(buf, 0)
        assert model.SubgraphsLength() == 1
        sg = model.Subgraphs(0)
        self.sg = sg
        BO = tflite.BuiltinOperator
        names = {v: k for k, v in BO.__dict__.items() if not k.startswith("_") and isinstance(v, int)}
        self.consts = {}
        self.shapes = {}
        for i in range(sg.TensorsLength()):
            t = sg.Tensors(i)
            shape = [int(s) for s in t.ShapeAsNumpy()] if t.ShapeLength() else []
            self.shapes[i] = shape
            data = model.Buffers(t.Buffer()).DataAsNumpy()
            if isinstance(data, np.ndarray) and data.size:
                assert t.Type() == tflite.TensorType.FLOAT32, "only float32 constants expected"
                self.consts[i] = np.frombuffer(data.tobytes(), dtype=np.float32).reshape(shape).copy()
        self.inputs = [int(i) for i in sg.InputsAsNumpy()]
        self.outputs = [int(i) for i in sg.OutputsAsNumpy()]
        self.ops = []
        for i in range(sg.OperatorsLength()):
            op = sg.Operators(i)
            oc = model.OperatorCodes(op.OpcodeIndex())
            code = max(oc.BuiltinCode(), oc.DeprecatedBuiltinCode())
            kind = oc.CustomCode().decode() if code == BO.CUSTOM else names[code]
            rec = dict(kind=kind, ins=[int(j) for j in op.InputsAsNumpy()],
                       outs=[int(j) for j in op.OutputsAsNumpy()])
            if kind == "CONV_2D":
                o = self._opts(op, tflite.Conv2DOptions)
                rec.update(padding=o.Padding(), stride=(o.StrideH(), o.StrideW()), act=o.FusedActivationFunction(),
                           dilation=(o.DilationHFactor(), o.DilationWFactor()))
            elif kind == "DEPTHWISE_CONV_2D":
                o = self._opts(op, tflite.DepthwiseConv2DOptions)
                rec.update(padding=o.Padding(), stride=(o.StrideH(), o.StrideW()), act=o.FusedActivationFunction(),
                           dilation=(o.DilationHFactor(), o.DilationWFactor()), mult=o.DepthMultiplier())
            elif kind == "ADD":
                rec.update(act=self._opts(op, tflite.AddOptions).FusedActivationFunction())
            elif kind == "CONCATENATION":
                o = self._opts(op, tflite.ConcatenationOptions)
                rec.update(axis=o.Axis(), act=o.FusedActivationFunction())
            elif kind in ("MaxPoolingWithArgmax2D", "MaxUnpooling2D", "Convolution2DTransposeBias"):
                raw = bytes(op.CustomOptionsAsNumpy().tobytes())
                rec["custom"] = np.frombuffer(raw, dtype="<i4").tolist()
            elif kind == "PRELU":
                pass
            else:
                raise NotImplementedError(kind)
            self.ops.append(rec)

    @staticmethod
    def _opts(op, cls):
        o = cls()
        t = op.BuiltinOptions()
        o.Init(t.Bytes, t.Pos)
        return o


# --------------------------------------------------------------------------------------------------
# PyTorch re-implementation of the graph
# --------------------------------------------------------------------------------------------------
def build_module(graph, fold_output=True, drop_alpha_channel=True):
    import torch
    import torch.nn as nn
    import torch.nn.functional as F

    # tflite enum Padding: SAME=0, VALID=1 (builtin ops); custom ops use TfLitePadding: SAME=1, VALID=2
    ops = graph.ops

    class Net(nn.Module):
        def __init__(self):
            super().__init__()
            self.ops = ops
            self.params = nn.ParameterDict()
            for i, a in graph.consts.items():
                arr = a
                self.params[str(i)] = nn.Parameter(torch.from_numpy(arr.copy()), requires_grad=False)
            self.first_conv_out = ops[0]["outs"][0]
            self.last_op = len(ops) - 1
            self.debug = None  # dict to collect intermediates (NCHW torch tensors) when set

        def p(self, i):
            return self.params[str(i)]

        # ---- individual ops (NCHW internally) ----
        def conv(self, x, op, idx):
            w = self.p(op["ins"][1]).permute(0, 3, 1, 2)       # OHWI -> OIHW
            b = self.p(op["ins"][2])
            if idx == 0 and drop_alpha_channel:
                w = w[:, :3]                                   # 4th (prior) channel is always zero
            kh, kw = int(w.shape[2]), int(w.shape[3])
            sh, sw = op["stride"]
            dh, dw = op["dilation"]
            if op["padding"] == 0:                              # SAME (effective kernel includes dilation)
                x = self.same_pad(x, graph.shapes[op["ins"][0]], (kh - 1) * dh + 1, (kw - 1) * dw + 1, sh, sw)
            return F.conv2d(x, w.contiguous(), b, stride=(sh, sw), dilation=(dh, dw))

        def dwconv(self, x, op):
            w = self.p(op["ins"][1]).permute(3, 0, 1, 2)       # [1,H,W,C] -> [C,1,H,W]
            b = self.p(op["ins"][2])
            assert op["mult"] == 1 and op["dilation"] == (1, 1)
            kh, kw = int(w.shape[2]), int(w.shape[3])
            sh, sw = op["stride"]
            if op["padding"] == 0:
                x = self.same_pad(x, graph.shapes[op["ins"][0]], kh, kw, sh, sw)
            return F.conv2d(x, w.contiguous(), b, stride=(sh, sw), groups=int(w.shape[0]))

        @staticmethod
        def same_pad(x, nhwc, kh, kw, sh, sw):
            h, w = nhwc[1], nhwc[2]                              # static python ints (no traced shape ops)
            oh, ow = -(-h // sh), -(-w // sw)
            th = max((oh - 1) * sh + kh - h, 0)
            tw = max((ow - 1) * sw + kw - w, 0)
            if th == 0 and tw == 0:
                return x
            return F.pad(x, (tw // 2, tw - tw // 2, th // 2, th - th // 2))

        @staticmethod
        def _swap_mid(t):
            # window positions dy*2+dx -> dx*2+dy (self-inverse): [0,1,2,3] -> [0,2,1,3]
            return torch.cat([t[:, :, 0:1], t[:, :, 2:3], t[:, :, 1:2], t[:, :, 3:4]], dim=2)

        def pool(self, x, nhwc):
            # MaxPoolingWithArgmax2D, 2x2 stride 2. Returns (max, one-hot window-position mask).
            # MediaPipe scans the window column-major (index = dx*2+dy) and keeps the FIRST maximum, so ties
            # (frequent in flat / dark image areas) resolve exactly like the original op.
            n, h, w, c = nhwc
            u = F.pixel_unshuffle(x, 2).reshape(n, c, 4, h // 2, w // 2)   # channel order: dy*2+dx
            uc = self._swap_mid(u)                                          # column-major scan order
            idx = torch.argmax(uc, dim=2, keepdim=True)
            ar = torch.arange(4, dtype=idx.dtype).reshape(1, 1, 4, 1, 1)
            mask = self._swap_mid((ar == idx).to(x.dtype))                  # back to dy*2+dx order
            return u.amax(dim=2), mask

        @staticmethod
        def unpool(v, mask, nhwc):
            n, h, w, c = nhwc                                   # shape of the pooled (small) tensor
            z = (mask * v.unsqueeze(2)).reshape(n, c * 4, h, w)
            return F.pixel_shuffle(z, 2)

        def convt(self, x, op, idx):
            w = self.p(op["ins"][1])                            # [O,kH,kW,I]
            b = self.p(op["ins"][2])
            if fold_output and idx == self.last_op:
                w = (w[1:2] - w[0:1])                           # logit(hair) - logit(background)
                b = (b[1:2] - b[0:1])
            w = w.permute(3, 0, 1, 2).contiguous()              # -> [I,O,kH,kW] for conv_transpose2d
            kh, kw = int(w.shape[2]), int(w.shape[3])
            h, wd = graph.shapes[op["ins"][0]][1:3]
            y = F.conv_transpose2d(x, w, b, stride=2)           # size (h-1)*2+k
            # SAME: output = 2*in; crop the forward-conv SAME padding (before = (k-2)//2)
            ph, pw = max(kh - 2, 0) // 2, max(kw - 2, 0) // 2
            return y[:, :, ph:ph + 2 * h, pw:pw + 2 * wd]

        def forward(self, img):
            """img: [1,3,512,512] RGB in 0..255 (Core ML image pixel values) -> p(hair) [1,1,512,512]
            (or [1,2,512,512] softmax(background, hair) if fold_output=False)."""
            t = {self.graph_input: img * (1.0 / 255.0)}       # model was trained with mean 0, std 255
            masks = {}
            for idx, op in enumerate(self.ops):
                k = op["kind"]
                ins = op["ins"]
                if k == "CONV_2D":
                    y = self.conv(t[ins[0]], op, idx)
                    t[op["outs"][0]] = y
                elif k == "DEPTHWISE_CONV_2D":
                    t[op["outs"][0]] = self.dwconv(t[ins[0]], op)
                elif k == "PRELU":
                    a = self.p(ins[1]).reshape(-1)
                    t[op["outs"][0]] = F.prelu(t[ins[0]], a)
                elif k == "ADD":
                    t[op["outs"][0]] = t[ins[0]] + t[ins[1]]
                elif k == "CONCATENATION":
                    assert op["axis"] in (-1, 3)
                    t[op["outs"][0]] = torch.cat([t[i] for i in ins], dim=1)
                elif k == "MaxPoolingWithArgmax2D":
                    v, m = self.pool(t[ins[0]], graph.shapes[ins[0]])
                    t[op["outs"][0]] = v
                    masks[op["outs"][1]] = m                    # 'indices' tensor == position mask
                elif k == "MaxUnpooling2D":
                    t[op["outs"][0]] = self.unpool(t[ins[0]], masks[ins[1]], graph.shapes[ins[0]])
                elif k == "Convolution2DTransposeBias":
                    t[op["outs"][0]] = self.convt(t[ins[0]], op, idx)
                else:
                    raise NotImplementedError(k)
                if self.debug is not None:
                    self.debug[op["outs"][0]] = t[op["outs"][0]]
            out = t[graph.outputs[0]]
            if fold_output:
                return torch.sigmoid(out)
            return torch.softmax(out, dim=1)

    net = Net()
    net.graph_input = graph.inputs[0]
    return net.eval()


# --------------------------------------------------------------------------------------------------
# verification against the original TFLite model (ai-edge-litert) and MediaPipe Tasks
# --------------------------------------------------------------------------------------------------
def tflite_run(path, rgb01):
    """rgb01: float32 [512,512,3] in 0..1. Returns p(hair) [512,512] from the original model."""
    from ai_edge_litert.interpreter import Interpreter
    it = Interpreter(model_path=path)
    it.allocate_tensors()
    x = np.concatenate([rgb01, np.zeros((SIZE, SIZE, 1), np.float32)], -1)[None]   # 4th channel = 0
    it.set_tensor(it.get_input_details()[0]["index"], x)
    it.invoke()
    o = it.get_tensor(it.get_output_details()[0]["index"])[0]
    e = np.exp(o - o.max(-1, keepdims=True))
    return (e / e.sum(-1, keepdims=True))[..., 1]


def iou(a, b, thr=0.5):
    a, b = a >= thr, b >= thr
    u = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / u) if u else 1.0


def load_rgb512(path):
    from PIL import Image
    im = Image.open(path).convert("RGB").resize((SIZE, SIZE), Image.BILINEAR)
    return np.asarray(im, dtype=np.float32) / 255.0


def verify_torch(net, tfl_path, photos):
    import torch
    rows = []
    for p in photos:
        x = load_rgb512(p)
        ref = tflite_run(tfl_path, x)
        with torch.no_grad():
            out = net(torch.from_numpy(x * 255.0).permute(2, 0, 1)[None]).numpy()[0, 0]
        rows.append(dict(image=os.path.basename(p), mae=float(np.abs(out - ref).mean()),
                         max_abs=float(np.abs(out - ref).max()), iou_05=iou(out, ref),
                         ref_cov=float((ref >= 0.5).mean()), new_cov=float((out >= 0.5).mean())))
        print(rows[-1])
    return rows


# --------------------------------------------------------------------------------------------------
# Core ML conversion
# --------------------------------------------------------------------------------------------------
def convert_coreml(net, out_path, precision="fp16"):
    import coremltools as ct
    import torch
    example = torch.rand(1, 3, SIZE, SIZE) * 255.0
    with torch.no_grad():
        traced = torch.jit.trace(net, example, strict=False)
    prec = ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, SIZE, SIZE), color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="hair_probability", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=prec,
        compute_units=ct.ComputeUnit.ALL,
    )
    mlmodel.short_description = ("Hair segmentation (MediaPipe hair segmenter, Apache-2.0, converted to Core ML). "
                                 "Input: 512x512 RGB image. Output: per-pixel probability of hair, 1x1x512x512, 0..1.")
    mlmodel.author = "Google MediaPipe (converted by Ecom Swift LLC)"
    mlmodel.license = "Apache License 2.0"
    mlmodel.version = "1"
    mlmodel.user_defined_metadata["source_url"] = MODEL_URL
    mlmodel.user_defined_metadata["source_sha256"] = MODEL_SHA256
    mlmodel.user_defined_metadata["preprocessing"] = "stretch to 512x512, RGB; the 1/255 scaling is inside the model"
    mlmodel.save(out_path)
    return mlmodel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="build/model")
    ap.add_argument("--out", default="Sources/Resources/Models/HairSegmenter.mlpackage")
    ap.add_argument("--verify-dir", default=None, help="folder with portrait jpg/png for the TFLite vs torch comparison")
    ap.add_argument("--report", default=None)
    ap.add_argument("--no-coreml", action="store_true")
    ap.add_argument("--precision", default="fp16", choices=["fp16", "fp32"])
    args = ap.parse_args()

    path = fetch(args.work)
    graph = Graph(path)
    print(len(graph.ops), "ops;", len(graph.consts), "constant tensors")
    net = build_module(graph)
    report = {"source_sha256": MODEL_SHA256}
    if args.verify_dir:
        photos = sorted(os.path.join(args.verify_dir, f) for f in os.listdir(args.verify_dir)
                        if f.lower().endswith((".jpg", ".jpeg", ".png")))
        report["torch_vs_tflite"] = verify_torch(net, path, photos)
    if not args.no_coreml:
        if os.path.exists(args.out):
            import shutil
            shutil.rmtree(args.out)
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        convert_coreml(net, args.out, args.precision)
        report["coreml_saved"] = args.out
        print("saved", args.out)
    if args.report:
        os.makedirs(os.path.dirname(args.report) or ".", exist_ok=True)
        json.dump(report, open(args.report, "w"), indent=2)


if __name__ == "__main__":
    main()
