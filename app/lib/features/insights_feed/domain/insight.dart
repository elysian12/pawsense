import 'package:equatable/equatable.dart';
import 'package:pawsense/ml/ml_types.dart';

enum InsightType { detection, sound, clip }

/// One entry of the offline-first feed (Drift `insights` table).
///
/// [payload] keys per [type]:
/// - detection: `{score: double}`
/// - sound: `{kind: 'dog'|'cat', label: String, score: double}`
/// - clip: `{clipId: String, insight: <ClipInsight.toJson()>}`
class Insight extends Equatable {
  const new({
    required this.id,
    required this.type,
    required this.petType,
    required this.payload,
    required this.createdAt,
    this.breed,
  });

  /// UUID v4.
  final String id;
  final InsightType type;
  final PetType petType;
  final String? breed;
  final Map<String, Object?> payload;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, type, petType, breed, payload, createdAt];
}
