# Metrics

Every number in this file must come from a real measurement. **Phone numbers must come from a real
mid-range phone, not a simulator or emulator.** Nothing below has been measured on a phone yet. Each
`TBD — measure on device` cell has the exact steps to fill it under [How to measure](#how-to-measure).

Record the device, OS version, build mode and date next to every number.

## Summary

| Metric | Android `<device>` | iOS `<device>` |
|---|---|---|
| Detection inference, EfficientDet-Lite0 TFLite (median / p95 ms) | TBD — measure on device | TBD — measure on device |
| Breed classification, TFLite (median / p95 ms) | TBD — measure on device | TBD — measure on device |
| Breed classification, Core ML (median / p95 ms) | n/a (iOS only) | TBD — measure on device |
| Camera preview fps with detection running | TBD — measure on device | TBD — measure on device |
| Battery drain, 10 min live detection, adaptive skipping **off** | TBD — measure on device | TBD — measure on device |
| Battery drain, 10 min live detection, adaptive skipping **on** | TBD — measure on device | TBD — measure on device |
| Time to first insight token, clip analysis (s) | TBD — measure on device | TBD — measure on device |
| Cold start to first frame (ms) | TBD — measure on device | TBD — measure on device |
| Release build size (MB) | TBD — measure on device | TBD — measure on device |

## Measured offline (not phone numbers)

These come from `ml/README.md` and `ml/artifacts/metrics.json`. They were measured on the Oxford-IIIT
Pet `test` split (3,669 images) on an Apple M4 MacBook, so the accuracy and size figures are exactly
what ships.

| Breed model | Size | Test top-1 | Test top-5 |
|---|---|---|---|
| MobileNetV3-Small (not shipped, comparison) | — | 84.3 % | 98.7 % |
| EfficientNet-B0, Keras float32 (reference) | — | 91.66 % | 99.56 % |
| EfficientNet-B0 → TFLite float16 `breeds.tflite` (shipped) | 8.2 MB | 91.66 % | 99.56 % |
| EfficientNet-B0 → Core ML float16 `BreedClassifier.mlpackage` (shipped, iOS) | 8.4 MB | 91.69 % | 99.56 % |

**Mac-only latency. These are not device numbers and must not go on the resume:**

| Engine | Where | Median per image |
|---|---|---|
| TFLite, CPU/XNNPACK, from Python | Apple M4 MacBook | 14.0 ms |
| Core ML via coremltools (ANE/GPU) | Apple M4 MacBook | 0.58 ms |

---

## How to measure

### Common setup

```sh
cd app
cp dart_defines.example.json dart_defines.json   # real API_BASE_URL / API_TOKEN; SENTRY_DSN optional
flutter run --profile -t lib/main_production.dart --dart-define-from-file=dart_defines.json
```

- Use **profile** mode for every latency and fps number. Debug mode is JIT-compiled and several
  times slower; release mode has no DevTools.
- Turn on **Settings → Debug HUD**.
- The `log()` lines named below appear in **DevTools → Logging** (open the DevTools URL that
  `flutter run` prints). Use the filter box.
- Point the camera at a real cat or dog, or at a pet photo on another screen, so a box and breed label
  are showing.

### 1. Inference ms: detection and classification, per engine

The HUD shows:
- `detect N ms`: the latest detector call (isolate round trip, frame conversion included).
- `breed <engine> N ms`: the latest classifier call, wall clock, crop included. For Core ML this also
  includes the JPEG encode and the method channel.
- `inference avg / p95`: the whole per-frame processing time (detect plus any classify) over the
  scheduler's last 50 frames.

Steps, for each platform and, on iOS, for each engine (Settings → Breed engine → TFLite, then Core ML):
1. Keep a pet in view for 30 s so the scheduler is in `full` mode.
2. Screen-record the HUD for 30 s. Read 20 `detect` values and 20 `breed` values from the recording.
3. Sort each set. Median = the mean of the 10th and 11th values; p95 = the 19th value.
4. Also record the HUD's `inference avg` and `p95` at the end of the 30 s.
5. Optional cross-check: build with `"SENTRY_TRACES_SAMPLE_RATE": "1.0"` and a `SENTRY_DSN`. In Sentry
   → Performance, the `ml.inference` transactions `tflite detector` and `tflite breeds` (one in every
   30 calls is traced) show p50 and p95 directly.
6. Core ML-only time (without the crop and channel): in DevTools → Logging, filter `coreml`. The
   lines read `Core ML inference N ms`, measured around `VNImageRequestHandler.perform` in Swift.

Write the TFLite vs Core ML comparison (latency, plus the accuracy and size from the offline table)
and which engine you would ship and why into the summary and `ARCHITECTURE.md` ADR-4.

### 2. Camera preview fps with detection running

1. Same profile build, Live tab, HUD on, pet in view.
2. After 30 s, read `camera N fps` (the camera stream rate while detection runs) and
   `processed N fps` (frames that actually reached the model). Record both. Do this with adaptive
   skipping on, the default.

### 3. Battery drain: 10 minutes, adaptive skipping off, then on

Use a **release** build (profile mode adds overhead):

```sh
flutter run --release -t lib/main_production.dart --dart-define-from-file=dart_defines.json
```

1. Charge to about 90 %, then **unplug**. Set auto-lock / screen timeout to **Never** and brightness to
   a fixed value (turn auto-brightness off). Close other apps.
2. Settings → **Adaptive frame skipping off** → Settings → **Battery test** → **Start 10-minute
   test**. Keep the phone still, pointed at the same scene (a pet photo works), on that page.
3. When it finishes, tap **Copy for METRICS.md** and paste the row into the table below. Replace
   `<device>` with the phone model.
4. Let the phone cool for 10 min and recharge to the same starting level. Then repeat with
   **adaptive frame skipping on**, pointed at an **empty scene** for the first run of this mode (this
   shows the idle saving) and, if time allows, a second run with a pet in view.
5. Battery percent is coarse (1 % steps). If both runs show the same drop, run 20 min each instead
   and say so.

| Date | Device (OS) | Adaptive skipping | Battery | Avg processed fps |
|---|---|---|---|---|
| TBD | TBD — measure on device | OFF | TBD | TBD |
| TBD | TBD — measure on device | ON (empty scene) | TBD | TBD |

### 4. Time to first insight token (clip analysis)

Backend running (`cd backend && docker compose up --build`, or the deployed VM) with a real
`ANTHROPIC_API_KEY`, and the phone online.

1. Clips tab → record a 10 s clip. Do this 5 times.
2. **App side (what the user feels):** in DevTools → Logging, filter `first delta`. Each clip logs
   `Clip <id>: first delta Nms after socket open`. Median of the 5 runs, in seconds.
3. **Sentry (release builds):** Performance → transaction `clip.ws` → measurement
   `time_to_first_delta`.
4. **Backend side (model latency only):** `docker compose logs api | grep ttfdMs` shows the
   `vision first delta` lines with `ttfdMs`, measured from the start of the Claude call. The
   difference between the app and backend numbers is network plus WebSocket overhead.

Record the app-side median in the summary and both numbers in the notes.

### 5. Cold start

```sh
flutter run --profile --trace-startup -t lib/main_production.dart --dart-define-from-file=dart_defines.json
```

The app starts, then exits and writes `build/start_up_info.json`. Record `timeToFirstFrameMicros`
(÷ 1000 → ms). Force-quit the app between runs, run 5 times, take the median. For an OS-level number
that includes process start:
- Android: `adb shell am force-stop com.elysian12.pawsense && adb shell am start -W -n com.elysian12.pawsense/.MainActivity`
  → `TotalTime`.
- iOS: Xcode → Product → Profile → **App Launch** template.

### 6. Release build size

```sh
flutter build apk --release --analyze-size --target-platform android-arm64 \
  -t lib/main_production.dart --dart-define-from-file=dart_defines.json
flutter build ipa --release --analyze-size \
  -t lib/main_production.dart --dart-define-from-file=dart_defines.json
```

`--analyze-size` works only with `--release` and cannot be combined with `--split-debug-info`, so these
builds are not obfuscated. `build ipa` needs signing; without a team, use
`flutter build ios --release --analyze-size --no-codesign`. Record the total size each command prints. The breakdown also shows the three models: about 8 MB
for the breed model, plus the detector and YAMNet. After the first store upload, also record the
**download size** from Play Console (App size) and App Store Connect (App File Sizes), because that
is what users see.
