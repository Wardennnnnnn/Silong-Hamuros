# Silong Hamuros

Flutter Android app for monitoring a coffee drying bed. Includes a dashboard, batch records, measurement charts, alerts, farm settings, and weather guidance.

You can browse the screens and save farm settings without a backend or ESP32. Sensor readings and batch history start empty. Device controls require a connected device with fresh telemetry; there is no simulator or sample data. Weather uses Open-Meteo and needs an internet connection.

## Getting started

Use Flutter **3.47.6** (includes Dart 3.13.5), the version used for this project. Install the Android SDK and Java 17 or a compatible JDK. Android Studio can manage the SDK and emulator; you can write code in either Android Studio or VS Code with its Flutter extension.

```bash
git clone https://github.com/Wardennnnnnn/Silong-Hamuros.git
cd Silong-Hamuros
flutter doctor
flutter pub get
flutter devices
flutter run -d <device-id>
```

Replace `<device-id>` with an ID from `flutter devices`. Start an Android emulator through Android Studio's Device Manager, or connect an Android phone with USB debugging enabled. `flutter doctor` lists missing tools; run `flutter doctor --android-licenses` if it requests license acceptance.

Open this repository folder in your editor. Do not open just the `android/` folder when working on Flutter screens. Flutter generates `android/local.properties` with your local SDK paths; keep it out of Git.

## Working on the UI

Most UI work is in `lib/main.dart`:

- Colors and `ThemeData` are near the top.
- `HomeShell` contains the navigation and screen layouts.
- `TrendChart` and `_TrendPainter` draw the measurement charts.

`lib/controller.dart` handles state, persistence, API requests, and device commands. `lib/weather.dart` handles forecasts and drying-window calculations. Keep presentation changes in the UI where possible. Farm coordinates can be changed in Settings; the default is an approximate Lipa City location.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the group workflow and [weather notes](docs/weather.md) for forecast behavior and limitations.

## Check and build

```bash
flutter analyze
flutter test
flutter build apk --debug
```

The test APK is `build/app/outputs/flutter-apk/app-debug.apk`. Build output is ignored by Git. For sharing an APK, attach it to a GitHub release or send it separately.

## Optional device connection

UI work does not need the backend. When integrating hardware, configure the server URL and app access token in Settings. An Android emulator reaches a server running on the host computer at `http://10.0.2.2:8787`. A physical phone needs a reachable LAN address or HTTPS endpoint. Debug builds allow HTTP development connections; release builds require HTTPS.

The companion backend is maintained separately from this Android repository. If you have the original workspace, its setup instructions are in `../backend/README.md`. Use the app token, never the device token. Do not commit tokens, server data, or signing keys.

## Current limits

Firmware integration and physical motor behavior still need device testing. Automatic rain protection must run on the ESP32 independently of the phone and internet. Weather reminders are in-app only and do not move the cover. Drying suggestions are experimental heuristics that need farm validation; weight loss is not a moisture measurement.

Background notifications, multi-farm accounts, deployment, and full historical pagination are not implemented. Charts display up to 2,000 readings per batch; alerts display the latest 500 events. Release builds currently use debug signing and are not ready for Play Store distribution.

Weather data: [Open-Meteo](https://open-meteo.com/), CC BY 4.0. The free endpoint is intended here for noncommercial prototyping within provider limits.
