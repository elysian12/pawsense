import CoreML
import Flutter
import Vision

/// Core ML breed classifier behind the `pawsense/coreml` method channel.
///
/// Methods:
/// - `load` -> nil. Loads BreedClassifier.mlmodelc once (Xcode compiles the
///   .mlpackage into the app bundle).
/// - `classify` {jpeg: Uint8List} -> {predictions: [{label, confidence}] (top 3),
///   inferenceMs: Double}. The JPEG is the pet crop; Vision stretches it to 224x224
///   (same as training). Pixel scaling happens inside the model, so no normalization here.
/// - `dispose` -> nil. Drops the model.
final class CoreMLBreedClassifier: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "pawsense.coreml", qos: .userInitiated)
  private var model: VNCoreMLModel?  // only touched on `queue`

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pawsense/coreml", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CoreMLBreedClassifier(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Inference runs on a serial background queue; FlutterResult goes back on main.
    let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
    switch call.method {
    case "load":
      queue.async { [self] in
        do { _ = try loadedModel(); reply(nil) } catch { reply(Self.error("load_failed", error)) }
      }
    case "classify":
      guard let args = call.arguments as? [String: Any],
            let jpeg = args["jpeg"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "expected {jpeg: Uint8List}", details: nil))
        return
      }
      queue.async { [self] in
        do { reply(try classify(jpeg.data)) } catch { reply(Self.error("classify_failed", error)) }
      }
    case "dispose":
      queue.async { [self] in model = nil; reply(nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func loadedModel() throws -> VNCoreMLModel {
    if let model { return model }
    guard let url = Bundle.main.url(forResource: "BreedClassifier", withExtension: "mlmodelc") else {
      throw NSError(domain: "pawsense.coreml", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "BreedClassifier.mlmodelc not in bundle"])
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all  // let Core ML pick Neural Engine / GPU / CPU
    let loaded = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))
    model = loaded
    return loaded
  }

  private func classify(_ jpeg: Data) throws -> [String: Any] {
    let request = VNCoreMLRequest(model: try loadedModel())
    request.imageCropAndScaleOption = .scaleFill
    let handler = VNImageRequestHandler(data: jpeg, options: [:])
    let start = DispatchTime.now().uptimeNanoseconds
    try handler.perform([request])
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    // Classifier models give VNClassificationObservation sorted by confidence.
    let top = (request.results as? [VNClassificationObservation] ?? []).prefix(3)
    return [
      "predictions": top.map { ["label": $0.identifier, "confidence": Double($0.confidence)] },
      "inferenceMs": ms,
    ]
  }

  private static func error(_ code: String, _ error: Error) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }
}
