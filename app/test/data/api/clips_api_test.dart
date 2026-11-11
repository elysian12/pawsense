import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';

import '../fakes.dart';

void main() {
  group('parseServerMessage', () {
    ClipAnalysisEvent? parse(Map<String, Object?> json) =>
        parseServerMessage(jsonEncode({'jobId': 'j', ...json}));

    test('maps every protocol message', () {
      expect(
        parse({'type': 'status', 'status': 'analyzing'}),
        const ClipStatusChanged(ClipStatus.analyzing),
      );
      expect(parse({'type': 'delta', 'text': 'Hi'}), const ClipDelta('Hi'));
      expect(
        parse({'type': 'insight', 'insight': testInsight.toJson()}),
        const ClipInsightReady(testInsight),
      );
      expect(
        parse({'type': 'error', 'code': 'refused', 'message': 'no'}),
        const ClipAnalysisError(ClipErrorCode.refused, 'no'),
      );
      expect(parse({'type': 'done'}), const ClipAnalysisDone());
    });

    test('ignores unknown types and statuses', () {
      expect(parse({'type': 'ping'}), isNull);
      expect(parse({'type': 'status', 'status': 'paused'}), isNull);
    });
  });

  test('retryable statuses', () {
    for (final code in [null, 408, 429, 500, 503]) {
      expect(isRetryableStatus(code), isTrue, reason: '$code');
    }
    for (final code in [400, 401, 413]) {
      expect(isRetryableStatus(code), isFalse, reason: '$code');
    }
  });
}
