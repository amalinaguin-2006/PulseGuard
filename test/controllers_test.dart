import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_guard/controllers/history_controller.dart';
import 'package:pulse_guard/controllers/measurement_controller.dart';
import 'package:pulse_guard/models/ppg_reading.dart';
import 'package:pulse_guard/models/ppg_sample.dart';
import 'package:pulse_guard/models/user_profile.dart';
import 'package:pulse_guard/services/database_service.dart';
import 'package:pulse_guard/services/permission_service.dart';
import 'package:pulse_guard/services/ppg_camera_service.dart';
import 'package:pulse_guard/services/signal_processor_service.dart';

// Fake DatabaseService for unit testing controllers in memory
class FakeDatabaseService implements DatabaseService {
  final List<PpgReading> readings = <PpgReading>[];
  UserProfile? currentProfile;
  int _nextId = 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<PpgReading>> fetchRecentReadings({int limit = 30}) async {
    final list = List<PpgReading>.of(readings)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  @override
  Future<UserProfile?> fetchCurrentProfile() async {
    return currentProfile;
  }

  @override
  Future<int> insertPpgReading(PpgReading reading) async {
    final id = reading.id ?? _nextId++;
    final withId = reading.copyWith(id: id);
    readings.add(withId);
    return id;
  }

  @override
  Future<int> deleteReading(int id) async {
    final before = readings.length;
    readings.removeWhere((r) => r.id == id);
    return before - readings.length;
  }

  @override
  Future<int> clearAllReadings() async {
    final count = readings.length;
    readings.clear();
    return count;
  }

  @override
  Future<int> insertUserProfile(UserProfile profile) async {
    final id = _nextId++;
    currentProfile = profile.copyWith(id: id);
    return id;
  }

  @override
  Future<int> updateUserProfile(UserProfile profile) async {
    currentProfile = profile;
    return 1;
  }
}

// Fake PermissionService granting camera access
class FakePermissionService implements PermissionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> isCameraPermissionGranted() async => true;
}

// Fake PpgCameraService that emits simulated frame samples
class FakePpgCameraService implements PpgCameraService {
  final StreamController<PpgFrameSample> _controller =
      StreamController<PpgFrameSample>.broadcast();

  bool _streaming = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Stream<PpgFrameSample> get sampleStream => _controller.stream;

  @override
  Stream<PpgFrameSample> get frameStream => _controller.stream;

  @override
  bool get isStreaming => _streaming;

  @override
  Future<void> startAcquisition({dynamic camera}) async {
    _streaming = true;
  }

  @override
  Future<void> startStreaming({dynamic camera}) async => startAcquisition();

  @override
  Future<void> stopAcquisition() async {
    _streaming = false;
  }

  @override
  Future<void> stopStreaming() async => stopAcquisition();

  @override
  Future<void> setTorch(bool enable) async {}

  @override
  Future<void> dispose() async {
    await stopAcquisition();
    await _controller.close();
  }

  void emitSample(PpgFrameSample sample) {
    _controller.add(sample);
  }
}

void main() {
  group('HistoryController Tests', () {
    late FakeDatabaseService db;
    late HistoryController controller;

    setUp(() {
      db = FakeDatabaseService();
      controller = HistoryController(database: db);
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts with empty list and loads cleanly', () async {
      expect(controller.readings, isEmpty);
      expect(controller.totalCount, equals(0));

      await controller.load();
      expect(controller.readings, isEmpty);
      expect(controller.isLoading, isFalse);
    });

    test('registers saved reading and computes statistics', () async {
      await controller.load();

      final reading1 = PpgReading(
        id: 1,
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
        bpm: 70.0,
        rmssd: 42.0,
        stressIndex: 45.0,
        signalQuality: 90.0,
      );
      final reading2 = PpgReading(
        id: 2,
        timestamp: DateTime.now().toIso8601String(),
        bpm: 74.0,
        rmssd: 38.0,
        stressIndex: 50.0,
        signalQuality: 85.0,
      );

      controller.registerSavedReading(reading1);
      controller.registerSavedReading(reading2);

      expect(controller.totalCount, equals(2));
      expect(controller.summary, isNotNull);
      expect(controller.summary!.averageBpm, closeTo(72.0, 0.1));
      expect(controller.summary!.minBpm, equals(70.0));
      expect(controller.summary!.maxBpm, equals(74.0));
    });

    test('deletes single reading and clears all readings', () async {
      final reading = PpgReading(
        id: 1,
        timestamp: DateTime.now().toIso8601String(),
        bpm: 72.0,
        rmssd: 40.0,
        stressIndex: 48.0,
        signalQuality: 95.0,
      );
      await db.insertPpgReading(reading);
      await controller.load();

      expect(controller.totalCount, equals(1));

      final deleted = await controller.deleteReading(1);
      expect(deleted, isTrue);
      expect(controller.totalCount, equals(0));

      // Re-insert and test clearAll
      await db.insertPpgReading(reading);
      await controller.load();
      expect(controller.totalCount, equals(1));

      final cleared = await controller.clearAll();
      expect(cleared, equals(1));
      expect(controller.totalCount, equals(0));
    });

    test('exports CSV and JSON formatted logs', () {
      final reading = PpgReading(
        id: 1,
        timestamp: '2026-10-08T12:00:00.000Z',
        bpm: 72.0,
        rmssd: 40.0,
        stressIndex: 48.0,
        signalQuality: 95.0,
      );
      controller.registerSavedReading(reading);

      final csv = controller.exportCsv();
      expect(csv, contains('bpm,rmssd_ms,stress_index'));
      expect(csv, contains('72.0,40.0,48.0'));

      final json = controller.exportSummaryJson();
      expect(json, contains('"averageBpm"'));
      expect(json, contains('"readings"'));
    });

    test('saves and updates UserProfile', () async {
      const profile = UserProfile(
        name: 'Jane Doe',
        age: 28,
        gender: 'female',
        createdAt: '2026-10-08T12:00:00.000Z',
      );

      final saved = await controller.saveProfile(profile);
      expect(saved, isTrue);
      expect(controller.profile, isNotNull);
      expect(controller.profile!.name, equals('Jane Doe'));
    });
  });

  group('MeasurementController Tests', () {
    late FakeDatabaseService db;
    late FakePpgCameraService camera;
    late SignalProcessorService processor;
    late MeasurementController controller;

    setUp(() {
      db = FakeDatabaseService();
      camera = FakePpgCameraService();
      processor = SignalProcessorService();
      controller = MeasurementController(
        camera: camera,
        processor: processor,
        database: db,
        config: const MeasurementConfig(
          duration: Duration(seconds: 5),
          tickInterval: Duration(milliseconds: 50),
        ),
        observeAppLifecycle: false,
      );
    });

    tearDown(() async {
      controller.dispose();
      await camera.dispose();
      await processor.dispose();
    });

    test('initial state is idle', () {
      expect(controller.phase, equals(MeasurementPhase.idle));
      expect(controller.isMeasuring, isFalse);
      expect(controller.canStart, isTrue);
      expect(controller.progress, equals(0.0));
      expect(controller.result, isNull);
    });

    test('cancel resets state and stops streaming cleanly', () async {
      await controller.cancel();
      expect(controller.phase, equals(MeasurementPhase.idle));
      expect(controller.isMeasuring, isFalse);
    });

    test('tracks progress and remaining time accurately', () {
      expect(controller.remainingSeconds, equals(5));
      expect(controller.sqi, equals(0.0));
      expect(controller.sqiPercent, equals(0));
    });
  });
}
