import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'controller.dart';
import 'weather.dart';

const brown = Color(0xFF563A2B);
const green = Color(0xFF47614B);
const paper = Color(0xFFF6F3EC);
const amber = Color(0xFF95630A);
const muted = Color(0xFF7D776C);
String n(dynamic v) => v is num
    ? (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1))
    : '—';
String dt(dynamic value) {
  if (value == null) return '—';
  final d = DateTime.parse(value).toLocal();
  return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String duration(Map<String, dynamic> b) {
  final h =
      (b['endedAt'] == null ? DateTime.now() : DateTime.parse(b['endedAt']))
          .difference(DateTime.parse(b['startedAt']))
          .inHours;
  return '${h ~/ 24}d ${h % 24}h';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {/* Server records remain available. */}
  final controller =
      DryingController(storage: prefs, secrets: const FlutterSecureStorage());
  if (prefs == null)
    controller.storageError =
        'Local storage unavailable. Records will not persist after closing.';
  runApp(SilongApp(controller: controller));
  await controller.initialize();
}

class SilongApp extends StatelessWidget {
  final DryingController controller;
  const SilongApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Silong Hamuros',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16, height: 1.4),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(
                seedColor: green, surface: const Color(0xFFFFFDF8))
            .copyWith(
                primary: brown,
                onPrimary: Colors.white,
                secondary: green,
                onSecondary: Colors.white,
                primaryContainer: const Color(0xFFE7DACA),
                onPrimaryContainer: brown,
                secondaryContainer: const Color(0xFFDCE8D9),
                onSecondaryContainer: green),
        navigationBarTheme: NavigationBarThemeData(
            backgroundColor: const Color(0xFFE9EEDF),
            indicatorColor: green,
            iconTheme: WidgetStateProperty.resolveWith((states) =>
                IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? Colors.white
                        : brown)),
            labelTextStyle: WidgetStateProperty.all(
                const TextStyle(color: brown, fontWeight: FontWeight.w600))),
        appBarTheme:
            const AppBarTheme(backgroundColor: paper, foregroundColor: brown),
        inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48))),
      ),
      home: HomeShell(c: controller));
}

class HomeShell extends StatefulWidget {
  final DryingController c;
  const HomeShell({super.key, required this.c});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  DryingController get c => widget.c;
  void message(String? error, [String success = 'Saved']) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? success)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
            appBar: AppBar(
                title: const Text('SILONG HAMUROS',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                actions: [
                  IconButton(
                      onPressed: c.refreshAll,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh weather and device data')
                ]),
            body: SafeArea(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                  Text(
                      (c.settings['farm'] as String).isEmpty
                          ? 'Your coffee drying bed'
                          : c.settings['farm'],
                      style: const TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  if (!c.fresh)
                    warning(c.backend == null
                        ? 'Device not connected. Readings will appear when your drying bed is connected.'
                        : c.serverOnline
                            ? 'Waiting for the drying bed. Last reading: ${dt(c.device['capturedAt'])}.'
                            : c.connectionError ??
                                'Connecting to your server…'),
                  if (c.storageError != null) warning(c.storageError!),
                  if (c.device['fault'] != null)
                    warning('${c.device['fault']}. Check the cover mechanism.'),
                  if (c.device['paused'] == true)
                    warning(
                        'Automatic movement paused.${c.device['wet'] == true ? ' Rain is detected!' : ''} Resume in Cover Controls.'),
                  ...switch (tab) {
                    0 => home(),
                    1 => batches(),
                    2 => alerts(),
                    _ => settings()
                  },
                ])),
            bottomNavigationBar: NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home'),
                  NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined), label: 'Batches'),
                  NavigationDestination(
                      icon: Icon(Icons.notifications_outlined),
                      label: 'Alerts'),
                  NavigationDestination(
                      icon: Icon(Icons.settings_outlined), label: 'Settings'),
                ]),
          ));
  Widget heading(String title, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 29, fontWeight: FontWeight.w600, color: brown)),
        const SizedBox(height: 6),
        Text(sub, style: const TextStyle(color: muted))
      ]));
  List<Widget> home() {
    final b = c.active;
    return [
      heading('Good things take time.', 'Your Barako drying bed, at a glance.'),
      Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
              color: green, borderRadius: BorderRadius.circular(20)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                  c.device['wet'] == null
                      ? Icons.sensors_off
                      : c.device['wet'] == true
                          ? Icons.water_drop
                          : Icons.wb_sunny_outlined,
                  color: Colors.white),
              const SizedBox(width: 10),
              Flexible(
                  child: Text(
                      c.device['wet'] == null
                          ? 'Waiting for rain sensor'
                          : c.device['wet'] == true
                              ? 'Rain detected'
                              : 'No rain detected',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)))
            ]),
            const SizedBox(height: 16),
            Text(
                c.fresh
                    ? 'Cover ${c.device['cover']}'
                    : 'Cover status unavailable',
                style: const TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
                'Local rain protection operates independently of the app.',
                style: TextStyle(color: Color(0xFFDDE5DA))),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: controls, child: const Text('Cover controls →')),
          ])),
      const SizedBox(height: 16),
      panel('Sample weight', [
        const Text('25 × 25 cm sample tray',
            style: TextStyle(color: muted, fontSize: 12)),
        metric('${n(c.device['weightG'])} g'),
        Wrap(spacing: 30, runSpacing: 12, children: [
          small('Initial', b == null ? '—' : '${n(b['initialWeightG'])} g'),
          small(
              'Weight lost',
              b == null || c.device['weightG'] == null
                  ? '—'
                  : '${n(b['initialWeightG'] - c.device['weightG'])} g')
        ]),
        if (b != null &&
            c.device['weightG'] is num &&
            c.device['weightG'] > b['initialWeightG'])
          warning('Weight increased. Check sample changes or scale drift.'),
      ]),
      panel('Drying conditions', [
        Wrap(spacing: 32, runSpacing: 14, children: [
          small('Temperature', '${n(c.device['temperatureC'])} °C'),
          small('Relative humidity', '${n(c.device['humidityPct'])} %RH')
        ])
      ]),
      panel(b == null ? 'Start tracking a sample' : b['name'], [
        if (b != null) ...[
          Text('${duration(b)} elapsed · Started ${dt(b['startedAt'])}',
              style: const TextStyle(color: muted, fontSize: 12)),
          SizedBox(
              height: 140,
              child: TrendChart(readings: b['readings'], field: 'weightG')),
          FilledButton(
              onPressed: () => viewBatch(b), child: const Text('View batch'))
        ] else
          FilledButton(
              onPressed: c.controllable ? () => startDialog() : null,
              child: const Text('Start batch')),
      ]),
      forecast(),
      Text(
          '${c.fresh ? '● Device connected' : c.device['capturedAt'] == null ? '○ No readings yet' : '○ Last known readings'} · ${dt(c.device['capturedAt'])}',
          style: const TextStyle(color: muted, fontSize: 12)),
    ];
  }

  Widget forecast() {
    final f = c.forecast;
    final hours = upcomingHours(f);
    final fresh = weatherFresh(f);
    final advice = fresh && c.settings['advisories'] == true;
    final windows = dryingWindows(f);
    final today = manilaTime(DateTime.now());
    final todayWindows = windows.where((w) {
      final day = manilaTime(DateTime.parse(w['start']));
      return day.year == today.year &&
          day.month == today.month &&
          day.day == today.day;
    }).toList();
    final ranked = [...windows]
      ..sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
    final risks = hours
        .where((r) => rainRisk(r, c.settings['threshold'] as num))
        .toList();
    final risk = risks.isEmpty ? null : risks.first;
    final reminder = risk == null
        ? null
        : DateTime.parse(risk['start']).subtract(const Duration(minutes: 30));
    String windowLabel(Map<String, dynamic> w) =>
        '${weatherTime(w['start'], date: true)} – ${weatherTime(w['end'])}';
    return panel('Weather & drying guide', [
      Text(
          c.approximateLocation
              ? 'Lipa, Batangas · Approximate city location'
              : '${(c.settings['farm'] as String).isEmpty ? 'Farm location' : c.settings['farm']} · Saved coordinates',
          style: const TextStyle(color: muted, fontSize: 12)),
      const Text('All forecast times: Philippine time',
          style: TextStyle(fontSize: 12, color: muted)),
      if (c.approximateLocation)
        const Text('Update the location when your partner farm is confirmed.',
            style: TextStyle(fontSize: 12, color: muted)),
      if (c.weatherLoading) const LinearProgressIndicator(),
      if (c.weatherError != null)
        Text(c.weatherError!, style: const TextStyle(color: amber)),
      if (f['available'] == true && hours.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: const Color(0xFFE8EEE3),
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.water_drop_outlined, color: green),
                SizedBox(width: 8),
                Text('CHANCE OF RAIN',
                    style: TextStyle(
                        color: green,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1))
              ]),
              Text('${n(hours.first['probability'])}%',
                  style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: brown,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Text(
                  '${weatherTime(hours.first['start'], date: true)} – ${weatherTime(hours.first['end'])}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              chip(
                  !fresh
                      ? 'Outdated forecast'
                      : hours.first['probability'] is! num
                          ? 'Chance unavailable'
                          : rainRisk(hours.first, c.settings['threshold'])
                              ? 'Rain risk · prepare cover'
                              : hours.first['probability'] < 30
                                  ? 'Lower rain risk'
                                  : 'Monitor conditions',
                  !fresh || rainRisk(hours.first, c.settings['threshold'])
                      ? amber
                      : green),
            ])),
        if (!fresh) warning('Forecast outdated. Refresh before planning.'),
        if (fresh && !advice)
          const Text('Drying recommendations are off in Settings.'),
        if (advice) ...[
          const SizedBox(height: 16),
          guidanceCard(
              Icons.wb_sunny_outlined,
              'DRYING TODAY',
              todayWindows.isEmpty
                  ? 'No suitable hours yet'
                  : todayWindows.map(windowLabel).join('\n'),
              todayWindows.isEmpty
                  ? 'Check again later—conditions may change.'
                  : 'Suggested outdoor drying window. Check the bed before opening.',
              green),
          guidanceCard(
              Icons.calendar_month_outlined,
              'SUGGESTED START',
              ranked.isEmpty
                  ? 'No suitable window found'
                  : windowLabel(ranked.first),
              'Best matching window in the next 3 forecast days.',
              green),
          guidanceCard(
              Icons.roofing_outlined,
              'COVER REMINDER',
              risk == null
                  ? 'Keep checking conditions'
                  : reminder!.isAfter(DateTime.now())
                      ? 'Prepare to close by ${weatherTime(reminder.toIso8601String(), date: true)}'
                      : 'Check the bed now',
              risk == null
                  ? 'No rainy period flagged in this forecast.'
                  : 'Possible rain: ${weatherTime(risk['start'], date: true)} – ${weatherTime(risk['end'])} · ${n(risk['probability'])}% chance. Prepare the cover.',
              risk == null ? brown : amber),
        ],
        const SizedBox(height: 16),
        const Text('Hourly rain forecast',
            style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
            height: 145,
            child: ListView(
                scrollDirection: Axis.horizontal,
                children: hours.take(24).map((r) {
                  final p = r['probability'];
                  final color = p is! num
                      ? muted
                      : rainRisk(r, c.settings['threshold'])
                          ? amber
                          : p < 30
                              ? green
                              : brown;
                  return Container(
                      width: 165,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(right: 8, top: 8),
                      decoration: BoxDecoration(
                          color: paper,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(weatherTime(r['start'], date: true),
                                style: const TextStyle(fontSize: 12)),
                            Text('– ${weatherTime(r['end'])}',
                                style: const TextStyle(fontSize: 12)),
                            Text('${n(p)}%',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                            const Text('Rain chance',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ]));
                }).toList())),
        Text('Fetched ${weatherTime(f['fetchedAt'], date: true)} · Open-Meteo',
            style: const TextStyle(fontSize: 12, color: muted)),
      ] else
        const Text(
            'Forecast unavailable. Connect your phone to the internet and refresh.'),
      TextButton.icon(
          onPressed:
              c.weatherLoading ? null : () => c.refreshWeather(force: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh weather')),
      const SizedBox(height: 8),
      const Text(
          'Weather advice only, not a guarantee. Rain timing is an hourly estimate. The local rain sensor triggers automatic closure.',
          style: TextStyle(fontSize: 12, color: muted)),
      const ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('About this guide',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        children: [
          Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                  'Suggestions favor daylight, lower rain risk, sunlight, and lower humidity. These are prototype rules that need farm validation. Check actual conditions before opening. Do not delay already prepared coffee based only on the suggested date. Reminders appear in the app; background notifications are not yet enabled.',
                  style: TextStyle(fontSize: 12, color: muted)))
        ],
      ),
    ]);
  }

  List<Widget> batches() => [
        heading('Batch records', 'From the first sample to the final reading.'),
        FilledButton.icon(
            onPressed: c.active == null && c.controllable ? startDialog : null,
            icon: const Icon(Icons.add),
            label: const Text('Start new batch')),
        const SizedBox(height: 16),
        if (c.batches.isEmpty) const Text('No batches recorded yet.'),
        ...c.batches.map((b) => panel(b['name'], [
              chip(b['status'], green),
              const SizedBox(height: 8),
              Text('${dt(b['startedAt'])} · ${duration(b)} elapsed'),
              Text(
                  'Initial ${n(b['initialWeightG'])} g → ${n(b['status'] == 'active' ? c.device['weightG'] : b['finalWeightG'])} g'),
              TextButton(
                  onPressed: () => viewBatch(b),
                  child: const Text('View record →'))
            ])),
      ];
  List<Widget> alerts() => [
        heading(
            'Alerts & rain log', 'Rain, cover movements, and device updates.'),
        forecast(),
        ...eventTiles(c.events)
      ];
  List<Widget> eventTiles(List<dynamic> list) => list.isEmpty
      ? [
          panel('All quiet for now', [const Text('No events recorded yet.')])
        ]
      : list
          .map((e) => panel(e['message'], [
                Text(dt(e['capturedAt']),
                    style: const TextStyle(color: muted, fontSize: 12)),
                if (e['type'] == 'rain')
                  Text(
                      '${e['closedAt'] == null ? 'Closure not confirmed' : 'Closed ${dt(e['closedAt'])}'} · ${e['dryAt'] == null ? 'Wet period ongoing' : 'Dry ${dt(e['dryAt'])}'}',
                      style: const TextStyle(fontSize: 12))
              ]))
          .toList();
  List<Widget> settings() => [
        heading('Farm settings',
            'Set up your farm. Connect your drying bed later.'),
        panel('Device connection', [
          Text(
              c.serverOnline ? 'Connection available' : 'Device not connected'),
          Text(
              (c.data['url'] as String).isEmpty
                  ? 'No setup needed yet. Add connection details when your drying bed is ready.'
                  : c.data['url'],
              style: const TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: connectionDialog,
              child: const Text('Connection setup · optional')),
          TextButton(
              onPressed: c.backend == null ? null : c.refresh,
              child: const Text('Refresh connection'))
        ]),
        panel('Farm & advisories', [
          Text(c.approximateLocation
              ? 'Weather location: Lipa, Batangas (approximate)'
              : 'Weather location: saved farm coordinates'),
          Text((c.settings['farm'] as String).isEmpty
              ? 'Farm not configured'
              : c.settings['farm']),
          Text('Rain advisory threshold: ${n(c.settings['threshold'])}%'),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('In-app weather advisories'),
              value: c.settings['advisories'],
              onChanged: c.backend == null || c.serverOnline
                  ? (v) async {
                      message(await c
                          .saveSettings({...c.settings, 'advisories': v}));
                    }
                  : null),
          OutlinedButton(
              onPressed: c.backend == null || c.serverOnline ? editFarm : null,
              child: const Text('Edit farm settings'))
        ]),
        panel('Local records', [
          const Text(
              'Records are saved on this phone. Clearing app data removes them. Keep a backup.',
              style: TextStyle(color: muted, fontSize: 12)),
          TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(c.data)));
                if (mounted)
                  message(null,
                      'JSON records copied. Paste into a file for backup.');
              },
              child: const Text('Copy records as JSON'))
        ]),
      ];
  void viewBatch(Map<String, dynamic> b) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final weight = b['status'] == 'active'
                  ? c.device['weightG']
                  : b['finalWeightG'];
              final loss = weight is num ? b['initialWeightG'] - weight : null;
              final events =
                  c.events.where((e) => e['batchId'] == b['id']).toList();
              return Scaffold(
                  appBar: AppBar(title: Text(b['name'])),
                  body: SafeArea(
                      child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                        chip(b['status'], green),
                        const SizedBox(height: 12),
                        Text('${dt(b['startedAt'])} · ${duration(b)} elapsed'),
                        const SizedBox(height: 16),
                        panel('Sample weight', [
                          Wrap(spacing: 24, runSpacing: 12, children: [
                            small('Initial', '${n(b['initialWeightG'])} g'),
                            small(b['status'] == 'active' ? 'Current' : 'Final',
                                '${n(weight)} g'),
                            small('Weight lost', '${n(loss)} g')
                          ]),
                          const SizedBox(height: 12),
                          Text(
                              '${n(loss == null ? null : loss / b['initialWeightG'] * 100)}% weight loss'),
                          SizedBox(
                              height: 160,
                              child: TrendChart(
                                  readings: b['readings'], field: 'weightG')),
                          const Text(
                              'Recorded sensor measurements. Gaps may be unobserved.',
                              style: TextStyle(color: muted, fontSize: 12))
                        ]),
                        panel('Temperature · °C', [
                          SizedBox(
                              height: 120,
                              child: TrendChart(
                                  readings: b['readings'],
                                  field: 'temperatureC'))
                        ]),
                        panel('Humidity · %RH', [
                          SizedBox(
                              height: 120,
                              child: TrendChart(
                                  readings: b['readings'],
                                  field: 'humidityPct'))
                        ]),
                        panel('Reference moisture', [
                          Text(b['moisturePct'] == null
                              ? 'Reference moisture not recorded'
                              : '${n(b['moisturePct'])}% · ${dt(b['moistureMeasuredAt'])}'),
                          const SizedBox(height: 8),
                          const Text(
                              'Use a separate coffee moisture meter. Weight loss alone does not confirm storage moisture.',
                              style: TextStyle(color: muted, fontSize: 12)),
                          if ((b['notes'] as String).isNotEmpty)
                            Text('Notes: ${b['notes']}'),
                          if (b['status'] == 'active')
                            FilledButton(
                                onPressed: () => endDialog(context),
                                child: const Text('End batch'))
                        ]),
                        Text(
                            '${b['rainCount'] ?? events.where((e) => e['type'] == 'rain').length} rain events · ${b['coverActivationCount'] ?? events.where((e) => e['type'] == 'cover' && (e['message'].toString().startsWith('Cover opening') || e['message'].toString().startsWith('Cover closing'))).length} cover activations'),
                        const SizedBox(height: 12),
                        ...eventTiles(events),
                      ])));
            })));
  }

  void controls() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => AnimatedBuilder(
            animation: c,
            builder: (context, _) => SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cover controls',
                              style: TextStyle(
                                  fontSize: 25, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          chip(
                              c.fresh
                                  ? 'Cover ${c.device['cover']}'
                                  : 'Cover status unavailable',
                              green),
                          const SizedBox(height: 12),
                          Text(c.device['wet'] == null
                              ? 'Rain status unavailable.'
                              : c.device['wet'] == true
                                  ? 'Rain detected. Opening is blocked.'
                                  : 'No rain detected.'),
                          if (c.device['paused'] == true) ...[
                            warning(
                                'Movement paused. Wet conditions need attention.'),
                            FilledButton(
                                onPressed: c.controllable
                                    ? () async => message(await c.resume(),
                                        'Resume requested; waiting for device')
                                    : null,
                                child: const Text('Resume protection'))
                          ],
                          const SizedBox(height: 20),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            OutlinedButton(
                                onPressed: c.controllable &&
                                        c.device['wet'] == false &&
                                        c.device['paused'] != true
                                    ? () async => message(await c.cover('open'),
                                        'Open requested; waiting for device')
                                    : null,
                                child: const Text('Open')),
                            FilledButton(
                                onPressed: c.controllable &&
                                        c.device['paused'] != true
                                    ? () async => message(
                                        await c.cover('close'),
                                        'Close requested; waiting for device')
                                    : null,
                                child: const Text('Close')),
                            OutlinedButton(
                                onPressed: c.controllable
                                    ? () async => message(await c.cover('stop'),
                                        'Stop requested; verify device acknowledgment')
                                    : null,
                                child: const Text('Stop')),
                          ]),
                          const SizedBox(height: 16),
                          const Text(
                              'Position is confirmed by the drying bed. Stop requests pause until Resume.',
                              style: TextStyle(color: muted, fontSize: 12)),
                          ...c.commands.take(3).map((cmd) => Text(
                              '${cmd['action']}: ${cmd['status']}',
                              style:
                                  const TextStyle(color: muted, fontSize: 12))),
                        ])))));
  }

  Future<void> connectionDialog() async {
    final url = TextEditingController(text: c.data['url']);
    final token = TextEditingController();
    String? error;
    bool saving = false;
    await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Connection setup'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'https://your-server')),
                    const SizedBox(height: 16),
                    TextField(
                        controller: token,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                            labelText: 'App access token')),
                    const SizedBox(height: 12),
                    const Text(
                        'Set this up later when your drying bed and connection service are ready. You can use the app without filling this in.',
                        style: TextStyle(fontSize: 12, color: muted)),
                    if (error != null) warning(error!),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                update(() => saving = true);
                                final result =
                                    await c.configure(url.text, token.text);
                                if (!ctx.mounted) return;
                                if (result != null) {
                                  update(() {
                                    error = result;
                                    saving = false;
                                  });
                                } else {
                                  Navigator.pop(ctx);
                                  if (mounted)
                                    message(null, 'Server connected');
                                }
                              },
                        child: Text(saving ? 'Connecting…' : 'Connect'))
                  ],
                )));
    url.dispose();
    token.dispose();
  }

  Future<void> startDialog() async {
    final name =
        TextEditingController(text: 'Barako · ${dt(now()).split(' ').first}');
    bool empty = false;
    String? error;
    await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AnimatedBuilder(
                animation: c,
                builder: (ctx, _) => AlertDialog(
                      title: const Text('Start batch'),
                      content: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            TextField(
                                controller: name,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                    labelText: 'Batch name')),
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('The sample tray is empty'),
                                value: empty,
                                onChanged: (v) => update(() => empty = v!)),
                            OutlinedButton(
                                onPressed: empty && c.controllable
                                    ? () async {
                                        final result = await c.tare();
                                        if (ctx.mounted)
                                          update(() => error = result);
                                      }
                                    : null,
                                child: const Text('Tare empty tray')),
                            Text(
                                c.tareConfirmed
                                    ? 'Tare confirmed by device ✓'
                                    : 'Waiting for tare acknowledgment',
                                style: const TextStyle(
                                    fontSize: 12, color: muted)),
                            const SizedBox(height: 16),
                            const Text(
                                'Add the coffee sample after tare is confirmed.'),
                            metric('${n(c.device['weightG'])} g'),
                            Text(c.device['weightStable'] == true
                                ? 'Stable sensor reading'
                                : 'Waiting for stable sensor reading'),
                            const Text(
                                'Keep the same sample throughout drying.',
                                style: TextStyle(fontSize: 12, color: muted)),
                            if (error != null) warning(error!),
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: c.controllable &&
                                    c.tareConfirmed &&
                                    c.weightValid
                                ? () async {
                                    final result = await c.start(name.text);
                                    if (!ctx.mounted) return;
                                    if (result != null) {
                                      update(() => error = result);
                                    } else {
                                      Navigator.pop(ctx);
                                      if (mounted)
                                        message(null,
                                            'Start requested. Waiting for device confirmation.');
                                    }
                                  }
                                : null,
                            child: const Text('Start'))
                      ],
                    ))));
    name.dispose();
  }

  Future<void> endDialog(BuildContext parent) async {
    final b = c.active;
    if (b == null) return;
    final draft = c.drafts[b['id']] ?? {};
    final moisture = TextEditingController(text: draft['moisture'] ?? '');
    final notes = TextEditingController(text: draft['notes'] ?? b['notes']);
    String? error;
    await showDialog(
        context: parent,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AnimatedBuilder(
                animation: c,
                builder: (ctx, _) => AlertDialog(
                      title: const Text('Complete batch'),
                      content: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Sample weight: ${n(c.device['weightG'])} g'),
                        Text('Captured ${dt(c.device['capturedAt'])}',
                            style: const TextStyle(fontSize: 12, color: muted)),
                        const SizedBox(height: 16),
                        TextField(
                            controller: moisture,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText:
                                    'Reference moisture (%) · optional')),
                        const SizedBox(height: 16),
                        TextField(
                            controller: notes,
                            maxLength: 2000,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                labelText: 'Farmer notes')),
                        const Text(
                            'Use a separate meter. Rain protection stays active.',
                            style: TextStyle(fontSize: 12, color: muted)),
                        if (error != null) warning(error!),
                      ])),
                      actions: [
                        TextButton(
                            onPressed: () {
                              c.saveDraft(b['id'], moisture.text, notes.text);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Save draft')),
                        FilledButton(
                            onPressed: c.controllable && c.weightValid
                                ? () async {
                                    final text = moisture.text.trim();
                                    final value = text.isEmpty
                                        ? null
                                        : double.tryParse(text);
                                    final result = text.isNotEmpty &&
                                            value == null
                                        ? 'Enter a valid moisture percentage.'
                                        : await c.end(value, notes.text);
                                    if (!ctx.mounted) return;
                                    if (result != null) {
                                      update(() => error = result);
                                    } else {
                                      Navigator.pop(ctx);
                                      if (mounted)
                                        message(null,
                                            'Completion requested. Waiting for device.');
                                    }
                                  }
                                : null,
                            child: const Text('Complete'))
                      ],
                    ))));
    moisture.dispose();
    notes.dispose();
  }

  Future<void> editFarm() async {
    final farm = TextEditingController(text: c.settings['farm']);
    final threshold = TextEditingController(text: n(c.settings['threshold']));
    final lat = TextEditingController(text: c.weatherLatitude.toString());
    final lon = TextEditingController(text: c.weatherLongitude.toString());
    String? error;
    await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Farm settings'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: farm,
                        maxLength: 100,
                        decoration:
                            const InputDecoration(labelText: 'Farm name')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: threshold,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Rain advisory threshold (%)')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: lat,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: const InputDecoration(
                            labelText: 'Farm latitude · optional')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: lon,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: const InputDecoration(
                            labelText: 'Farm longitude · optional')),
                    if (error != null) warning(error!),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () async {
                          final t = double.tryParse(threshold.text),
                              latitude = double.tryParse(lat.text),
                              longitude = double.tryParse(lon.text);
                          if (farm.text.trim().isEmpty ||
                              t == null ||
                              !t.isFinite ||
                              t < 0 ||
                              t > 100 ||
                              (lat.text.isNotEmpty || lon.text.isNotEmpty) &&
                                  (latitude == null ||
                                      longitude == null ||
                                      !latitude.isFinite ||
                                      !longitude.isFinite ||
                                      latitude.abs() > 90 ||
                                      longitude.abs() > 180)) {
                            update(() => error =
                                'Check farm name, threshold and coordinates.');
                            return;
                          }
                          final result = await c.saveSettings({
                            ...c.settings,
                            'farm': farm.text.trim(),
                            'threshold': t,
                            'latitude': latitude,
                            'longitude': longitude
                          });
                          if (!ctx.mounted) return;
                          if (result != null) {
                            update(() => error = result);
                          } else {
                            Navigator.pop(ctx);
                          }
                        },
                        child: const Text('Save'))
                  ],
                )));
    farm.dispose();
    threshold.dispose();
    lat.dispose();
    lon.dispose();
  }
}

Widget panel(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
        color: const Color(0xFFFFFDF8),
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE6DFD3)),
            borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800, color: brown)),
              const SizedBox(height: 12),
              ...children
            ]))));
Widget metric(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(value,
        style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: brown,
            fontFeatures: [FontFeature.tabularFigures()])));
Widget small(String label, String value) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 13, color: muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(value,
          style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()]))
    ]);
Widget guidanceCard(IconData icon, String label, String value, String detail,
        Color color) =>
    Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color.withAlpha(13),
            border: Border.all(color: color.withAlpha(45)),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800)))
          ]),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  height: 1.3,
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 6),
          Text(detail,
              style: const TextStyle(fontSize: 13, color: muted, height: 1.4)),
        ]));
Widget chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
        color: color.withAlpha(24), borderRadius: BorderRadius.circular(100)),
    child: Text(text,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600)));
Widget warning(String text) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: const Color(0xFFFAEED9),
        borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: const TextStyle(color: amber, fontSize: 13)));

class TrendChart extends StatelessWidget {
  final List<dynamic> readings;
  final String field;
  const TrendChart({super.key, required this.readings, required this.field});
  @override
  Widget build(BuildContext context) {
    final points = readings.where((r) => r[field] is num).toList();
    if (points.length < 2)
      return const Center(
          child: Text('Waiting for more readings.',
              style: TextStyle(color: muted)));
    return Semantics(
        label:
            '$field trend, ${points.length} readings, from ${n(points.first[field])} to ${n(points.last[field])}',
        child: CustomPaint(
            painter: _TrendPainter(points, field), size: Size.infinite));
  }
}

class _TrendPainter extends CustomPainter {
  final List<dynamic> points;
  final String field;
  _TrendPainter(this.points, this.field);
  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => (p[field] as num).toDouble()).toList();
    final low = values.reduce(math.min),
        high = values.reduce(math.max),
        range = high - low == 0 ? 1.0 : high - low;
    final first =
        DateTime.parse(points.first['capturedAt']).millisecondsSinceEpoch;
    final span = math.max(
        1,
        DateTime.parse(points.last['capturedAt']).millisecondsSinceEpoch -
            first);
    const left = 36.0;
    final width = math.max(1.0, size.width - left - 8);
    final height = math.max(1.0, size.height - 46);
    final grid = Paint()
      ..color = const Color(0xFFE6DFD3)
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = 12 + fraction * height;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), grid);
    }
    void text(String s, Offset at) {
      final p = TextPainter(
          text: TextSpan(
              text: s, style: const TextStyle(color: muted, fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout();
      p.paint(canvas, at);
    }

    text(n(high), const Offset(0, 7));
    text(n(low), Offset(0, height + 7));
    text('Start', Offset(left, height + 24));
    text('Latest', Offset(left + width - 32, height + 24));
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = left +
          (DateTime.parse(points[i]['capturedAt']).millisecondsSinceEpoch -
                  first) /
              span *
              width;
      final y = 12 + (1 - (values[i] - low) / range) * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = green
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
