import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';

void main() {
  group('ClipInsight.fromJson', () {
    test('parses the WS insight object and round-trips', () {
      final json = <String, Object?>{
        'mood': 'playful',
        'activity': 'playing',
        'healthFlags': [
          {'flag': 'limping', 'severity': 'medium', 'evidence': 'favors leg'},
        ],
        'summary': 'A dog chasing a ball.',
        'confidence': 1,
      };

      final insight = ClipInsight.fromJson(json);

      expect(insight.mood, Mood.playful);
      expect(insight.activity, Activity.playing);
      expect(insight.healthFlags.single.severity, Severity.medium);
      expect(insight.confidence, 1.0);
      expect(ClipInsight.fromJson(insight.toJson()), insight);
    });

    test('unknown enum values fall back instead of throwing', () {
      final insight = ClipInsight.fromJson(const {
        'mood': 'ecstatic',
        'activity': 'flying',
        'summary': 's',
        'confidence': 0.5,
      });

      expect(insight.mood, Mood.unknown);
      expect(insight.activity, Activity.other);
      expect(insight.healthFlags, isEmpty);
    });
  });
}
