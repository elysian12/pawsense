# PawSense

<!-- TODO: docs/demo.gif, about 20 s: live detection with a breed label, a bark event, and a streamed clip insight. Record it on a real phone. -->
> `docs/demo.gif` — TODO record on device

PawSense is an AI companion app for pet parents on iOS and Android. Point the camera at your pet and
it boxes the cat or dog live and names its breed, entirely **on-device**: EfficientDet-Lite0 and a
37-breed classifier run in a background TensorFlow Lite isolate with adaptive frame skipping, and
iOS can switch to Core ML on the Neural Engine. It listens for barks and meows with Google's YAMNet,
also on-device. Record a 10-second clip, and five keyframes go to a small Node.js backend, where a
cloud vision model's read on mood, activity and visible health flags **streams back over a
WebSocket** as it is written. Everything lands first in an **offline-first** feed, and clips queue
until the network returns.

## Architecture

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

Decision records: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Wire protocol:
[`docs/WS_PROTOCOL.md`](docs/WS_PROTOCOL.md). Release pipeline: [`docs/RELEASE.md`](docs/RELEASE.md).

## Metrics

Copied from [`docs/METRICS.md`](docs/METRICS.md), which also has the exact measurement steps. Phone
numbers have **not been measured yet**, and none are estimated.

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

Measured offline on the Oxford-IIIT Pet test split (3,669 images):

| Breed model | Size | Top-1 | Top-5 |
|---|---|---|---|
| MobileNetV3-Small (comparison) | — | 84.3 % | 98.7 % |
| EfficientNet-B0 → TFLite fp16 (shipped) | 8.2 MB | 91.66 % | 99.56 % |
| EfficientNet-B0 → Core ML fp16 (shipped, iOS) | 8.4 MB | 91.69 % | 99.56 % |

## Engineering decisions

- **One long-lived inference isolate, not `compute()` per frame.** Spawning an isolate and rebuilding
  an interpreter (model parse, GPU/Metal delegate compile, warm-up) every frame would use the whole
  33 ms budget. One isolate owns all three interpreters and only frames and results cross the
  boundary. Frames are converted inside it in one fused pass (YUV420 or BGRA → rotate → crop →
  resize → RGB) into a reused buffer.
- **Drop frames, never queue them, and adapt the rate.** While a frame is in flight, new frames are
  dropped, because a queue only adds latency. `FrameScheduler` targets `max(33 ms, avg × 1.5)`,
  drops to about 2 fps after 5 s with no pet or below 20 % battery, and returns to full rate on the
  first detection. The 10-minute before/after battery test is built into Settings.
- **TFLite and Core ML, same model.** One EfficientNet-B0 (91.6 % top-1, beating MobileNetV3-Small's
  84.3 %) is exported to fp16 TFLite (8.2 MB) and Core ML (8.4 MB) with the same accuracy. Core ML
  runs through a Swift `MethodChannel` and can use the Neural Engine. Classification runs on every
  5th frame or when the box moves, and is EMA-smoothed so the label does not flicker. The on-phone
  latency comparison is TBD in METRICS.md.
- **Offline-first.** Every result is written to Drift first and the UI only reads Drift streams.
  Clips go through an upload queue with exponential backoff (capped at 5 min, no attempt limit) that
  drains as soon as connectivity returns. The client-generated `clipId` makes uploads idempotent.
- **Stream, don't wait.** Five 768 px keyframes, not video, go to the backend, which streams Claude's
  text deltas over a WebSocket. The user sees the typing effect after the first token instead of
  waiting for the whole answer. Dropped sockets reconnect by `jobId`, and finished results are
  replayed for 15 min.
- **Health flags are observations, not diagnoses.** The prompt allows only what is visible, requires
  evidence for each flag, says to suggest a vet for anything concerning, treats the on-device breed
  as a hint, and uses `unknown` when unsure. A JSON schema constrains the output.

## Repository

| Path | What |
|---|---|
| `app/` | Flutter app (BLoC, go_router, get_it, Drift) |
| `backend/` | Node.js + TypeScript (Fastify) clip-analysis API |
| `ml/` | Breed classifier training and export (Python 3.11) |
| `docs/` | Architecture, metrics, WebSocket protocol, release pipeline |

## Setup

### App (Flutter, iOS 16+ / Android 8.0+)

```sh
cd app
cp dart_defines.example.json dart_defines.json   # API_BASE_URL, API_TOKEN (same as backend), SENTRY_DSN optional
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift code
flutter run -t lib/main_development.dart --dart-define-from-file=dart_defines.json

flutter analyze && flutter test                   # unit + bloc tests
flutter test integration_test                     # E2E with fake ML (needs a device or emulator)
```

The flavors are the two Dart entrypoints, `main_development.dart` and `main_production.dart`. There
are no native flavors. On a physical phone, set `API_BASE_URL` to your Mac's LAN address (for example
`http://192.168.1.20:8080`) or to the deployed `https://` backend. On macOS, run CocoaPods with
`LANG=en_US.UTF-8`.

### Backend (Node 26)

```sh
cd backend
cp .env.example .env    # API_TOKEN (long random string) and ANTHROPIC_API_KEY. Never commit it.
npm ci
npm run dev             # http://localhost:8080, or: docker compose up --build
npm run lint && npm test
```

### ML (Python 3.11, optional: the exported models are committed)

```sh
cd ml
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python tensorflow tensorflow-datasets coremltools numpy pillow importlib_resources
.venv/bin/python train.py && .venv/bin/python export_tflite.py && .venv/bin/python export_coreml.py
```

See [`ml/README.md`](ml/README.md) for where EfficientDet-Lite0 and YAMNet come from, the training
recipe and a TFLite/Core ML primer.

## CI

[![app-ci](https://github.com/elysian12/pawsense/actions/workflows/app-ci.yml/badge.svg)](https://github.com/elysian12/pawsense/actions/workflows/app-ci.yml)
[![backend-ci](https://github.com/elysian12/pawsense/actions/workflows/backend-ci.yml/badge.svg)](https://github.com/elysian12/pawsense/actions/workflows/backend-ci.yml)
[![release-android](https://github.com/elysian12/pawsense/actions/workflows/release-android.yml/badge.svg)](https://github.com/elysian12/pawsense/actions/workflows/release-android.yml)
[![release-ios](https://github.com/elysian12/pawsense/actions/workflows/release-ios.yml/badge.svg)](https://github.com/elysian12/pawsense/actions/workflows/release-ios.yml)

## License

MIT
