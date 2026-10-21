# DepthPolyp-iOS

A minimal SwiftUI iPhone demo for **DepthPolyp**, with a bundled dense FP16 Core ML model. Camera frames are processed on device using Core ML with CPU and Apple Neural Engine enabled.

The app shows the camera frame, segmentation overlay, binary mask, relative depth visualization, and timing. This release contains one unquantized, unpruned model. FP16 refers to floating-point precision.

## Run

Requires Xcode with an iOS 18 SDK or newer and an iPhone running iOS 18 or newer. No Python, package manager, or external Swift dependencies are needed to build the app.

1. Clone this repository and open `DepthPolypLive.xcodeproj`.
2. Select the **DepthPolypLive** scheme and your connected iPhone.
3. In **Signing & Capabilities**, select your own development team and a unique bundle identifier.
4. Build and run, then allow camera access.

The model is included under `Models/`; there is no additional download. A simulator build can check compilation, but live camera use and Neural Engine performance require a physical device.

Unsigned build check, from the repository root:

```bash
xcodebuild -project DepthPolypLive.xcodeproj \
  -scheme DepthPolypLive -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/DepthPolyp-iOS-build \
  CODE_SIGNING_ALLOWED=NO build
```

Optionally verify the bundled model files with Python 3:

```bash
python3 scripts/verify_model.py
```

## Model and inference

| Item | Value |
| --- | --- |
| Package | `Models/DepthPolyp_Kvasir_coreml_fp16.mlpackage` |
| Format | Core ML ML Program, dense FP16 |
| Input | `image`, Float16 tensor `[1, 3, 224, 224]` |
| Preprocessing | Center crop to square, resize to 224 × 224, RGB / 255 |
| Outputs | `segmentation` and `depth`, each `[1, 1, 224, 224]` |
| Mask | Segmentation probability ≥ 0.30 |
| Depth display | Per-frame min–max color visualization of relative depth |
| Compute policy | `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` |

Segmentation is already sigmoid-activated; the app applies the threshold directly to its probabilities. Only the depth visualization uses per-frame normalization. Model loading or prediction errors leave prediction panels empty and display an error status.

The compute policy enables CPU and Neural Engine execution; Core ML chooses the placement of individual operations. Depth colors are a relative visualization, not metric distance measurements.

## Timing

**Model ms** measures the synchronous `model.prediction` call. **Model FPS** is `1000 / model ms`; the mean uses the mean model latency over the recent samples. **Pipeline ms** additionally includes frame conversion and result rendering on the inference queue. These values exclude camera acquisition, waiting before processing, and screen presentation. They do not measure delivered camera/display FPS. Busy frames are dropped.

For comparisons, use a Release build on the same physical iPhone, discard warm-up frames, and record the device, OS version, thermal state and sample count. No fixed speed or accuracy claim is made by this demo.

## Source and license

The iOS app and model were extracted from [ReaganWu/DepthPolyp](https://github.com/ReaganWu/DepthPolyp). The original MIT copyright notice is preserved in [LICENSE](LICENSE). Model file hashes are recorded in [Models/SHA256.json](Models/SHA256.json).

This repository contains the iOS inference demo and its model. Research training workflows and datasets remain in the original project. This is research/demo software, not a clinical diagnostic tool.
