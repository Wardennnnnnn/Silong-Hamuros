import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'weather.dart';

String now() => DateTime.now().toUtc().toIso8601String();
String uid() => '${DateTime.now().microsecondsSinceEpoch}';

abstract class Backend {
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]);
  void close();
}

class HttpBackend implements Backend {
  final Uri base;
  final String token;
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  HttpBackend(String url, this.token) : base = Uri.parse('$url/');
  @override
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final req = await client
        .openUrl(method, base.resolve(path))
        .timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close().timeout(const Duration(seconds: 10));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 401)
      throw const FormatException(
          'Connection credentials rejected. Check Settings.');
    final result = jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode >= 400)
      throw FormatException(
          result['error']?.toString() ?? 'Server request failed.');
    return result;
  }

  @override
  void close() => client.close(force: true);
}

class DryingController extends ChangeNotifier {
  static const storageKey = 'silong_android_live_v2';
  final SharedPreferences? storage;
  final FlutterSecureStorage? secrets;
  late Map<String, dynamic> data;
  Backend? backend;
  Timer? _poll;
  Future<void> _saveQueue = Future.value();
  bool busy = false,
      serverOnline = false,
      _refreshing = false,
      _disposed = false;
  int _connectionGeneration = 0;
  String? storageError, connectionError, tareCommandId;
  bool weatherLoading = false;
  String? weatherError;
  DateTime? _weatherAttempt;
  DryingController(
      {this.storage, this.secrets, this.backend, bool polling = true}) {
    data = empty();
    try {
      final saved = storage?.getString(storageKey);
      if (saved != null) {
        final value = jsonDecode(saved) as Map<String, dynamic>;
        if (value['version'] == 2) data = value;
      }
    } catch (_) {
      storageError =
          'Saved records could not be read. Reconnect to restore server records.';
    }
    if (polling)
      _poll = Timer.periodic(const Duration(seconds: 15), (_) {
        refresh();
        refreshWeather();
      });
  }
  static Map<String, dynamic> empty() => {
        'version': 2,
        'url': '',
        'settings': <String, dynamic>{
          'farm': '',
          'threshold': 60.0,
          'advisories': true,
          'latitude': lipaLatitude,
          'longitude': lipaLongitude
        },
        'device': <String, dynamic>{
          'id': null,
          'online': false,
          'lastSeen': null,
          'capturedAt': null,
          'wet': null,
          'cover': 'unknown',
          'paused': null,
          'fault': null,
          'weightG': null,
          'weightStable': false,
          'temperatureC': null,
          'humidityPct': null,
          'activeBatchId': null
        },
        'batches': <dynamic>[],
        'events': <dynamic>[],
        'commands': <dynamic>[],
        'forecast': <String, dynamic>{
          'available': false,
          'probability': null,
          'period': null,
          'fetchedAt': null
        }
      };
  Map<String, dynamic> get device => data['device'];
  Map<String, dynamic> get settings => data['settings'];
  Map<String, dynamic> get forecast =>
      data['phoneForecast'] as Map<String, dynamic>? ?? {'available': false};
  double get weatherLatitude =>
      (settings['latitude'] as num?)?.toDouble() ?? lipaLatitude;
  double get weatherLongitude =>
      (settings['longitude'] as num?)?.toDouble() ?? lipaLongitude;
  bool get approximateLocation =>
      weatherLatitude == lipaLatitude && weatherLongitude == lipaLongitude;
  Future<void> refreshAll() async {
    await Future.wait([refresh(), refreshWeather(force: true)]);
  }

  Future<void> refreshWeather({bool force = false}) async {
    if (_disposed || weatherLoading) return;
    final lat = weatherLatitude, lon = weatherLongitude;
    final same = forecast['latitude'] == lat && forecast['longitude'] == lon;
    final fetched = DateTime.tryParse(forecast['fetchedAt']?.toString() ?? '');
    if (!force &&
        same &&
        fetched != null &&
        DateTime.now().difference(fetched).inMinutes < 30) return;
    if (!force &&
        _weatherAttempt != null &&
        DateTime.now().difference(_weatherAttempt!).inMinutes < 5 &&
        same) return;
    if (!same)
      data['phoneForecast'] = {
        'available': false,
        'latitude': lat,
        'longitude': lon
      };
    _weatherAttempt = DateTime.now();
    weatherLoading = true;
    changed();
    try {
      final result = await fetchWeather(lat, lon);
      if (_disposed || lat != weatherLatitude || lon != weatherLongitude)
        return;
      data['phoneForecast'] = result;
      weatherError = null;
    } catch (_) {
      if (!_disposed && lat == weatherLatitude && lon == weatherLongitude) {
        weatherError =
            'Could not update weather. Check your internet connection.';
      }
    } finally {
      weatherLoading = false;
      changed();
    }
  }

  Map<String, dynamic> get drafts =>
      data.putIfAbsent('drafts', () => <String, dynamic>{});
  void saveDraft(String batchId, String moisture, String notes) {
    drafts[batchId] = {'moisture': moisture, 'notes': notes};
    changed();
  }

  List<dynamic> get batches => data['batches'];
  List<dynamic> get events => data['events'];
  List<dynamic> get commands => data['commands'];
  Map<String, dynamic>? get active {
    for (final b in batches) {
      if (b['id'] == device['activeBatchId'] && b['status'] == 'active')
        return b;
    }
    return null;
  }

  bool get fresh {
    final captured = DateTime.tryParse(device['capturedAt']?.toString() ?? '');
    return serverOnline &&
        device['online'] == true &&
        captured != null &&
        DateTime.now().difference(captured).inSeconds >= -5 &&
        DateTime.now().difference(captured).inSeconds < 90;
  }

  bool get controllable => fresh && device['fault'] == null && !busy;
  bool get weightValid =>
      fresh &&
      device['weightG'] is num &&
      device['weightG'] > 0 &&
      device['weightStable'] == true;
  bool get tareConfirmed =>
      tareCommandId != null &&
      commands
          .any((c) => c['id'] == tareCommandId && c['status'] == 'completed');
  Future<void> initialize() async {
    unawaited(refreshWeather());
    if (backend != null) {
      await refresh();
      return;
    }
    try {
      final token = await secrets?.read(key: 'silong_access_token');
      if ((data['url'] as String).isNotEmpty &&
          token != null &&
          token.isNotEmpty) {
        backend = HttpBackend(data['url'], token);
        await refresh();
      }
    } catch (_) {
      connectionError =
          'Unable to read credentials. Set them again in Settings.';
      changed();
    }
  }

  void changed() {
    if (_disposed) return;
    final snapshot = jsonEncode(data);
    if (storage != null)
      _saveQueue = _saveQueue.then((_) async {
        try {
          if (!await storage!.setString(storageKey, snapshot))
            throw StateError('Save failed');
        } catch (_) {
          storageError =
              'Could not save local cache. Server records remain available.';
          if (!_disposed) notifyListeners();
        }
      });
    notifyListeners();
  }

  Future<String?> configure(String url, String token) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['https', 'http'].contains(uri.scheme))
      return 'Enter a valid server URL.';
    if (uri.scheme != 'https' && !kDebugMode)
      return 'Use an HTTPS server for the release app.';
    if (token.trim().isEmpty) return 'Enter your app access token.';
    try {
      await secrets?.write(key: 'silong_access_token', value: token.trim());
    } catch (_) {
      return 'Could not securely save credentials.';
    }
    _connectionGeneration++;
    backend?.close();
    data = empty();
    data['url'] = url.trim().replaceAll(RegExp(r'/+$'), '');
    backend = HttpBackend(data['url'], token.trim());
    tareCommandId = null;
    serverOnline = false;
    changed();
    await refresh();
    return connectionError;
  }

  Future<void> refresh() async {
    if (backend == null || _refreshing || _disposed) return;
    _refreshing = true;
    final generation = _connectionGeneration;
    try {
      final result = await backend!.request('GET', 'v1/snapshot');
      if (generation != _connectionGeneration || _disposed) return;
      if (result['device'] is! Map ||
          result['batches'] is! List ||
          result['events'] is! List ||
          result['commands'] is! List ||
          result['settings'] is! Map ||
          result['forecast'] is! Map)
        throw const FormatException(
            'Server returned an unsupported data format.');
      for (final key in [
        'device',
        'batches',
        'events',
        'commands',
        'settings',
        'forecast'
      ]) {
        data[key] = result[key];
      }
      serverOnline = true;
      connectionError = null;
    } on FormatException catch (e) {
      if (generation == _connectionGeneration) {
        serverOnline = false;
        connectionError = e.message.toString();
      }
    } catch (_) {
      if (generation == _connectionGeneration) {
        serverOnline = false;
        connectionError = 'Cannot reach your server. Showing saved records.';
      }
    } finally {
      _refreshing = false;
      changed();
    }
  }

  Future<String?> _command(String action,
      [Map<String, dynamic> args = const {}]) async {
    if (!controllable || backend == null)
      return 'Connect a live drying bed first.';
    busy = true;
    changed();
    try {
      final result = await backend!.request('POST', 'v1/commands',
          {'requestId': uid(), 'action': action, ...args});
      if (result['command'] is! Map)
        return 'Server did not confirm command receipt.';
      if (action == 'tare') tareCommandId = result['command']['id'];
      await refresh();
      return null;
    } on FormatException catch (e) {
      return e.message.toString();
    } catch (_) {
      return 'Command delivery is uncertain. Refresh status before retrying.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<String?> cover(String action) async {
    if (action == 'open' && device['wet'] == true)
      return 'Opening is blocked while rain is detected.';
    if (action == 'open' && device['wet'] == null)
      return 'Rain sensor status is unknown.';
    if (action != 'stop' && device['paused'] == true)
      return 'Resume protection before moving.';
    return _command(action);
  }

  Future<String?> resume() => _command('resume');
  Future<String?> tare() => _command('tare');
  Future<String?> start(String name) async {
    if (active != null) return 'End the current batch first.';
    if (!tareConfirmed) return 'Wait for the device to confirm tare.';
    if (!weightValid) return 'Wait for a fresh, stable sample weight.';
    return _command(
        'start_batch', {'name': name.trim(), 'tareCommandId': tareCommandId});
  }

  Future<String?> end(double? moisture, String notes) async {
    if (active == null) return 'No active batch.';
    if (!weightValid) return 'A fresh, stable final weight is required.';
    if (moisture != null &&
        (!moisture.isFinite || moisture < 0 || moisture > 100))
      return 'Enter moisture between 0 and 100%.';
    return _command('end_batch',
        {'batchId': active!['id'], 'moisturePct': moisture, 'notes': notes});
  }

  Future<String?> saveSettings(Map<String, dynamic> value) async {
    if (backend == null) {
      data['settings'] = Map<String, dynamic>.from(value);
      changed();
      unawaited(refreshWeather(force: true));
      return null;
    }
    if (!serverOnline || backend == null)
      return 'Connect to the server to save farm settings.';
    try {
      await backend!.request('PUT', 'v1/settings', value);
      await refresh();
      unawaited(refreshWeather(force: true));
      return null;
    } on FormatException catch (e) {
      return e.message.toString();
    } catch (_) {
      return 'Settings could not be saved.';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    backend?.close();
    super.dispose();
  }
}
