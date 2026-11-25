# Hair model: Core ML interface and measurements

`Sources/Resources/Models/HairSegmenter.mlpackage` (compiled by Xcode to `HairSegmenter.mlmodelc` in the app bundle) is the
MediaPipe hair segmenter (Google, Apache-2.0, see [licences/hair-segmenter.md](licences/hair-segmenter.md)) converted to Core ML on CI.
Reproduce: `.github/workflows/convert-model.yml` (workflow_dispatch) running `tools/convert_hair_model.py`, verified by
`tools/verify_hair_model.py` (Linux), `tools/verify_coreml_macos.py` (real Core ML runtime on a macOS runner) and
`tools/experiment_hair_input.py` (input experiments). The conversion is deterministic: weights are float16, 387 KB; the package is 0.6 MB.

## Exact interface

| | |
|---|---|
| Format | ML Program (`.mlpackage`), specification version 8, minimum deployment target iOS 17, float16 weights and compute, `computeUnits = .all` is fine |
| Input name | `image` |
| Input type | image (`MLFeatureType.image`), **512 x 512**, colour order **RGB** (Core ML converts BGRA / ARGB pixel buffers for you), 8-bit pixel values 0...255 |
| Input scaling | none to apply: the model divides by 255 itself (original model: mean 0, std 255). Do not normalise, do not subtract a mean |
| Output name | `hair_probability` |
| Output type | `MLMultiArray`, **float32**, shape **[1, 1, 512, 512]** (N, C, H, W), row major, `[0, 0, y, x]`, origin top left, same orientation as the input image |
| Output values | **probability that the pixel is hair, 0...1** (sigmoid of the hair-minus-background logit, same as MediaPipe's softmax "hair" confidence). 0.5 = decision threshold; the map is nearly binary (few pixels between 0.05 and 0.95), so soften the edge in post-processing |
| Output size | 512 x 512, always. Upscale it (bilinear) to the photo or crop it was taken from |

Swift (what `CoreMLHairSegmenter` in `Sources/Engine/HairSegmenter.swift` already does): Vision `VNCoreMLRequest` with
`imageCropAndScaleOption = .scaleFill`, then `VNCoreMLFeatureValueObservation.featureValue.multiArrayValue`, read with the array strides.
`HairSegmenter.plane(from:hairChannel:)` handles `[1,1,512,512]` with `channels = 1` and sees values already in 0...1 (no logit conversion).

## Pre-processing

* **Stretch the square to 512 x 512** (Vision `.scaleFill`). This is what MediaPipe's own ImageSegmenter does (verified: our output
  matches MediaPipe Tasks, see below). Feed square inputs (the app already draws a square canvas) so stretching does not distort.
* Pad with mid grey (0.5, as the app does) where a crop leaves the photo; no false hair appeared on the grey padding in our tests.
* Use upright pixels (apply the EXIF orientation first); the model is not rotation invariant (upright heads work).
* No alpha channel needed. (The original TFLite model has a 4th "previous mask" input channel that MediaPipe feeds as zeros for single photos; it was removed.)

## What works best on real photos

Ten real Pexels portraits (head and shoulders, half length, a full-body shot, a side-lit face, dark and black-and-white; table below) were run through the
model with five inputs. There is no ground truth for stock photos, so the table uses proxies (mean of 10 photos): hair blobs = number of separate
hair regions at p >= 0.5 (fewer = cleaner, spurious specks count as blobs), main blob = share of hair area in the largest region. Overlay sheets are
produced by the CI job (artifact `hair-segmenter-coreml`, `out/experiments`) and were checked by eye.

| Input to the model | hair blobs | main blob | verdict |
|---|---|---|---|
| Whole photo, stretched to 512 (any aspect) | 5.2 | 0.962 | good when the head is large; distorts tall/wide photos; hair of a small head is coarse |
| Whole photo, letterboxed to a square | 8.6 | 0.927 | **worst**: the head gets small, specks on clothes and background, a full-body shot loses its hair |
| Face crop 2.6 x 3.2 face widths/heights | 7.2 | 0.961 | hair tops and long hair get clipped |
| **Face crop 3.4 x 4.2 (centre 0.55 face heights below the face centre), square, grey padding** | **4.3** | 0.960 | **best**: cleanest, robust for small faces (full-body shot: whole-photo input produced a hair blob in the sky, the crop did not) |
| Face crop 4.4 x 5.4 | 6.0 | 0.944 | head too small, specks return |

The same five inputs were repeated on the 23 licensed fixtures in `Tests/Fixtures/portraits` (curly, afro, long, bob, silver, bald, beanie, hood, from
behind, low light, a group of three, a landscape without a person). The blob count is noisier there (curls fragment the mask: stretch 12.8, letterbox 9.2, tight 12.2, **app 10.7**,
wide 7.1; main-blob share 0.93 / 0.91 / 0.94 / **0.96** / 0.97), so the decision rests on the overlay sheets as well:

* 2.6 x 3.2 clips the top of big hair (afro, long wavy): a straight horizontal cut across the hair.
* 4.4 x 5.4 makes the head small: hair leaks onto garments (from-behind shot, hood shot) and the chin/neck of a small face is marked.
* Whole photo stretched or letterboxed is fine for large heads but loses small heads (group of three: no hair at all) and
  returns specks in the background; the face crop keeps full quality.
* 3.4 x 4.2 had none of these faults on any of the 33 photos.

**Recommendation: use a face-centred square crop (about 3.4 face widths wide, 4.2 face heights tall, centre shifted down by 0.55 face height from the face centre), stretched to 512. This is exactly what `HairSession.computeMatte` does.** Use the whole photo only when no
face is found or the face is already large (crop side >= 0.9 of the long side, as the code does). Keep the head between roughly 20 and 40 percent of
the crop width.

## Quirks and limits (from the model card and our tests)

* A photo with no person can still produce hair (whole-photo input of a mountain landscape gave 19 percent hair coverage and a soft map): only trust the matte when a face was found (the engine's `noFace` hint) and clear it far away from the face.
* One person per window. Several people merge into one hair mask: crop around the chosen face (already done) and fade the window edge.
* Strong one-sided face shadow can be read as hair (seen on a side-lit male portrait, whole-photo and crop inputs alike): clear the inner face (Vision face rect, ellipse) from the matte before
  colouring.
* Thin long strands, braids, mohawks and hair under hats/hoods may be incomplete (model card). Hair behind clothing/arms is cut by the model, flyaway strands are not found: the guided-filter refine in the engine fixes edges.
* Output is crisp at 512 px: upscaling then guided filtering is needed for a soft hair edge. Expect an IoU of about 0.8 on diverse selfies (model card: 81.5 percent).
* Latency: the network is small (0.8 MB) but uses rank-5 tensors for the un-pooling; Core ML may place part of it off the Neural Engine. Measured on a CI runner CPU: see `coreml-runtime-report` below.

## Verification (numbers)

All on the same 10 portraits (Pexels, not stored in the repo), original = TFLite float32 run with the TFLite interpreter (4th channel 0, softmax).

| Check | Result |
|---|---|
| Re-implemented PyTorch graph vs TFLite (before Core ML conversion) | MAE 2e-8 to 9e-7, max abs error <= 2.8e-3 (a single pixel), IoU@0.5 = **1.000** on every image |
| Saved .mlpackage reloaded into PyMIL, weights as shipped (float16), evaluated with a reference interpreter that rounds every float16 op | mean MAE **2.7e-4**, max abs 0.068 (single edge pixels), mean IoU@0.5 **0.998**, min IoU 0.993 |
| The same converted graph vs MediaPipe Tasks ImageSegmenter output (full production pipeline, original-size photo, bilinear upscale) | mean MAE 1.6e-3, mean IoU 0.987 (min 0.958 on the image with only 1.2 percent hair; difference is the resize path) |
| Real Core ML runtime (macOS runner, `tools/verify_coreml_macos.py`) | mean MAE 6.1e-4, mean IoU@0.5 **0.996**, min 0.990 |

Core ML cannot run on Linux: the first rows prove the graph and the weights on Linux, the macOS job runs the real Core ML runtime, and `Tests/HairModelTests.swift` repeats the sanity checks inside the app's test bundle.

## Core ML runtime on macOS

CI job `verify-coreml-macos` (macos-26 runner, coremltools 9.0, `MLModel.predict`, same 10 portraits; compute units CPU_ONLY and ALL gave identical numbers because the runner VM has no Neural Engine):

| Metric vs the original TFLite model | Result |
|---|---|
| Input / output as loaded by Core ML | input `image` (imageType), output `hair_probability`, shape (1, 1, 512, 512), min 0.0, max 1.0 |
| Mean absolute error | **6.1e-4** (worst image 1.8e-3) |
| IoU at 0.5 | mean **0.996**, minimum 0.990 |
| Largest single-pixel difference | 0.10 (float16 rounding at edge pixels) |
| Hair coverage difference | at most 0.1 percentage points of the frame |
| Latency on the runner CPU | about 8 to 15 ms per 512 x 512 prediction (first call 60 ms). A real iPhone Neural Engine / GPU timing was not measured |

The ML Program therefore runs correctly in the real Core ML runtime. Not covered by this job: the Neural Engine path on a device.

## Tests

`Tests/HairModelTests.swift` (macOS CI): checks the bundled model's input/output description (`image` 512 x 512, `hair_probability` [1,1,512,512]),
a flat grey picture (no hair, valid 0...1 output), and, when portrait fixtures exist in `Tests/Fixtures/*.jpg|png`, hair coverage between 0.4 and 65 percent, a mostly binary map and
hair mostly in the upper half of the frame, through the same Vision path the app uses.
