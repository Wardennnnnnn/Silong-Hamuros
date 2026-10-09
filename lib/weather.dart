import 'dart:convert';
import 'dart:io';

// Approximate city reference from Open-Meteo geocoding; replace with farm location.
const lipaLatitude = 13.9411;
const lipaLongitude = 121.1631;

DateTime manilaTime(DateTime time) =>
    time.toUtc().add(const Duration(hours: 8));
String weatherTime(dynamic value, {bool date = false}) {
  final t = manilaTime(DateTime.parse(value.toString()));
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${date ? '${t.day}/${t.month} · ' : ''}$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

Future<Map<String, dynamic>> fetchWeather(double lat, double lon) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'hourly':
          'precipitation_probability,precipitation,relative_humidity_2m,shortwave_radiation,weather_code,is_day',
      'forecast_days': '3',
      'timezone': 'Asia/Manila',
      'timeformat': 'unixtime',
    });
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != 200)
      throw const FormatException('Weather unavailable');
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 12));
    final raw = jsonDecode(body) as Map<String, dynamic>;
    final h = raw['hourly'] as Map<String, dynamic>;
    final rows = <Map<String, dynamic>>[];
    final times = h['time'] as List;
    for (var i = 0; i < times.length; i++) {
      final end = DateTime.fromMillisecondsSinceEpoch(
          (times[i] as num).toInt() * 1000,
          isUtc: true);
      // Rain probability, precipitation and radiation describe the preceding hour.
      final start = end.subtract(const Duration(hours: 1));
      rows.add({
        'start': start.toIso8601String(), 'end': end.toIso8601String(),
        'probability': h['precipitation_probability'][i],
        'rainMm': h['precipitation'][i],
        'humidity': h['relative_humidity_2m'][i],
        'sunlight': h['shortwave_radiation'][i], 'code': h['weather_code'][i],
        // Both endpoints must be daytime before recommending this whole hour.
        'daylight': i > 0 && h['is_day'][i] == 1 && h['is_day'][i - 1] == 1,
      });
    }
    return {
      'available': true,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'latitude': lat,
      'longitude': lon,
      'hours': rows
    };
  } finally {
    client.close(force: true);
  }
}

bool weatherFresh(Map<String, dynamic> f) {
  final time = DateTime.tryParse(f['fetchedAt']?.toString() ?? '');
  if (f['available'] != true || time == null) return false;
  final age = DateTime.now().difference(time).inSeconds;
  return age >= -5 && age < 3600;
}

List<Map<String, dynamic>> upcomingHours(Map<String, dynamic> f) =>
    (f['hours'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r))
        .where((r) => DateTime.parse(r['end']).isAfter(DateTime.now()))
        .toList();

// Configurable research prototype rules, not a validated coffee drying model.
bool favorableHour(Map<String, dynamic> r) =>
    r['daylight'] == true &&
    r['probability'] is num &&
    r['probability'] < 30 &&
    r['rainMm'] is num &&
    r['rainMm'] < 0.1 &&
    r['humidity'] is num &&
    r['humidity'] < 80 &&
    r['sunlight'] is num &&
    r['sunlight'] >= 150 &&
    r['code'] is num &&
    r['code'] <= 3;

List<Map<String, dynamic>> dryingWindows(Map<String, dynamic> f) {
  if (!weatherFresh(f)) return [];
  final windows = <Map<String, dynamic>>[];
  DateTime? start, end;
  var score = 0.0;
  void finish() {
    if (start != null &&
        end != null &&
        end!.difference(start!).inMinutes >= 120) {
      windows.add({
        'start': start!.toIso8601String(),
        'end': end!.toIso8601String(),
        'score': score
      });
    }
    start = end = null;
    score = 0;
  }

  final clock = DateTime.now().toUtc();
  for (final r in upcomingHours(f)) {
    final a = DateTime.parse(r['start']), b = DateTime.parse(r['end']);
    if (!favorableHour(r)) {
      finish();
      continue;
    }
    if (end != null && a != end) finish();
    start ??= a.isBefore(clock) ? clock : a;
    end = b;
    score += (r['sunlight'] as num).toDouble() *
        (1 - (r['probability'] as num) / 100) *
        (1 - (r['humidity'] as num) / 100);
  }
  finish();
  return windows;
}

bool rainRisk(Map<String, dynamic> r, num threshold) =>
    (r['probability'] is num && r['probability'] >= threshold) ||
    (r['rainMm'] is num && r['rainMm'] >= 0.1) ||
    (r['code'] is num && r['code'] >= 95);
