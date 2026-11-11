/// Records clips and extracts keyframes. An interface so E2E tests can fake
/// recording on emulators without a camera.
abstract interface class ClipRecorder {
  /// Opens the camera for video. Requires camera + microphone permission.
  Future<void> initialize();

  /// Records [length] of video and returns the video file path.
  /// [onTick] is called about once per second with the time left.
  Future<String> recordClip(
    Duration length, {
    void Function(Duration remaining)? onTick,
  });

  /// Saves one 768px JPEG (quality ~80) per timestamp in [at] and returns
  /// their paths in the same order. Spec timestamps: 1, 3, 5, 7, 9 s.
  Future<List<String>> extractKeyframes(String videoPath, List<Duration> at);

  /// Releases the camera.
  Future<void> dispose();
}
