import 'package:equatable/equatable.dart';

/// Enum values match the `insight` object in docs/WS_PROTOCOL.md exactly.
enum Mood { relaxed, playful, anxious, alert, tired, unknown }

enum Activity { sleeping, playing, eating, walking, resting, grooming, other }

enum Severity { low, medium, high }

/// An observation, not a diagnosis.
class HealthFlag extends Equatable {
  const new({
    required this.flag,
    required this.severity,
    required this.evidence,
  });

  factory fromJson(Map<String, Object?> json) => HealthFlag(
    flag: json['flag']! as String,
    severity: _byName(Severity.values, json['severity'], Severity.low),
    evidence: json['evidence']! as String,
  );

  /// e.g. `limping`.
  final String flag;
  final Severity severity;

  /// What in the frames led to the flag.
  final String evidence;

  Map<String, Object?> toJson() => {
    'flag': flag,
    'severity': severity.name,
    'evidence': evidence,
  };

  @override
  List<Object?> get props => [flag, severity, evidence];
}

/// The final structured result of a clip analysis (WS `insight` message).
class ClipInsight extends Equatable {
  const new({
    required this.mood,
    required this.activity,
    required this.healthFlags,
    required this.summary,
    required this.confidence,
  });

  /// Parses the `insight` object. Unknown enum values fall back to
  /// [Mood.unknown] / [Activity.other] / [Severity.low] so a newer backend
  /// cannot crash the app; missing required fields throw.
  factory fromJson(Map<String, Object?> json) => ClipInsight(
    mood: _byName(Mood.values, json['mood'], Mood.unknown),
    activity: _byName(Activity.values, json['activity'], Activity.other),
    healthFlags: [
      for (final f in (json['healthFlags'] as List<Object?>?) ?? const [])
        HealthFlag.fromJson((f! as Map).cast<String, Object?>()),
    ],
    summary: json['summary']! as String,
    confidence: (json['confidence']! as num).toDouble(),
  );

  final Mood mood;
  final Activity activity;
  final List<HealthFlag> healthFlags;

  /// 2-3 sentence plain-language summary.
  final String summary;

  /// Model's self-reported confidence in [0, 1].
  final double confidence;

  Map<String, Object?> toJson() => {
    'mood': mood.name,
    'activity': activity.name,
    'healthFlags': [for (final f in healthFlags) f.toJson()],
    'summary': summary,
    'confidence': confidence,
  };

  @override
  List<Object?> get props => [mood, activity, healthFlags, summary, confidence];
}

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;
