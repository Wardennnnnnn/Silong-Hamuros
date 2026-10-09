import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silong_hamuros/controller.dart';

// Test fixtures are isolated here; application code generates no sensor data.
class TestBackend implements Backend {
  Map<String, dynamic> snapshot = DryingController.empty();
  final List<String> actions = [];
  bool unavailable = false;
  @override
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    if (unavailable) throw Exception('Offline');
    if (method == 'GET') return snapshot;
    actions.add(body!['action']);
    final cmd = {
      'id': 'test-command',
      'action': body['action'],
      'status': 'pending'
    };
    snapshot['commands'] = [cmd];
    return {'command': cmd};
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fresh installation has no measurements, batches, or synthetic weather',
      () {
    final c = DryingController(polling: false);
    addTearDown(c.dispose);
    expect(c.device['weightG'], isNull);
    expect(c.device['wet'], isNull);
    expect(c.batches, isEmpty);
    expect(c.events, isEmpty);
    expect(c.forecast['available'], false);
    expect(c.fresh, false);
  });
  test('previous demo cache is not imported into live records', () async {
    SharedPreferences.setMockInitialValues({
      'silong_android_demo_v1': jsonEncode({
        'version': 1,
        'batches': [
          {'name': 'Fake'}
        ]
      })
    });
    final prefs = await SharedPreferences.getInstance();
    final c = DryingController(storage: prefs, polling: false);
    addTearDown(c.dispose);
    expect(c.batches, isEmpty);
    expect(c.device['weightG'], isNull);
  });
  test('device commands cannot succeed while disconnected', () async {
    final c = DryingController(polling: false);
    addTearDown(c.dispose);
    expect(await c.cover('close'), isNotNull);
    expect(await c.tare(), isNotNull);
    expect(await c.start('Batch'), isNotNull);
    expect(c.device['cover'], 'unknown');
  });
  test('a queued command never invents a cover endpoint confirmation',
      () async {
    final api = TestBackend();
    api.snapshot['device'].addAll({
      'online': true,
      'capturedAt': now(),
      'lastSeen': now(),
      'cover': 'open',
      'wet': false
    });
    final c = DryingController(backend: api, polling: false);
    addTearDown(c.dispose);
    await c.refresh();
    expect(await c.cover('close'), isNull);
    expect(api.actions, ['close']);
    expect(c.device['cover'], 'open');
    expect(c.commands.first['status'], 'pending');
  });
  test('stale data, server outage, and rain block remote opening', () async {
    final api = TestBackend();
    api.snapshot['device']
        .addAll({'online': true, 'capturedAt': now(), 'wet': true});
    final c = DryingController(backend: api, polling: false);
    addTearDown(c.dispose);
    await c.refresh();
    expect(await c.cover('open'), contains('rain'));
    api.snapshot['device']['wet'] = false;
    api.snapshot['device']['capturedAt'] =
        DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String();
    await c.refresh();
    expect(await c.cover('close'), isNotNull);
    api.unavailable = true;
    await c.refresh();
    expect(c.serverOnline, false);
    expect(c.connectionError, isNotNull);
    expect(api.actions, isEmpty);
  });
}
