"""Train the 37-breed classifier on Oxford-IIIT Pet (transfer learning).

Run from ml/:  .venv/bin/python train.py
Outputs:
  artifacts/breeds.keras   trained Keras model (input: float32 RGB 0..255, 224x224)
  artifacts/metrics.json   top-1 / top-5 on the test split
  labels/breeds.txt        37 labels in model output order

train_breed_classifier.ipynb runs the same steps cell by cell (for Colab).
"""

import argparse
import json
import time
from pathlib import Path

import keras
import tensorflow as tf
import tensorflow_datasets as tfds

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
ARTIFACTS = ROOT / "artifacts"
LABELS_FILE = ROOT / "labels" / "breeds.txt"
IMG = 224
BATCH = 64
HEAD_EPOCHS = 8
FINE_EPOCHS = 20  # upper bound; early stopping on val top-1 usually ends sooner
FINE_TUNE_LAYERS = 60  # top layers of the backbone to unfreeze (BatchNorm stays frozen)
# Both take raw 0..255 RGB: their rescaling/normalization layers are part of the model.
BACKBONES = {
    "mobilenetv3small": lambda: keras.applications.MobileNetV3Small(
        input_shape=(IMG, IMG, 3), include_top=False, weights="imagenet",
        pooling="avg", include_preprocessing=True),
    "efficientnetb0": lambda: keras.applications.EfficientNetB0(
        input_shape=(IMG, IMG, 3), include_top=False, weights="imagenet", pooling="avg"),
}
SEED = 42

keras.utils.set_random_seed(SEED)


def resize_eval(image, label):
    # What the app does: crop the detection box, then stretch it to 224x224.
    # Pixel values stay 0..255: rescaling is inside the model.
    return tf.image.resize(image, (IMG, IMG)), label


def augment(image, label):
    # Light augmentation: random zoom-crop, flip, small brightness/contrast jitter.
    size = tf.random.uniform([], IMG, int(IMG * 1.25), dtype=tf.int32)
    image = tf.image.resize(image, (size, size))
    image = tf.image.random_crop(image, (IMG, IMG, 3))
    image = tf.image.random_flip_left_right(image)
    image = tf.image.random_brightness(image, 20.0)
    image = tf.image.random_contrast(image, 0.85, 1.15)
    return tf.clip_by_value(image, 0.0, 255.0), label


def load_split(split):
    """(dataset of (uint8 image, int label), label names). Images keep original size."""
    ds, info = tfds.load(
        "oxford_iiit_pet", split=split, data_dir=str(DATA_DIR),
        as_supervised=True, with_info=True,
    )
    return ds, info.features["label"].names


def load_test_images(limit=None):
    """Test split resized like the app does, for the export scripts' accuracy checks."""
    ds, names = load_split("test")
    if limit:
        ds = ds.take(limit)
    return ds.map(resize_eval), names


def build_datasets():
    train_raw, names = load_split("train[:90%]")
    val_raw, _ = load_split("train[90%:]")
    test_raw, _ = load_split("test")
    pipe = lambda ds: ds.map(lambda i, l: (tf.cast(i, tf.float32), l))  # noqa: E731
    train = (pipe(train_raw).cache().shuffle(2048, seed=SEED)
             .map(augment, num_parallel_calls=tf.data.AUTOTUNE)
             .batch(BATCH).prefetch(tf.data.AUTOTUNE))
    val = pipe(val_raw).map(resize_eval).cache().batch(BATCH).prefetch(tf.data.AUTOTUNE)
    test = pipe(test_raw).map(resize_eval).batch(BATCH).prefetch(tf.data.AUTOTUNE)
    return train, val, test, names


def build_model(num_classes, backbone_name="efficientnetb0"):
    # The backbone's preprocessing layers are INSIDE the model, so TFLite and
    # Core ML both take plain RGB pixel values 0..255.
    backbone = BACKBONES[backbone_name]()
    backbone.trainable = False
    inputs = keras.Input((IMG, IMG, 3), name="image")
    x = backbone(inputs, training=False)  # keep BatchNorm in inference mode, also when fine-tuning
    x = keras.layers.Dropout(0.3)(x)
    outputs = keras.layers.Dense(num_classes, activation="softmax", name="probs")(x)
    return keras.Model(inputs, outputs, name="breed_classifier"), backbone


def compile_model(model, lr):
    model.compile(
        optimizer=keras.optimizers.Adam(lr),
        loss=keras.losses.SparseCategoricalCrossentropy(),
        metrics=[
            keras.metrics.SparseCategoricalAccuracy(name="top1"),
            keras.metrics.SparseTopKCategoricalAccuracy(k=5, name="top5"),
        ],
    )


def _early_stop():
    return keras.callbacks.EarlyStopping(
        monitor="val_top1", mode="max", patience=3, restore_best_weights=True)


def train_head(model, train, val):
    """Stage 1: backbone frozen, train only the new classification head."""
    compile_model(model, 1e-3)
    model.fit(train, validation_data=val, epochs=HEAD_EPOCHS, callbacks=[_early_stop()], verbose=2)


def fine_tune(model, backbone, train, val):
    """Stage 2: unfreeze the top of the backbone (not BatchNorm) at a 10x lower learning rate."""
    backbone.trainable = True
    for layer in backbone.layers[:-FINE_TUNE_LAYERS]:
        layer.trainable = False
    for layer in backbone.layers:
        if isinstance(layer, keras.layers.BatchNormalization):
            layer.trainable = False
    compile_model(model, 1e-4)
    model.fit(train, validation_data=val, epochs=FINE_EPOCHS, callbacks=[_early_stop()], verbose=2)


def evaluate_and_save(model, test, names, backbone_name, started):
    """Top-1 / top-5 on the held-out test split; saves model, labels and metrics."""
    loss, top1, top5 = model.evaluate(test, verbose=2)
    ARTIFACTS.mkdir(exist_ok=True)
    model.save(ARTIFACTS / "breeds.keras")
    LABELS_FILE.write_text("\n".join(names) + "\n")
    metrics = {
        "backbone": backbone_name,
        "test_top1": round(top1, 4),
        "test_top5": round(top5, 4),
        "test_loss": round(loss, 4),
        "params": model.count_params(),
        "wall_time_min": round((time.time() - started) / 60, 1),
        "tensorflow": tf.__version__,
    }
    (ARTIFACTS / "metrics.json").write_text(json.dumps(metrics, indent=2))
    return metrics


def export_saved_model():
    """Trained Keras model -> TF SavedModel with a fixed float32 [1, 224, 224, 3] input "image".

    Both converters read this SavedModel: converting a tf.function over a Keras 3 model
    directly dropped the weights (8 MB model came out as 0.3 MB with random accuracy).
    """
    model = keras.models.load_model(ARTIFACTS / "breeds.keras")
    path = ARTIFACTS / "saved_model"
    model.export(str(path), format="tf_saved_model", verbose=False,
                 input_signature=[tf.TensorSpec([1, IMG, IMG, 3], tf.float32, name="image")])
    return model, path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backbone", choices=BACKBONES, default="efficientnetb0")
    args = parser.parse_args()
    started = time.time()
    train, val, test, names = build_datasets()
    assert len(names) == 37, names
    model, backbone = build_model(len(names), args.backbone)
    train_head(model, train, val)
    fine_tune(model, backbone, train, val)
    print(json.dumps(evaluate_and_save(model, test, names, args.backbone, started), indent=2))


if __name__ == "__main__":
    main()
