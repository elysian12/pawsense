import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';

AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

const testInsight = ClipInsight(
  mood: Mood.playful,
  activity: Activity.playing,
  healthFlags: [
    HealthFlag(flag: 'limping', severity: Severity.low, evidence: 'frame 3'),
  ],
  summary: 'A dog chasing a ball.',
  confidence: 0.8,
);

/// Scripted backend. [uploadResults]: a jobId String or an exception to
/// throw, consumed per upload. [sockets]: events per WS connection; a list
/// without [ClipAnalysisDone] simulates a dropped socket.
class FakeClipsApi implements ClipsApi {
  final uploadResults = <Object>[];
  final uploaded = <String>[];
  final sockets = <List<ClipAnalysisEvent>>[];
  final connectedJobs = <String>[];

  @override
  Future<String> uploadClip(Clip clip) async {
    uploaded.add(clip.id);
    final result = uploadResults.removeAt(0);
    if (result is Exception) throw result;
    return result as String;
  }

  @override
  Stream<ClipAnalysisEvent> streamAnalysis(String jobId) {
    connectedJobs.add(jobId);
    return Stream.fromIterable(sockets.isEmpty ? [] : sockets.removeAt(0));
  }
}

class FakeConnectivity implements Connectivity {
  new({this.online = true});

  bool online;
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  void set({required bool online}) {
    this.online = online;
    _changes.add([
      if (online) ConnectivityResult.wifi else ConnectivityResult.none,
    ]);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    if (online) ConnectivityResult.wifi else ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}
