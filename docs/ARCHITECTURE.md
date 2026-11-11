# Architecture

PawSense is a Flutter app (`app/`) with a small Node.js backend (`backend/`) and a one-time training
pipeline (`ml/`). Everything that can run on the phone does; only clip analysis goes to the cloud.

```
┌──────────────────────────── Flutter app ─────────────────────────────┐
│                                                                      │
│  Camera (image stream) ──► FrameScheduler ──► TFLite isolate         │
│        │                    (adaptive skip)    ├─ EfficientDet-Lite0 │
│        │                                       └─ Breed classifier ──┼─► LiveDetectionBloc ─► UI (boxes, breed, FPS/ms HUD)
│        │                                          (or Core ML via    │
│        │                                           MethodChannel)    │
│        │                                                             │
│  Mic (record, 16 kHz PCM) ──► YAMNet (isolate) ───────────────────── ┼─► SoundBloc ─► UI + feed entry
│        │                                                             │
│  Record clip (10 s) ─► keyframes (5) ─► Drift upload queue ─► REST ──┼──► POST /v1/clips ──┐
│                                                                      │                     │
│  InsightsFeed (Drift) ◄── ClipAnalysisBloc ◄── WebSocket ◄───────────┼──── WS /v1/stream ◄─┤
│                                                                      │                     │
│  Sentry: errors + perf spans (inference, upload, ws)                 │                     │
└──────────────────────────────────────────────────────────────────────┘                     │
                                                                                             │
┌──────────────────────── Node.js backend ─────────────────────────────┐                     │
│  Fastify ── /v1/clips (multipart) ── JobStore ── VisionService ──────┼─► Claude (claude-opus-5-5,
│        └─── /v1/stream?jobId=… (WebSocket) ◄── streamed deltas ◄─────┤    streaming, images)
└──────────────────────────────────────────────────────────────────────┘
```

The WebSocket and REST contract is in [`WS_PROTOCOL.md`](WS_PROTOCOL.md). The release pipeline is in
[`RELEASE.md`](RELEASE.md). How the models were trained is in [`../ml/README.md`](../ml/README.md).

## Code layout

| Layer | Where | Rule |
|---|---|---|
| App shell | `lib/app/` | `bootstrap()` builds the get_it graph (no codegen); `createRouter()` is a go_router `StatefulShellRoute` with four tabs |
| ML engine | `lib/ml/` | No Flutter UI. Used only through `PetDetector`, `BreedClassifier`, `SoundClassifier`, so every bloc is tested with fakes |
| Data | `lib/data/` | Drift database and DAOs, the dio/WebSocket client, the sync service |
| Features | `lib/features/<name>/` | `data/` → `domain/` → `presentation/` (bloc/cubit + widgets) |

`clip_analysis` and `insights_feed` have all three layers because they own entities and
repositories (`Clip`, `ClipRepository`, `Insight`, `InsightsRepository`). `live_detection`, `sound`,
`settings` and `onboarding` have only `presentation/`. Their domain is the ML interfaces in `lib/ml/`
(plus `permission_handler` for onboarding), and a `domain/` folder that re-exported those
interfaces would be empty indirection.

---

## Decision records

Each ADR is short: the decision, why, and what it costs. The numbers that need a real phone are in
[`METRICS.md`](METRICS.md) and are still **TBD**.

### ADR-1: One long-lived inference isolate, not `compute()` per frame

**Decision.** `TfliteIsolate` (`lib/ml/tflite_isolate.dart`) spawns one isolate on the first model
load and keeps it for the app's lifetime. It owns every TFLite interpreter (detector, breed, YAMNet).
The main isolate sends typed task objects through a `SendPort` and gets typed results back.

**Why.**
- `compute()` spawns a fresh isolate every call. That costs milliseconds before any work starts, and
  the new isolate would have to rebuild the interpreter each time: parse the model, compile the
  GPU/Metal delegate, allocate tensors and warm up. At 30 fps that is the whole budget.
- Interpreters are not thread-safe and hold native memory. One owner keeps one copy of each model in
  memory and makes ownership clear.
- Asset bytes are read with `rootBundle` on the main isolate (the worker has no platform channels)
  and sent once at load.

**Delegates.** GPU on Android and Metal on iOS are tried first. The first candidate that loads *and*
survives a warm-up run wins, otherwise CPU. The CPU path already uses XNNPACK by default. An explicit
`XNNPackDelegate` segfaults natively in tflite_flutter 0.12.1 on Android, so it is not a candidate.

**Cost.** One extra isolate's memory for the app's lifetime. The isolate is spawned lazily, so
building the DI graph in tests spawns nothing.

### ADR-2: Frame conversion inside the isolate, with no per-frame allocation

**Decision.** `FrameData.fromCameraImage` copies the camera planes out on the main isolate (the
`CameraImage` buffers are reused by the plugin). `frame_converter.dart` then runs inside the isolate
and writes RGB straight into a preallocated input buffer.

- **Formats.** Android streams `yuv420` (three planes; U/V are subsampled 2×2 and may be interleaved
  with pixel stride 2). iOS streams `bgra8888` (one plane, 4 bytes per pixel). YUV is converted with
  BT.601 in 10-bit fixed point.
- **Rotation.** The sensor is landscape. For every *output* pixel the converter maps the upright
  coordinate back to the sensor coordinate using `sensorOrientation`, so rotation costs no extra pass.
- **One fused pass.** Crop, rotate, resize (320×320 for EfficientDet-Lite0, 224×224 for the breed
  crop) and colour conversion all happen per output pixel. There is no full-size RGB intermediate,
  and the same `out` buffer is reused every frame. The `image` package is not used on this hot path
  because each of its helpers allocates a full image.
- **Boxes.** A crop is stretched to fill the output, so a detector box maps straight back to the
  upright preview in normalized [0,1] coordinates (`Detection.box`).

**Cost.** Nearest-neighbour sampling, which is fine for a 640×480 → 320 downscale. Switch to bilinear
if small-object recall suffers. Front-camera mirroring is not undone.

### ADR-3: Drop frames, never queue them, and adapt the rate with `FrameScheduler`

**Decision.** At most one frame per model is in flight. `TfliteIsolate.run` throws when busy, and
`FrameScheduler.shouldProcess()` drops every frame that arrives while one is processing.

**Why drop.** A queue only adds latency (the boxes would describe the past) and memory (a YUV frame at
the medium preset is about 0.5 MB). The newest frame is always the most useful one.

**Adaptive frame skipping** (`lib/ml/frame_scheduler.dart`):
- Target interval = `max(minInterval 33 ms, avgInferenceMs × k)`, so a slow device does not run
  saturated.
- **Idle:** no pet for 5 s → about 2 fps (500 ms interval).
- **Low battery:** below 20 % (polled every minute through `battery_plus`) → about 2 fps.
- **Thermal:** the scheduler has a `thermalThrottled` input (1 fps), but **no thermal-state platform
  source is wired**. The spec lists it as the first thing to cut.
- Battery and thermal win over a detected pet, because they protect the device.
- **Back to full rate** on the first frame that detects a pet.
- Stats exposed to the HUD: processed fps, dropped frames, average and p95 inference ms, mode.

Settings has an "adaptive skipping" switch. When it is off, a fixed-rate scheduler still drops frames
while busy but ignores idle and battery. The Battery Test page (Settings) runs 10 minutes in either
mode so the before/after drain can be measured. The savings are **TBD — measure on device** (see
METRICS.md).

### ADR-4: Breed model: EfficientNet-B0, both engines, classify sparingly, smooth with EMA

**Model choice** (full numbers in `ml/README.md`, Oxford-IIIT Pet test split, 3,669 images):

| Backbone | Params | Top-1 | Top-5 |
|---|---|---|---|
| MobileNetV3-Small | 0.96 M | 84.3 % | 98.7 % |
| **EfficientNet-B0 (shipped)** | 4.10 M | **91.6 %** | **99.6 %** |

B0 is 7.3 points more accurate. The classifier runs far less often than the detector (below), so its
extra cost matters less than its accuracy. EfficientNet-Lite0 is not in `keras.applications`; B0 is
the closest.

**Engines.** The same Keras model is exported twice, both fp16: TFLite `breeds.tflite` is 8.2 MB
(91.66 % top-1) and Core ML `BreedClassifier.mlpackage` is 8.4 MB (91.69 %, a one-image difference
from fp16 rounding). Normalization layers live inside the model, so Dart and Swift both feed raw
0..255 pixels and cannot drift apart.
- TFLite runs on both platforms in the shared isolate.
- Core ML runs on iOS through `MethodChannel('pawsense/coreml')`: Dart crops and JPEG-encodes the
  box, and `CoreMLBreedClassifier.swift` runs it through `VNCoreMLModel` with `computeUnits = .all`,
  so Core ML can use the **Neural Engine**, which TFLite cannot. It returns the top 3 and `inferenceMs`.
- Settings switches engines on iOS, and the HUD shows the active engine and its ms.

**Which to ship.** Undecided until measured on a real iPhone. On a Mac, Core ML (0.58 ms) beat
TFLite CPU (14.0 ms), but those are **not** phone numbers. The expectation is that Core ML wins on
iPhone because of the ANE, even with the JPEG and channel overhead. METRICS.md has the measurement
steps.

**When to classify** (`lib/ml/breed_smoother.dart`): on the first box, then every 5th processed
frame, or sooner when the box moves (IoU with the last classified box below 0.5, which suggests a
different pet or view).

**Smoothing.** An exponential moving average (α = 0.3) of each label's confidence over the raw top-3
results, bias-corrected so the first readings are not artificially low. It is reset when the pet
leaves. The label stops flickering without the lag of a long majority-vote window.

### ADR-5: YAMNet windowing and debounce

**YAMNet** is Google's AudioSet-trained audio event classifier. It takes **15,600 float32 samples
(0.975 s at 16 kHz mono)** in [-1, 1] and returns scores for 521 classes, which `yamnet_class_map.csv`
names.

- `record` streams PCM16 at 16 kHz mono. `AudioWindower` (`lib/ml/audio_windower.dart`) cuts it on the main isolate into
  15,600-sample windows with a 7,800-sample hop (**50 % overlap**), so a bark that straddles a window
  edge still lands whole in one window. It carries an odd byte across recorder chunks. PCM16 → float and
  inference run in the TFLite isolate on CPU (XNNPACK); a window that arrives while YAMNet is busy
  is dropped.
- Dog score = max of Dog, Bark, Yip, Howl, Bow-wow, Growling, Whimper (dog). Cat score = max of Cat,
  Purr, Meow, Hiss, Caterwaul.
- **False positives.** `SoundDebouncer` (`lib/ml/sound_debouncer.dart`) fires only when a kind stays
  at or above its threshold for **2 consecutive windows** (about 0.5 s of sustained sound, so a door
  slam is not a bark). It then stays quiet for a **3 s cooldown**, so one barking fit is one event.
- **Thresholds are 0.3 for both kinds and are untuned.** They are a starting point. Tune them with
  real recordings on a phone (the Sound tab shows the current top label and its score).

### ADR-6: Keyframes via `fc_native_video_thumbnail`

**Decision.** Record a 10 s clip with `camera` (720p, the smallest preset whose long side exceeds
768 px), then extract **5 keyframes at 1, 3, 5, 7 and 9 s** as JPEG, longest side **768 px, quality
80**, into the documents directory so queued clips survive restarts. The video file is deleted after
extraction; only the keyframes are uploaded.

- **Why not `video_thumbnail`** (the package the spec names): 0.5.6 still uses `jcenter()` and fails
  to build with current AGP. `fc_native_video_thumbnail` 4.0.0 does the same job natively.
- **iOS:** `AVAssetImageGenerator` with zero time tolerance, so frames are exact.
- **Android:** `MediaMetadataRetriever.getScaledFrameAtTime` with `OPTION_CLOSEST_SYNC`, so frames
  **snap to the nearest sync (key) frame**, usually within about 1 s of the requested time. That is
  fine for a mood/activity read.
- **Fallback not implemented:** sampling the camera stream every 2 s while recording. The recorder
  throws if a device returns no thumbnail. Implement the fallback if that happens in the field.

### ADR-7: Keyframes plus a cloud model, streamed

**Why not on-device.** Mood, activity and health observations need a large vision-language model.
No model of that quality fits on a phone at interactive speed.

**Why keyframes, not video.** Five 768 px JPEGs are a few hundred KB instead of megabytes of video.
They upload quickly on mobile data, cost a fraction of the image tokens, and a 10 s pet clip rarely
changes faster than every 2 s.

**Trade-offs.** Cost per clip (Claude API tokens), network latency, and privacy: frames leave the
device, though only on an explicit record action, and the backend keeps results in memory for 15
minutes only. The Anthropic key stays on the backend; the app holds only a bearer `API_TOKEN`.

**Streaming.** The backend calls `claude-opus-5-5` with `output_config.effort: "low"` and a JSON-schema
structured output, and forwards text deltas over the WebSocket as they arrive. The app shows them as
a typing effect, so the user sees progress within the time to the first delta, not the time to the
full answer. The final message is parsed into a typed `insight`. A `stop_reason` of `refusal`
becomes `error: refused`. Refusal fallbacks (`server-side-fallback-2026-07-01`) let the API retry on
a fallback model within the same stream.

### ADR-8: Offline-first: Drift first, queue second

1. **Write locally first.** Recording writes a `clips` row (`pending_upload`) and the keyframe paths
   to Drift **before** any network call. Detections and sound events go straight to the Drift
   `insights` table. The UI reads only Drift `watch()` streams, so it works in airplane mode.
2. **Upload queue.** `SyncService` (`lib/data/sync/sync_service.dart`) uploads pending clips while
   online. Retryable failures back off exponentially (2 s, 4 s, 8 s … each wait capped at 5 min) with
   **no attempt limit**: a clip stays "queued" until it uploads. A 4xx response marks it failed
   (retrying cannot fix bad input), and the Clips tab has a manual retry.
3. **Reconnect.** When `connectivity_plus` reports a connection, **the whole queue is due
   immediately** and the remaining backoff is skipped.
4. **Idempotency.** The client generates `clipId` (UUID) and the backend's `JobStore` maps
   `clipId → job`. A retried upload after a lost response returns the same `jobId` instead of a
   second analysis.
5. **WebSocket reconnect by `jobId`.** If the socket drops, the app reconnects to the same `jobId`
   (up to 5 drops per analysis, then it waits for the next connectivity change or app start). The
   backend attaches to the running job or **replays the final insight if the job finished in the last
   15 minutes**.
6. **Order of writes.** The final insight is written to Drift (clip → `analyzed`, plus a feed entry)
   *before* `ClipInsightReady` is emitted, so a crash cannot lose a result the user already saw.
   `addClipInsight` is idempotent per `clipId`.
7. **Feed spam.** A detection is saved at most once per minute per pet type.

**Cost.** The JobStore is in memory and single-process, so a backend restart loses running jobs.
The app re-posts by `clipId`, which recovers them. Move it to Redis to scale past one VM.

### ADR-9: Health flags must not read as medical advice

The system prompt in `backend/src/services/vision.ts` sets these rules:
- Act as a careful pet-behaviour observer and describe **only what is visible** in the frames.
- Health flags are **observations, not diagnoses** ("favoring left hind leg", not "hip dysplasia"),
  and each one cites its visible **evidence**.
- For anything concerning, the summary suggests that **a vet should take a look**.
- Never invent breed or medical facts. The on-device breed is passed as a hint, "not a fact". Use
  `unknown` mood or `other` activity when unsure, and lower `confidence` to match.
- If nothing looks concerning, return an empty `healthFlags` list.

The structured-output JSON schema limits `severity` to `low|medium|high` and `mood`/`activity` to
fixed enums, so the app never renders free-form medical labels. Unknown enum values fall back
instead of crashing.

### ADR-10: Sentry: errors, bloc breadcrumbs, sampled spans

**Sentry** collects crash/error reports and performance traces. It is initialised only when
`SENTRY_DSN` is set through dart-define, so local and CI builds run without it.
- A `SentryBlocObserver` records bloc transitions as breadcrumbs and reports bloc errors.
- `ml.inference`: every **30th** request per model is wrapped in a transaction, so tracing costs
  nothing on most frames.
- `clip.upload` (`http.client`) around the multipart upload.
- `clip.ws` (`websocket.client`) around each analysis stream, with a `time_to_first_delta`
  measurement in ms.
- Release builds upload the Dart debug symbols, the obfuscation map and the iOS dSYMs (see
  RELEASE.md), so obfuscated stack traces are readable.

### ADR-11: State and DI

`flutter_bloc` with one bloc or cubit per screen. `get_it` is wired by hand in `lib/app/di/`, with no
code generation. ML engines are factories: the bloc that receives one owns it (`load()` on start,
`dispose()` in `close()`), while the inference isolate is a lazy singleton. `bootstrap(overrides:)`
re-registers fakes for E2E tests, which is how `integration_test/` runs on a CI emulator without
models, camera or network.
