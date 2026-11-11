# ml/: how PawSense's models were obtained and trained

| Model | File in the app | Where it comes from |
|---|---|---|
| Breed classifier, TFLite (Android + iOS) | `app/assets/models/breeds.tflite`, `breeds.txt` | Trained here: `train.py` → `export_tflite.py` |
| Breed classifier, Core ML (iOS) | `app/ios/Runner/BreedClassifier.mlpackage` | Same Keras model → `export_coreml.py` |
| Pet detector (EfficientDet-Lite0) and YAMNet | `app/assets/models/` | Pretrained downloads (COCO / AudioSet), not trained here; see below |

The pretrained models come first, then the breed classifier, which is the only model trained here.

## Pretrained models (downloaded, not trained)

Both files come from Kaggle Models, which now hosts the old TF Hub models. They are committed as
downloaded, with no changes. Check a fresh download against these hashes with `shasum -a 256 <file>`
(the hashes below match the files in `app/assets/models/`).

| File in `app/assets/models/` | Source | sha256 | License |
|---|---|---|---|
| `efficientdet_lite0.tflite` | [kaggle.com/models/tensorflow/efficientdet](https://www.kaggle.com/models/tensorflow/efficientdet/tfLite/lite0-detection-metadata/1), variation `tfLite/lite0-detection-metadata`, version 1 | `2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b` | Apache-2.0 |
| `coco_labels.txt` | The `labelmap.txt` embedded in the detector's metadata: `unzip -p efficientdet_lite0.tflite labelmap.txt > coco_labels.txt` (a `.tflite` with metadata is also a zip) | `f8803ef7900160c629d570848dfda4175e21667bf7b71f73f8ece4938c9f2bf2` | Apache-2.0 (ships in the model) |
| `yamnet.tflite` | [kaggle.com/models/google/yamnet](https://www.kaggle.com/models/google/yamnet/tfLite/classification-tflite/1), variation `tfLite/classification-tflite`, version 1 | `10c95ea3eb9a7bb4cb8bddf6feb023250381008177ac162ce169694d05c317de` | Apache-2.0 |
| `yamnet_class_map.csv` | [github.com/tensorflow/models](https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/yamnet_class_map.csv), `research/audioset/yamnet/yamnet_class_map.csv` | `cdf24d193e196d9e95912a2667051ae203e92a2ba09449218ccb40ef787c6df2` | Apache-2.0 |

Apache-2.0 allows commercial use and redistribution inside the app. It requires keeping the license
notice, so include these models in the app's open-source licenses screen.

**EfficientDet-Lite0 (pet detector).** A small object detector trained on COCO (90 classes), the
smallest of the EfficientDet-Lite family that Google built for phones. The "detection-metadata"
variant has non-max suppression and quantization built in, so the app sends raw pixels and gets
final boxes back. Tensors, as checked with the TFLite interpreter:

- Input: `uint8 [1, 320, 320, 3]`, RGB 0..255. The app stretches the upright frame to 320×320.
- Outputs (all float32): boxes `[1, 25, 4]` as `[ymin, xmin, ymax, xmax]` normalized to the input,
  classes `[1, 25]` (index into `coco_labels.txt`), scores `[1, 25]`, count `[1]` (how many of the 25
  slots are valid).
- In `coco_labels.txt`, index **16 is `cat` and 17 is `dog`** (0 is `person`). The app keeps only
  those two above a score threshold (0.5 by default). See `app/lib/ml/pet_detector.dart`.

**YAMNet (bark and meow detection).** Tensors:

- Input: `float32 [15600]`, a mono waveform at **16 kHz** with samples in **[-1, 1]**. 15,600
  samples is 0.975 s. PCM16 from the mic is divided by 32768.
- Output: `float32 [1, 521]`, one score per AudioSet class. Row *i* of `yamnet_class_map.csv`
  (`index,mid,display_name`) names score *i*: for example 69 `Dog`, 70 `Bark`, 76 `Cat`, 78 `Meow`.

### What YAMNet is, for a Flutter engineer

YAMNet is Google's general-purpose sound classifier: give it about one second of audio and it returns
how likely each of 521 everyday sound classes is, such as speech, music, a car horn, a dog barking or
a cat meowing. It was trained on **AudioSet**, Google's dataset of labeled clips from YouTube videos.
The network is MobileNet-v1, the same lightweight convolutional design used for phone vision models,
which is why it is cheap enough to run continuously on a phone (on-device timing: TBD — measure on device, from the sampled Sentry `ml.inference` transactions named `tflite yamnet`).

The trick is that it doesn't "listen" to raw audio. Inside the model, the waveform is first turned
into a **log-mel spectrogram**: a picture of the sound with time on one axis, pitch (on the mel
scale, which follows how humans hear pitch) on the other, and loudness as brightness. The CNN then
classifies that picture much like an image model would. The spectrogram step is built into
`yamnet.tflite`, so the app only has to provide the right samples. That means the right sample rate
(16 kHz), the right range ([-1, 1]) and the right length (15,600). Get any of those wrong and the
scores are garbage, without any error.

The scores are independent (sigmoid, not softmax), because several sounds can happen at once, so
they don't add up to 1. PawSense groups the classes that mean "dog" (`Dog`, `Bark`, `Yip`, `Howl`,
`Bow-wow`, `Growling`, `Whimper (dog)`) and "cat" (`Cat`, `Purr`, `Meow`, `Hiss`, `Caterwaul`) and
takes the highest score in each group. It runs YAMNet on overlapping windows (about 50% overlap) and
counts a bark or meow only after two windows in a row pass the threshold, followed by a cooldown.
That prevents one loud noise from flooding the feed. See `app/lib/ml/sound_classifier.dart` and
`sound_debouncer.dart`.

Nothing in YAMNet is fine-tuned here. It already knows barks and meows from AudioSet, so all the
PawSense-specific work is the windowing, class grouping and debouncing above.

## Breed classifier results (measured)

Trained on an Apple M4 MacBook (TensorFlow 2.21 on CPU, no GPU plugin), Keras 3.15,
coremltools 9.0. Numbers come from `artifacts/metrics.json`, written by the scripts below.

**Backbone choice.** Both candidates were trained with the same recipe and evaluated on the full
Oxford-IIIT Pet `test` split (3,669 images):

| Backbone (ImageNet weights) | Params | Test top-1 | Test top-5 | Training wall time |
|---|---|---|---|---|
| MobileNetV3-Small | 0.96 M | 84.3% | 98.7% | 1.4 min |
| **EfficientNet-B0 (shipped)** | 4.10 M | **91.6%** | **99.6%** | 7.7 min |

EfficientNet-B0 is 7.3 points more accurate. The app classifies only every Nth processed frame (the
detector runs on every frame), so the extra cost of B0 matters less than the accuracy.
EfficientNet-Lite0 isn't in `keras.applications`; B0 is the closest available.

**Exports of the shipped model** (full test split, same uint8 pixels for all three):

| Format | File | Size | Test top-1 | Test top-5 |
|---|---|---|---|---|
| Keras float32 (reference) | `artifacts/breeds.keras` | — | 91.66% | 99.56% |
| TFLite float16 | `breeds.tflite` | 8.2 MB | 91.66% | 99.56% |
| Core ML ML Program (float16) | `BreedClassifier.mlpackage` | 8.4 MB | 91.69% | 99.56% |

float16 cost nothing measurable. The 0.03-point Core ML difference is a net 1 image out of 3,669,
flipped by fp16 rounding.

Latency on the Mac, as a sanity check only (these are **not** phone numbers): TFLite
CPU/XNNPACK from Python, median 14.0 ms per image; Core ML through coremltools, median 0.58 ms (Core
ML picks the Neural Engine/GPU). The Core ML path was also run end to end in the iOS Simulator
(Dart crop → JPEG → method channel → Swift → Vision) on three test images: Russian_Blue,
miniature_pinscher and Bombay all came back as top-1 with confidence above 0.99.

**On-device latency: TBD — measure on device.** For `docs/METRICS.md`, on a real mid-range
iPhone and Android phone, release or profile build (`flutter run --profile`):
1. Point the camera at a pet (or a photo of one) so the breed label shows in the Live tab.
2. Read the classification ms in the HUD for about 30 s per engine (Settings toggles TFLite / Core
   ML on iOS), and record the median and p95. The HUD number is wall clock, crop and channel
   included. For Core ML-only inference time, open DevTools → Logging (profile build) and filter for
   `coreml` (the Swift side returns `inferenceMs`, measured around `VNImageRequestHandler.perform`).
3. Record the device, OS version and build mode next to each number.

## Model contract (what the app must feed)

Both exports come from the same Keras model and expect the same pixels:

- **Input:** one RGB image, 224×224, **raw pixel values 0..255** (float32 for TFLite). Do **not**
  normalize in Dart or Swift: EfficientNet-B0's own `Rescaling(1/255)` + ImageNet mean/std
  `Normalization` layers are the first layers inside the model.
  - TFLite: input tensor `float32 [1, 224, 224, 3]`, channel order R, G, B, row-major (height, width).
  - Core ML: input `image` is an `ImageType` (RGB, no scale/bias). Vision stretches the crop to
    224×224 (`imageCropAndScaleOption = .scaleFill`).
- **Resize:** the training/eval pipeline **stretches** the image to 224×224 (no aspect-preserving
  crop), because the app stretches the detector's pet box. Keep it that way in the app.
- **Output:** TFLite gives `float32 [1, 37]` softmax probabilities; index *i* is line *i* of
  `labels/breeds.txt` (= `app/assets/models/breeds.txt`). Core ML is a classifier model:
  `classLabel` + `classLabel_probs` (label → probability).
- **Labels:** the 37 Oxford-IIIT Pet names exactly as `tensorflow_datasets` gives them
  (alphabetical ignoring case; the 12 cat breeds are capitalised, e.g. `Abyssinian`, the 25 dog
  breeds are lowercase, e.g. `beagle`). Make them pretty in the UI, not in the file.

## Reproduce

```bash
cd ml
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python tensorflow tensorflow-datasets coremltools numpy pillow importlib_resources
.venv/bin/python train.py                      # downloads the dataset to ml/data (~800 MB), trains B0
.venv/bin/python train.py --backbone mobilenetv3small   # the smaller comparison model
.venv/bin/python export_tflite.py              # writes + copies breeds.tflite and breeds.txt into app/
.venv/bin/python export_coreml.py              # writes + copies BreedClassifier.mlpackage (macOS only)
```

`ml/data`, `ml/artifacts` and `ml/.venv` are gitignored; only the exported models and labels are
committed. `train_breed_classifier.ipynb` runs the same steps cell by cell (it imports `train.py`, so
they cannot drift) and works in Colab for anyone without a Mac.

### How training works

- **Data:** `oxford_iiit_pet` from `tensorflow_datasets`: 3,680 `train` images (90% train, 10%
  validation) and 3,669 `test` images. The test split is used once, at the end.
- **Augmentation (light):** random zoom-crop (resize to 224–280, random 224 crop), horizontal flip,
  ±20 brightness, 0.85–1.15 contrast.
- **Transfer learning:** ImageNet backbone (EfficientNet-B0 by default) with global average pooling → dropout 0.3 → 37-way
  softmax.
  1. **Head only** (backbone frozen), Adam 1e-3.
  2. **Fine-tune** the top 60 backbone layers at Adam 1e-4. BatchNorm layers stay frozen and in
     inference mode, so the small dataset does not wreck their ImageNet statistics.
  Early stopping on validation top-1 (patience 3) keeps the best weights.

## New to this? TFLite, Core ML and quantization in five minutes

**TensorFlow Lite (TFLite)** is TensorFlow's on-device runtime. A `.tflite` file is a flat
buffer holding the graph and its weights. In the app, `tflite_flutter`'s `Interpreter` loads it, you
write the input tensor, call `run`, and read the output tensor. Speed comes from **delegates**: the
GPU delegate on Android and the Metal delegate on iOS run supported ops on the GPU, and XNNPACK is
the optimised CPU fallback. Interpreters are expensive to create and are not thread-safe, so the app
keeps one per model inside a long-lived isolate.

**Core ML** is Apple's on-device runtime. Xcode compiles the `.mlpackage` (an "ML Program": the
model as a MIL program plus a weights blob) into `BreedClassifier.mlmodelc` inside the app bundle at
build time. At runtime `MLModel(contentsOf:)` loads it, and Core ML chooses where each layer runs:
**Neural Engine (ANE)**, GPU or CPU (`computeUnits = .all`). The ANE is the main reason to bother:
TFLite cannot use it. **Vision** (`VNCoreMLModel` + `VNCoreMLRequest`) wraps the model and handles
image decoding, scaling and pixel-format conversion, so Swift only hands it JPEG bytes. Flutter talks
to it over a `MethodChannel` (`pawsense/coreml`); see `app/ios/Runner/CoreMLBreedClassifier.swift`.

**Post-training quantization** shrinks a trained model without retraining by storing numbers in
fewer bits:

| Kind | Weights | Size | Accuracy | Notes |
|---|---|---|---|---|
| float32 (none) | 32-bit | 1× | baseline | |
| **float16** (used here) | 16-bit | ~½ | practically unchanged | GPU/Metal delegates compute in fp16 natively; on CPU weights are expanded to fp32 |
| dynamic range | 8-bit weights, float activations | ~¼ | small drop | CPU only; the GPU delegate can't use it |
| full int8 | 8-bit weights and activations | ~¼ | needs a calibration set | fastest on CPU/NPU, most work |

float16 fits PawSense: the model is already small, the Android path runs on the GPU delegate, and
the accuracy cost is negligible (measured above). Core ML ML Programs store weights and compute in
float16 by default, so both exports are fp16.

**Why the rescaling layer lives inside the model:** preprocessing mismatches are the most common
on-device ML bug (the model sees [0, 255] when it was trained on normalized values and silently
outputs garbage). With normalization baked in, TFLite, Core ML and the Python evaluation all take
the same raw pixels.

**Conversion gotcha we hit (Keras 3):** converting a `tf.function` that wraps a Keras 3 model
produced an 8 MB model shrunk to 0.3 MB with 3% accuracy: the weights were silently dropped. Both
export scripts therefore go through `model.export(..., format="tf_saved_model")` first, and every
export is re-evaluated on the test set so a broken conversion can't ship unnoticed.
