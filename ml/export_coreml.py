"""Convert artifacts/breeds.keras to a Core ML ML Program and check its accuracy (macOS only).

Run from ml/ after train.py:  .venv/bin/python export_coreml.py [--limit N]
Writes artifacts/BreedClassifier.mlpackage and copies it to app/ios/Runner/.

Model contract (what CoreMLBreedClassifier.swift relies on):
  input  "image": 224x224 RGB image (Vision scales the crop to it). Pixels go in as 0..255;
         the model's own rescaling/normalization layers handle the rest, so ImageType has no scale/bias.
  output classifier: "classLabel" (top label) + "classLabel_probs" (all 37), labels from breeds.txt.
"""

import argparse
import json
import shutil
import time

import coremltools as ct
import numpy as np
import tensorflow as tf
from PIL import Image

from train import ARTIFACTS, IMG, LABELS_FILE, ROOT, export_saved_model, load_test_images

APP_RUNNER = ROOT.parent / "app" / "ios" / "Runner"


def to_coreml(saved_model, labels):
    # Keras' SavedModel holds two functions (serve + serving_default); coremltools wants one.
    loaded = tf.saved_model.load(str(saved_model))
    mlmodel = ct.convert(
        [loaded.signatures["serving_default"]],
        source="tensorflow",
        inputs=[ct.ImageType(name="image", shape=(1, IMG, IMG, 3), color_layout=ct.colorlayout.RGB)],
        classifier_config=ct.ClassifierConfig(labels),
        convert_to="mlprogram",  # .mlpackage; weights and compute in float16 by default
        minimum_deployment_target=ct.target.iOS16,  # app's iOS deployment target
    )
    mlmodel.short_description = "PawSense: 37 Oxford-IIIT Pet breeds (EfficientNet-B0, fine-tuned)"
    mlmodel.input_description["image"] = "Pet crop, RGB; scaled to 224x224"
    return mlmodel


def evaluate(mlmodel, labels, limit):
    top1 = top5 = n = 0
    times = []
    for image, label in load_test_images(limit)[0]:
        name = labels[int(label)]
        pil = Image.fromarray(tf.cast(tf.round(image), tf.uint8).numpy())
        t = time.perf_counter()
        probs = mlmodel.predict({"image": pil})["classLabel_probs"]
        times.append((time.perf_counter() - t) * 1000)
        ranked = sorted(probs, key=probs.get, reverse=True)
        top1 += ranked[0] == name
        top5 += name in ranked[:5]
        n += 1
    return {"top1": round(top1 / n, 4), "top5": round(top5 / n, 4), "images": n,
            "coreml_ms_median_mac": round(float(np.median(times)), 2)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None, help="test images to evaluate (default: all)")
    args = parser.parse_args()

    labels = LABELS_FILE.read_text().split()
    assert len(labels) == 37, len(labels)
    _, saved_model = export_saved_model()
    mlmodel = to_coreml(saved_model, labels)
    out = ARTIFACTS / "BreedClassifier.mlpackage"
    shutil.rmtree(out, ignore_errors=True)
    mlmodel.save(str(out))
    dest = APP_RUNNER / "BreedClassifier.mlpackage"
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(out, dest)

    size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
    result = {"size_mb": round(size / 1e6, 2), **evaluate(mlmodel, labels, args.limit)}
    metrics_file = ARTIFACTS / "metrics.json"
    metrics = json.loads(metrics_file.read_text()) | {"coreml_export": result}
    metrics_file.write_text(json.dumps(metrics, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
