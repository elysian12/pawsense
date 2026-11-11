"""Export artifacts/breeds.keras to a float16-quantized TFLite model and check its accuracy.

Run from ml/ after train.py:  .venv/bin/python export_tflite.py [--limit N]
Writes artifacts/breeds.tflite and copies it plus labels/breeds.txt to app/assets/models/.

Model contract (what the Dart side must feed):
  input  float32 [1, 224, 224, 3], RGB, raw pixel values 0..255 (rescaling is inside the model)
  output float32 [1, 37] softmax probabilities, index i = line i of breeds.txt
"""

import argparse
import json
import shutil
import time

import numpy as np
import tensorflow as tf

from train import ARTIFACTS, LABELS_FILE, ROOT, export_saved_model, load_test_images

APP_MODELS = ROOT.parent / "app" / "assets" / "models"


def to_tflite(saved_model):
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model))
    # Post-training float16 quantization: weights stored as fp16 (half the size),
    # dequantized to fp32 on CPU, used natively by the GPU / Metal delegates.
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    return converter.convert()


def topk_hits(probs, label):
    order = np.argsort(probs)[::-1]
    return int(order[0] == label), int(label in order[:5])


def evaluate(model, tflite_bytes, limit):
    interpreter = tf.lite.Interpreter(model_content=tflite_bytes)
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]["index"]
    out = interpreter.get_output_details()[0]["index"]
    hits = {"keras": [0, 0], "tflite": [0, 0]}
    n, tflite_ms = 0, []
    for image, label in load_test_images(limit)[0]:
        # Round to uint8 like a camera frame, so Keras / TFLite / Core ML see identical pixels.
        x = tf.cast(tf.round(image), tf.float32)[None].numpy()
        t = time.perf_counter()
        interpreter.set_tensor(inp, x)
        interpreter.invoke()
        tflite_ms.append((time.perf_counter() - t) * 1000)
        for name, probs in (("keras", model(x, training=False)[0].numpy()),
                            ("tflite", interpreter.get_tensor(out)[0])):
            h1, h5 = topk_hits(probs, int(label))
            hits[name][0] += h1
            hits[name][1] += h5
        n += 1
    return {name: {"top1": round(h[0] / n, 4), "top5": round(h[1] / n, 4)} for name, h in hits.items()} | {
        "images": n, "tflite_ms_median_mac_cpu": round(float(np.median(tflite_ms)), 2)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None, help="test images to evaluate (default: all)")
    args = parser.parse_args()

    model, saved_model = export_saved_model()
    tflite_bytes = to_tflite(saved_model)
    out = ARTIFACTS / "breeds.tflite"
    out.write_bytes(tflite_bytes)
    APP_MODELS.mkdir(parents=True, exist_ok=True)
    shutil.copy(out, APP_MODELS / "breeds.tflite")
    shutil.copy(LABELS_FILE, APP_MODELS / "breeds.txt")

    result = {"size_mb": round(out.stat().st_size / 1e6, 2), **evaluate(model, tflite_bytes, args.limit)}
    metrics_file = ARTIFACTS / "metrics.json"
    metrics = json.loads(metrics_file.read_text()) | {"tflite_export": result}
    metrics_file.write_text(json.dumps(metrics, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
